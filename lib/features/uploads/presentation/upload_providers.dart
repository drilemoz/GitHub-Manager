import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/providers/core_providers.dart';
import 'package:github_manager/features/projects/presentation/project_providers.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';
import 'package:github_manager/features/uploads/data/upload_manager_service.dart';
import 'package:github_manager/features/uploads/data/upload_recovery_settings.dart';

final uploadManagerProvider = Provider<UploadManagerService>((ref) {
  var disposed = false;
  final manager = UploadManagerService(
    uploadService: ref.watch(gitProjectUploadServiceProvider),
    gitService: ref.watch(repositoryGitServiceProvider),
    onRepositoryChanged: () {
      unawaited(() async {
        try {
          final service = ref.read(repositoryServiceProvider);
          await service.waitForPendingListRefreshes();
          if (disposed) return;
          ref.invalidate(repositoriesProvider);
          ref.invalidate(followedRepositoriesProvider);
          ref.invalidate(repositoryProjectSummaryProvider);
          ref.invalidate(repositoryProjectInfoProvider);
        } catch (_) {
          // A próxima abertura/atualização manual consultará o GitHub.
        }
      }());
    },
    automaticRecoveryEnabled: () =>
        UploadRecoverySettings.isAutomaticRecoveryEnabled(
      database: ref.read(localDatabaseProvider),
    ),
  );
  ref.onDispose(() {
    disposed = true;
    unawaited(manager.dispose());
  });
  return manager;
});
