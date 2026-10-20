import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/core/notifications/app_notification_service.dart';
import 'package:github_manager/core/notifications/notification_preferences.dart';
import 'package:github_manager/core/persistence/local_database.dart';
import 'package:github_manager/core/security/secure_storage_service.dart';
import 'package:github_manager/core/telemetry/app_telemetry_service.dart';
import 'package:github_manager/features/repositories/data/repository_service.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';
import 'package:workmanager/workmanager.dart';

const _buildMonitorTask = 'github_manager_build_monitor';
const _buildMonitorUniqueName = 'github_manager_build_monitor_periodic';
const _buildMonitorTag = 'github_manager_build_monitor_tag';
const _startedAtKey = 'notifications.build_monitor_started_at';
const _notifiedRunsKey = 'notifications.notified_run_ids';
const _migratedKey = 'notifications.ledger_migrated';
const _maxNotificationAge = Duration(hours: 2);
const _watchedRepositoriesKey = 'notifications.watched_repositories';

@pragma('vm:entry-point')
void buildMonitorCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != _buildMonitorTask) {
      return true;
    }
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      return await BuildMonitorService.runBackgroundCheck();
    } catch (error, stackTrace) {
      await AppTelemetryService.instance.recordError(
        source: 'background.build_monitor',
        error: error,
        stackTrace: stackTrace,
      );
      // Uma falha transitória não deve desativar o monitor.
      return true;
    }
  });
}

class BuildMonitorService {
  BuildMonitorService._();

  static LocalDatabase get _database => LocalDatabase.shared;

  static Timer? _fastPollTimer;
  static bool _fastCheckRunning = false;

  static Future<void> initialize() async {
    await Workmanager().initialize(buildMonitorCallbackDispatcher);
    await AppNotificationService.initialize();
  }

  static Future<void> ensureDefaultEnabled() async {
    // Preferências opcionais são opt-in. Instalações antigas deixam de receber
    // avisos por padrão até o usuário escolher o que deseja em Configurações.
    await refreshConfiguration();
  }

  static Future<bool> isEnabled() async =>
      (await NotificationPreferences.read()).watchBuilds;

  /// Mantido para pontos de integração legados: só altera categorias de build.
  static Future<bool> setEnabled(bool enabled) async {
    final old = await NotificationPreferences.read();
    if (enabled && !await requestPermission()) return false;
    await NotificationPreferences.save(old.copyWith(
      enabled: enabled ? true : old.enabled,
      buildSuccess: enabled,
      buildProblems: enabled,
    ));
    await refreshConfiguration();
    return enabled;
  }

  static Future<void> refreshConfiguration() async {
    final policy = await NotificationPreferences.read();
    if (!policy.watchBuilds) {
      await Workmanager().cancelByUniqueName(_buildMonitorUniqueName);
      _stopFastPolling();
      if (!policy.enabled) {
        await AppNotificationService.cancelAllOptional();
      }
      return;
    }
    await _database.putJson(_startedAtKey, DateTime.now().millisecondsSinceEpoch);
    await _register();
    _startFastPolling();
  }

  static Future<bool> requestPermission() =>
      AppNotificationService.requestPermission();

  static Future<void> _register() =>
      Workmanager().registerPeriodicTask(
        _buildMonitorUniqueName,
        _buildMonitorTask,
        tag: _buildMonitorTag,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
      );

  static Future<void> watchRepository(String fullName) async {
    final value = fullName.trim();
    if (value.isEmpty) return;
    final raw = await _database.readJson(_watchedRepositoriesKey);
    final items = <String>[
      value,
      if (raw is List)
        ...raw.whereType<String>().where(
              (item) => item.toLowerCase() != value.toLowerCase(),
            ),
    ].take(12).toList(growable: false);
    await _database.putJson(_watchedRepositoriesKey, items);
    if (await isEnabled()) {
      _startFastPolling();
      unawaited(_runFastCheck());
    }
  }

  static Future<bool> runBackgroundCheck({int maxRepositories = 30}) async {
    final database = _database;
    final preferences = await NotificationPreferences.read(database: database);
    if (!preferences.watchBuilds) return true;

    final startedRaw = await database.readJson(_startedAtKey);
    final startedAt = startedRaw is int
        ? startedRaw
        : DateTime.now().millisecondsSinceEpoch;
    if (startedRaw is! int) {
      await database.putJson(_startedAtKey, startedAt);
    }

    // Protege usuários de versões anteriores: jamais republicar uma build que
    // já foi registrada na lista legada, ainda que o monitor reinicie.
    if (await database.readJson(_migratedKey) != true) {
      final legacy = await database.readJson(_notifiedRunsKey);
      if (legacy is List) {
        await database.migrateLegacyBuildIds(
          legacy.whereType<num>().map((v) => v.toInt()),
        );
      }
      await database.putJson(_migratedKey, true);
    }

    final secureStorage = SecureStorageService();
    if (!await secureStorage.hasGitHubToken()) return true;

    final client = GitHubApiClient(secureStorage);
    final repositoryService = RepositoryService(client, database);
    final repositories = await repositoryService.listRepositories();
    final watchedRaw = await database.readJson(_watchedRepositoriesKey);
    final watched = watchedRaw is List
        ? watchedRaw.whereType<String>().map((item) => item.toLowerCase()).toList()
        : const <String>[];
    final byName = {
      for (final repository in repositories)
        repository.fullName.toLowerCase(): repository,
    };
    final ordered = [
      for (final name in watched)
        if (byName[name] != null) byName[name]!,
      ...repositories.where(
        (repository) => !watched.contains(repository.fullName.toLowerCase()),
      ),
    ];
    final earliest = DateTime.now().subtract(_maxNotificationAge);

    for (final repository in ordered.take(maxRepositories)) {
      if (!(await NotificationPreferences.read(database: database)).watchBuilds) break;
      try {
        final response = await client.get<Map<String, dynamic>>(
          '/repos/${repository.fullName}/actions/runs',
          queryParameters: const {'per_page': 10, 'page': 1},
        );
        final rawRuns = response.data?['workflow_runs'];
        if (rawRuns is! List) continue;

        for (final raw in rawRuns.whereType<Map>()) {
          final run = Map<String, dynamic>.from(raw);
          final id = (run['id'] as num?)?.toInt();
          if (id == null || run['status'] != 'completed') continue;
          final conclusion = run['conclusion'] as String? ?? '';
          if (!const {
            'success', 'failure', 'cancelled', 'timed_out', 'action_required',
          }.contains(conclusion)) continue;

          // `updated_at` representa o último estado da execução concluída.
          // Evita notificações de eventos antigos ao reconectar ou atualizar.
          final eventAt = DateTime.tryParse(
            (run['updated_at'] ?? run['created_at']) as String? ?? '',
          );
          final createdAt = DateTime.tryParse(run['created_at'] as String? ?? '');
          if (eventAt == null || createdAt == null ||
              eventAt.isBefore(earliest) ||
              createdAt.millisecondsSinceEpoch < startedAt) continue;

          final current = await NotificationPreferences.read(database: database);
          if (!current.acceptsBuild(conclusion)) continue;

          // Reserva atômica ANTES do aviso: primeiro plano e WorkManager usam
          // a mesma tabela SQLite, sem janela de repetição entre isolates.
          if (!await database.claimBuildNotification(id)) continue;

          final workflowName =
              (run['name'] as String?)?.trim().isNotEmpty == true
                  ? run['name'] as String
                  : 'Build';
          final runNumber = (run['run_number'] as num?)?.toInt();
          await _showBuildNotification(
            id: id,
            repository: repository.fullName,
            workflowName: workflowName,
            runNumber: runNumber,
            version: RepositoryWorkflowRun.fromJson(run).detectedVersion,
            conclusion: conclusion,
            branch: run['head_branch'] as String?,
          );
          await database.markBuildNotification(id, 'sent');
        }
      } catch (_) {
        // Um repositório sem Actions/permissão não bloqueia os demais.
      }
    }
    return true;
  }

  static Future<void> _showBuildNotification({
    required int id,
    required String repository,
    required String workflowName,
    required int? runNumber,
    required String conclusion,
    String? version,
    String? branch,
  }) =>
      AppNotificationService.showBuildResult(
        id: id,
        repository: repository,
        workflowName: workflowName,
        runNumber: runNumber,
        version: version,
        conclusion: conclusion,
        branch: branch,
      );

  static void _startFastPolling() {
    if (_fastPollTimer != null) return;
    unawaited(_runFastCheck());
    _fastPollTimer = Timer.periodic(
      const Duration(seconds: 35),
      (_) => unawaited(_runFastCheck()),
    );
  }

  static void _stopFastPolling() {
    _fastPollTimer?.cancel();
    _fastPollTimer = null;
  }

  static Future<void> _runFastCheck() async {
    if (_fastCheckRunning) return;
    _fastCheckRunning = true;
    try {
      if (await isEnabled()) {
        await runBackgroundCheck(maxRepositories: 10);
      }
    } catch (_) {
      // O monitor periódico continua sendo o fallback em segundo plano.
    } finally {
      _fastCheckRunning = false;
    }
  }
}
