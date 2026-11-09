import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/features/builds/domain/apk_installation_assessment.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/latest_apk_shortcut.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/builds/presentation/build_providers.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';

class RepositoryApkStatus {
  const RepositoryApkStatus({
    required this.latest,
    required this.assessment,
    this.releaseError,
    this.artifactError,
  });

  final LatestApkShortcut latest;
  final ApkInstallationAssessment assessment;
  final Object? releaseError;
  final Object? artifactError;

  bool get sourcesComplete => releaseError == null && artifactError == null;
  bool get sourcesUnavailable => releaseError != null && artifactError != null;
}

/// Carrega as duas fontes independentemente e consulta somente o pacote com
/// applicationId identificado. Não enumera aplicativos do dispositivo.
final repositoryApkStatusProvider = FutureProvider.autoDispose
    .family<RepositoryApkStatus, GitHubRepository>((ref, repository) async {
  final infoFuture = ref.watch(repositoryProjectInfoProvider(repository).future);
  final service = ref.watch(artifactServiceProvider);
  List<ReleaseAsset> releases = const [];
  List<ActionArtifact> artifacts = const [];
  Object? releaseError;
  Object? artifactError;

  Future<void> loadReleases() async {
    try {
      releases = await service.listReleaseAssets(repository.fullName)
          .timeout(const Duration(seconds: 16));
    } catch (error) {
      releaseError = error;
    }
  }

  Future<void> loadArtifacts() async {
    try {
      artifacts = await service.listArtifacts(repository.fullName)
          .timeout(const Duration(seconds: 16));
    } catch (error) {
      artifactError = error;
    }
  }

  await Future.wait<void>([loadReleases(), loadArtifacts()]);
  final info = await infoFuture;
  final latest = LatestApkShortcut.resolve(
    releases: releases,
    artifacts: artifacts,
  );
  final id = info.applicationId?.trim();
  InstalledAndroidApp? installed;
  if (id != null && id.isNotEmpty) {
    try {
      installed = await PlatformActions.getInstalledAppInfo(id)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      installed = const InstalledAndroidApp(
        status: InstalledAppQueryStatus.unknown,
        reason: 'platform_unavailable',
      );
    }
  }
  final assessment = ApkInstallationAssessment.evaluate(
    applicationId: id,
    installed: installed,
    availableVersion: latest.version,
    hasApk: !latest.isEmpty,
    sourcesComplete: releaseError == null && artifactError == null,
  );
  return RepositoryApkStatus(
    latest: latest,
    assessment: assessment,
    releaseError: releaseError,
    artifactError: artifactError,
  );
});
