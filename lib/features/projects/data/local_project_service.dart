import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';

class LocalProjectService {
  static const maxArchiveBytes = 300 * 1024 * 1024;
  static const maxUncompressedBytes = 500 * 1024 * 1024;
  static const maxFiles = 5000;
  static const maxFileBytes = 95 * 1024 * 1024;
  static const _maxIdentityFileBytes = 1024 * 1024;

  Future<ZipProjectPreview?> pickAndAnalyzeZip() async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (selected == null) {
      return null;
    }
    final path = selected.path;
    if (path == null || path.isEmpty) {
      throw const InvalidZipException(
        'Não foi possível acessar o ZIP selecionado.',
        code: 'ZIP_PATH_UNAVAILABLE',
      );
    }
    return analyzeZip(path, displayName: selected.name);
  }

  Future<ZipProjectPreview> analyzeZip(
    String path, {
    String? displayName,
  }) async {
    final source = File(path);
    if (!await source.exists()) {
      throw const InvalidZipException('O ZIP selecionado não existe mais.');
    }
    final archiveBytes = await source.length();
    if (archiveBytes <= 0 || archiveBytes > maxArchiveBytes) {
      throw const InvalidZipException(
        'O ZIP está vazio ou ultrapassa o limite local de 300 MB.',
        code: 'ZIP_SIZE_LIMIT',
      );
    }

    final input = InputFileStream(path);
    Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input, verify: true);
    } catch (_) {
      input.closeSync();
      throw const InvalidZipException(
        'O arquivo não é um ZIP válido ou está corrompido.',
        code: 'ZIP_CORRUPT',
      );
    }

    var files = 0;
    var folders = 0;
    var totalBytes = 0;
    final paths = <String>[];
    final seenPaths = <String>{};
    final important = <String>[];
    final identityTexts = <String, String>{};

    try {
      for (final entry in archive) {
        final normalized = validateArchivePath(entry.name);
        if (entry.isSymbolicLink) {
          throw const InvalidZipException(
            'ZIPs com links simbólicos não são aceitos por segurança.',
            code: 'ZIP_SYMLINK',
          );
        }
        if (entry.isDirectory) {
          folders++;
          continue;
        }
        if (!entry.isFile) {
          continue;
        }
        files++;
        if (files > maxFiles) {
          throw const InvalidZipException(
            'O ZIP ultrapassa o limite de 5.000 arquivos.',
            code: 'ZIP_FILE_COUNT',
          );
        }
        if (entry.size > maxFileBytes) {
          throw InvalidZipException(
            'O arquivo $normalized ultrapassa 95 MB e não pode ser enviado ao GitHub.',
            code: 'ZIP_FILE_TOO_LARGE',
          );
        }
        totalBytes += entry.size;
        if (totalBytes > maxUncompressedBytes) {
          throw const InvalidZipException(
            'O conteúdo descompactado ultrapassa o limite local de 500 MB.',
            code: 'ZIP_EXPANDED_SIZE',
          );
        }
        if (!seenPaths.add(normalized)) {
          throw InvalidZipException(
            'O ZIP contém o caminho duplicado $normalized.',
            code: 'ZIP_DUPLICATE_PATH',
          );
        }
        paths.add(normalized);
        if (_isImportant(normalized)) {
          important.add(normalized);
        }

        final lowerPath = normalized.toLowerCase();
        if (_isIdentityFile(lowerPath) &&
            entry.size <= _maxIdentityFileBytes &&
            identityTexts.length < 64) {
          final bytes = entry.readBytes();
          if (bytes != null) {
            identityTexts[normalized] = utf8.decode(bytes, allowMalformed: true);
          }
          entry.clear();
        }
      }
    } finally {
      archive.clearSync();
      input.closeSync();
    }

    if (files == 0) {
      throw const InvalidZipException('O ZIP não contém arquivos para enviar.');
    }

    final commonRoot = _findCommonRoot(paths);
    final identity = _detectIdentity(identityTexts, commonRoot);
    final resolvedDisplayName = displayName ?? source.uri.pathSegments.last;
    final inferredVersion = identity.version == null
        ? _versionFromArchiveName(resolvedDisplayName)
        : null;
    return ZipProjectPreview(
      path: path,
      name: resolvedDisplayName,
      archiveBytes: archiveBytes,
      uncompressedBytes: totalBytes,
      fileCount: files,
      folderCount: folders,
      projectType: _detectProjectType(paths),
      importantFiles: important.take(12).toList(growable: false),
      commonRoot: commonRoot,
      projectName: identity.projectName,
      packageName: identity.packageName,
      applicationId: identity.applicationId,
      version: identity.version,
      versionCode: identity.versionCode,
      versionSource: identity.versionSource,
      inferredVersion: inferredVersion,
      hasWorkflowFiles: paths.any((rawPath) {
        final normalized = rawPath.replaceAll('\\', '/').toLowerCase();
        return normalized.startsWith('.github/workflows/') ||
            normalized.contains('/.github/workflows/');
      }),
    );
  }

  static String validateArchivePath(String raw) {
    final normalized = raw.replaceAll('\\', '/').trim();
    if (normalized.isEmpty || normalized.contains('\u0000')) {
      throw const InvalidZipException(
        'O ZIP contém um caminho de arquivo inválido.',
        code: 'ZIP_PATH_INVALID',
      );
    }
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      throw const InvalidZipException(
        'O ZIP contém caminho absoluto e foi bloqueado por segurança.',
        code: 'ZIP_ABSOLUTE_PATH',
      );
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part == '..')) {
      throw const InvalidZipException(
        'O ZIP contém tentativa de sair da pasta temporária (../).',
        code: 'ZIP_PATH_TRAVERSAL',
      );
    }
    final safe = parts.where((part) => part.isNotEmpty && part != '.').join('/');
    if (safe.isEmpty) {
      throw const InvalidZipException(
        'O ZIP contém um caminho vazio ou inválido.',
        code: 'ZIP_PATH_INVALID',
      );
    }
    return safe;
  }

  static String? _findCommonRoot(List<String> paths) {
    if (paths.isEmpty || paths.any((path) => !path.contains('/'))) {
      return null;
    }
    final first = paths.first.split('/').first;
    if (first.isEmpty) {
      return null;
    }
    return paths.every((path) => path.split('/').first == first) ? first : null;
  }

  static bool _isIdentityFile(String lowerPath) =>
      lowerPath.endsWith('github-manager.json') ||
      lowerPath.endsWith('app_identity.json') ||
      lowerPath.endsWith('status.json') ||
      lowerPath.endsWith('app.json') ||
      lowerPath.endsWith('project.json') ||
      lowerPath.endsWith('manifest.json') ||
      lowerPath.endsWith('package.json') ||
      lowerPath.endsWith('pubspec.yaml') ||
      lowerPath.endsWith('project.godot') ||
      lowerPath.endsWith('pyproject.toml') ||
      lowerPath.endsWith('cargo.toml') ||
      lowerPath.endsWith('composer.json') ||
      lowerPath.endsWith('/version') ||
      lowerPath == 'version' ||
      lowerPath.endsWith('manager.sh') ||
      lowerPath.endsWith('app/build.gradle') ||
      lowerPath.endsWith('app/build.gradle.kts');

  static _DetectedProjectIdentity _detectIdentity(
    Map<String, String> identityTexts,
    String? commonRoot,
  ) {
    final candidates = identityTexts.entries.map((entry) {
      final relative = _stripCommonRoot(entry.key, commonRoot);
      return _IdentityTextCandidate(
        relativePath: relative,
        text: entry.value,
        priority: _identityPriority(relative.toLowerCase()),
      );
    }).where((entry) => entry.priority < 1000).toList()
      ..sort((a, b) => a.priority != b.priority
          ? a.priority.compareTo(b.priority)
          : a.relativePath.length.compareTo(b.relativePath.length));

    String? projectName;
    String? packageName;
    String? applicationId;
    String? version;
    int? versionCode;
    String? versionSource;

    void useVersion(String? value, String source, {int? code}) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty || version != null) return;
      final parts = normalized.split('+');
      version = parts.first;
      versionSource = source;
      versionCode ??= code ?? (parts.length > 1 ? int.tryParse(parts.last) : null);
    }

    for (final candidate in candidates) {
      final lower = candidate.relativePath.toLowerCase();
      final text = candidate.text;
      final source = candidate.relativePath;

      if (lower == 'github-manager.json' ||
          lower == 'app_identity.json' ||
          lower == 'app.json' ||
          lower == 'project.json' ||
          lower == 'manifest.json') {
        try {
          final raw = jsonDecode(text);
          if (raw is Map) {
            final map = Map<String, dynamic>.from(raw);
            projectName ??= _firstString([
              map['displayName'], map['product'], map['projectName'],
              map['appName'], map['name'],
            ]);
            packageName ??= _firstString([map['name'], map['package']]);
            useVersion(_versionFromJsonMap(map), source);
            final android = map['android'];
            if (android is Map) {
              final androidMap = Map<String, dynamic>.from(android);
              applicationId ??= _firstString([
                androidMap['applicationId'], androidMap['namespace'],
              ]);
              final code = androidMap['versionCode'];
              final parsedCode = code is num ? code.toInt() : int.tryParse('$code');
              useVersion(_firstString([androidMap['versionName']]), source, code: parsedCode);
              versionCode ??= parsedCode;
            }
          }
        } catch (_) {}
      } else if (lower == 'status.json') {
        // STATUS.json do Termux Manager descreve a versão da integração.
        // Os campos de versão do Termux/manager embutido/APK esperado
        // representam produtos diferentes e NÃO devem ser comparados com ela.
        try {
          final raw = jsonDecode(text);
          if (raw is Map) {
            final map = Map<String, dynamic>.from(raw);
            projectName ??= _firstString([map['app_name'], map['project']]);
            applicationId ??= _firstString([map['application_id']]);
            useVersion(_firstString([map['version']]), source);
          }
        } catch (_) {
          // Metadata opcional inválida não substitui outros identificadores.
        }
      } else if (lower == 'pubspec.yaml') {
        packageName ??= RegExp(r'^name:\s*([^\s#]+)', multiLine: true)
            .firstMatch(text)?.group(1)?.trim();
        useVersion(
          RegExp(r'^version:\s*([^\s#]+)', multiLine: true)
              .firstMatch(text)?.group(1)?.trim(),
          source,
        );
      } else if (lower == 'package.json' || lower == 'composer.json') {
        try {
          final raw = jsonDecode(text);
          if (raw is Map) {
            final map = Map<String, dynamic>.from(raw);
            projectName ??= _firstString([map['displayName'], map['productName'], map['appName']]);
            packageName ??= _firstString([map['name']]);
            useVersion(_firstString([map['version']]), source);
          }
        } catch (_) {}
      } else if (lower == 'project.godot') {
        projectName ??= RegExp(r'^config/name\s*=\s*"([^"]+)"', multiLine: true)
            .firstMatch(text)?.group(1)?.trim();
        useVersion(
          RegExp(r'^config/version\s*=\s*"([^"]+)"', multiLine: true)
              .firstMatch(text)?.group(1)?.trim(),
          source,
        );
      } else if (lower == 'pyproject.toml' || lower == 'cargo.toml') {
        packageName ??= RegExp(r'''^name\s*=\s*["']([^"']+)["']''', multiLine: true)
            .firstMatch(text)?.group(1)?.trim();
        useVersion(
          RegExp(r'''^version\s*=\s*["']([^"']+)["']''', multiLine: true)
              .firstMatch(text)?.group(1)?.trim(),
          source,
        );
      } else if (lower == 'version') {
        useVersion(text.trim(), source);
      } else if (lower == 'manager.sh') {
        useVersion(_versionFromShellScript(text), source);
      } else if (lower == 'android/app/build.gradle' ||
          lower == 'android/app/build.gradle.kts' ||
          lower == 'app/build.gradle' ||
          lower == 'app/build.gradle.kts' ||
          lower == 'build.gradle' ||
          lower == 'build.gradle.kts') {
        applicationId ??= RegExp(
          r'''applicationId\s*(?:=\s*)?["']([^"']+)["']''',
        ).firstMatch(text)?.group(1)?.trim();
        applicationId ??= RegExp(
          r'''namespace\s*(?:=\s*)?["']([^"']+)["']''',
        ).firstMatch(text)?.group(1)?.trim();
        final code = int.tryParse(
          RegExp(r'''versionCode\s*(?:=\s*)?(\d+)''').firstMatch(text)?.group(1) ?? '',
        );
        useVersion(
          RegExp(r'''versionName\s*(?:=\s*)?["']([^"']+)["']''')
              .firstMatch(text)?.group(1)?.trim(),
          source,
          code: code,
        );
        versionCode ??= code;
      }
    }

    return _DetectedProjectIdentity(
      projectName: projectName,
      packageName: packageName,
      applicationId: applicationId,
      version: version,
      versionCode: versionCode,
      versionSource: versionSource,
    );
  }

  static int _identityPriority(String relativePath) {
    const priorities = <String, int>{
      'github-manager.json': 0,
      'app_identity.json': 1,
      'manifest.json': 2,
      'app.json': 3,
      'project.json': 4,
      'status.json': 5,
      'pubspec.yaml': 10,
      'project.godot': 11,
      'package.json': 12,
      'pyproject.toml': 13,
      'cargo.toml': 14,
      'composer.json': 15,
      'version': 16,
      'manager.sh': 17,
      'android/app/build.gradle.kts': 20,
      'android/app/build.gradle': 21,
      'app/build.gradle.kts': 22,
      'app/build.gradle': 23,
      // Quando o ZIP contém apenas o módulo Android app/, o commonRoot é
      // removido e o Gradle do módulo passa a aparecer na raiz efetiva.
      'build.gradle.kts': 24,
      'build.gradle': 25,
    };
    return priorities[relativePath] ?? 1000;
  }

  static String _stripCommonRoot(String path, String? root) {
    if (root == null || root.isEmpty) return path;
    final prefix = '$root/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  static String? _versionFromJsonMap(Map<String, dynamic> map) {
    final direct = _firstString([
      map['version'],
      map['versionName'],
      map['appVersion'],
    ]);
    if (direct != null) return direct.split('+').first;

    for (final key in const ['release', 'app', 'project', 'metadata']) {
      final nested = map[key];
      if (nested is Map) {
        final nestedMap = Map<String, dynamic>.from(nested);
        final value = _firstString([
          nestedMap['version'],
          nestedMap['versionName'],
          nestedMap['appVersion'],
        ]);
        if (value != null) return value.split('+').first;
      }
    }
    return null;
  }

  static String? _versionFromShellScript(String text) {
    final match = RegExp(
      r'''^(?:(?:export|readonly)\s+)?[A-Z0-9_]*VERSION\s*=\s*["']?v?([0-9]+(?:\.[0-9]+){1,3}(?:[-+][A-Za-z0-9._-]+)?)["']?\s*(?:#.*)?$''',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(1)?.trim();
  }

  static String? _versionFromArchiveName(String fileName) {
    final base = fileName.replaceFirst(
      RegExp(r'\.zip$', caseSensitive: false),
      '',
    );
    final match = RegExp(
      r'''(?:^|[-_.\s])v?([0-9]+\.[0-9]+(?:\.[0-9]+){0,2}(?:-(?:alpha|beta|rc|pre|preview|dev)(?:[._-]?[0-9]+)?)?(?:\+[0-9A-Za-z.-]+)?)(?=$|[-_.\s])''',
      caseSensitive: false,
    ).firstMatch(base);
    return match?.group(1)?.trim();
  }

  static String? _firstString(List<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static bool _isLikelyRootFile(String path, String fileName) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    final target = fileName.toLowerCase();
    if (normalized == target) return true;
    final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
    return parts.length == 2 && parts.last == target;
  }

  static bool _isImportant(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('pubspec.yaml') ||
        lower.endsWith('package.json') ||
        lower.endsWith('project.godot') ||
        lower.endsWith('pyproject.toml') ||
        lower.endsWith('cargo.toml') ||
        _isLikelyRootFile(lower, 'manifest.json') ||
        _isLikelyRootFile(lower, 'manager.sh') ||
        lower.endsWith('/version') ||
        lower == 'version' ||
        lower.endsWith('build.gradle') ||
        lower.endsWith('build.gradle.kts') ||
        lower.endsWith('androidmanifest.xml') ||
        lower.endsWith('readme.md') ||
        lower.contains('/.github/workflows/') ||
        lower.startsWith('.github/workflows/');
  }

  static String _detectProjectType(List<String> paths) {
    final lower = paths.map((path) => path.toLowerCase()).toList();
    if (lower.any((path) => path.endsWith('pubspec.yaml')) &&
        lower.any((path) => path.contains('lib/main.dart'))) {
      return 'Flutter';
    }
    if (lower.any((path) => path.endsWith('project.godot'))) {
      return 'Godot';
    }
    if (lower.any((path) => path.endsWith('androidmanifest.xml')) &&
        lower.any(
          (path) => path.endsWith('build.gradle') || path.endsWith('build.gradle.kts'),
        )) {
      return 'Android';
    }
    if (lower.any((path) => path.endsWith('pyproject.toml'))) {
      return 'Python';
    }
    if (lower.any((path) => path.endsWith('cargo.toml'))) {
      return 'Rust';
    }
    if (_looksLikeStaticWebProject(lower)) {
      return 'Site estático';
    }
    if (lower.any((path) => path.endsWith('package.json'))) {
      return 'Node/JavaScript';
    }
    if (lower.any((path) => _isLikelyRootFile(path, 'manager.sh'))) {
      return 'Shell/Termux';
    }
    if (lower.any((path) => path.endsWith('.php'))) {
      return 'PHP';
    }
    return 'Projeto genérico';
  }

  static bool _looksLikeStaticWebProject(List<String> lower) {
    final hasHtml = lower.any(
      (path) => path.endsWith('.html') || path.endsWith('.htm'),
    );
    if (!hasHtml) return false;
    final hasRootIndex = lower.any((path) => _isLikelyRootFile(path, 'index.html'));
    final hasCss = lower.any((path) => path.endsWith('.css'));
    final hasJs = lower.any(
      (path) => path.endsWith('.js') || path.endsWith('.mjs') || path.endsWith('.cjs'),
    );
    final hasStaticHostingConfig = lower.any(
      (path) => _isLikelyRootFile(path, 'vercel.json') ||
          _isLikelyRootFile(path, 'netlify.toml') ||
          _isLikelyRootFile(path, '_headers') ||
          _isLikelyRootFile(path, '_redirects'),
    );
    return hasRootIndex || (hasCss && hasJs) || hasStaticHostingConfig;
  }
}


class _IdentityTextCandidate {
  const _IdentityTextCandidate({
    required this.relativePath,
    required this.text,
    required this.priority,
  });

  final String relativePath;
  final String text;
  final int priority;
}

class _DetectedProjectIdentity {
  const _DetectedProjectIdentity({
    this.projectName,
    this.packageName,
    this.applicationId,
    this.version,
    this.versionCode,
    this.versionSource,
  });

  final String? projectName;
  final String? packageName;
  final String? applicationId;
  final String? version;
  final int? versionCode;
  final String? versionSource;
}
