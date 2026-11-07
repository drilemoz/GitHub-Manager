import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/domain/repository_project_info.dart';

enum ProjectVersionComparison { older, same, newer, unknown }

class ProjectSafetyCheck {
  const ProjectSafetyCheck({
    required this.blocked,
    required this.warning,
    required this.message,
    required this.identitySource,
    required this.versionComparison,
  });

  final bool blocked;
  final bool warning;
  final String message;
  final String identitySource;
  final ProjectVersionComparison versionComparison;

  static ProjectSafetyCheck compare({
    required ZipProjectPreview project,
    required GitHubRepository repository,
    required RepositoryProjectInfo repositoryInfo,
  }) {
    final zipAppId = _normalize(project.applicationId);
    final repoAppId = _normalize(repositoryInfo.applicationId);
    final appIdsComparable = zipAppId.isNotEmpty && repoAppId.isNotEmpty;
    final appIdDiffers = appIdsComparable && zipAppId != repoAppId;

    final zipPackage = _canonicalProjectName(
      project.packageName,
      stripVersionSuffix: true,
    );
    final repoPackage = _canonicalProjectName(
      repositoryInfo.packageName,
      stripVersionSuffix: true,
    );
    final packagesComparable = zipPackage.isNotEmpty && repoPackage.isNotEmpty;
    final packageDiffers = packagesComparable && zipPackage != repoPackage;

    final explicitZipName = _canonicalProjectName(
      project.projectName,
      stripVersionSuffix: true,
    );
    final repoProjectName = _canonicalProjectName(
      repositoryInfo.projectName,
      stripVersionSuffix: true,
    );
    final repositoryName = _canonicalProjectName(
      repository.name,
      stripVersionSuffix: true,
    );
    final explicitNameMatches = explicitZipName.isNotEmpty &&
        (explicitZipName == repoProjectName || explicitZipName == repositoryName);

    final weakZipName = _canonicalProjectName(
      project.name.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), ''),
      stripVersionSuffix: true,
    );
    final weakNameMatches = weakZipName.isNotEmpty &&
        (weakZipName == repoProjectName || weakZipName == repositoryName);

    final versionComparison = compareVersions(
      project.version,
      project.versionCode,
      repositoryInfo.version,
      repositoryInfo.versionCode,
    );

    // A versioned selected ZIP has a strong filename hint. If its actual
    // internal identity differs, the selector may have supplied cached bytes
    // from another project. Do not permit a manual "force" bypass.
    final filenameHint = _versionedFilenameProjectHint(project.name);
    final rootHint = _versionedFilenameProjectHint('${project.commonRoot ?? ''}.zip');
    if (filenameHint.isNotEmpty && rootHint.isNotEmpty && rootHint != filenameHint) {
      return ProjectSafetyCheck(
        blocked: true,
        warning: true,
        identitySource: 'arquivo escolhido ≠ pasta raiz do ZIP',
        versionComparison: versionComparison,
        message:
            'BLOQUEADO: a pasta principal do ZIP pertence a outro projeto. '
            'Selecione novamente para evitar sincronizar arquivos incorretos.',
      );
    }
    // No display metadata? Validate the actual package name (pubspec.yaml,
    // composer.json, package.json) against a versioned selected filename.
    // Namespaced packages may use vendor/name or org.package.name.
    // Remove the version suffix *before* splitting namespace components.
    // Otherwise social-lite-0.1.1 is split into social-lite-0, 1, 1 and
    // incorrectly classified as a different package ("1").
    final fallbackPackageHint = _packageProjectHint(project.packageName);
    if (filenameHint.isNotEmpty &&
        explicitZipName.isEmpty &&
        fallbackPackageHint.isNotEmpty &&
        filenameHint != fallbackPackageHint) {
      return ProjectSafetyCheck(
        blocked: true,
        warning: true,
        identitySource: 'arquivo escolhido ≠ pacote interno',
        versionComparison: versionComparison,
        message:
            'BLOQUEADO: o pacote declarado dentro do ZIP não corresponde '
            'ao arquivo escolhido. A seleção pode ter retornado dados de '
            'outro projeto; selecione novamente.',
      );
    }
    if (filenameHint.isNotEmpty &&
        explicitZipName.isNotEmpty &&
        filenameHint != explicitZipName) {
      return ProjectSafetyCheck(
        blocked: true,
        warning: true,
        identitySource: 'arquivo escolhido ≠ conteúdo identificado',
        versionComparison: versionComparison,
        message:
            'BLOQUEADO: o nome do ZIP escolhido aponta para outro projeto '
            'diferente dos metadados internos. Isso pode indicar cache trocado '
            'do seletor Android. Cancele e selecione novamente; nada será enviado.',
      );
    }

    final strongMatch = (appIdsComparable && !appIdDiffers) ||
        (packagesComparable && !packageDiffers);
    if (explicitZipName.isNotEmpty &&
        !explicitNameMatches &&
        !strongMatch) {
      return ProjectSafetyCheck(
        blocked: true,
        warning: true,
        identitySource: 'projeto identificado ≠ repositório',
        versionComparison: versionComparison,
        message:
            'BLOQUEADO: o projeto identificado no ZIP não corresponde ao '
            'repositório de destino. Selecione o ZIP correto. Renomeações '
            'intencionais precisam ser feitas fora deste envio automático.',
      );
    }

    if (appIdDiffers && packageDiffers) {
      return ProjectSafetyCheck(
        blocked: true,
        warning: true,
        identitySource: 'applicationId + pacote divergentes',
        versionComparison: versionComparison,
        message:
            'Dois identificadores fortes apontam para outro projeto: applicationId e pacote são diferentes. O envio foi bloqueado para proteger o repositório.',
      );
    }

    final identitySource = appIdsComparable && !appIdDiffers
        ? 'applicationId'
        : packagesComparable && !packageDiffers
            ? 'pacote do projeto'
            : explicitNameMatches
                ? 'metadados do projeto'
                : weakNameMatches
                    ? 'nome do ZIP (pista)'
                    : 'não confirmada';

    if (appIdDiffers) {
      return ProjectSafetyCheck(
        blocked: false,
        warning: true,
        identitySource: 'applicationId divergente',
        versionComparison: versionComparison,
        message:
            'O applicationId mudou em relação ao repositório. Isso pode ser intencional após migração ou renomeação; confira antes de enviar.',
      );
    }

    if (packageDiffers) {
      return ProjectSafetyCheck(
        blocked: false,
        warning: true,
        identitySource: 'pacote divergente',
        versionComparison: versionComparison,
        message:
            'O pacote do projeto mudou em relação ao repositório. O envio continua disponível, mas confirme se a mudança é intencional.',
      );
    }

    if (versionComparison == ProjectVersionComparison.older) {
      return ProjectSafetyCheck(
        blocked: false,
        warning: true,
        identitySource: identitySource,
        versionComparison: versionComparison,
        message:
            'O ZIP contém uma versão anterior à atual do GitHub. Regressão é permitida; confirme se deseja substituir o conteúdo atual.',
      );
    }

    if (!explicitNameMatches &&
        explicitZipName.isNotEmpty &&
        !appIdsComparable &&
        !packagesComparable) {
      return ProjectSafetyCheck(
        blocked: false,
        warning: true,
        identitySource: 'nome/metadados (pista)',
        versionComparison: versionComparison,
        message:
            'O nome do projeto no ZIP difere do nome do repositório. Como nomes podem mudar, isso é apenas um aviso e não bloqueia o envio.',
      );
    }

    if (versionComparison == ProjectVersionComparison.same) {
      return ProjectSafetyCheck(
        blocked: false,
        warning: true,
        identitySource: identitySource,
        versionComparison: versionComparison,
        message:
            'A mesma versão já está no GitHub. O reenvio é permitido; confira se deseja substituir o conteúdo atual.',
      );
    }

    final hasIdentityEvidence =
        (appIdsComparable && !appIdDiffers) ||
        (packagesComparable && !packageDiffers) ||
        explicitNameMatches ||
        weakNameMatches;

    if (versionComparison == ProjectVersionComparison.unknown) {
      return ProjectSafetyCheck(
        blocked: false,
        warning: true,
        identitySource: identitySource,
        versionComparison: versionComparison,
        message: hasIdentityEvidence
            ? 'A identidade parece compatível, mas não foi possível comparar as versões com segurança. Toque em ? para ver como corrigir.'
            : 'Não foi possível confirmar totalmente a identidade nem a versão. Confira o destino antes de enviar e toque em ? para ver como corrigir.',
      );
    }

    if (!hasIdentityEvidence) {
      return ProjectSafetyCheck(
        blocked: false,
        warning: true,
        identitySource: identitySource,
        versionComparison: versionComparison,
        message:
            'A identidade não pôde ser confirmada por um identificador forte. Nome e versão não são usados como bloqueio.',
      );
    }

    return ProjectSafetyCheck(
      blocked: false,
      warning: false,
      identitySource: identitySource,
      versionComparison: versionComparison,
      message: 'Projeto compatível. Os identificadores disponíveis foram conferidos.',
    );
  }

  static ProjectVersionComparison compareVersions(
    String? zipVersion,
    int? zipCode,
    String? repoVersion,
    int? repoCode,
  ) {
    final zipSemantic = _SemanticVersion.tryParse(zipVersion);
    final repoSemantic = _SemanticVersion.tryParse(repoVersion);

    if (zipSemantic != null && repoSemantic != null) {
      final semantic = zipSemantic.compareTo(repoSemantic);
      if (semantic != 0) {
        return semantic < 0
            ? ProjectVersionComparison.older
            : ProjectVersionComparison.newer;
      }

      // Quando versionName é semanticamente igual, o versionCode ainda ajuda
      // a distinguir revisões Android da mesma versão visível.
      if (zipCode != null && repoCode != null && zipCode != repoCode) {
        return zipCode < repoCode
            ? ProjectVersionComparison.older
            : ProjectVersionComparison.newer;
      }
      return ProjectVersionComparison.same;
    }

    // Projetos sem SemVer confiável ainda podem usar o versionCode como sinal
    // forte de ordenação, sem tentar transformar qualquer número do texto em
    // uma versão semântica.
    if (zipCode != null && repoCode != null && zipCode != repoCode) {
      return zipCode < repoCode
          ? ProjectVersionComparison.older
          : ProjectVersionComparison.newer;
    }

    return ProjectVersionComparison.unknown;
  }

  static String _packageProjectHint(String? rawPackageName) {
    var value = (rawPackageName ?? '').trim();
    if (value.isEmpty) return '';
    value = value.replaceFirst(
      RegExp(
        r'(?:[-_.\s]+v?\d+(?:\.\d+){1,3}(?:[-+._a-z0-9].*)?)$',
        caseSensitive: false,
      ),
      '',
    );
    // e.g. @vendor/social-lite, com.example.social_lite or social-lite.
    return _canonicalProjectName(value.split(RegExp(r'[/.]')).last);
  }

  static String _versionedFilenameProjectHint(String filename) {
    final basename = filename.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');
    final match = RegExp(
      r'^(.+?)[-_. ]+v?\d+\.\d+(?:\.\d+)?(?:[-+._ ].*)?$',
      caseSensitive: false,
    ).firstMatch(basename);
    return match == null ? '' : _normalize(match.group(1));
  }

  static String _canonicalProjectName(
    String? value, {
    bool stripVersionSuffix = false,
  }) {
    var resolved = (value ?? '').trim();
    if (stripVersionSuffix && resolved.isNotEmpty) {
      final versionSuffix = RegExp(
        r'(?:[-_.\s]+v?\d+(?:\.\d+){1,3}(?:[-+._a-z0-9].*)?)$',
        caseSensitive: false,
      );
      resolved = resolved.replaceFirst(versionSuffix, '');
    }
    return _normalize(resolved);
  }

  static String _normalize(String? value) {
    var normalized = (value ?? '').trim().toLowerCase();
    const folds = <String, String>{
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    folds.forEach((accented, plain) {
      normalized = normalized.replaceAll(accented, plain);
    });
    return normalized.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.preRelease,
  });

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  static _SemanticVersion? tryParse(String? raw) {
    var value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }

    // Metadados após + não participam da precedência SemVer.
    value = value.split('+').first.trim();
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$',
    ).firstMatch(value);
    if (match == null) return null;

    final preRelease = (match.group(4) ?? '')
        .split('.')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return _SemanticVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      preRelease: preRelease,
    );
  }

  @override
  int compareTo(_SemanticVersion other) {
    for (final pair in <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (pair.$1 != pair.$2) return pair.$1.compareTo(pair.$2);
    }

    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final max = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < max; i++) {
      if (i >= preRelease.length) return -1;
      if (i >= other.preRelease.length) return 1;

      final left = preRelease[i];
      final right = other.preRelease[i];
      if (left == right) continue;
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      if (leftNumber != null) return -1;
      if (rightNumber != null) return 1;
      return left.toLowerCase().compareTo(right.toLowerCase());
    }
    return 0;
  }
}

