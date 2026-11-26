import 'dart:async';

import 'package:flutter/material.dart';
import 'package:github_manager/app/router/app_router.dart';
import 'package:github_manager/core/persistence/local_database.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/core/telemetry/app_telemetry_service.dart';
import 'package:github_manager/core/widgets/installed_version_banner.dart';
import 'package:github_manager/features/update/presentation/self_update_dialog.dart';
import 'package:github_manager/features/update/presentation/update_whats_new_screen.dart';

/// Abre as novidades somente depois que a Activity e a primeira interface
/// Flutter estão estáveis.
///
/// A tela não participa do `MaterialApp.builder`: ela é uma rota opaca comum.
/// Em reattach de um FlutterEngine já em execução, a abertura automática é
/// pulada para não disputar o ciclo de splash/reattach do Android.
class StartupUpdateCoordinator with WidgetsBindingObserver {
  StartupUpdateCoordinator._();

  static final StartupUpdateCoordinator instance = StartupUpdateCoordinator._();

  static const _lastSeenVersionKey = 'app.whats_new.last_seen_version';
  static const _settleDelay = Duration(milliseconds: 350);
  static const _platformTimeout = Duration(seconds: 2);
  static const _storageTimeout = Duration(seconds: 3);
  static const _maxReadinessRetries = 4;

  bool _started = false;
  bool _running = false;
  bool _finishedForProcess = false;
  int _readinessRetries = 0;

  /// Um toque de notificação deve priorizar o evento, não a tela de novidades.
  void suppressAutomaticForNotification() => _finishForProcess(checkForUpdate: false);

  void start() {
    if (_started || _finishedForProcess) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_attemptWhenReady());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_attemptWhenReady());
    }
  }

  Future<void> _attemptWhenReady() async {
    if (_finishedForProcess || _running) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    _running = true;
    var retryAfterAttempt = false;
    try {
      // Espera a Home completar frames próprios antes de sequer consultar se
      // as novidades precisam ser mostradas. Isso tira a troca de rota do
      // período crítico em que o Android encerra a splash nativa.
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(_settleDelay);

      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }

      ActivityLaunchState launchState;
      try {
        launchState = await PlatformActions.getActivityLaunchState().timeout(
          _platformTimeout,
        );
      } catch (error, stackTrace) {
        await AppTelemetryService.instance.recordError(
          source: 'startup.whats_new_launch_state',
          error: error,
          stackTrace: stackTrace,
        );
        retryAfterAttempt = _requestReadinessRetry();
        if (!retryAfterAttempt) _finishForProcess();
        return;
      }

      await AppTelemetryService.instance.recordInfo(
        source: 'startup.whats_new_check_started',
        message: 'Verificação automática de novidades iniciada',
        context: launchState.toTelemetryContext(),
      );

      // Um isolate preservado já passou pelo startup. Reabrir uma rota nesse
      // exato reattach pode conflitar com a nova superfície Android. A tela
      // continua disponível manualmente em Configurações.
      if (launchState.cachedEngineReattach) {
        await AppTelemetryService.instance.recordInfo(
          source: 'startup.whats_new_skipped_reattach',
          message: 'Novidades automáticas ignoradas durante reattach do engine',
          context: launchState.toTelemetryContext(),
        );
        _finishForProcess();
        return;
      }

      // onFlutterUiDisplayed é a confirmação nativa de que a FlutterView já
      // apresentou pixels. Se ainda não chegou, adiamos em vez de abrir uma
      // tela sobre uma Activity cuja splash pode estar encerrando.
      if (!launchState.flutterUiDisplayed) {
        retryAfterAttempt = _requestReadinessRetry();
        if (!retryAfterAttempt) {
          await AppTelemetryService.instance.recordInfo(
            source: 'startup.whats_new_skipped_not_ready',
            message: 'Novidades automáticas ignoradas porque a UI não estabilizou',
            context: launchState.toTelemetryContext(),
          );
          _finishForProcess();
        }
        return;
      }

      final version = await InstalledVersionBanner.versionLabel.timeout(
        _storageTimeout,
      );
      if (version == 'versão não identificada') {
        _finishForProcess();
        return;
      }

      final lastSeen = await LocalDatabase.shared
          .readJson(_lastSeenVersionKey)
          .timeout(_storageTimeout);
      if (lastSeen?.toString() == version) {
        _finishForProcess();
        return;
      }

      await AppTelemetryService.instance.recordInfo(
        source: 'startup.whats_new_needed',
        message: 'Versão atual ainda não teve as novidades confirmadas',
        context: {
          ...launchState.toTelemetryContext(),
          'version': version,
          if (lastSeen != null) 'lastSeenVersion': lastSeen.toString(),
        },
      );

      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }

      if (_finishedForProcess) return;
      final navigator = rootNavigatorKey.currentState;
      if (navigator == null) {
        retryAfterAttempt = _requestReadinessRetry();
        if (!retryAfterAttempt) _finishForProcess();
        return;
      }

      final routeResult = navigator.push<bool>(
        MaterialPageRoute<bool>(
          settings: const RouteSettings(name: 'startup-whats-new'),
          builder: (routeContext) => UpdateWhatsNewScreen(
            versionLabel: version,
            requireConfirmation: true,
            onContinue: () async {
              if (routeContext.mounted) {
                Navigator.of(routeContext).pop(true);
              }
            },
          ),
        ),
      );

      await AppTelemetryService.instance.recordInfo(
        source: 'startup.whats_new_route_opened',
        message: 'Rota opaca de novidades aberta após startup estável',
        context: {
          ...launchState.toTelemetryContext(),
          'version': version,
        },
      );

      await WidgetsBinding.instance.endOfFrame;
      await AppTelemetryService.instance.recordInfo(
        source: 'startup.whats_new_first_frame',
        message: 'Primeiro frame da rota de novidades apresentado',
        context: {'version': version},
      );

      final confirmed = await routeResult;
      if (confirmed == true) {
        await LocalDatabase.shared
            .putJson(_lastSeenVersionKey, version)
            .timeout(const Duration(seconds: 2));
        await AppTelemetryService.instance.recordInfo(
          source: 'startup.whats_new_continue',
          message: 'Novidades confirmadas pela ação Continuar',
          context: {'version': version},
        );
        _finishForProcess();
      }
    } catch (error, stackTrace) {
      await AppTelemetryService.instance.recordError(
        source: 'startup.whats_new_check',
        error: error,
        stackTrace: stackTrace,
      );
      // Novidades são auxiliares: qualquer falha deve liberar a Home e não
      // criar novas tentativas em loop durante esta execução do processo.
      _finishForProcess();
    } finally {
      _running = false;
      if (retryAfterAttempt && !_finishedForProcess) {
        unawaited(
          Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
            return _attemptWhenReady();
          }),
        );
      }
    }
  }

  bool _requestReadinessRetry() {
    _readinessRetries += 1;
    return _readinessRetries <= _maxReadinessRetries;
  }

  void _finishForProcess({bool checkForUpdate = true}) {
    if (_finishedForProcess) return;
    _finishedForProcess = true;
    WidgetsBinding.instance.removeObserver(this);
    if (checkForUpdate) unawaited(SelfUpdateCoordinator.check());
  }
}
