import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/providers/core_providers.dart';
import 'package:github_manager/features/builds/data/artifact_service.dart';
import 'package:github_manager/features/builds/data/actions_storage_service.dart';
import 'package:github_manager/features/builds/data/build_cleanup_service.dart';
import 'package:github_manager/features/builds/data/global_builds_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/builds/domain/global_build_entry.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';

final artifactServiceProvider = Provider<ArtifactService>(
  (ref) => ArtifactService(ref.watch(githubApiClientProvider)),
);

final actionsStorageServiceProvider = Provider<ActionsStorageService>(
  (ref) => ActionsStorageService(
    ref.watch(githubApiClientProvider),
    ref.watch(artifactServiceProvider),
  ),
);

final repositoryArtifactsProvider = FutureProvider.autoDispose.family<List<ActionArtifact>, String>(
  (ref, repositoryFullName) =>
      ref.watch(artifactServiceProvider).listArtifacts(repositoryFullName),
);

final buildCleanupServiceProvider = Provider<BuildCleanupService>(
  (ref) => BuildCleanupService(
    ref.watch(githubApiClientProvider),
    ref.watch(artifactServiceProvider),
  ),
);

final repositoryReleaseAssetsProvider =
    FutureProvider.autoDispose.family<List<ReleaseAsset>, String>(
  (ref, repositoryFullName) =>
      ref.watch(artifactServiceProvider).listReleaseAssets(repositoryFullName),
);

final globalBuildsServiceProvider = Provider<GlobalBuildsService>(
  (ref) => GlobalBuildsService(
    ref.watch(repositoryServiceProvider),
    ref.watch(repositoryGitServiceProvider),
  ),
);

final globalBuildsProvider = FutureProvider.autoDispose<GlobalBuildsSnapshot>(
  (ref) => ref.watch(globalBuildsServiceProvider).load(),
);
