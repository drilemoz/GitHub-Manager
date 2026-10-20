import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/notifications/notification_preferences.dart';

void main() {
  test('notificações opcionais ficam desligadas por padrão', () {
    const preferences = NotificationPreferences();
    expect(preferences.enabled, false);
    expect(preferences.watchBuilds, false);
    expect(preferences.notifyDownloaded, false);
    expect(preferences.notifyDownloadError, false);
    expect(preferences.acceptsBuild('success'), false);
  });

  test('categorias de builds e downloads são independentes', () {
    final preferences = const NotificationPreferences().copyWith(
      enabled: true,
      buildSuccess: false,
      buildProblems: true,
      downloadSuccess: false,
      downloadProblems: true,
    );
    expect(preferences.acceptsBuild('success'), false);
    expect(preferences.acceptsBuild('failure'), true);
    expect(preferences.acceptsBuild('timed_out'), true);
    expect(preferences.notifyDownloaded, false);
    expect(preferences.notifyDownloadError, true);
    expect(preferences.copyWith(enabled: false).watchBuilds, false);
  });

  test('desabilitar ambas as categorias de build suspende o monitor', () {
    final preferences = const NotificationPreferences().copyWith(
      enabled: true,
      buildSuccess: false,
      buildProblems: false,
    );
    expect(preferences.watchBuilds, false);
    expect(preferences.notifyDownloaded, true);
  });
}
