import 'package:flutter/material.dart';
import 'package:github_manager/app/router/app_router.dart';
import 'package:github_manager/app/theme/app_theme.dart';
import 'package:github_manager/app/theme/app_theme_controller.dart';
import 'package:github_manager/features/downloads/presentation/download_center_button.dart';
import 'package:github_manager/features/drive_sync/presentation/drive_sync_foreground_watcher.dart';
import 'package:github_manager/features/uploads/presentation/upload_center_button.dart';

class GitHubManagerApp extends StatelessWidget {
  const GitHubManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.instance,
      builder: (context, themeMode, _) => MaterialApp.router(
        title: 'GitHub Manager',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        routerConfig: appRouter,
        builder: (context, child) => DriveSyncForegroundWatcher(child: Stack(
          children: [
            Positioned.fill(child: child ?? const SizedBox.shrink()),
            Positioned(
              right: 14,
              bottom: MediaQuery.paddingOf(context).bottom + 82,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  UploadFloatingStatusButton(
                    onTap: () => appRouter.push('/uploads'),
                  ),
                  const SizedBox(height: 8),
                  DownloadFloatingStatusButton(
                    onTap: () => appRouter.push('/downloads'),
                  ),
                ],
              ),
            ),
          ],
        )),
      ),
    );
  }
}
