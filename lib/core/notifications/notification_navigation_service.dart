import 'dart:async';

import 'package:flutter/services.dart';
import 'package:github_manager/app/router/app_router.dart';
import 'package:github_manager/core/notifications/app_notification_service.dart';
import 'package:github_manager/core/notifications/notification_destination.dart';
import 'package:github_manager/core/persistence/local_database.dart';
import 'package:github_manager/features/update/application/startup_update_coordinator.dart';

/// Ponte para notificações locais e para os serviços foreground nativos.
abstract final class NotificationNavigationService {
  static const MethodChannel _platform =
      MethodChannel('br.com.githubmanager.app/notifications');
  static bool _started = false;
  static String? _lastRoute;
  static DateTime? _lastOpenAt;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _platform.setMethodCallHandler((call) async {
      if (call.method != 'notificationTapped') return;
      final destination = NotificationDestination.fromNativeRoute(
        call.arguments is String ? call.arguments as String : null,
      );
      _navigate(destination);
      // Consome também o evento nativo em memória, se ainda estiver lá.
      try {
        await _platform.invokeMethod<String>('consumeNotificationRoute');
      } catch (_) {}
    });

    AppNotificationService.onNotificationTapped = (payload) {
      _navigate(NotificationDestination.fromPayload(payload));
    };
    try {
      await AppNotificationService.initialize();
      final launchPayload = await AppNotificationService.initialLaunchPayload();
      _navigate(NotificationDestination.fromPayload(launchPayload));
    } catch (_) {
      // O app continua utilizável sem permissões de notificação.
    }
    try {
      final route =
          await _platform.invokeMethod<String>('consumeNotificationRoute');
      _navigate(NotificationDestination.fromNativeRoute(route));
    } catch (_) {
      // iOS/web ou canal indisponível.
    }
  }

  static void _navigate(NotificationDestination? destination) {
    if (destination == null) return;
    final now = DateTime.now();
    // O Android pode entregar o mesmo toque por onNewIntent + launch details.
    if (_lastRoute == destination.route && _lastOpenAt != null &&
        now.difference(_lastOpenAt!) < const Duration(seconds: 2)) return;
    _lastRoute = destination.route;
    _lastOpenAt = now;
    StartupUpdateCoordinator.instance.suppressAutomaticForNotification();
    // Abertura por toque: guarda como lida e retira o aviso local. Mesmo se o
    // usuário o dispensar pelo sistema, a reserva persistente impede repetição.
    final uri = Uri.tryParse(destination.route);
    final runId = int.tryParse(uri?.queryParameters['runId'] ?? '');
    if (runId != null && uri!.pathSegments.contains('builds')) {
      unawaited(LocalDatabase.shared.markBuildNotification(runId, 'opened')
          .catchError((Object _) {}));
      unawaited(AppNotificationService.cancelBuild(runId));
    }
    appRouter.go(destination.route);
  }
}
