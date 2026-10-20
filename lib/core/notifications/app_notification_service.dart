import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:github_manager/core/notifications/notification_destination.dart';
import 'package:github_manager/core/notifications/notification_preferences.dart';
import 'package:github_manager/core/platform/platform_actions.dart';

abstract final class AppNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static Future<void>? _initialization;
  static void Function(String payload)? onNotificationTapped;

  static void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      onNotificationTapped?.call(payload);
    }
  }

  static Future<String?> initialLaunchPayload() async {
    await initialize();
    final details = await _notifications.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return details?.notificationResponse?.payload;
  }

  static Future<void> initialize() => _initialization ??= _initializePlugin();

  static Future<void> _initializePlugin() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_github_manager'),
      );
      await _notifications.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  static Future<bool> requestPermission() async {
    try {
      await initialize();
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final result = await android?.requestNotificationsPermission();
      return result ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Remove apenas avisos locais opcionais, sem encerrar serviços Android
  /// foreground que sustentam transferências em andamento.
  static Future<void> cancelAllOptional() async {
    try {
      await PlatformActions.clearOptionalNotifications();
    } catch (_) {}
  }

  static Future<void> cancelBuild(int id) async {
    try {
      await initialize();
      await _notifications.cancel(id: id & 0x7fffffff);
    } catch (_) {}
  }

  static Future<void> showBuildResult({
    required int id,
    required String repository,
    required String workflowName,
    required int? runNumber,
    required String conclusion,
    String? version,
    String? branch,
  }) async {
    try {
      if (!(await NotificationPreferences.read()).acceptsBuild(conclusion)) return;
    } catch (_) {
      return;
    }
    await initialize();
    final (title, status) = switch (conclusion) {
      'success' => ('Build concluída ✓', 'concluída com sucesso'),
      'failure' => ('Build falhou', 'falhou'),
      'cancelled' => ('Build cancelada', 'foi cancelada'),
      'timed_out' => ('Build excedeu o tempo', 'excedeu o tempo limite'),
      _ => ('Build precisa de atenção', 'precisa de atenção'),
    };
    // Conclusões rotineiras são discretas; falhas exigem atenção.
    final success = conclusion == 'success';
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        success ? 'github_build_success' : 'github_build_alerts',
        success ? 'Builds concluídas' : 'Alertas de builds',
        channelDescription: success
            ? 'Confirmações discretas das builds concluídas.'
            : 'Falhas, cancelamentos e builds que precisam de atenção.',
        importance: success ? Importance.defaultImportance : Importance.high,
        priority: success ? Priority.defaultPriority : Priority.high,
        category: AndroidNotificationCategory.status,
      ),
    );
    final number = runNumber == null ? '' : ' • execução #$runNumber';
    final appVersion = version == null || version.trim().isEmpty
        ? '' : ' • versão provável ${version.trim()}';
    try {
      await _notifications.show(
        id: id & 0x7fffffff,
        title: title,
        body: '$repository$appVersion • $workflowName$number $status. '
            'Toque para ver a execução.',
        notificationDetails: details,
        payload: NotificationDestination.forBuild(
          repository: repository,
          runId: id,
          branch: branch,
        ),
      );
    } catch (_) {
      // Notificação nunca invalida a operação principal.
    }
  }

  static Future<void> showDownloadCompleted({
    required String id,
    required String fileName,
    required String repository,
  }) async {
    try {
      if (!(await NotificationPreferences.read()).notifyDownloaded) return;
    } catch (_) {
      return;
    }
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'github_download_completed',
        'Downloads concluídos',
        channelDescription: 'Avisos discretos de downloads finalizados.',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.status,
      ),
    );
    try {
      await _notifications.show(
        id: _stableId('download:$id'),
        title: 'Download concluído ✓',
        body: repository.trim().isEmpty
            ? '$fileName • toque para abrir na Central'
            : '$fileName • $repository • toque para abrir',
        notificationDetails: details,
        payload: NotificationDestination.forDownload(id),
      );
    } catch (_) {
      // O arquivo já foi salvo; falha visual não muda o download.
    }
  }

  static Future<void> showDownloadFailed({
    required String id,
    required String fileName,
    required String message,
  }) async {
    try {
      if (!(await NotificationPreferences.read()).notifyDownloadError) return;
    } catch (_) {
      return;
    }
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'github_download_failures',
        'Falhas de downloads',
        channelDescription: 'Falhas de download que precisam de atenção.',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
      ),
    );
    try {
      await _notifications.show(
        id: _stableId('download:$id'),
        title: 'Download com falha',
        body: '$fileName • $message • toque para ver detalhes',
        notificationDetails: details,
        payload: NotificationDestination.forDownload(id),
      );
    } catch (_) {
      // A Central de Downloads continua exibindo a falha normalmente.
    }
  }

  static int _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final code in value.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
