import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/build_manifest.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/builds/domain/release_asset_group.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OlderApkCleanupResult {
  const OlderApkCleanupResult({
    required this.artifactsDeleted,
    required this.releaseAssetsDeleted,
    required this.warnings,
  });

  final int artifactsDeleted;
  final int releaseAssetsDeleted;
  final List<String> warnings;

  int get totalDeleted => artifactsDeleted + releaseAssetsDeleted;
  bool get hasWarnings => warnings.isNotEmpty;
}

class ReleasePublishResult {
  const ReleasePublishResult({
    required this.tagName,
    required this.releaseName,
    required this.assetName,
    required this.htmlUrl,
  });

  final String tagName;
  final String releaseName;
  final String assetName;
  final String htmlUrl;
}

class ArtifactService {
  ArtifactService(this._client);

  final GitHubApiClient _client;

  Future<List<ActionArtifact>> listArtifacts(String repositoryFullName) async {
    final artifacts = <ActionArtifact>[];
    for (var page = 1; page <= 100; page++) {
      final response = await _client.get<Map<String, dynamic>>(
        '/repos/$repositoryFullName/actions/artifacts',
        queryParameters: {'per_page': 100, 'page': page},
      );
      final raw = response.data?['artifacts'];
      if (raw is! List) break;
      final pageItems = raw
          .whereType<Map>()
          .map((json) => ActionArtifact.fromJson(Map<String, dynamic>.from(json)))
          .toList(growable: false);
      artifacts.addAll(pageItems);
      if (raw.length < 100) break;
      if (page == 100) {
        throw StateError('Mais de 10.000 artifacts: contagem incompleta; não é seguro apresentar este total como completo.');
      }
    }
    artifacts.sort(
      (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return artifacts;
  }

  Future<List<ActionArtifact>> listArtifactsForRun({
    required String repositoryFullName,
    required int runId,
  }) async {
    final artifacts = <ActionArtifact>[];
    for (var page = 1; page <= 100; page++) {
      final response = await _client.get<Map<String, dynamic>>(
        '/repos/$repositoryFullName/actions/runs/$runId/artifacts',
        queryParameters: {'per_page': 100, 'page': page},
      );
      final raw = response.data?['artifacts'];
      if (raw is! List) break;
      final pageItems = raw
          .whereType<Map>()
          .map((json) => ActionArtifact.fromJson(Map<String, dynamic>.from(json)))
          .toList(growable: false);
      artifacts.addAll(pageItems);
      if (raw.length < 100) break;
      if (page == 100) {
        throw StateError('Mais de 10.000 artifacts na execução: consulta incompleta.');
      }
    }
    return List<ActionArtifact>.unmodifiable(artifacts);
  }

  /// Busca sob demanda, somente quando a pessoa abre a seleção do APK.
  /// O artifact de metadados é um ZIP pequeno e separado do artifact do APK.
  Future<BuildManifest?> loadBuildManifest({
    required String repositoryFullName,
    required int runId,
    required String commitSha,
    List<ActionArtifact>? knownArtifacts,
  }) async {
    final artifacts = knownArtifacts ?? await listArtifactsForRun(
      repositoryFullName: repositoryFullName,
      runId: runId,
    );
    final available = artifacts.where((item) => !item.expired &&
        (item.name == 'build-info' || item.name.startsWith('build-info-')) &&
        item.sizeBytes < 1024 * 1024 && item.id > 0).toList();
    if (available.isEmpty) return null;
    final temporary = await getTemporaryDirectory();
    final download = File(p.join(temporary.path,
        'gm-build-info-$runId-${DateTime.now().microsecondsSinceEpoch}.zip'));
    try {
      await _client.downloadRedirectedFile(
        '/repos/$repositoryFullName/actions/artifacts/${available.first.id}/zip',
        download.path,
      );
      if (!await download.exists() || await download.length() > 2 * 1024 * 1024) {
        return null;
      }
      final input = InputFileStream(download.path);
      try {
        final zip = ZipDecoder().decodeStream(input, verify: true);
        for (final entry in zip) {
          if (!entry.isFile || entry.name != 'build-info.json' ||
              entry.size > 128 * 1024) continue;
          final bytes = entry.readBytes();
          if (bytes == null) return null;
          final parsed = jsonDecode(utf8.decode(bytes)) as Object?;
          return BuildManifest.parse(parsed,
              expectedRunId: runId, expectedCommit: commitSha);
        }
      } finally {
        input.closeSync();
      }
    } on Exception {
      // Metadados são opcionais: o seletor continua funcionando sem eles.
      return null;
    } finally {
      try { if (await download.exists()) await download.delete(); } catch (_) {}
    }
    return null;
  }

  Future<void> deleteArtifact({
    required String repositoryFullName,
    required int artifactId,
  }) =>
      _client.delete<void>(
        '/repos/$repositoryFullName/actions/artifacts/$artifactId',
      );

  Future<int> deleteArtifacts({
    required String repositoryFullName,
    required Iterable<int> artifactIds,
  }) async {
    var deleted = 0;
    for (final artifactId in artifactIds.toSet()) {
      await deleteArtifact(
        repositoryFullName: repositoryFullName,
        artifactId: artifactId,
      );
      deleted++;
    }
    return deleted;
  }

  Future<List<ReleaseAsset>> listReleaseAssets(String repositoryFullName) async {
    final result = <ReleaseAsset>[];
    for (var page = 1; page <= 5; page++) {
      final response = await _client.get<List<dynamic>>(
        '/repos/$repositoryFullName/releases',
        queryParameters: {'per_page': 100, 'page': page},
      );
      final releases = response.data ?? const <dynamic>[];
      for (final rawRelease in releases) {
        if (rawRelease is! Map) continue;
        final release = Map<String, dynamic>.from(rawRelease);
        final tag = release['tag_name'] as String? ?? '';
        final published =
            DateTime.tryParse(release['published_at'] as String? ?? '');
        final releaseId = (release['id'] as num?)?.toInt() ?? 0;
        final releaseName = release['name'] as String? ?? tag;
        final targetCommitish = release['target_commitish'] as String? ?? '';
        final assets = release['assets'];
        if (assets is! List) continue;
        for (final rawAsset in assets) {
          if (rawAsset is! Map) continue;
          final asset = ReleaseAsset.fromJson(
            Map<String, dynamic>.from(rawAsset),
            tagName: tag,
            publishedAt: published,
            releaseId: releaseId,
            releaseName: releaseName,
            targetCommitish: targetCommitish,
          );
          if (asset.id > 0) result.add(asset);
        }
      }
      if (releases.length < 100) break;
    }
    result.sort(
      (a, b) => (b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return List<ReleaseAsset>.unmodifiable(result);
  }

  Future<void> deleteReleaseAsset({
    required String repositoryFullName,
    required int assetId,
  }) =>
      _client.delete<void>(
        '/repos/$repositoryFullName/releases/assets/$assetId',
      );

  Future<List<ReleaseAsset>> findReleaseApksForBuild({
    required String repositoryFullName,
    required RepositoryWorkflowRun run,
  }) async {
    final assets = await listReleaseAssets(repositoryFullName);
    final apkAssets = assets.where((asset) => asset.isApk).toList(growable: false);
    if (apkAssets.isEmpty || run.headSha.trim().isEmpty) {
      return const <ReleaseAsset>[];
    }

    final normalizedSha = run.headSha.trim().toLowerCase();
    final matches = <ReleaseAsset>[];
    final resolvedTags = <String, String?>{};
    final version = run.detectedVersion?.trim().toLowerCase();

    for (final asset in apkAssets) {
      final target = asset.targetCommitish.trim().toLowerCase();
      if (target == normalizedSha) {
        matches.add(asset);
        continue;
      }

      // Releases antigas podem ter sido criadas usando a branch como
      // target_commitish. Nesses casos só resolvemos a tag quando há um forte
      // indício de mesma versão, evitando apagar APKs de outra build.
      if (version == null || !_releaseMentionsVersion(asset, version)) {
        continue;
      }

      final tag = asset.tagName.trim();
      if (tag.isEmpty) continue;
      String? tagSha = resolvedTags[tag];
      if (!resolvedTags.containsKey(tag)) {
        try {
          final response = await _client.get<Map<String, dynamic>>(
            '/repos/$repositoryFullName/commits/${Uri.encodeComponent(tag)}',
          );
          tagSha = response.data?['sha'] as String?;
        } catch (_) {
          tagSha = null;
        }
        resolvedTags[tag] = tagSha;
      }
      if (tagSha?.trim().toLowerCase() == normalizedSha) {
        matches.add(asset);
      }
    }

    return List<ReleaseAsset>.unmodifiable(matches);
  }

  static bool _releaseMentionsVersion(ReleaseAsset asset, String version) {
    final normalizedVersion = _normalizedVersionToken(version);
    if (normalizedVersion == null) return false;
    return <String>[asset.tagName, asset.name, asset.releaseName]
        .map(_normalizedVersionToken)
        .whereType<String>()
        .any((value) => value == normalizedVersion);
  }

  static String? _normalizedVersionToken(String value) {
    final match = RegExp(
      r'v?(\d+\.\d+\.\d+(?:[-.][A-Za-z0-9.-]+)?(?:\+[A-Za-z0-9.-]+)?)',
      caseSensitive: false,
    ).firstMatch(value.trim());
    final token = match?.group(1)?.trim().toLowerCase();
    if (token == null || token.isEmpty) return null;
    // Build metadata não muda a versão funcional da Release, mas evitar
    // `contains` impede confundir, por exemplo, 2.0.7 com 2.0.70.
    return token.split('+').first;
  }

  Future<ReleasePublishResult> publishArtifactAsRelease({
    required String repositoryFullName,
    required String targetCommitish,
    required ActionArtifact artifact,
    required String tagName,
    required String releaseName,
    required String notes,
    required bool makeLatest,
    required bool prerelease,
    void Function(String stage)? onProgress,
  }) async {
    if (artifact.expired) {
      throw const FormatException(
        'Este artifact expirou e não pode mais ser publicado em uma Release.',
      );
    }

    final tempRoot = await getTemporaryDirectory();
    final work = await Directory(
      p.join(
        tempRoot.path,
        'release-${artifact.id}-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create(recursive: true);
    final artifactZip = File(p.join(work.path, 'artifact.zip'));
    File? apkFile;
    int? releaseId;

    try {
      onProgress?.call('Baixando o artifact do GitHub');
      await _client.downloadRedirectedFile(
        '/repos/$repositoryFullName/actions/artifacts/${artifact.id}/zip',
        artifactZip.path,
      );

      onProgress?.call('Localizando o APK dentro do artifact');
      final input = InputFileStream(artifactZip.path);
      try {
        final archive = ZipDecoder().decodeStream(input, verify: false);
        final apkEntries = archive
            .where(
              (entry) =>
                  entry.isFile && entry.name.toLowerCase().endsWith('.apk'),
            )
            .toList(growable: false);

        if (apkEntries.isNotEmpty) {
          final selected = apkEntries.firstWhere(
            (entry) {
              final lower = entry.name.toLowerCase();
              return lower.contains('universal') ||
                  (!lower.contains('arm64') &&
                      !lower.contains('armeabi') &&
                      !lower.contains('x86'));
            },
            orElse: () =>
                apkEntries.reduce((a, b) => a.size >= b.size ? a : b),
          );

          final bytes = selected.readBytes();
          if (bytes == null) {
            throw const FormatException(
              'Não foi possível extrair o APK do artifact.',
            );
          }
          final safeAssetName = _safeAssetName(selected.name.split('/').last);
          apkFile = File(p.join(work.path, safeAssetName));
          await apkFile.writeAsBytes(bytes, flush: true);
        } else {
          final names = archive
              .where((entry) => entry.isFile)
              .map((entry) => entry.name.replaceAll('\\', '/').toLowerCase())
              .toSet();
          final directApk = names.contains('androidmanifest.xml') &&
              (names.contains('classes.dex') ||
                  names.contains('resources.arsc'));
          if (!directApk) {
            throw const FormatException(
              'O artifact selecionado não contém um APK.',
            );
          }

          // upload-artifact v7 com archive:false já entregou o APK real.
          // Reutiliza o arquivo baixado em vez de descompactar/recompactar.
          final directName = artifact.name.toLowerCase().endsWith('.apk')
              ? artifact.name
              : 'app-release.apk';
          final safeAssetName = _safeAssetName(directName);
          apkFile = File(p.join(work.path, safeAssetName));
          await artifactZip.copy(apkFile.path);
        }
        archive.clearSync();
      } finally {
        input.closeSync();
      }

      onProgress?.call('Criando a Release no GitHub');
      final releaseResponse = await _client.post<Map<String, dynamic>>(
        '/repos/$repositoryFullName/releases',
        data: {
          'tag_name': tagName.trim(),
          'target_commitish': targetCommitish.trim(),
          'name': releaseName.trim(),
          'body': notes.trim(),
          'draft': false,
          'prerelease': prerelease,
          'make_latest': makeLatest ? 'true' : 'false',
        },
      );
      final release = releaseResponse.data ?? const <String, dynamic>{};
      releaseId = (release['id'] as num?)?.toInt();
      if (releaseId == null || releaseId <= 0) {
        throw const FormatException(
          'O GitHub criou uma resposta de Release inválida.',
        );
      }

      onProgress?.call('Enviando o APK para a Release');
      final fileLength = await apkFile.length();
      final assetName = p.basename(apkFile.path);
      await _client.uploadBinary<Map<String, dynamic>>(
        url:
            'https://uploads.github.com/repos/$repositoryFullName/releases/$releaseId/assets',
        stream: apkFile.openRead(),
        contentLength: fileLength,
        contentType: 'application/vnd.android.package-archive',
        queryParameters: {'name': assetName},
      );

      return ReleasePublishResult(
        tagName: tagName.trim(),
        releaseName: releaseName.trim(),
        assetName: assetName,
        htmlUrl: release['html_url'] as String? ?? '',
      );
    } catch (_) {
      if (releaseId != null) {
        try {
          await _client.delete<void>(
            '/repos/$repositoryFullName/releases/$releaseId',
          );
        } catch (_) {
          // A falha original é mais importante; rollback é apenas proteção.
        }
      }
      rethrow;
    } finally {
      if (await work.exists()) {
        await work.delete(recursive: true);
      }
    }
  }

  /// Exclui saídas APK antigas sem apagar a mais recente de cada origem.
  ///
  /// Artifacts do Actions e APKs anexados a Releases são recursos diferentes
  /// no GitHub. A limpeza precisa tratar os dois grupos separadamente; caso
  /// contrário, a opção "Excluir APKs anteriores" pode parecer não funcionar
  /// quando os APKs antigos foram publicados como assets de Release.
  Future<OlderApkCleanupResult> deleteOlderApkOutputs(
    String repositoryFullName, {
    List<ActionArtifact>? artifactsSnapshot,
    List<ReleaseAsset>? releaseAssetsSnapshot,
  }) async {
    final warnings = <String>[];
    var artifactsDeleted = 0;
    var releaseAssetsDeleted = 0;

    try {
      final artifacts = artifactsSnapshot ?? await listArtifacts(repositoryFullName);
      final apks = artifacts
          .where((item) => item.likelyContainsApk)
          .toList(growable: false);
      if (apks.length > 1) {
        // A lista já vem ordenada do mais recente para o mais antigo. Quando
        // houver um artifact ativo, preservamos toda a saída APK do mesmo run;
        // se todos expiraram, usamos o run do registro mais recente.
        final keep = apks.firstWhere(
          (item) => !item.expired,
          orElse: () => apks.first,
        );
        final keepRunId = keep.workflowRunId;
        for (final artifact in apks.where(
          (item) => keepRunId != null
              ? item.workflowRunId != keepRunId
              : item.id != keep.id,
        )) {
          try {
            await deleteArtifact(
              repositoryFullName: repositoryFullName,
              artifactId: artifact.id,
            );
            artifactsDeleted++;
          } catch (error) {
            warnings.add(
              'Não foi possível excluir o artifact ${artifact.name}: ${_cleanupMessage(error)}',
            );
          }
        }
      }
    } catch (error) {
      warnings.add(
        'Não foi possível listar os artifacts para limpeza: ${_cleanupMessage(error)}',
      );
    }

    try {
      final releaseAssets = (releaseAssetsSnapshot ??
              await listReleaseAssets(repositoryFullName))
          .where((item) => item.isApk)
          .toList(growable: false);
      final releaseGroups = groupReleaseAssets(releaseAssets);
      if (releaseGroups.length > 1) {
        // Mantém todas as variantes da versão mais recente. Isso também
        // funciona em projetos que acumulam várias versões dentro de uma única
        // Release/tag fixa, pois o agrupamento considera a versão do asset.
        final keepIds = releaseGroups.first.assets.map((asset) => asset.id).toSet();
        for (final asset in releaseAssets.where(
          (item) => !keepIds.contains(item.id),
        )) {
          try {
            await deleteReleaseAsset(
              repositoryFullName: repositoryFullName,
              assetId: asset.id,
            );
            releaseAssetsDeleted++;
          } catch (error) {
            warnings.add(
              'Não foi possível excluir o APK ${asset.name} da Release ${asset.tagName}: ${_cleanupMessage(error)}',
            );
          }
        }
      }
    } catch (error) {
      warnings.add(
        'Não foi possível listar os APKs de Release para limpeza: ${_cleanupMessage(error)}',
      );
    }

    return OlderApkCleanupResult(
      artifactsDeleted: artifactsDeleted,
      releaseAssetsDeleted: releaseAssetsDeleted,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  /// Mantido por compatibilidade com chamadas antigas.
  Future<int> deleteOlderApkArtifacts(String repositoryFullName) async {
    final result = await deleteOlderApkOutputs(repositoryFullName);
    return result.artifactsDeleted;
  }

  static String _cleanupMessage(Object error) {
    if (error is AppException) return error.message;
    final value = error.toString().trim();
    return value.isEmpty ? 'falha não identificada' : value;
  }

  static String _safeAssetName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), '-')
        .trim();
    return cleaned.isEmpty ? 'app-release.apk' : cleaned;
  }
}
