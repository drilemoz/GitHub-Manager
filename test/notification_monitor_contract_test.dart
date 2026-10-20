import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ledger SQLite coordena dois monitores sem lista circular de IDs', () {
    final database = File('lib/core/persistence/local_database.dart').readAsStringSync();
    final monitor = File('lib/core/background/build_monitor_service.dart').readAsStringSync();
    expect(database, contains('CREATE TABLE IF NOT EXISTS notification_events'));
    expect(database, contains('db.transaction((txn) async'));
    expect(database, contains('claimBuildNotification(int runId)'));
    expect(monitor, contains('database.claimBuildNotification(id)'));
    expect(monitor, contains('database.migrateLegacyBuildIds('));
    expect(monitor, contains('Duration(hours: 2)'));
    expect(monitor.contains('recent.length <= 250'), isFalse);
  });

  test('controles e cancelamento dos avisos opcionais estão integrados', () {
    final screen = File('lib/features/settings/presentation/settings_screen.dart').readAsStringSync();
    final actions = File('lib/features/settings/presentation/settings_screen_actions.dart').readAsStringSync();
    final notifications = File('lib/core/notifications/app_notification_service.dart').readAsStringSync();
    for (final title in [
      'Permitir avisos opcionais',
      'Build concluída com sucesso',
      'Falhas ou problemas nas builds',
      'Downloads concluídos',
      'Falhas de downloads',
    ]) {
      expect(screen, contains(title));
    }
    expect(actions, contains('NotificationPreferences.save('));
    expect(actions, contains('BuildMonitorService.refreshConfiguration()'));
    expect(notifications, contains('cancelAllOptional()'));
    expect(notifications.contains('cancelAll();'), isFalse);
    final kotlin = File('android/app/src/main/kotlin/br/com/githubmanager/app/MainActivity.kt').readAsStringSync();
    expect(kotlin, contains('clearOptionalNotifications'));
    expect(kotlin, contains('active.notification.channelId in optionalChannels'));
    expect(notifications, contains('notifyDownloaded'));
    expect(notifications, contains('notifyDownloadError'));
  });
}
