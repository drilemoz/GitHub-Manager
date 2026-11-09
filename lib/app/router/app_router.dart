import 'package:flutter/material.dart';
import 'package:github_manager/features/builds/presentation/global_builds_screen.dart';
import 'package:github_manager/features/builds/presentation/actions_storage_screen.dart';
import 'package:github_manager/features/downloads/presentation/downloads_screen.dart';
import 'package:github_manager/features/drive_sync/presentation/drive_sync_screen.dart';
import 'package:github_manager/features/home/presentation/profile_screen.dart';
import 'package:github_manager/features/help/presentation/help_screen.dart';
import 'package:github_manager/features/issues/presentation/repository_issues_screen.dart';
import 'package:github_manager/features/permissions/presentation/repository_permission_diagnostics_screen.dart';
import 'package:github_manager/features/repositories/presentation/repositories_screen.dart';
import 'package:github_manager/features/repositories/presentation/repository_actions_screen.dart';
import 'package:github_manager/features/repositories/presentation/repository_artifacts_screen.dart';
import 'package:github_manager/features/repositories/presentation/repository_commits_screen.dart';
import 'package:github_manager/features/repositories/presentation/repository_detail_screen.dart';
import 'package:github_manager/features/repositories/presentation/repository_files_screen.dart';
import 'package:github_manager/features/repositories/presentation/repository_text_preview_screen.dart';
import 'package:github_manager/features/secrets/presentation/repository_secrets_screen.dart';
import 'package:github_manager/features/settings/presentation/error_telemetry_screen.dart';
import 'package:github_manager/features/settings/presentation/settings_screen.dart';
import 'package:github_manager/features/setup/presentation/setup_wizard_screen.dart';
import 'package:github_manager/features/uploads/presentation/uploads_screen.dart';
import 'package:go_router/go_router.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, state) => RepositoriesScreen(
        initialSection:
            state.uri.queryParameters['section'] == 'followed' ? 1 : 0,
      ),
    ),
    GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    GoRoute(path: '/builds', builder: (_, _) => const GlobalBuildsScreen()),
    GoRoute(
      path: '/builds/storage',
      builder: (_, state) => ActionsStorageScreen(
        initialRepository: state.uri.queryParameters['repository'],
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => const SettingsScreen(),
      routes: [
        GoRoute(
          path: 'telemetry',
          builder: (_, _) => const ErrorTelemetryScreen(),
        ),
      ],
    ),
    GoRoute(path: '/drive-sync', builder: (_, _) => const DriveSyncScreen()),
    GoRoute(
      path: '/downloads',
      builder: (_, state) => DownloadsScreen(
        focusDownloadId: state.uri.queryParameters['downloadId'],
      ),
    ),
    GoRoute(
      path: '/uploads',
      builder: (_, state) => UploadsScreen(
        focusUploadId: state.uri.queryParameters['uploadId'],
      ),
    ),
    GoRoute(
      path: '/setup',
      builder: (_, _) => const SetupWizardScreen(),
    ),
    GoRoute(
      path: '/help',
      builder: (_, _) => const HelpScreen(),
    ),
    GoRoute(
      path: '/repositories/:owner/:repo',
      builder: (_, state) {
        final fullName =
            '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
        return RepositoryDetailScreen(
          repositoryFullName: fullName,
          readOnly: state.uri.queryParameters['readOnly'] == '1',
        );
      },
      routes: [
        GoRoute(
          path: 'readme',
          builder: (_, state) {
            final fullName =
                '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
            return RepositoryTextPreviewScreen.readme(
              repositoryFullName: fullName,
              branch: state.uri.queryParameters['branch'] ?? 'main',
            );
          },
        ),
        GoRoute(
          path: 'files',
          builder: (_, state) {
            final fullName =
                '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
            return RepositoryFilesScreen(
              repositoryFullName: fullName,
              defaultBranch: state.uri.queryParameters['branch'] ?? 'main',
              readOnly: state.uri.queryParameters['readOnly'] == '1',
            );
          },
        ),
        GoRoute(
          path: 'builds',
          builder: (_, state) {
            final fullName =
                '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
            return RepositoryActionsScreen(
              repositoryFullName: fullName,
              defaultBranch: state.uri.queryParameters['branch'] ?? 'main',
              readOnly: state.uri.queryParameters['readOnly'] == '1',
              initialRunId: int.tryParse(state.uri.queryParameters['runId'] ?? ''),
            );
          },
        ),
        GoRoute(
          path: 'commits',
          builder: (_, state) {
            final fullName =
                '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
            return RepositoryCommitsScreen(
              repositoryFullName: fullName,
              initialBranch: state.uri.queryParameters['branch'] ?? 'main',
              readOnly: state.uri.queryParameters['readOnly'] == '1',
            );
          },
        ),
        GoRoute(
          path: 'bugs',
          builder: (_, state) {
            final fullName =
                '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
            return RepositoryIssuesScreen(repositoryFullName: fullName);
          },
        ),
        GoRoute(
          path: 'artifacts',
          builder: (_, state) {
            final fullName =
                '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
            return RepositoryArtifactsScreen(
              repositoryFullName: fullName,
              readOnly: state.uri.queryParameters['readOnly'] == '1',
            );
          },
        ),
        GoRoute(
          path: 'permissions',
          builder: (_, state) {
            final fullName =
                '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
            return RepositoryPermissionDiagnosticsScreen(
              repositoryFullName: fullName,
            );
          },
        ),
        GoRoute(
          path: 'secrets',
          builder: (_, state) {
            final fullName =
                '${state.pathParameters['owner']}/${state.pathParameters['repo']}';
            return RepositorySecretsScreen(repositoryFullName: fullName);
          },
        ),
      ],
    ),
  ],
);
