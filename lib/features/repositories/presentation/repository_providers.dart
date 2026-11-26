import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/providers/core_providers.dart';
import 'package:github_manager/features/repositories/data/repository_git_service.dart';
import 'package:github_manager/features/repositories/data/repository_description_settings.dart';
import 'package:github_manager/features/repositories/data/repository_project_info_service.dart';
import 'package:github_manager/features/repositories/data/repository_service.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/domain/repository_project_info.dart';

final repositoryServiceProvider = Provider<RepositoryService>(
  (ref) => RepositoryService(
    ref.watch(githubApiClientProvider),
    ref.watch(localDatabaseProvider),
  ),
);

final repositoriesProvider = FutureProvider.autoDispose<List<GitHubRepository>>(
  (ref) => ref.watch(repositoryServiceProvider).listRepositories(),
);

final followedRepositoriesProvider = FutureProvider.autoDispose<List<GitHubRepository>>(
  (ref) => ref.watch(repositoryServiceProvider).listFollowedRepositories(),
);

final favoriteRepositoryIdsProvider = FutureProvider.autoDispose<Set<int>>(
  (ref) => ref.watch(repositoryServiceProvider).listFavoriteRepositoryIds(),
);

final repositoryGitServiceProvider = Provider<RepositoryGitService>(
  (ref) => RepositoryGitService(ref.watch(githubApiClientProvider)),
);

final repositoryProjectInfoServiceProvider = Provider<RepositoryProjectInfoService>(
  (ref) => RepositoryProjectInfoService(ref.watch(githubApiClientProvider)),
);

final repositoryProjectSummaryProvider = FutureProvider.autoDispose
    .family<RepositoryProjectInfo, GitHubRepository>(
  (ref, repository) => ref
      .watch(repositoryProjectInfoServiceProvider)
      .loadSummary(repository)
      .timeout(
        const Duration(seconds: 15),
        onTimeout: () => RepositoryProjectInfo(
          projectName: repository.name,
          version: null,
          technologies: [
            if (repository.language?.isNotEmpty == true) repository.language!,
          ],
        ),
      ),
);

final repositoryProjectInfoProvider = FutureProvider.autoDispose
    .family<RepositoryProjectInfo, GitHubRepository>(
  (ref, repository) => ref
      .watch(repositoryProjectInfoServiceProvider)
      .load(repository)
      .timeout(
        const Duration(seconds: 18),
        onTimeout: () => RepositoryProjectInfo(
          metadataIssue: 'Tempo limite ao consultar metadados.',
          projectName: repository.name,
          version: null,
          technologies: [
            if (repository.language?.isNotEmpty == true) repository.language!,
          ],
        ),
      ),
);

/// Compartilhado entre Configurações e os cartões da Home.
final showRepositoryDescriptionsProvider = FutureProvider<bool>((ref) =>
    RepositoryDescriptionSettings.isEnabled(
      database: ref.watch(localDatabaseProvider),
    ));
