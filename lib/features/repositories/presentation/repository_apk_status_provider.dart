import 'dart:async';

import 'package:flutter/services.dart';
import 'package:github_manager/core/telemetry/app_telemetry_service.dart';
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

/// Identidade conhecida do próprio produto, sem inferir pacotes de outros repos.
String? ownRepositoryApplicationId(String fullName) =>
    fullName.toLowerCase() == 'drilemoz/github-manager'
        ? 'br.com.githubmanager.app' : null;

class RepositoryLocalApk {
  const RepositoryLocalApk(this.packageName, this.installed);
  final String? packageName;
  final InstalledAndroidApp? installed;
}

class RepositoryRemoteApk {
  const RepositoryRemoteApk(this.latest, this.releaseError, this.artifactError);
  final LatestApkShortcut latest;
  final Object? releaseError;
  final Object? artifactError;
  bool get sourcesComplete => releaseError == null && artifactError == null;
}

final repositoryLocalApkProvider = FutureProvider.autoDispose
    .family<RepositoryLocalApk, GitHubRepository>((ref, repository) async {
  final ownId = ownRepositoryApplicationId(repository.fullName);
  String? id = ownId;
  if (id == null) {
    try {
      final info = await ref.watch(repositoryProjectInfoProvider(repository).future);
      id = info.applicationId?.trim();
    } catch (error, stack) {
      unawaited(AppTelemetryService.instance.recordError(
        source: 'apk_identity', error: error, stackTrace: stack));
      return const RepositoryLocalApk(null, InstalledAndroidApp(
        status: InstalledAppQueryStatus.unknown, reason: 'identity_unavailable'));
    }
  }
  if (id != null && id.isNotEmpty) {
    try {
      final installed = await PlatformActions.getInstalledAppInfo(id)
          .timeout(const Duration(seconds: 5));
      if (installed.status == InstalledAppQueryStatus.unknown &&
          installed.reason != 'package_visibility') {
        unawaited(AppTelemetryService.instance.recordError(
          source: 'apk_local', error: installed.reason ?? 'empty_result',
          context: {'package': id}));
      }
      return RepositoryLocalApk(id, installed);
    } catch (error, stack) {
      unawaited(AppTelemetryService.instance.recordError(
        source: 'apk_local', error: error, stackTrace: stack,
        context: {'package': id}));
      return RepositoryLocalApk(id, InstalledAndroidApp(
        status: InstalledAppQueryStatus.unknown,
        reason: error is PlatformException ? error.code :
            error is TimeoutException ? 'timeout' : 'platform_unavailable'));
    }
  }
  return const RepositoryLocalApk(null, null);
});

/// A busca remota não depende da identidade nem da consulta Android.
final repositoryRemoteApkProvider = FutureProvider.autoDispose
    .family<RepositoryRemoteApk, String>((ref, fullName) async {
  final service = ref.watch(artifactServiceProvider);
  List<ReleaseAsset> releases = const [];
  List<ActionArtifact> artifacts = const [];
  Object? releaseError;
  Object? artifactError;

  Future<void> loadReleases() async {
    try {
      releases = await service.listReleaseAssets(fullName)
          .timeout(const Duration(seconds: 16));
    } catch (error) {
      releaseError = error;
    }
  }

  Future<void> loadArtifacts() async {
    try {
      artifacts = await service.listArtifacts(fullName)
          .timeout(const Duration(seconds: 16));
    } catch (error) {
      artifactError = error;
    }
  }

  await Future.wait<void>([loadReleases(), loadArtifacts()]);
  return RepositoryRemoteApk(LatestApkShortcut.resolve(
    releases: releases, artifacts: artifacts,
  ), releaseError, artifactError);
});

/// Mantém o atalho de download compatível com as duas consultas independentes.
final repositoryApkStatusProvider = FutureProvider.autoDispose
    .family<RepositoryApkStatus, GitHubRepository>((ref, repository) async {
  final localFuture = ref.watch(repositoryLocalApkProvider(repository).future);
  final remoteFuture = ref.watch(repositoryRemoteApkProvider(repository.fullName).future);
  final local = await localFuture;
  final remote = await remoteFuture;
  return RepositoryApkStatus(
    latest: remote.latest,
    assessment: ApkInstallationAssessment.evaluate(
      applicationId: local.packageName,
      installed: local.installed,
      availableVersion: remote.latest.version,
      hasApk: !remote.latest.isEmpty,
      sourcesComplete: remote.sourcesComplete,
    ),
    releaseError: remote.releaseError,
    artifactError: remote.artifactError,
  );
});
