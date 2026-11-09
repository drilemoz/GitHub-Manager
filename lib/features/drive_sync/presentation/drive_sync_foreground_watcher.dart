import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/providers/core_providers.dart';
import 'package:github_manager/features/drive_sync/data/drive_sync_coordinator.dart';
import 'package:github_manager/features/drive_sync/presentation/drive_sync_screen.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';

/// Best effort, foreground-only automatic checks. Android may suspend timers;
/// therefore checks also run on resume. This is NOT a headless WorkManager.
class DriveSyncForegroundWatcher extends ConsumerStatefulWidget {
  const DriveSyncForegroundWatcher({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<DriveSyncForegroundWatcher> createState() => _DriveSyncForegroundWatcherState();
}

class _DriveSyncForegroundWatcherState extends ConsumerState<DriveSyncForegroundWatcher>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _running = false;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => unawaited(_check()));
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (!mounted || _running ||
        (_lastCheck != null &&
            DateTime.now().difference(_lastCheck!) < const Duration(minutes: 15))) return;
    _running = true;
    _lastCheck = DateTime.now();
    try {
      final store = ref.read(driveSyncStoreProvider);
      final links = (await store.read()).where((link) => link.automatic).toList();
      if (links.isEmpty || !mounted) return;
      final coordinator = ref.read(driveSyncCoordinatorProvider);
      for (final link in links) {
        if (!mounted) break;
        var queued = false;
        DriveSyncCandidate? candidate;
        try {
          candidate = await coordinator.check(link);
          if (candidate != null && candidate.canQueue) {
            await coordinator.queue(candidate);
            queued = true;
          }
          await ref.read(localDatabaseProvider).putJson(
            'drive_sync.status.${link.key}',
            candidate == null ? 'Nenhum ZIP na pasta' : candidate.reason,
          );
        } catch (error) {
          await ref.read(localDatabaseProvider).putJson(
            'drive_sync.status.${link.key}', 'Verificação automática: $error');
        } finally {
          if (!queued && candidate?.project != null) {
            await LocalProjectService.discardPreviewPath(candidate.project.path);
          }
        }
      }
    } catch (_) {
      // An unavailable Drive/account must not prevent app startup or navigation.
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
