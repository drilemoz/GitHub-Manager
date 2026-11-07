import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:github_manager/core/background/build_monitor_service.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/features/projects/data/git_project_upload_service.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:github_manager/features/repositories/data/repository_git_service.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';
import 'package:github_manager/features/uploads/data/upload_foreground_service.dart';
import 'package:github_manager/features/uploads/data/upload_recovery_settings.dart';
import 'package:github_manager/features/uploads/domain/managed_upload.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ProjectUploadExecutor = Future<ProjectUploadResult> Function({
  required ZipProjectPreview project,
  required String repositoryFullName,
  required String branch,
  required String commitMessage,
  void Function(ProjectUploadProgress progress)? onProgress,
  required Map<String, String> reusableBlobShas,
  void Function(String path, String sha)? onBlobUploaded,
  required ProjectUploadMethod method,
  required bool allowAutomaticRecovery,
});

typedef BuildEnsureExecutor = Future<RepositoryBuildLaunchResult> Function({
  required String repositoryFullName,
  required String branch,
  required String commitSha,
  void Function(String status)? onStatus,
  required int verificationAttempts,
  required Duration verificationDelay,
  required Duration postDispatchDelay,
});

class UploadManagerService {
  UploadManagerService({
    required GitProjectUploadService uploadService,
    required RepositoryGitService gitService,
    Future<File> Function()? historyFileFactory,
    Future<Directory> Function()? queueDirectoryFactory,
    UploadForegroundController? foregroundController,
    Future<bool> Function()? automaticRecoveryEnabled,
    bool restoreHistory = true,
    Duration persistDebounce = const Duration(milliseconds: 650),
  })  : _uploadZip = (({
          required ZipProjectPreview project,
          required String repositoryFullName,
          required String branch,
          required String commitMessage,
          void Function(ProjectUploadProgress progress)? onProgress,
          required Map<String, String> reusableBlobShas,
          void Function(String path, String sha)? onBlobUploaded,
          required ProjectUploadMethod method,
          required bool allowAutomaticRecovery,
        }) =>
            uploadService.uploadZip(
              project: project,
              repositoryFullName: repositoryFullName,
              branch: branch,
              commitMessage: commitMessage,
              onProgress: onProgress,
              reusableBlobShas: reusableBlobShas,
              onBlobUploaded: onBlobUploaded,
              method: method,
              allowAutomaticRecovery: allowAutomaticRecovery,
            )),
        _ensureBuild = (({
          required String repositoryFullName,
          required String branch,
          required String commitSha,
          void Function(String status)? onStatus,
          required int verificationAttempts,
          required Duration verificationDelay,
          required Duration postDispatchDelay,
        }) =>
            gitService.ensureBuildForCommit(
              repositoryFullName: repositoryFullName,
              branch: branch,
              commitSha: commitSha,
              onStatus: onStatus,
              verificationAttempts: verificationAttempts,
              verificationDelay: verificationDelay,
              postDispatchDelay: postDispatchDelay,
            )),
        _historyFileFactory = historyFileFactory,
        _queueDirectoryFactory = queueDirectoryFactory,
        _foregroundController = foregroundController ??
            PlatformUploadForegroundController(),
        _automaticRecoveryEnabled = automaticRecoveryEnabled ??
            (() => UploadRecoverySettings.isAutomaticRecoveryEnabled()),
        _persistDebounce = persistDebounce,
        _runBackgroundQueue = true,
        _requireZipFingerprint = true {
    if (restoreHistory) {
      unawaited(_restoreHistory());
    } else {
      _restoreCompleter.complete();
    }
  }

  UploadManagerService.forTest({
    required ProjectUploadExecutor uploadZip,
    required BuildEnsureExecutor ensureBuild,
    Future<File> Function()? historyFileFactory,
    Future<Directory> Function()? queueDirectoryFactory,
    UploadForegroundController? foregroundController,
    Future<bool> Function()? automaticRecoveryEnabled,
    bool restoreHistory = false,
    Duration persistDebounce = Duration.zero,
    bool runBackgroundQueue = true,
  })  : _uploadZip = uploadZip,
        _ensureBuild = ensureBuild,
        _historyFileFactory = historyFileFactory,
        _queueDirectoryFactory = queueDirectoryFactory,
        _foregroundController = foregroundController,
        _automaticRecoveryEnabled =
            automaticRecoveryEnabled ?? (() async => true),
        _persistDebounce = persistDebounce,
        _runBackgroundQueue = runBackgroundQueue,
        _requireZipFingerprint = false {
    if (restoreHistory) {
      unawaited(_restoreHistory());
    } else {
      _restoreCompleter.complete();
    }
  }

  final ProjectUploadExecutor _uploadZip;
  final BuildEnsureExecutor _ensureBuild;
  final Future<File> Function()? _historyFileFactory;
  final Future<Directory> Function()? _queueDirectoryFactory;
  final UploadForegroundController? _foregroundController;
  final Future<bool> Function() _automaticRecoveryEnabled;
  final Duration _persistDebounce;
  final bool _runBackgroundQueue;
  final bool _requireZipFingerprint;
  final _controller = StreamController<List<ManagedUpload>>.broadcast();
  final Completer<void> _restoreCompleter = Completer<void>();
  final List<ManagedUpload> _items = [];
  final List<_QueuedUploadTask> _queue = [];
  Timer? _persistTimer;
  Timer? _foregroundTimer;
  Future<void> _persistTail = Future<void>.value();
  Completer<void>? _idleCompleter;
  bool _running = false;
  bool _foregroundWasActive = false;
  bool _disposed = false;
  int _sequence = 0;

  Stream<List<ManagedUpload>> get stream => _controller.stream;
  List<ManagedUpload> get items => List.unmodifiable(_items);
  int get activeCount => _items.where((item) => item.isActive).length;
  Future<void> get ready => _restoreCompleter.future;

  ManagedUpload startBuild({
    required ZipProjectPreview project,
    required String repositoryFullName,
    required String branch,
    ManagedUploadBuildPolicy buildPolicy = ManagedUploadBuildPolicy.automatic,
  }) {
    if (_requireZipFingerprint && (project.sha256 == null || project.sha256!.isEmpty)) {
      throw const InvalidZipException(
        'O ZIP não foi verificado. Selecione novamente antes de enviar.',
        code: 'UPLOAD_ZIP_UNVERIFIED',
      );
    }
    final duplicate = _items.where((item) => item.isActive).firstWhereOrNull(
          (item) =>
              item.repositoryFullName == repositoryFullName &&
              item.branch == branch &&
              item.sourceZipPath == project.path,
        );
    if (duplicate != null) {
      duplicate.addLog('Tentativa duplicada ignorada; o envio já está ativo');
      _emit();
      return duplicate;
    }

    final item = ManagedUpload(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      repositoryFullName: repositoryFullName,
      branch: branch,
      zipPath: project.path,
      sourceZipPath: project.path,
      zipName: project.name,
      projectName: project.identityLabel,
      projectType: project.projectType,
      archiveBytes: project.archiveBytes,
      archiveSha256: project.sha256,
      uncompressedBytes: project.uncompressedBytes,
      fileCount: project.fileCount,
      folderCount: project.folderCount,
      importantFiles: List<String>.from(project.importantFiles),
      commonRoot: project.commonRoot,
      packageName: project.packageName,
      applicationId: project.applicationId,
      version: project.version,
      versionCode: project.versionCode,
      buildPolicy: buildPolicy,
      status: ManagedUploadStatus.queued,
      createdAt: DateTime.now(),
      total: project.fileCount,
    )..addLog('Envio adicionado à fila');

    _items.insert(0, item);
    _emit();

    // Seam exclusivo do construtor forTest. Testes de interface precisam
    // validar que o fluxo escolheu branch/política corretas, mas não devem
    // iniciar cópia de ZIP e persistência em disco dentro do FakeAsync do
    // testWidgets. Os testes unitários do gerenciador mantêm o padrão `true`
    // e continuam exercitando a fila real completa.
    if (!_runBackgroundQueue) {
      return item;
    }

    _queue.add(
      _QueuedUploadTask(
        item.id,
        buildOnly: false,
        method: ProjectUploadMethod.incremental,
      ),
    );
    _schedulePersist();
    unawaited(_drainQueue());
    return item;
  }

  ManagedUpload? find(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> retry(String id) async {
    final item = find(id);
    if (item == null || item.isActive || !item.canRetry) return;
    final buildOnly = item.failureStage == 'build' &&
        item.commitSha != null &&
        item.commitSha!.isNotEmpty;
    final recommended = item.recommendedRecoveryMethod;
    final method = buildOnly
        ? item.uploadMethod
        : (recommended ?? item.uploadMethod);
    await _queueRetry(
      item,
      buildOnly: buildOnly,
      method: method,
      allowAutomaticRecovery: !buildOnly,
      reason: recommended != null && recommended != item.uploadMethod
          ? 'Recuperação recomendada selecionada: ${recommended.label}'
          : null,
    );
  }

  Future<void> retrySameMethod(String id) async {
    final item = find(id);
    if (item == null || item.isActive || !item.canRetry) return;
    final buildOnly = item.failureStage == 'build' &&
        item.commitSha != null &&
        item.commitSha!.isNotEmpty;
    await _queueRetry(
      item,
      buildOnly: buildOnly,
      method: item.uploadMethod,
      allowAutomaticRecovery: false,
      reason: buildOnly
          ? 'Repetindo a inicialização da build'
          : 'Repetindo exatamente o método ${item.uploadMethod.label}',
    );
  }

  Future<void> retryAlternative(String id) async {
    final item = find(id);
    if (item == null || item.isActive || !item.canRetry) return;
    final method = item.recommendedRecoveryMethod;
    if (method == null || method == item.uploadMethod) return;
    await _queueRetry(
      item,
      buildOnly: false,
      method: method,
      allowAutomaticRecovery: false,
      reason: 'Método alternativo solicitado: ${method.label}',
    );
  }

  Future<void> _queueRetry(
    ManagedUpload item, {
    required bool buildOnly,
    required ProjectUploadMethod method,
    required bool allowAutomaticRecovery,
    String? reason,
  }) async {
    item.resetForRetry(buildOnly: buildOnly, method: method);
    if (reason != null) item.addLog(reason);
    _queue.add(
      _QueuedUploadTask(
        item.id,
        buildOnly: buildOnly,
        method: method,
        allowAutomaticRecovery: allowAutomaticRecovery,
      ),
    );
    _emit();
    await _persistHistory();
    unawaited(_drainQueue());
  }

  Future<void> runBuildAnyway(String id) async {
    final item = find(id);
    if (item == null || item.isActive || !item.canRunBuildAnyway) return;
    item
      ..buildPolicy = ManagedUploadBuildPolicy.automatic
      ..status = ManagedUploadStatus.queued
      ..phase = 'Aguardando execução da build'
      ..completedAt = null
      ..failedAt = null
      ..errorMessage = null
      ..errorCode = null
      ..errorHttpStatus = null
      ..errorEndpoint = null
      ..errorApiMessage = null
      ..failureStage = null
      ..failureOperation = null;
    item.addLog('Execução da build solicitada mesmo sem alterações no ZIP');
    _queue.add(
      _QueuedUploadTask(
        item.id,
        buildOnly: true,
        method: item.uploadMethod,
      ),
    );
    _emit();
    await _persistHistory();
    unawaited(_drainQueue());
  }

  Future<void> removeFromHistory(String id) async {
    final item = find(id);
    if (item == null || item.isActive) return;
    _items.remove(item);
    await _deleteManagedZipIfSafe(item);
    _emit();
    await _persistHistory();
  }

  Future<void> clearFinishedHistory() async {
    final removed = _items
        .where((item) => !item.isActive)
        .toList(growable: false);
    _items.removeWhere((item) => !item.isActive);
    for (final item in removed) {
      await _deleteManagedZipIfSafe(item);
    }
    _emit();
    await _persistHistory();
  }

  Future<void> waitUntilIdle() async {
    await ready;
    while (!_disposed && (_running || _queue.isNotEmpty)) {
      final idle = _idleCompleter;
      if (idle != null && !idle.isCompleted) {
        await idle.future;
        continue;
      }

      // A fila pode ter sido preenchida imediatamente antes de _drainQueue()
      // assumir a execução. Ceder uma microtask é suficiente e, ao contrário
      // de Future.delayed/Timer, funciona também dentro do FakeAsync usado por
      // testWidgets.
      await Future<void>.value();
    }
    await _flushScheduledPersistence();
  }

  Future<void> _drainQueue() async {
    if (_running || _disposed) return;
    _running = true;
    final idle = Completer<void>();
    _idleCompleter = idle;
    try {
      while (_queue.isNotEmpty && !_disposed) {
        final task = _queue.removeAt(0);
        final item = find(task.id);
        if (item == null || !item.isActive) continue;
        await _runItem(
          item,
          buildOnly: task.buildOnly,
          continueBuildOnNoChanges: task.continueBuildOnNoChanges,
          method: task.method,
          allowAutomaticRecovery: task.allowAutomaticRecovery,
        );
      }
    } finally {
      _running = false;
      if (!idle.isCompleted) {
        idle.complete();
      }
      if (identical(_idleCompleter, idle)) {
        _idleCompleter = null;
      }
    }
  }

  Future<void> _runItem(
    ManagedUpload item, {
    required bool buildOnly,
    required bool continueBuildOnNoChanges,
    required ProjectUploadMethod method,
    required bool? allowAutomaticRecovery,
  }) async {
    if (buildOnly) {
      if (!item.shouldStartBuild) {
        await _completeWithoutBuild(item);
        return;
      }
      await _runBuild(item);
      return;
    }

    var automaticRecovery = allowAutomaticRecovery ?? true;
    if (allowAutomaticRecovery == null) {
      try {
        automaticRecovery = await _automaticRecoveryEnabled();
      } catch (_) {
        automaticRecovery = true;
        item.addLog(
          'Não foi possível ler a preferência de recuperação; usando o padrão seguro ativado',
        );
      }
    }
    item.uploadMethod = method;
    item.addLog(
      'Método selecionado: ${method.label} • recuperação automática ${automaticRecovery ? 'ativada' : 'desativada'}',
    );

    item
      ..status = ManagedUploadStatus.syncing
      ..startedAt = DateTime.now()
      ..phase = 'Preparando cópia segura do ZIP'
      ..current = 0
      ..total = item.fileCount
      ..currentFile = null;
    item.resetFileSummary();
    item.addLog('Preparando arquivo durável para o envio');
    _emit();
    await _persistHistory();

    try {
      if (_requireZipFingerprint &&
          (item.archiveSha256 == null || item.archiveSha256!.isEmpty)) {
        throw const InvalidZipException(
          'Envio antigo sem impressão digital do ZIP. Selecione o projeto novamente.',
          code: 'UPLOAD_ZIP_LEGACY_UNVERIFIED',
        );
      }
      await _prepareDurableZip(item);
      item.phase = 'Preparando sincronização';
      item.addLog('Sincronização iniciada');
      _emit();
      await _persistHistory();

      final result = await _uploadZip(
        project: item.toProjectPreview(),
        repositoryFullName: item.repositoryFullName,
        branch: item.branch,
        commitMessage: '',
        reusableBlobShas: Map<String, String>.from(item.uploadedBlobShas),
        onBlobUploaded: (path, sha) {
          item.uploadedBlobShas[path] = sha;
          _emit();
          unawaited(_persistHistory());
        },
        method: method,
        allowAutomaticRecovery: automaticRecovery,
        onProgress: (progress) {
          item
            ..status = ManagedUploadStatus.syncing
            ..phase = progress.phase
            ..current = progress.current
            ..total = progress.total > 0 ? progress.total : item.fileCount
            ..currentFile = progress.fileName;
          item.recordProgress(progress);
          if (!progress.isFileActivity) {
            item.addLog(progress.phase);
          }
          _emit();
          _schedulePersist();
        },
      );
      final resolvedCommitCount = result.commitCount > item.fallbackCommitCount
          ? result.commitCount
          : item.fallbackCommitCount;
      item
        ..commitSha = result.commitSha
        ..changed = result.changed
        ..uploadMethod = result.method
        ..fallbackCommitCount = resolvedCommitCount
        ..current = item.fileCount
        ..total = item.fileCount
        ..currentFile = null;
      item.uploadedBlobShas.clear();
      item.addLog('Checkpoint do commit salvo em disco');
      _emit();
      await _persistHistory();

      if (!result.changed) {
        if (continueBuildOnNoChanges && item.shouldStartBuild) {
          item.addLog(
            'Retomada confirmou o commit atual; continuando para a build',
          );
          _emit();
          await _persistHistory();
          await _runBuild(item);
          return;
        }
        item
          ..status = ManagedUploadStatus.noChanges
          ..phase = 'Projeto já está atualizado'
          ..completedAt = DateTime.now();
        item.addLog('Nenhuma alteração encontrada; nenhum commit foi criado');
        _emit();
        await _persistHistory();
        await _deleteManagedZipIfSafe(item);
        return;
      }

      item.addLog('Projeto sincronizado no commit ${_shortSha(result.commitSha)}');
      if (!item.shouldStartBuild) {
        await _completeWithoutBuild(item);
        return;
      }
      await _runBuild(item);
    } catch (error) {
      await _fail(item, error, stage: 'upload');
    }
  }

  Future<void> _completeWithoutBuild(ManagedUpload item) async {
    final noWorkflow =
        item.buildPolicy == ManagedUploadBuildPolicy.skipNoWorkflow;
    item
      ..workflowName = null
      ..workflowPath = null
      ..workflowRunId = null
      ..dispatchTriggered = false
      ..status = ManagedUploadStatus.completed
      ..phase = noWorkflow
          ? 'Projeto atualizado • Sem workflow de build'
          : 'Projeto atualizado • Build não solicitada'
      ..completedAt = DateTime.now()
      ..failedAt = null
      ..errorMessage = null
      ..errorCode = null
      ..errorHttpStatus = null
      ..errorEndpoint = null
      ..errorApiMessage = null
      ..failureStage = null
      ..failureOperation = null;
    item.addLog(
      noWorkflow
          ? 'Projeto sincronizado sem build porque esta branch não utiliza workflow de APK.'
          : 'Projeto sincronizado sem iniciar build por escolha do usuário.',
    );
    _emit();
    await _persistHistory();
    await _deleteManagedZipIfSafe(item);
  }

  Future<void> _runBuild(ManagedUpload item) async {
    final commitSha = item.commitSha;
    if (commitSha == null || commitSha.isEmpty) {
      await _fail(
        item,
        const RepositoryFileException(
          'Não há commit válido para iniciar a build.',
          code: 'UPLOAD_BUILD_COMMIT_MISSING',
        ),
        stage: 'build',
      );
      return;
    }

    item
      ..status = ManagedUploadStatus.startingBuild
      ..phase = 'Confirmando o disparo da build'
      ..current = item.fileCount
      ..total = item.fileCount
      ..currentFile = null;
    item.addLog('Verificando a build do commit ${_shortSha(commitSha)}');
    _emit();
    _schedulePersist();

    try {
      try {
        await BuildMonitorService.watchRepository(item.repositoryFullName);
      } catch (_) {
        // O monitor de notificações é auxiliar: uma falha local não pode
        // impedir que a build real seja localizada ou iniciada no GitHub.
        item.addLog('Monitoramento de build indisponível; continuando normalmente');
      }
      final launch = await _ensureBuild(
        repositoryFullName: item.repositoryFullName,
        branch: item.branch,
        commitSha: commitSha,
        onStatus: (status) {
          item.phase = status;
          item.addLog(status);
          _emit();
          _schedulePersist();
        },
        verificationAttempts: 5,
        verificationDelay: const Duration(seconds: 2),
        postDispatchDelay: const Duration(seconds: 2),
      );
      item
        ..workflowName = launch.workflow?.name
        ..workflowPath = launch.workflow?.path
        ..workflowRunId = launch.workflowRunId ??
            (launch.runs.isNotEmpty ? launch.runs.first.id : null)
        ..dispatchTriggered = launch.dispatchTriggered
        ..status = ManagedUploadStatus.completed
        ..phase = launch.dispatchTriggered
            ? 'Projeto atualizado • Build iniciada manualmente'
            : 'Projeto atualizado • Build iniciada'
        ..completedAt = DateTime.now()
        ..failedAt = null
        ..errorMessage = null
        ..errorCode = null
        ..errorHttpStatus = null
        ..errorEndpoint = null
        ..errorApiMessage = null
        ..failureStage = null
        ..failureOperation = null;
      item.addLog(item.phase);
      _emit();
      await _persistHistory();
      await _deleteManagedZipIfSafe(item);
    } catch (error) {
      final appError = error is AppException ? error : null;
      if (appError?.technicalCode == 'APK_WORKFLOW_NOT_FOUND') {
        item
          ..buildPolicy = ManagedUploadBuildPolicy.skipNoWorkflow
          ..workflowName = null
          ..workflowPath = null
          ..workflowRunId = null
          ..dispatchTriggered = false
          ..status = ManagedUploadStatus.completed
          ..phase = 'Projeto atualizado • Sem workflow de build'
          ..completedAt = DateTime.now()
          ..failedAt = null
          ..errorMessage = null
          ..errorCode = null
          ..errorHttpStatus = null
          ..errorEndpoint = null
          ..errorApiMessage = null
          ..failureStage = null
          ..failureOperation = null;
        item.addLog(
          'Nenhum workflow de APK detectado nesta branch; envio concluído sem build.',
        );
        _emit();
        await _persistHistory();
        await _deleteManagedZipIfSafe(item);
        return;
      }
      await _fail(item, error, stage: 'build');
    }
  }

  Future<void> _fail(
    ManagedUpload item,
    Object error, {
    required String stage,
  }) async {
    final appError = error is AppException ? error : null;
    final failedFile = item.currentFile;
    final failedOperation = item.phase.trim();

    // Depois que um commit válido já foi publicado, uma falha ao localizar ou
    // iniciar o GitHub Actions não significa que o envio falhou. Mantemos o
    // commit como checkpoint e mostramos um estado de atenção que pode ser
    // rechecado sem reenviar o ZIP.
    if (stage == 'build' && item.commitSha?.isNotEmpty == true) {
      item
        ..status = ManagedUploadStatus.buildPending
        ..failedAt = DateTime.now()
        ..phase = 'Projeto enviado • Build não iniciada'
        ..errorMessage = appError?.message ?? 'Não foi possível iniciar a build.'
        ..errorCode = appError?.technicalCode ?? error.runtimeType.toString()
        ..errorHttpStatus = appError?.httpStatus
        ..errorEndpoint = appError?.endpoint
        ..errorApiMessage = appError?.apiMessage
        ..failureStage = stage
        ..failureOperation = failedOperation.isEmpty ? null : failedOperation
        ..failedFilePath = failedFile
        ..currentFile = null;
      if (failedOperation.isNotEmpty) {
        item.addLog('Build pendente após: $failedOperation');
      }
      item.addLog('Projeto enviado; build pendente: ${item.errorMessage}');
      _emit();
      await _persistHistory();
      await _deleteManagedZipIfSafe(item);
      return;
    }

    item
      ..status = ManagedUploadStatus.failed
      ..failedAt = DateTime.now()
      ..phase = stage == 'build' ? 'Falha ao iniciar a build' : 'Falha no envio'
      ..errorMessage = appError?.message ?? 'Não foi possível concluir o envio.'
      ..errorCode = appError?.technicalCode ?? error.runtimeType.toString()
      ..errorHttpStatus = appError?.httpStatus
      ..errorEndpoint = appError?.endpoint
      ..errorApiMessage = appError?.apiMessage
      ..failureStage = stage
      ..failureOperation = failedOperation.isEmpty ? null : failedOperation
      ..failedFilePath = failedFile
      ..currentFile = null;
    if (failedOperation.isNotEmpty) {
      item.addLog('Falha durante: $failedOperation');
    }
    item.addLog('${item.phase}: ${item.errorMessage}');
    if (appError?.httpStatus != null || appError?.apiMessage?.isNotEmpty == true) {
      item.addLog(
        [
          if (appError?.httpStatus != null) 'HTTP ${appError!.httpStatus}',
          if (appError?.apiMessage?.isNotEmpty == true) appError!.apiMessage!,
        ].join(' • '),
      );
    }
    _emit();
    await _persistHistory();
  }

  Future<void> _restoreHistory() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) {
        _emit();
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      final restored = decoded
          .whereType<Map>()
          .map((raw) => ManagedUpload.fromJson(Map<String, dynamic>.from(raw)))
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false);

      final liveItems = List<ManagedUpload>.from(_items);
      final liveIds = liveItems.map((item) => item.id).toSet();
      final liveKeys = liveItems
          .where((item) => item.isActive)
          .map(_uploadIdentityKey)
          .toSet();
      final acceptedRestored = <ManagedUpload>[];

      for (final item in restored) {
        if (liveIds.contains(item.id)) continue;
        if (item.isActive && liveKeys.contains(_uploadIdentityKey(item))) {
          continue;
        }
        if (item.isActive) {
          final buildOnly = item.hasBuildCheckpoint;
          final canResume = buildOnly ||
              await File(item.zipPath).exists() ||
              await File(item.sourceZipPath).exists();
          if (canResume) {
            item.prepareAutomaticResume(buildOnly: buildOnly);
            _queue.add(
              _QueuedUploadTask(
                item.id,
                buildOnly: buildOnly,
                continueBuildOnNoChanges: !buildOnly,
                method: item.uploadMethod,
              ),
            );
          } else {
            item.markInterruptedByAppExit();
            item.errorMessage =
                'O ZIP original não está mais disponível. Selecione o projeto novamente para continuar.';
            item.errorCode = 'UPLOAD_ZIP_MISSING_AFTER_RESTART';
          }
        }
        acceptedRestored.add(item);
      }

      final merged = <ManagedUpload>[
        ...liveItems,
        ...acceptedRestored,
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _items
        ..clear()
        ..addAll(merged);
      _emit();
      await _persistHistory();
      if (_queue.isNotEmpty) {
        unawaited(_drainQueue());
      }
    } catch (_) {
      // O histórico é auxiliar e nunca deve bloquear o aplicativo.
    } finally {
      if (!_restoreCompleter.isCompleted) {
        _restoreCompleter.complete();
      }
    }
  }

  void _schedulePersist() {
    if (_disposed) return;
    _persistTimer?.cancel();
    _persistTimer = null;

    if (_persistDebounce.inMicroseconds <= 0) {
      unawaited(_persistHistory());
      return;
    }

    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(_persistHistory());
    });
  }

  Future<void> _flushScheduledPersistence() async {
    final timer = _persistTimer;
    if (timer != null) {
      timer.cancel();
      _persistTimer = null;
      await _persistHistory();
    }
    await _persistTail;
  }

  Future<void> _persistHistory() {
    final payload = jsonEncode(
      _items.take(80).map((item) => item.toJson()).toList(growable: false),
    );
    _persistTail = _persistTail.then((_) async {
      try {
        final file = await _historyFile();
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(payload, flush: true);
        try {
          await temporary.rename(file.path);
        } on FileSystemException {
          if (await file.exists()) {
            await file.delete();
          }
          await temporary.rename(file.path);
        }
      } catch (_) {
        // Falha de histórico não invalida um envio em andamento.
      }
    });
    return _persistTail;
  }

  Future<void> _prepareDurableZip(ManagedUpload item) async {
    final directory = await _queueDirectory();
    await directory.create(recursive: true);
    final destination = File(
      p.join(directory.path, '${_safeFileToken(item.id)}.zip'),
    );
    final expectedSha = item.archiveSha256;

    Future<bool> matches(File file) async {
      if (!await file.exists() || await file.length() != item.archiveBytes) {
        return false;
      }
      return expectedSha == null ||
          await LocalProjectService.sha256OfFile(file) == expectedSha;
    }

    if (item.zipPath == destination.path && await matches(destination)) {
      return;
    }
    if (await matches(destination)) {
      item.zipPath = destination.path;
      await LocalProjectService.discardPreviewPath(item.sourceZipPath);
      item.addLog('Cópia do ZIP restaurada e integridade conferida');
      return;
    }
    if (await destination.exists()) await destination.delete();

    var source = File(item.zipPath);
    if (!await source.exists() && item.sourceZipPath != item.zipPath) {
      source = File(item.sourceZipPath);
    }
    if (!await source.exists()) {
      throw const InvalidZipException(
        'O ZIP original não está mais disponível. Selecione novamente.',
        code: 'UPLOAD_ZIP_MISSING',
      );
    }
    if (!await matches(source)) {
      throw const InvalidZipException(
        'O conteúdo do ZIP não corresponde ao arquivo aprovado. Envio interrompido.',
        code: 'UPLOAD_ZIP_HASH_MISMATCH',
      );
    }

    final temporary = File('${destination.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    try {
      await source.copy(temporary.path);
      if (!await matches(temporary) || !await matches(source)) {
        throw const InvalidZipException(
          'A cópia do ZIP está diferente do arquivo aprovado. Nada foi enviado.',
          code: 'UPLOAD_ZIP_COPY_INVALID',
        );
      }
      await temporary.rename(destination.path);
    } on InvalidZipException {
      rethrow;
    } on FileSystemException {
      throw const InvalidZipException(
        'Não foi possível preparar a cópia íntegra do ZIP. Verifique o armazenamento.',
        code: 'UPLOAD_ZIP_COPY_FAILED',
      );
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    item.zipPath = destination.path;
    await LocalProjectService.discardPreviewPath(item.sourceZipPath);
    item.addLog('Cópia segura do ZIP confirmada por SHA-256');
  }

  Future<Directory> _queueDirectory() async {
    final custom = _queueDirectoryFactory;
    if (custom != null) return custom();
    final root = await getApplicationSupportDirectory();
    return Directory(p.join(root.path, 'upload_queue'));
  }

  Future<void> _deleteManagedZipIfSafe(ManagedUpload item) async {
    if (item.zipPath == item.sourceZipPath) return;
    try {
      final file = File(item.zipPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Limpeza de cache não altera o resultado do envio.
    }
  }

  Future<File> _historyFile() async {
    final custom = _historyFileFactory;
    if (custom != null) return custom();
    final root = await getApplicationSupportDirectory();
    return File(p.join(root.path, 'uploads_history.json'));
  }

  void _emit() {
    if (!_disposed) {
      _controller.add(List<ManagedUpload>.unmodifiable(_items));
      _scheduleForegroundSync();
    }
  }

  void _scheduleForegroundSync() {
    final controller = _foregroundController;
    if (controller == null || _disposed) return;
    final hasActive = _items.any((item) => item.isActive);
    if (hasActive != _foregroundWasActive) {
      _foregroundWasActive = hasActive;
      _foregroundTimer?.cancel();
      unawaited(_syncForeground());
      return;
    }
    if (!hasActive) return;
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_syncForeground());
    });
  }

  Future<void> _syncForeground() async {
    final controller = _foregroundController;
    if (controller == null || _disposed) return;
    final active = _items.where((item) => item.isActive).toList(growable: false);
    if (active.isEmpty) {
      await controller.stop();
      return;
    }
    final current = active.firstWhereOrNull(
          (item) => item.status != ManagedUploadStatus.queued,
        ) ??
        active.first;
    await controller.show(upload: current, activeCount: active.length);
  }

  String _safeFileToken(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'upload' : safe;
  }

  String _uploadIdentityKey(ManagedUpload item) =>
      '${item.repositoryFullName}|${item.branch}|${item.sourceZipPath}';

  String _shortSha(String sha) => sha.length > 7 ? sha.substring(0, 7) : sha;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _foregroundTimer?.cancel();
    _foregroundTimer = null;

    await _flushScheduledPersistence();
    try {
      await _foregroundController?.stop();
    } catch (_) {
      // Encerrar o serviço de foreground é best-effort durante o dispose.
    }
    await _controller.close();
  }
}

class _QueuedUploadTask {
  const _QueuedUploadTask(
    this.id, {
    required this.buildOnly,
    required this.method,
    this.continueBuildOnNoChanges = false,
    this.allowAutomaticRecovery,
  });

  final String id;
  final bool buildOnly;
  final ProjectUploadMethod method;
  final bool continueBuildOnNoChanges;
  final bool? allowAutomaticRecovery;
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
