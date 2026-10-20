import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/core/notifications/app_notification_service.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/apk_variant.dart';
import 'package:github_manager/features/downloads/data/download_speed_meter.dart';
import 'package:github_manager/features/downloads/data/download_cleanup_settings.dart';
import 'package:github_manager/features/downloads/domain/managed_download.dart';
import 'package:github_manager/features/downloads/domain/apk_package_inspector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DownloadManagerService {
  DownloadManagerService(this._client) {
    _historyReady = _restoreHistory();
  }

  final GitHubApiClient _client;
  late final Future<void> _historyReady;
  final Map<String, Future<void>> _projectCleanupLocks = {};
  final Set<String> _alreadyCleanedBefore = <String>{};
  final _controller = StreamController<List<ManagedDownload>>.broadcast();
  final List<ManagedDownload> _items = [];
  final Map<String, CancelToken> _cancelTokens = {};
  // Uma retomada deve aguardar o fechamento do sink da tentativa anterior.
  final Map<String, Future<void>> _operations = {};
  final Set<String> _finalizing = <String>{};
  // Links públicos com query assinada ficam apenas em memória; o histórico
  // persiste somente a URL sem parâmetros sensíveis.
  final Map<String, String> _publicSourceUrls = {};
  final Map<String, DateTime> _lastChunkAt = {};
  final Set<String> _stalledIds = <String>{};
  Timer? _stalledTimer;
  // Gravações em paralelo do histórico poderiam sobrescrever estado pausado.
  Future<void> _historyWrites = Future<void>.value();

  final Map<String, DownloadSpeedMeter> _progressSamples = {};
  DateTime? _lastForegroundUpdate;
  int _sequence = 0;

  Stream<List<ManagedDownload>> get stream => _controller.stream;
  List<ManagedDownload> get items => List.unmodifiable(_items);
  int get activeCount => _items.where((item) => item.isActive).length;
  bool isStalled(String id) => _stalledIds.contains(id);

  void _ensureStalledTimer() {
    _stalledTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      var changed = false;
      for (final item in _items) {
        if (item.status != ManagedDownloadStatus.downloading) continue;
        final last = _lastChunkAt[item.id];
        if (last == null ||
            now.difference(last) < const Duration(seconds: 15)) continue;
        if (_stalledIds.add(item.id)) changed = true;
        if (item.bytesPerSecond != 0 || item.estimatedSecondsRemaining != null) {
          item
            ..bytesPerSecond = 0
            ..estimatedSecondsRemaining = null;
          changed = true;
        }
      }
      if (changed) _emit();
    });
  }

  void _stopStalledTimerIfIdle() {
    if (_items.any((item) => item.isActive)) return;
    _stalledTimer?.cancel();
    _stalledTimer = null;
  }

  void _launch(ManagedDownload item, Future<void> Function() action) {
    final operation = action();
    _operations[item.id] = operation;
    unawaited(operation.then<void>(
      (_) {
        if (identical(_operations[item.id], operation)) {
          _operations.remove(item.id);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_operations[item.id], operation)) {
          _operations.remove(item.id);
        }
      },
    ));
  }

  Future<void> pause(String id) async {
    final item = _find(id);
    if (item == null ||
        item.status != ManagedDownloadStatus.downloading ||
        _finalizing.contains(id)) {
      return;
    }
    // Marcar antes de cancelar evita que o erro de rede vire uma falha comum.
    item.markPaused();
    _cancelTokens[id]?.cancel('Pausado pelo usuário');
    _progressSamples.remove(id);
    _lastChunkAt.remove(id);
    _stalledIds.remove(id);
    _emit();
    await _persistHistory();
    await _syncDownloadForegroundService();
  }

  Future<void> cancelPaused(String id) async {
    final item = _find(id);
    if (item == null || !item.isPaused) return;
    item
      ..status = ManagedDownloadStatus.cancelled
      ..failedAt = DateTime.now()
      ..errorMessage = 'Download cancelado pelo usuário. O arquivo parcial poderá ser reutilizado.'
      ..errorCode = 'DOWNLOAD_CANCELLED'
      ..failureStage = 'download';
    _emit();
    await _persistHistory();
  }

  Future<void> resume(String id) async {
    final item = _find(id);
    if (item == null || !item.isPaused) return;
    // O stream e o arquivo parcial precisam estar fechados antes do Range.
    final previous = _operations[id];
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // O estado pausado já foi registrado; a retomada usa o arquivo em disco.
      }
    }
    if (!item.isPaused) return;
    final endpoint = item.sourceEndpoint;
    if (endpoint == null || endpoint.isEmpty) return;
    item.resetForRetry(preserveProgress: true);
    _emit();
    await _persistHistory();
    _startExisting(item, endpoint);
  }

  void _startExisting(ManagedDownload item, String endpoint) {
    if (endpoint.startsWith('https://') || endpoint.startsWith('http://')) {
      _launch(item, () => _runDirectUrl(item, _publicSourceUrls[item.id] ?? endpoint));
    } else if (item.isApk && item.artifactId != null) {
      _launch(item, () => _runArtifactApk(
        item,
        endpoint,
        preferredAbis: item.preferredAbis.isNotEmpty
            ? item.preferredAbis
            : (item.preferredAbi?.trim().isNotEmpty == true
                ? <String>[item.preferredAbi!.trim()]
                : const <String>[]),
      ));
    } else {
      _launch(item, () => _runRedirected(item, endpoint));
    }
  }

  ManagedDownload startRepositoryZip({
    required String repositoryFullName,
    required String branch,
    required String projectName,
    String? version,
  }) {
    final safeName = _safeName(
      projectName.isEmpty ? repositoryFullName.split('/').last : projectName,
    );
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final safeVersion = version?.trim().isNotEmpty == true
        ? '-v${_safeName(version!.trim())}'
        : '';
    final fileName =
        '$safeName$safeVersion-$stamp-${_safeName(branch)}.zip';
    return _startRedirected(
      title: 'Projeto ${projectName.isEmpty ? safeName : projectName}',
      fileName: fileName,
      type: ManagedDownloadType.projectZip,
      repositoryFullName: repositoryFullName,
      endpoint:
          '/repos/$repositoryFullName/zipball/${Uri.encodeComponent(branch)}',
    );
  }

  ManagedDownload startWorkflowLogs({
    required String repositoryFullName,
    required int runId,
    required String runTitle,
  }) {
    final repositoryName = repositoryFullName.split('/').last.trim();
    final safeRepositoryName = _safeName(repositoryName);
    final safeRunTitle = _safeName(runTitle);
    final lowerRepositoryName = safeRepositoryName.toLowerCase();
    final lowerRunTitle = safeRunTitle.toLowerCase();
    final titleAlreadyIncludesRepository =
        lowerRunTitle == lowerRepositoryName ||
        lowerRunTitle.startsWith('$lowerRepositoryName-');
    final fileStem = titleAlreadyIncludesRepository
        ? safeRunTitle
        : '$safeRepositoryName-$safeRunTitle';
    return _startRedirected(
      title: 'Logs • $runTitle',
      fileName: '$fileStem-logs.zip',
      type: ManagedDownloadType.logs,
      repositoryFullName: repositoryFullName,
      endpoint: '/repos/$repositoryFullName/actions/runs/$runId/logs',
    );
  }

  ManagedDownload startArtifactZip({
    required String repositoryFullName,
    required ActionArtifact artifact,
  }) {
    final endpoint =
        '/repos/$repositoryFullName/actions/artifacts/${artifact.id}/zip';
    final artifactName = _safeName(artifact.name, keepExtension: true);
    final fileName = p.extension(artifactName).isEmpty
        ? '$artifactName.zip'
        : artifactName;
    final item = _createItem(
      title: artifact.name,
      fileName: fileName,
      type: ManagedDownloadType.artifact,
      repositoryFullName: repositoryFullName,
      sourceEndpoint: endpoint,
      artifactId: artifact.id,
    );
    _launch(item, () => _runRedirected(item, endpoint));
    return item;
  }

  ManagedDownload startArtifactApk({
    required String repositoryFullName,
    required ActionArtifact artifact,
    String? preferredAbi,
    List<String>? supportedAbis,
  }) {
    final endpoint =
        '/repos/$repositoryFullName/actions/artifacts/${artifact.id}/zip';
    final item = _createItem(
      title: artifact.name,
      fileName: '${_safeName(artifact.name)}.apk',
      type: ManagedDownloadType.apk,
      repositoryFullName: repositoryFullName,
      sourceEndpoint: endpoint,
      artifactId: artifact.id,
      preferredAbi: preferredAbi,
      preferredAbis: supportedAbis ??
          (preferredAbi?.trim().isNotEmpty == true
              ? <String>[preferredAbi!.trim()]
              : const <String>[]),
    );
    _launch(item, () => _runArtifactApk(
      item,
      endpoint,
      preferredAbis: item.preferredAbis,
    ));
    return item;
  }

  ManagedDownload startGitHubFile({
    required String title,
    required String fileName,
    required String repositoryFullName,
    required String endpoint,
  }) {
    return _startRedirected(
      title: title,
      fileName: fileName,
      type: ManagedDownloadType.file,
      repositoryFullName: repositoryFullName,
      endpoint: endpoint,
    );
  }

  ManagedDownload startReleaseAsset({
    required String title,
    required String fileName,
    required String repositoryFullName,
    required int assetId,
    required bool isApk,
  }) {
    final endpoint = '/repos/$repositoryFullName/releases/assets/$assetId';
    return _startRedirected(
      title: title,
      fileName: fileName,
      type: isApk ? ManagedDownloadType.apk : ManagedDownloadType.file,
      repositoryFullName: repositoryFullName,
      endpoint: endpoint,
    );
  }

  ManagedDownload startPublicUrl({
    required String title,
    required String fileName,
    required String repositoryFullName,
    required String url,
    required bool isApk,
  }) {
    final item = _createItem(
      title: title,
      fileName: fileName,
      type: isApk ? ManagedDownloadType.apk : ManagedDownloadType.file,
      repositoryFullName: repositoryFullName,
      sourceEndpoint: _sanitizeDiagnosticEndpoint(url),
    );
    _publicSourceUrls[item.id] = url;
    _launch(item, () => _runDirectUrl(item, url));
    return item;
  }

  Future<void> cancel(String id) async {
    final item = _find(id);
    if (item == null || !item.isActive || _finalizing.contains(id)) {
      return;
    }
    _cancelTokens[id]?.cancel('Cancelado pelo usuário');
    item
      ..status = ManagedDownloadStatus.cancelled
      ..failedAt = DateTime.now()
      ..bytesPerSecond = 0
      ..estimatedSecondsRemaining = null
      ..errorMessage = 'Download cancelado pelo usuário.'
      ..errorCode = 'DOWNLOAD_CANCELLED'
      ..failureStage = 'download';
    _progressSamples.remove(id);
    _lastChunkAt.remove(id);
    _stalledIds.remove(id);
    _emit();
    await _persistHistory();
    await _syncDownloadForegroundService();
  }

  Future<void> retry(String id) async {
    final item = _find(id);
    if (item == null) return;
    if (item.isPaused) {
      await resume(id);
      return;
    }
    final endpoint = item.sourceEndpoint;
    if (item.isActive || !item.canRetry || endpoint == null || endpoint.isEmpty) {
      return;
    }
    final previous = _operations[id];
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    if (item.isActive || item.isPaused) return;
    item.resetForRetry();
    _emit();
    await _persistHistory();
    _startExisting(item, endpoint);
  }

  Future<void> removeFromHistory(String id) async {
    final item = _find(id);
    if (item == null || item.isActive) {
      return;
    }
    await _deleteWorkingFile(item);
    _publicSourceUrls.remove(id);
    _alreadyCleanedBefore.remove(id);
    _items.remove(item);
    _emit();
    await _persistHistory();
  }

  Future<void> deleteFileAndHistory(String id) async {
    final item = _find(id);
    if (item == null || item.isActive) {
      return;
    }
    final location = item.localPath;
    if (location != null && location.isNotEmpty) {
      final removed = await PlatformActions.deletePublishedDownload(location);
      if (!removed) {
        throw PlatformException(
          code: 'DELETE_DOWNLOAD_NOT_CONFIRMED',
          message: 'O Android não confirmou a exclusão do arquivo em Downloads.',
        );
      }
    }
    await _deleteWorkingFile(item);
    _publicSourceUrls.remove(id);
    _alreadyCleanedBefore.remove(id);
    _items.remove(item);
    _emit();
    await _persistHistory();
  }

  Future<void> clearFinishedHistory() async {
    final finished = _items.where((item) => item.isHistoryClearable).toList(growable: false);
    for (final item in finished) {
      await _deleteWorkingFile(item);
    }
    _items.removeWhere((item) => item.isHistoryClearable);
    for (final item in finished) {
      _publicSourceUrls.remove(item.id);
    }
    _emit();
    await _persistHistory();
  }

  Future<void> _deleteWorkingFile(ManagedDownload item) async {
    final path = item.workingPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Arquivo parcial é auxiliar e pode já ter sido limpo pelo Android.
    }
    item.workingPath = null;
  }

  // Compatibilidade com chamadas antigas dentro do projeto.
  Future<void> delete(String id) => deleteFileAndHistory(id);
  Future<void> clearFinished() => clearFinishedHistory();

  ManagedDownload _startRedirected({
    required String title,
    required String fileName,
    required ManagedDownloadType type,
    required String repositoryFullName,
    required String endpoint,
  }) {
    final item = _createItem(
      title: title,
      fileName: fileName,
      type: type,
      repositoryFullName: repositoryFullName,
      sourceEndpoint: endpoint,
    );
    _launch(item, () => _runRedirected(item, endpoint));
    return item;
  }

  ManagedDownload _createItem({
    required String title,
    required String fileName,
    required ManagedDownloadType type,
    String? repositoryFullName,
    String? sourceEndpoint,
    int? artifactId,
    String? preferredAbi,
    List<String> preferredAbis = const <String>[],
  }) {
    final item = ManagedDownload(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
      title: title,
      fileName: fileName,
      type: type,
      status: ManagedDownloadStatus.queued,
      createdAt: DateTime.now(),
      repositoryFullName: repositoryFullName,
      sourceEndpoint: sourceEndpoint,
      artifactId: artifactId,
      preferredAbi: preferredAbi,
      preferredAbis: preferredAbis,
    );
    _items.insert(0, item);
    _emit();
    unawaited(_persistHistory());
    return item;
  }

  Future<T> _withProjectCleanupLock<T>(
    String folder,
    Future<T> Function() operation,
  ) async {
    final previous = _projectCleanupLocks[folder];
    final completer = Completer<void>();
    final locked = completer.future;
    _projectCleanupLocks[folder] = locked;
    try {
      if (previous != null) await previous;
      return await operation();
    } finally {
      if (identical(_projectCleanupLocks[folder], locked)) {
        _projectCleanupLocks.remove(folder);
      }
      completer.complete();
    }
  }

  Future<DownloadCleanupMode> _cleanupMode() async {
    try {
      return await DownloadCleanupSettings.read();
    } catch (_) {
      // Sempre preservar o anterior até o novo estar publicado por padrão.
      return DownloadCleanupMode.afterSuccess;
    }
  }

  Future<void> _cleanManagedProject(
    ManagedDownload item, {
    String? keepLocation,
  }) async {
    final folder = _projectFolderName(item.repositoryFullName);
    if (folder == null) return;
    // O histórico ainda pode estar sendo restaurado na primeira abertura.
    await _historyReady;
    final result = await PlatformActions.cleanupManagedProjectDownloads(
      relativeFolder: folder,
      keepLocation: keepLocation,
    );
    final nativeErrors = result['failed'];
    var failedCount = nativeErrors is num ? nativeErrors.toInt() : 0;

    // Reconcilia o histórico do Android 10+ usando as URIs efetivamente
    // removidas pelo provedor. Em Android antigo, só aceita caminhos já
    // registrados e que apontem diretamente à pasta gerenciada do projeto.
    final nativeRemoved = (result['removed'] as List?)
            ?.whereType<String>()
            .toSet() ??
        <String>{};
    final removedIds = <String>{};
    for (final previous in _items.toList(growable: false)) {
      if (previous.id == item.id ||
          previous.repositoryFullName != item.repositoryFullName ||
          previous.status != ManagedDownloadStatus.completed) continue;
      final location = previous.localPath;
      if (location == null || location.isEmpty || location == keepLocation) continue;
      if (!nativeRemoved.contains(location)) {
        // URIs não listadas pelo MediaStore não são excluídas às cegas.
        if (location.startsWith('content://')) continue;
        final directory = p.normalize(p.dirname(location));
        if (p.basename(directory) != folder ||
            p.basename(p.dirname(directory)) != 'GitHub' ||
            p.basename(p.dirname(p.dirname(directory))) != 'Download') {
          continue;
        }
        try {
          if (!await PlatformActions.deletePublishedDownload(location)) {
            failedCount++;
            continue;
          }
        } catch (_) {
          failedCount++;
          continue;
        }
      }
      removedIds.add(previous.id);
    }
    if (removedIds.isNotEmpty) {
      _items.removeWhere((entry) => removedIds.contains(entry.id));
      _emit();
      await _persistHistory();
    }
    if (failedCount > 0) {
      throw StateError(
        'O Android não confirmou a exclusão de $failedCount arquivo(s) do projeto.',
      );
    }
  }

  Future<void> _cleanBeforeStart(ManagedDownload item) async {
    if (item.isPaused || item.status == ManagedDownloadStatus.cancelled) return;
    if (!_alreadyCleanedBefore.add(item.id)) return;
    final mode = await _cleanupMode();
    if (mode != DownloadCleanupMode.beforeStart) return;
    if (item.isPaused || item.status == ManagedDownloadStatus.cancelled) return;
    final folder = _projectFolderName(item.repositoryFullName);
    if (folder == null) return;
    await _withProjectCleanupLock(folder, () => _cleanManagedProject(item));
  }

  Future<void> _runDirectUrl(ManagedDownload item, String url) async {
    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;
    File? partialFile;
    File? completedFile;
    try {
      await _cleanBeforeStart(item);
      final directory = await _workingDirectory();
      completedFile = await _uniqueFile(directory, item.fileName);
      partialFile = await _partialFileFor(item, directory, item.fileName);
      final resumeFrom = await partialFile.exists() ? await partialFile.length() : 0;
      item
        ..fileName = p.basename(completedFile.path)
        ..sourceEndpoint = _sanitizeDiagnosticEndpoint(url)
        ..receivedBytes = resumeFrom;
      if (cancelToken.isCancelled ||
          item.status == ManagedDownloadStatus.cancelled || item.isPaused) return;
      _markStarted(item, initialBytes: resumeFrom);

      await _downloadPublicUrl(
        url,
        partialFile,
        resumeFrom: resumeFrom,
        cancelToken: cancelToken,
        onProgress: (received, total) => _updateProgress(item, received, total),
      );

      if (item.status == ManagedDownloadStatus.cancelled || item.isPaused) return;
      _finalizing.add(item.id);
      completedFile = await partialFile.rename(completedFile.path);
      partialFile = null;
      item
        ..workingPath = null
        ..receivedBytes = await completedFile.length();
      if (item.totalBytes <= 0) item.totalBytes = item.receivedBytes;
      await _publishCompleted(item, completedFile);
      completedFile = null;
    } catch (error) {
      if (item.status != ManagedDownloadStatus.cancelled && !item.isPaused) {
        _recordFailure(
          item,
          error is DioException
              ? DownloadFailureException(
                  error.message ?? 'Falha ao baixar arquivo público.',
                  code: 'PUBLIC_DOWNLOAD_FAILED',
                  endpoint: _sanitizeDiagnosticEndpoint(url),
                  stage: 'baixar_arquivo',
                  httpStatus: error.response?.statusCode,
                )
              : error,
          fallbackStage: 'baixar_arquivo',
        );
      }
    } finally {
      _cancelTokens.remove(item.id);
      _progressSamples.remove(item.id);
      _finalizing.remove(item.id);
      _lastChunkAt.remove(item.id);
      _stalledIds.remove(item.id);
      await _refreshPausedBytes(item);
      if (completedFile != null && await completedFile.exists()) {
        await completedFile.delete();
      }
      _emit();
      await _persistHistory();
      await _syncDownloadForegroundService();
    }
  }

  Future<void> _runRedirected(ManagedDownload item, String endpoint) async {
    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;
    File? partialFile;
    File? completedFile;
    try {
      await _cleanBeforeStart(item);
      final directory = await _workingDirectory();
      completedFile = await _uniqueFile(directory, item.fileName);
      partialFile = await _partialFileFor(item, directory, item.fileName);
      final resumeFrom = await partialFile.exists() ? await partialFile.length() : 0;
      item
        ..fileName = p.basename(completedFile.path)
        ..sourceEndpoint = endpoint
        ..receivedBytes = resumeFrom;
      if (cancelToken.isCancelled ||
          item.status == ManagedDownloadStatus.cancelled || item.isPaused) return;
      _markStarted(item, initialBytes: resumeFrom);
      await _downloadGithubWithRecovery(
        endpoint,
        partialFile,
        item: item,
        cancelToken: cancelToken,
      );
      if (item.status == ManagedDownloadStatus.cancelled || item.isPaused) return;
      _finalizing.add(item.id);
      completedFile = await partialFile.rename(completedFile.path);
      partialFile = null;
      item
        ..workingPath = null
        ..receivedBytes = await completedFile.length();
      if (item.totalBytes <= 0) item.totalBytes = item.receivedBytes;
      await _publishCompleted(item, completedFile);
      completedFile = null;
    } catch (error) {
      if (item.status != ManagedDownloadStatus.cancelled && !item.isPaused) {
        _recordFailure(
          item,
          error,
          fallbackStage: item.failureStage ?? 'download',
        );
      }
    } finally {
      _cancelTokens.remove(item.id);
      _progressSamples.remove(item.id);
      _finalizing.remove(item.id);
      _lastChunkAt.remove(item.id);
      _stalledIds.remove(item.id);
      await _refreshPausedBytes(item);
      if (completedFile != null && await completedFile.exists()) {
        await completedFile.delete();
      }
      _emit();
      await _persistHistory();
      await _syncDownloadForegroundService();
    }
  }

  // Cada nova tentativa obtém outra URL assinada do GitHub e usa o tamanho
  // efetivamente gravado em disco. Não repete erros definitivos (401/403/404).
  Future<void> _downloadGithubWithRecovery(
    String endpoint,
    File partialFile, {
    required ManagedDownload item,
    required CancelToken cancelToken,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (cancelToken.isCancelled) return;
      final offset = await partialFile.exists() ? await partialFile.length() : 0;
      try {
        final onProgress = (int received, int total) =>
            _updateProgress(item, received, total);
        if (endpoint.contains('/releases/assets/')) {
          await _client.downloadReleaseAssetFile(
            endpoint,
            partialFile.path,
            cancelToken: cancelToken,
            onReceiveProgress: onProgress,
            resumeFrom: offset,
          );
        } else {
          await _client.downloadRedirectedFile(
            endpoint,
            partialFile.path,
            cancelToken: cancelToken,
            onReceiveProgress: onProgress,
            resumeFrom: offset,
          );
        }
        return;
      } catch (error) {
        if (cancelToken.isCancelled || attempt == 2 ||
            !_isRecoverableDownloadError(error)) {
          rethrow;
        }
        // Breve espera com checagem de cancelamento, sem requisições paralelas.
        for (var step = 0; step < (attempt + 1) * 4; step++) {
          if (cancelToken.isCancelled) return;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }
  }

  static bool _isRecoverableDownloadError(Object error) {
    if (error is DownloadFailureException) {
      return const {
        'DOWNLOAD_NETWORK',
        'DOWNLOAD_INTERRUPTED',
        'DOWNLOAD_INCOMPLETE',
        'DOWNLOAD_TEMP_URL_EXPIRED',
        'DOWNLOAD_HTTP_408',
        'DOWNLOAD_HTTP_500',
        'DOWNLOAD_HTTP_502',
        'DOWNLOAD_HTTP_503',
        'DOWNLOAD_HTTP_504',
      }.contains(error.technicalCode);
    }
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException) {
      return true;
    }
    if (error is DioException) {
      if (CancelToken.isCancel(error)) return false;
      final status = error.response?.statusCode;
      if (status != null) {
        return const {408, 500, 502, 503, 504}.contains(status);
      }
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout;
    }
    return false;
  }

  Future<String?> _firstZipEntryName(File file) async {
    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final length = await raf.length();
      if (length < 30) return null;
      final header = await raf.read(30);
      if (header.length < 30 ||
          header[0] != 0x50 ||
          header[1] != 0x4b ||
          header[2] != 0x03 ||
          header[3] != 0x04) {
        return null;
      }
      final fileNameLength = header[26] | (header[27] << 8);
      if (fileNameLength <= 0 || fileNameLength > 4096) return null;
      final nameBytes = await raf.read(fileNameLength);
      return utf8.decode(nameBytes, allowMalformed: true)
          .replaceAll('\\', '/')
          .trim();
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  Future<bool> _canUseArtifactAsDirectApk(
    ManagedDownload item,
    File downloaded,
  ) async {
    final advertisedAsApk =
        item.title.toLowerCase().endsWith('.apk') ||
        item.fileName.toLowerCase().endsWith('.apk');
    if (!advertisedAsApk) return false;

    // upload-artifact v7 + archive:false entrega o próprio APK.
    // Em workflows antigos (v4/v5/v6), a API pode devolver um ZIP externo
    // cujo primeiro item é justamente "app-release.apk".
    final firstEntry = await _firstZipEntryName(downloaded);
    if (firstEntry == null) return false;
    return !firstEntry.toLowerCase().endsWith('.apk');
  }

  Future<void> _runArtifactApk(
    ManagedDownload item,
    String endpoint, {
    List<String> preferredAbis = const <String>[],
  }) async {
    final cancelToken = CancelToken();
    _cancelTokens[item.id] = cancelToken;
    File? downloadedFile;
    File? publishFile;
    try {
      await _cleanBeforeStart(item);
      final directory = await _workingDirectory();
      downloadedFile = await _partialFileFor(
        item,
        directory,
        'artifact-${item.artifactId ?? 'download'}.zip',
      );
      final resumeFrom = await downloadedFile.exists()
          ? await downloadedFile.length()
          : 0;
      item
        ..sourceEndpoint = endpoint
        ..receivedBytes = resumeFrom;
      if (cancelToken.isCancelled ||
          item.status == ManagedDownloadStatus.cancelled || item.isPaused) return;
      _markStarted(item, initialBytes: resumeFrom);
      await _downloadGithubWithRecovery(
        endpoint,
        downloadedFile,
        item: item,
        cancelToken: cancelToken,
      );
      if (item.status == ManagedDownloadStatus.cancelled || item.isPaused) return;
      _finalizing.add(item.id);

      if (await _canUseArtifactAsDirectApk(item, downloadedFile)) {
        item.failureStage = 'preparar_apk_direto';
        final desiredName = item.fileName.toLowerCase().endsWith('.apk')
            ? item.fileName
            : '${_safeName(item.title)}.apk';
        publishFile = await _uniqueFile(directory, desiredName);
        publishFile = await downloadedFile.rename(publishFile.path);
        downloadedFile = null;
        item.workingPath = null;
        final length = await publishFile.length();
        item
          ..fileName = p.basename(publishFile.path)
          ..receivedBytes = length
          ..totalBytes = length;
        await _publishCompleted(item, publishFile);
        publishFile = null;
        return;
      }

      item.failureStage = 'identificar_artifact';
      final input = InputFileStream(downloadedFile.path);
      final archive = ZipDecoder().decodeStream(input, verify: false);
      ArchiveFile? selectedApk;
      var directApk = false;
      try {
        final apks = archive
            .where(
              (entry) =>
                  entry.isFile && entry.name.toLowerCase().endsWith('.apk'),
            )
            .toList(growable: false);
        if (apks.isNotEmpty) {
          final supported = preferredAbis;
          final sorted = [...apks]..sort((left, right) {
            final leftRank = apkRecommendationRank(left.name, supported);
            final rightRank = apkRecommendationRank(right.name, supported);
            if (leftRank != rightRank) return leftRank.compareTo(rightRank);
            return right.size.compareTo(left.size);
          });
          selectedApk = sorted.first;
        } else {
          final names = archive
              .where((entry) => entry.isFile)
              .map((entry) => entry.name.replaceAll('\\', '/').toLowerCase())
              .toSet();
          directApk = names.contains('androidmanifest.xml') &&
              (names.contains('classes.dex') || names.contains('resources.arsc'));
        }

        if (selectedApk == null && !directApk) {
          throw const FormatException(
            'O artifact foi baixado, mas não contém um APK reconhecível.',
          );
        }

        if (selectedApk != null) {
          item.failureStage = 'extrair_apk';
          final bytes = selectedApk.readBytes();
          if (bytes == null) {
            throw const FormatException('Não foi possível extrair o APK.');
          }
          publishFile = await _uniqueFile(
            directory,
            selectedApk.name.split('/').last,
          );
          await publishFile.writeAsBytes(bytes, flush: true);
          item
            ..fileName = p.basename(publishFile.path)
            ..receivedBytes = bytes.length
            ..totalBytes = bytes.length;
        }
      } finally {
        archive.clearSync();
        input.closeSync();
      }

      if (directApk) {
        item.failureStage = 'preparar_apk_direto';
        final desiredName = item.fileName.toLowerCase().endsWith('.apk')
            ? item.fileName
            : '${_safeName(item.title)}.apk';
        publishFile = await _uniqueFile(directory, desiredName);
        publishFile = await downloadedFile.rename(publishFile.path);
        downloadedFile = null;
        item.workingPath = null;
        final length = await publishFile.length();
        item
          ..fileName = p.basename(publishFile.path)
          ..receivedBytes = length
          ..totalBytes = length;
      } else {
        item.workingPath = null;
        if (await downloadedFile.exists()) {
          await downloadedFile.delete();
        }
        downloadedFile = null;
      }

      if (item.isPaused || item.status == ManagedDownloadStatus.cancelled) return;
      if (publishFile == null) {
        throw const FormatException('Não foi possível preparar o APK baixado.');
      }
      await _publishCompleted(item, publishFile);
      publishFile = null;
    } catch (error) {
      if (item.status != ManagedDownloadStatus.cancelled && !item.isPaused) {
        _recordFailure(
          item,
          error,
          fallbackStage: item.failureStage ?? 'identificar_artifact',
        );
      }
    } finally {
      _cancelTokens.remove(item.id);
      _progressSamples.remove(item.id);
      _finalizing.remove(item.id);
      _lastChunkAt.remove(item.id);
      _stalledIds.remove(item.id);
      await _refreshPausedBytes(item);
      if (publishFile != null && await publishFile.exists()) {
        await publishFile.delete();
      }
      _emit();
      await _persistHistory();
      await _syncDownloadForegroundService();
    }
  }

  Future<void> _refreshPausedBytes(ManagedDownload item) async {
    if (!item.isPaused) return;
    final path = item.workingPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        item.receivedBytes = await file.length();
      }
    } catch (_) {
      // Não apagar nem adivinhar bytes em caso de falha ao ler o arquivo.
    }
  }

  Future<File> _partialFileFor(
    ManagedDownload item,
    Directory directory,
    String requestedName,
  ) async {
    final existingPath = item.workingPath;
    if (existingPath != null && existingPath.isNotEmpty) {
      return File(existingPath);
    }
    final safe = _safeName(requestedName, keepExtension: true);
    final partial = File(p.join(directory.path, '.${item.id}-$safe.part'));
    item.workingPath = partial.path;
    await _persistHistory();
    return partial;
  }

  Future<void> _downloadPublicUrl(
    String url,
    File target, {
    required int resumeFrom,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        followRedirects: true,
      ),
    );
    Future<Response<ResponseBody>> request(int offset) => dio.get<ResponseBody>(
          url,
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            validateStatus: (status) =>
                status == 200 || status == 206 || status == 416,
            headers: {if (offset > 0) 'Range': 'bytes=$offset-'},
          ),
        );

    var offset = resumeFrom;
    var response = await request(offset);
    if (response.statusCode == 416 && offset > 0) {
      if (await target.exists()) await target.delete();
      offset = 0;
      response = await request(0);
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw DownloadFailureException(
        'O servidor não aceitou a retomada do download.',
        code: 'PUBLIC_DOWNLOAD_RESUME_FAILED',
        endpoint: _sanitizeDiagnosticEndpoint(url),
        stage: 'retomar_download',
        httpStatus: response.statusCode,
      );
    }
    final body = response.data;
    if (body == null) {
      throw const FormatException('O servidor retornou um download vazio.');
    }
    final acceptedResume = response.statusCode == 206 && offset > 0;
    final contentRange = response.headers.value('content-range');
    if (acceptedResume &&
        (contentRange == null ||
            !contentRange.startsWith('bytes $offset-'))) {
      throw DownloadFailureException(
        'O servidor retornou um intervalo diferente do solicitado.',
        code: 'PUBLIC_DOWNLOAD_RESUME_INVALID',
        endpoint: _sanitizeDiagnosticEndpoint(url),
        stage: 'retomar_download',
      );
    }
    final startingBytes = acceptedResume ? offset : 0;
    final rangeTotal = contentRange == null
        ? null
        : int.tryParse(contentRange.split('/').last.trim());
    final contentLength =
        int.tryParse(response.headers.value('content-length') ?? '');
    final total = rangeTotal ??
        (contentLength == null ? -1 : startingBytes + contentLength);
    final sink = target.openWrite(
      mode: acceptedResume ? FileMode.append : FileMode.write,
    );
    var received = startingBytes;
    try {
      await for (final chunk in body.stream) {
        if (cancelToken.isCancelled) return;
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
      if (!cancelToken.isCancelled && total > 0 && received != total) {
        throw DownloadFailureException(
          'Transferência encerrada antes de concluir o arquivo esperado.',
          code: 'PUBLIC_DOWNLOAD_INCOMPLETE',
          endpoint: _sanitizeDiagnosticEndpoint(url),
          stage: 'baixar_arquivo',
        );
      }
    } finally {
      await sink.close();
      dio.close(force: true);
    }
  }

  void _markStarted(ManagedDownload item, {int initialBytes = 0}) {
    final now = DateTime.now();
    item
      ..status = ManagedDownloadStatus.downloading
      ..startedAt = now
      ..failedAt = null
      ..completedAt = null
      ..errorMessage = null
      ..errorCode = null
      ..failureStage = null
      ..httpStatus = null
      ..responseMessage = null
      ..bytesPerSecond = 0
      ..estimatedSecondsRemaining = null;
    _progressSamples[item.id] = DownloadSpeedMeter(now, initialBytes);
    _lastChunkAt[item.id] = now;
    _stalledIds.remove(item.id);
    _ensureStalledTimer();
    _emit();
    unawaited(_persistHistory());
    unawaited(_syncDownloadForegroundService(startService: true));
  }

  void _updateProgress(ManagedDownload item, int received, int total) {
    if (!item.isActive) return;
    final now = DateTime.now();
    if (received > item.receivedBytes) {
      _lastChunkAt[item.id] = now;
      _stalledIds.remove(item.id);
    }
    // Os contadores continuam exatos, mas não redesenhamos a tela a cada
    // pacote recebido (podem ser centenas por segundo em Wi-Fi rápido).
    item
      ..receivedBytes = received
      ..totalBytes = total;
    final sample = _progressSamples[item.id];
    if (sample == null) return;
    final finished = total > 0 && received >= total;
    if (!sample.shouldRefresh(now, finished: finished)) return;

    final speed = sample.record(now, received);
    item.bytesPerSecond = speed;
    item.estimatedSecondsRemaining = total > received && speed > 1
        ? ((total - received) / speed).ceil()
        : null;
    _emit();
    final last = _lastForegroundUpdate;
    if (last == null ||
        now.difference(last) >= const Duration(milliseconds: 500)) {
      _lastForegroundUpdate = now;
      unawaited(_syncDownloadForegroundService());
    }
  }

  Future<void> _syncDownloadForegroundService({bool startService = false}) async {
    final active = _items.where((item) => item.isActive).toList(growable: false);
    if (active.isEmpty) {
      _stopStalledTimerIfIdle();
      _lastForegroundUpdate = null;
      try {
        await PlatformActions.stopDownloadForegroundService();
      } catch (_) {
        // O canal nativo pode não existir fora do Android/testes.
      }
      return;
    }
    final item = active.first;
    try {
      await PlatformActions.showDownloadForegroundService(
        startService: startService,
        downloadId: item.id,
        fileName: item.fileName,
        repositoryFullName: item.repositoryFullName ?? '',
        current: item.receivedBytes,
        total: item.totalBytes,
        indeterminate: item.totalBytes <= 0,
        activeCount: active.length,
      );
    } catch (_) {
      // A notificação auxilia o segundo plano, mas não invalida o download.
    }
  }

  Future<void> _publishCompleted(ManagedDownload item, File source) async {
    if (item.type == ManagedDownloadType.apk) {
      item.failureStage = 'verificar_estrutura_apk';
      final inspection = await ApkPackageInspection.inspect(source);
      item.inspectedAbis = inspection.nativeAbis;
      if (inspection.nativeAbis.isNotEmpty && item.preferredAbis.isNotEmpty &&
          !inspection.nativeAbis.any(item.preferredAbis.contains)) {
        throw const FormatException(
          'O APK contém bibliotecas nativas incompatíveis com as ABIs informadas '
          'pelo aparelho. Escolha a variante adequada.',
        );
      }
    }
    item.failureStage = 'salvar_downloads';
    final projectFolder = _projectFolderName(item.repositoryFullName);
    Future<void> publishAndClean() async {
      Future<String> publish() => PlatformActions.publishToDownloads(
            sourcePath: source.path,
            fileName: item.fileName,
            mimeType: _mimeType(item),
            relativeFolder: projectFolder,
          );

      String location;
      try {
        location = await publish();
      } on PlatformException catch (error) {
        if (error.code != 'STORAGE_PERMISSION_REQUIRED') rethrow;
        final granted = await PlatformActions.requestLegacyDownloadsPermission();
        if (!granted) {
          throw FileSystemException('Permissão negada para salvar na pasta Downloads.');
        }
        location = await publish();
      }

      // O download já foi salvo. Uma falha de limpeza nunca o transforma em
      // falha de transferência, mas deve ser mostrada ao usuário.
      _publicSourceUrls.remove(item.id);
      item
        ..localPath = location
        ..workingPath = null
        ..status = ManagedDownloadStatus.completed
        ..completedAt = DateTime.now()
        ..failedAt = null
        ..errorMessage = null
        ..errorCode = null
        ..failureStage = null
        ..httpStatus = null
        ..responseMessage = null
        ..bytesPerSecond = 0
        ..estimatedSecondsRemaining = null;

      final mode = await _cleanupMode();
      if (mode != DownloadCleanupMode.disabled && projectFolder != null) {
        try {
          await _cleanManagedProject(item, keepLocation: location);
        } catch (_) {
          item.cleanupWarning =
              'Arquivo salvo, mas a limpeza automática não foi concluída. '
              'Confira Downloads/GitHub/$projectFolder.';
        }
      }
      await AppNotificationService.showDownloadCompleted(
        id: item.id,
        fileName: item.fileName,
        repository: item.repositoryFullName ?? '',
      );
      if (await source.exists()) await source.delete();
    }

    if (projectFolder == null) {
      await publishAndClean();
    } else {
      await _withProjectCleanupLock(projectFolder, publishAndClean);
    }
  }

  void _recordFailure(
    ManagedDownload item,
    Object error, {
    required String fallbackStage,
  }) {
    item
      ..status = ManagedDownloadStatus.failed
      ..failedAt = DateTime.now()
      ..completedAt = null
      ..bytesPerSecond = 0
      ..estimatedSecondsRemaining = null;

    if (error is DownloadFailureException) {
      final partialPreserved = item.workingPath?.isNotEmpty == true &&
          item.receivedBytes > 0;
      item
        ..errorMessage = partialPreserved
            ? '${error.message} O progresso parcial foi preservado para retomada.'
            : error.message
        ..errorCode = error.technicalCode
        ..sourceEndpoint = error.endpoint
        ..failureStage = error.stage
        ..httpStatus = error.httpStatus
        ..responseMessage = _cleanTechnicalMessage(error.apiMessage);
      _notifyDownloadFailure(item);
      return;
    }

    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is DioException) {
      item
        ..errorMessage =
            'A conexão foi interrompida. O arquivo parcial foi preservado para tentar novamente.'
        ..errorCode = 'DOWNLOAD_NETWORK'
        ..failureStage = fallbackStage
        ..responseMessage = _cleanTechnicalMessage(error.toString());
      _notifyDownloadFailure(item);
      return;
    }

    if (error is PlatformException) {
      item
        ..errorMessage = _platformFriendlyError(error)
        ..errorCode = error.code
        ..failureStage = fallbackStage
        ..responseMessage = _cleanTechnicalMessage(error.message);
      _notifyDownloadFailure(item);
      return;
    }

    if (error is FileSystemException) {
      final message = '${error.message} ${error.osError?.message ?? ''}'.trim();
      final full = message.toLowerCase();
      final fullStorage = full.contains('no space left') ||
          full.contains('enospc') ||
          full.contains('espaço insuficiente');
      final permissionDenied = full.contains('permissão negada') ||
          full.contains('permission denied');
      item
        ..errorMessage = fullStorage
            ? 'Não há espaço suficiente no aparelho para concluir o download.'
            : permissionDenied
                ? 'Sem permissão para gravar o arquivo na pasta Downloads.'
                : 'Erro ao gravar o arquivo na pasta Downloads.'
        ..errorCode = fullStorage
            ? 'STORAGE_FULL'
            : permissionDenied
                ? 'DOWNLOAD_STORAGE_PERMISSION'
                : 'DOWNLOAD_WRITE_FAILED'
        ..failureStage = fallbackStage
        ..responseMessage = _cleanTechnicalMessage(message);
      _notifyDownloadFailure(item);
      return;
    }

    if (error is FormatException) {
      item
        ..errorMessage = error.message
        ..errorCode = 'DOWNLOAD_CONTENT_INVALID'
        ..failureStage = fallbackStage
        ..responseMessage = null;
      _notifyDownloadFailure(item);
      return;
    }

    item
      ..errorMessage = 'Erro desconhecido ao concluir o download.'
      ..errorCode = 'DOWNLOAD_UNKNOWN'
      ..failureStage = fallbackStage
      ..responseMessage = _cleanTechnicalMessage(error.toString());
    _notifyDownloadFailure(item);
  }

  void _notifyDownloadFailure(ManagedDownload item) {
    unawaited(
      AppNotificationService.showDownloadFailed(
        id: item.id,
        fileName: item.fileName,
        message: item.errorMessage ?? 'Não foi possível concluir o download.',
      ),
    );
  }

  static String _platformFriendlyError(PlatformException error) {
    final message = (error.message ?? '').toLowerCase();
    if (error.code == 'STORAGE_FULL' ||
        message.contains('no space left') ||
        message.contains('enospc')) {
      return 'Não há espaço suficiente no aparelho para concluir o download.';
    }
    if (error.code == 'STORAGE_PERMISSION_REQUIRED') {
      return 'O Android não permitiu gravar o arquivo na pasta Downloads.';
    }
    if (error.code == 'DOWNLOAD_SOURCE_NOT_FOUND') {
      return 'O arquivo temporário do download não foi encontrado.';
    }
    return 'Erro ao gravar o arquivo na pasta Downloads.';
  }

  static String _sanitizeDiagnosticEndpoint(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed == null || !parsed.hasScheme) {
      return value.split('?').first.split('#').first;
    }
    return parsed.replace(query: null, fragment: null).toString();
  }

  static String? _cleanTechnicalMessage(String? value) {
    if (value == null) {
      return null;
    }
    var result = value.trim();
    if (result.isEmpty) {
      return null;
    }
    result = result.replaceAll(
      RegExp(
        r'authorization\s*[:=]\s*(bearer\s+)?[^\s,;]+',
        caseSensitive: false,
      ),
      'Authorization=[REMOVIDO]',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(token|secret|api[_ -]?key|password)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}=[REMOVIDO]',
    );
    // URLs assinadas usadas por artifacts/releases podem carregar credenciais
    // efêmeras na query string. Nunca persista esses parâmetros no histórico.
    result = result.replaceAllMapped(
      RegExp(r'(https?://[^\s?]+)\?[^\s]+', caseSensitive: false),
      (match) => '${match.group(1)}?[PARAMETROS_REMOVIDOS]',
    );
    return result.length > 700 ? '${result.substring(0, 700)}…' : result;
  }

  Future<void> _restoreHistory() async {
    try {
      await _workingDirectory();
      final file = await _historyFile();
      if (!await file.exists()) {
        _emit();
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return;
      }
      final restored = decoded
          .whereType<Map>()
          .map(
            (json) => ManagedDownload.fromJson(
              Map<String, dynamic>.from(json),
            ),
          )
          .toList(growable: false);
      final autoResumeIds = <String>[];
      for (final item in restored) {
        if (item.isActive) {
          item.markInterruptedByAppExit();
          final partialPath = item.workingPath;
          if (partialPath != null &&
              partialPath.isNotEmpty &&
              item.sourceEndpoint?.isNotEmpty == true &&
              await File(partialPath).exists()) {
            item.receivedBytes = await File(partialPath).length();
            autoResumeIds.add(item.id);
          }
        }
      }
      final liveItems = List<ManagedDownload>.from(_items);
      final liveIds = liveItems.map((item) => item.id).toSet();
      final merged = <ManagedDownload>[
        ...liveItems,
        ...restored.where((item) => !liveIds.contains(item.id)),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _items
        ..clear()
        ..addAll(merged);
      _emit();
      await _persistHistory();
      for (final id in autoResumeIds) {
        unawaited(retry(id));
      }
    } catch (_) {
      // Histórico é auxiliar e nunca bloqueia o restante do aplicativo.
    }
  }

  Future<void> _persistHistory() {
    // Fotografia capturada no instante do evento, gravada em ordem.
    final snapshot = _items
        .take(100)
        .map((item) => item.toJson())
        .toList(growable: false);
    final pending = _historyWrites.then((_) async {
      try {
        final file = await _historyFile();
        await file.writeAsString(jsonEncode(snapshot), flush: true);
      } catch (_) {
        // Histórico é auxiliar; falha de disco não deve cancelar o download.
      }
    });
    _historyWrites = pending;
    return pending;
  }

  Future<Directory> _workingDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'download_work'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _historyFile() async {
    final root = await getApplicationSupportDirectory();
    return File(p.join(root.path, 'downloads_history.json'));
  }

  Future<File> _uniqueFile(Directory directory, String requestedName) async {
    final safe = _safeName(requestedName, keepExtension: true);
    var candidate = File(p.join(directory.path, safe));
    if (!await candidate.exists()) {
      return candidate;
    }
    final extension = p.extension(safe);
    final stem = p.basenameWithoutExtension(safe);
    var index = 2;
    while (await candidate.exists()) {
      candidate = File(p.join(directory.path, '$stem-$index$extension'));
      index++;
    }
    return candidate;
  }

  ManagedDownload? _find(String id) {
    for (final item in _items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_items));
    }
  }

  static String _mimeType(ManagedDownload item) {
    if (item.isApk) {
      return 'application/vnd.android.package-archive';
    }
    if (item.fileName.toLowerCase().endsWith('.zip')) {
      return 'application/zip';
    }
    return 'application/octet-stream';
  }

  static String? _projectFolderName(String? repositoryFullName) {
    if (repositoryFullName == null || repositoryFullName.trim().isEmpty) {
      return null;
    }
    final raw = repositoryFullName.split('/').last.trim();
    if (raw.isEmpty) return null;
    final readable = raw.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    return _safeName(readable, keepExtension: true);
  }

  static String _safeName(String raw, {bool keepExtension = false}) {
    final source = raw.trim().isEmpty ? 'download' : raw.trim();
    final replaced = source.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
    final collapsed = replaced.replaceAll(RegExp(r'-+'), '-');
    final clean = collapsed.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
    if (clean.isEmpty) {
      return 'download';
    }
    if (keepExtension) {
      return clean;
    }
    return clean.replaceAll(RegExp(r'\.(zip|apk)$', caseSensitive: false), '');
  }

  void dispose() {
    for (final token in _cancelTokens.values) {
      token.cancel('Download manager encerrado');
    }
    _cancelTokens.clear();
    _stalledTimer?.cancel();
    _stalledTimer = null;
    _stalledIds.clear();
    _lastChunkAt.clear();
    _operations.clear();
    _finalizing.clear();
    _publicSourceUrls.clear();
    _alreadyCleanedBefore.clear();
    _projectCleanupLocks.clear();
    _progressSamples.clear();
    unawaited(_stopDownloadForegroundService());
    _controller.close();
  }

  Future<void> _stopDownloadForegroundService() async {
    try {
      await PlatformActions.stopDownloadForegroundService();
    } catch (_) {
      // O app pode estar encerrando antes do canal nativo responder.
    }
  }
}

