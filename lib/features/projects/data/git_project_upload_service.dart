import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/core/utils/commit_message.dart';
import 'package:github_manager/core/utils/git_object_hash.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:path/path.dart' as p;

class GitProjectUploadService {
  GitProjectUploadService(this._client);

  static const _maxInlineFileBytes = 128 * 1024;
  static const _maxInlineTreeBytes = 4 * 1024 * 1024;
  static const _streamingFileThreshold = 1024 * 1024;
  static const _maxContentsFallbackOperations = 12;
  static const _maxContentsFallbackFileBytes = 8 * 1024 * 1024;
  static const _maxTransientRetries = 2;

  final GitHubApiClient _client;

  /// GitHub Actions workflows are repository infrastructure. A project ZIP can
  /// replace a workflow by including the same path, but a normal project sync
  /// must not delete an existing workflow simply because the ZIP omitted
  /// `.github/workflows`. This prevents a successful upload from disabling the
  /// very build that should run immediately afterwards.
  static bool isProtectedRepositoryInfrastructurePath(String path) {
    final normalized = path
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^/+'), '')
        .toLowerCase();
    return normalized.startsWith('.github/workflows/');
  }

  static bool shouldRemoveRepositoryPath({
    required String path,
    required Set<String> zipPaths,
  }) =>
      !zipPaths.contains(path) &&
      !isProtectedRepositoryInfrastructurePath(path);

  Future<ProjectSyncPreview> previewZipSync({
    required ZipProjectPreview project,
    required String repositoryFullName,
    required String branch,
  }) async {
    await LocalProjectService.verifyFingerprint(project);
    final existingEntries = await _loadExistingEntriesForPreview(
      repositoryFullName: repositoryFullName,
      branch: branch,
    );
    final newPaths = <String>{};
    final created = <String>[];
    final modified = <String>[];
    var unchanged = 0;

    final input = InputFileStream(project.path);
    final archive = ZipDecoder().decodeStream(input, verify: true);
    var index = 0;
    try {
      for (final entry in archive) {
        if (!entry.isFile || entry.isSymbolicLink) continue;
        final validated = LocalProjectService.validateArchivePath(entry.name);
        final gitPath = _stripCommonRoot(validated, project.commonRoot);
        if (gitPath.isEmpty) continue;
        newPaths.add(gitPath);

        List<int>? bytes;
        File? temporaryFile;
        int contentLength;
        String contentBlobSha;
        try {
          if (entry.size > _streamingFileThreshold) {
            temporaryFile = File(
              p.join(
                Directory.systemTemp.path,
                'github_manager_preview_${DateTime.now().microsecondsSinceEpoch}_${index++}.tmp',
              ),
            );
            final output = OutputFileStream(temporaryFile.path);
            try {
              entry.writeContent(output);
            } finally {
              output.closeSync();
            }
            contentLength = await temporaryFile.length();
            contentBlobSha = await GitObjectHash.blobShaFile(temporaryFile);
          } else {
            bytes = entry.readBytes();
            if (bytes == null) {
              throw InvalidZipException(
                'Não foi possível ler $gitPath para gerar a prévia.',
                code: 'ZIP_ENTRY_READ_FAILED',
              );
            }
            contentLength = bytes.length;
            contentBlobSha = GitObjectHash.blobSha(bytes);
          }
          final mode = _gitMode(entry.mode);
          final existing = existingEntries[gitPath];
          if (existing == null) {
            created.add(gitPath);
          } else if (existing.type == 'blob' &&
              existing.mode == mode &&
              (existing.size == null || existing.size == contentLength) &&
              existing.sha == contentBlobSha) {
            unchanged++;
          } else {
            modified.add(gitPath);
          }
        } finally {
          entry.clear();
          if (temporaryFile != null && await temporaryFile.exists()) {
            await temporaryFile.delete();
          }
        }
      }
    } finally {
      archive.clearSync();
      input.closeSync();
    }

    final deleted = existingEntries.keys
        .where((path) => shouldRemoveRepositoryPath(path: path, zipPaths: newPaths))
        .toList(growable: false)
      ..sort();
    created.sort();
    modified.sort();
    return ProjectSyncPreview(
      createdPaths: List.unmodifiable(created),
      modifiedPaths: List.unmodifiable(modified),
      deletedPaths: List.unmodifiable(deleted),
      unchangedCount: unchanged,
    );
  }

  Future<Map<String, _ExistingEntry>> _loadExistingEntriesForPreview({
    required String repositoryFullName,
    required String branch,
  }) async {
    try {
      final refResponse = await _client.get<Map<String, dynamic>>(
        '/repos/$repositoryFullName/git/ref/heads/$branch',
      );
      final object = refResponse.data?['object'];
      final commitSha = object is Map ? object['sha']?.toString() : null;
      if (commitSha?.isNotEmpty != true) return const <String, _ExistingEntry>{};
      final commitResponse = await _client.get<Map<String, dynamic>>(
        '/repos/$repositoryFullName/git/commits/$commitSha',
      );
      final treeRaw = commitResponse.data?['tree'];
      final treeSha = treeRaw is Map ? treeRaw['sha']?.toString() : null;
      if (treeSha?.isNotEmpty != true) return const <String, _ExistingEntry>{};
      final treeResponse = await _client.get<Map<String, dynamic>>(
        '/repos/$repositoryFullName/git/trees/$treeSha',
        queryParameters: const {'recursive': '1'},
      );
      if (treeResponse.data?['truncated'] == true) {
        throw const UnexpectedAppException('BASE_TREE_TRUNCATED');
      }
      final result = <String, _ExistingEntry>{};
      final rawTree = treeResponse.data?['tree'];
      if (rawTree is List) {
        for (final raw in rawTree.whereType<Map>()) {
          final path = raw['path'];
          final mode = raw['mode'];
          final type = raw['type'];
          final sha = raw['sha'];
          if (path is String && mode is String && type is String && sha is String &&
              (type == 'blob' || type == 'commit')) {
            result[path] = _ExistingEntry(
              mode: mode,
              type: type,
              sha: sha,
              size: (raw['size'] as num?)?.toInt(),
            );
          }
        }
      }
      return result;
    } on GitHubNotFoundException {
      // Repositório realmente vazio: a prévia deve ser somente leitura e não
      // inicializar a branch com .gitkeep.
      return const <String, _ExistingEntry>{};
    }
  }

  Future<ProjectUploadResult> uploadZip({
    required ZipProjectPreview project,
    required String repositoryFullName,
    required String branch,
    required String commitMessage,
    void Function(ProjectUploadProgress progress)? onProgress,
    Map<String, String> reusableBlobShas = const <String, String>{},
    void Function(String path, String sha)? onBlobUploaded,
    ProjectUploadMethod method = ProjectUploadMethod.incremental,
    bool allowAutomaticRecovery = true,
  }) async {
    await LocalProjectService.verifyFingerprint(project);
    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Tentativa com ${method.label}',
        kind: ProjectUploadProgressKind.recovery,
        method: method,
      ),
    );
    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Preparando branch',
        method: method,
      ),
    );

    final snapshot = await _loadRepositorySnapshot(
      repositoryFullName: repositoryFullName,
      branch: branch,
      method: method,
      onProgress: onProgress,
    );

    if (method == ProjectUploadMethod.contentsApi) {
      return _uploadViaContentsApi(
        project: project,
        repositoryFullName: repositoryFullName,
        branch: branch,
        commitMessage: commitMessage,
        snapshot: snapshot,
        onProgress: onProgress,
      );
    }

    final prepared = await _prepareTreeEntries(
      project: project,
      repositoryFullName: repositoryFullName,
      reusableBlobShas: reusableBlobShas,
      onBlobUploaded: onBlobUploaded,
      onProgress: onProgress,
      method: method,
      existingEntries: snapshot.existingEntries,
    );

    if (prepared.changedPaths.isEmpty && prepared.stalePaths.isEmpty) {
      onProgress?.call(
        ProjectUploadProgress(
          phase: 'Nenhuma alteração encontrada',
          current: project.fileCount,
          total: project.fileCount,
          method: method,
        ),
      );
      return ProjectUploadResult(
        commitSha: snapshot.parentCommitSha,
        fileCount: project.fileCount,
        changed: false,
        method: method,
      );
    }

    onProgress?.call(
      ProjectUploadProgress(
        phase: prepared.stalePaths.isEmpty
            ? 'Preparando sincronização no GitHub'
            : 'Removendo ${prepared.stalePaths.length} arquivo(s) antigo(s)',
        current: project.fileCount,
        total: project.fileCount,
        kind: prepared.stalePaths.isEmpty
            ? ProjectUploadProgressKind.stage
            : ProjectUploadProgressKind.removed,
        affectedCount: prepared.stalePaths.length,
        method: method,
      ),
    );

    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Confirmando branch antes de preparar o commit',
        current: project.fileCount,
        total: project.fileCount,
        method: method,
      ),
    );
    await _verifyBranchHead(
      repositoryFullName: repositoryFullName,
      branch: branch,
      expectedSha: snapshot.parentCommitSha,
      method: method,
      onProgress: onProgress,
    );

    var effectiveMethod = method;
    String newTreeSha;

    if (method == ProjectUploadMethod.fullTree) {
      newTreeSha = await _createTree(
        repositoryFullName: repositoryFullName,
        entries: prepared.projectEntries,
        method: method,
        onProgress: onProgress,
      );
    } else {
      final incrementalEntries = <Map<String, dynamic>>[
        ...prepared.projectEntries,
        for (final stalePath in prepared.stalePaths)
          {
            'path': stalePath,
            'mode': snapshot.existingEntries[stalePath]!.mode,
            'type': snapshot.existingEntries[stalePath]!.type,
            'sha': null,
          },
      ];

      try {
        newTreeSha = await _createTree(
          repositoryFullName: repositoryFullName,
          entries: incrementalEntries,
          baseTreeSha: snapshot.baseTreeSha,
          method: method,
          onProgress: onProgress,
        );
      } catch (error) {
        if (!allowAutomaticRecovery || !_shouldFallbackToFullTree(error)) {
          rethrow;
        }

        effectiveMethod = ProjectUploadMethod.fullTree;
        final recoveryReason = _recoveryErrorLabel(error);
        onProgress?.call(
          ProjectUploadProgress(
            phase:
                '$recoveryReason • método incremental falhou; tentando reconstrução da árvore completa',
            current: project.fileCount,
            total: project.fileCount,
            kind: ProjectUploadProgressKind.recovery,
            method: effectiveMethod,
          ),
        );

        onProgress?.call(
          ProjectUploadProgress(
            phase: 'Confirmando branch antes do método alternativo',
            current: project.fileCount,
            total: project.fileCount,
            kind: ProjectUploadProgressKind.recovery,
            method: effectiveMethod,
          ),
        );
        await _verifyBranchHead(
          repositoryFullName: repositoryFullName,
          branch: branch,
          expectedSha: snapshot.parentCommitSha,
          method: effectiveMethod,
          onProgress: onProgress,
        );

        newTreeSha = await _createTree(
          repositoryFullName: repositoryFullName,
          entries: prepared.projectEntries,
          method: effectiveMethod,
          onProgress: onProgress,
        );
      }
    }

    if (newTreeSha == snapshot.baseTreeSha) {
      onProgress?.call(
        ProjectUploadProgress(
          phase: 'Nenhuma alteração encontrada',
          current: project.fileCount,
          total: project.fileCount,
          method: effectiveMethod,
        ),
      );
      return ProjectUploadResult(
        commitSha: snapshot.parentCommitSha,
        fileCount: project.fileCount,
        changed: false,
        method: effectiveMethod,
      );
    }

    await Future<void>.delayed(const Duration(seconds: 1));
    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Criando commit',
        method: effectiveMethod,
      ),
    );
    final message = _commitMessage(project, commitMessage);
    final newCommitResponse = await _withTransientRetry(
      operation: 'criar o commit',
      method: effectiveMethod,
      onProgress: onProgress,
      request: () => _client.post<Map<String, dynamic>>(
        '/repos/$repositoryFullName/git/commits',
        data: {
          'message': message,
          'tree': newTreeSha,
          'parents': [snapshot.parentCommitSha],
        },
      ),
    );
    final newCommitSha = newCommitResponse.data?['sha'] as String?;
    if (newCommitSha == null || newCommitSha.isEmpty) {
      throw const UnexpectedAppException('COMMIT_SHA_MISSING');
    }

    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Confirmando branch antes de publicar o commit',
        current: project.fileCount,
        total: project.fileCount,
        method: effectiveMethod,
      ),
    );
    await _verifyBranchHead(
      repositoryFullName: repositoryFullName,
      branch: branch,
      expectedSha: snapshot.parentCommitSha,
      method: effectiveMethod,
      onProgress: onProgress,
    );

    await Future<void>.delayed(const Duration(seconds: 1));
    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Atualizando branch',
        method: effectiveMethod,
      ),
    );
    await _withTransientRetry(
      operation: 'atualizar a branch',
      method: effectiveMethod,
      onProgress: onProgress,
      request: () => _client.patch<Map<String, dynamic>>(
        '/repos/$repositoryFullName/git/refs/heads/$branch',
        data: {'sha': newCommitSha, 'force': false},
      ),
    );

    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Concluído',
        current: project.fileCount,
        total: project.fileCount,
        method: effectiveMethod,
      ),
    );
    return ProjectUploadResult(
      commitSha: newCommitSha,
      fileCount: project.fileCount,
      changed: true,
      method: effectiveMethod,
      commitCount: 1,
    );
  }

  Future<_RepositorySnapshot> _loadRepositorySnapshot({
    required String repositoryFullName,
    required String branch,
    required ProjectUploadMethod method,
    required void Function(ProjectUploadProgress progress)? onProgress,
  }) async {
    Map<String, dynamic> refData;
    try {
      final refResponse = await _withTransientRetry(
        operation: 'consultar a branch',
        method: method,
        onProgress: onProgress,
        request: () => _client.get<Map<String, dynamic>>(
          '/repos/$repositoryFullName/git/ref/heads/$branch',
        ),
      );
      refData = refResponse.data ?? const {};
    } on GitHubNotFoundException {
      await _client.put<Map<String, dynamic>>(
        '/repos/$repositoryFullName/contents/.gitkeep',
        data: {
          'message': automaticCommitMessage('Inicializa repositório'),
          'content': '',
        },
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      final refResponse = await _withTransientRetry(
        operation: 'confirmar a branch inicializada',
        method: method,
        onProgress: onProgress,
        request: () => _client.get<Map<String, dynamic>>(
          '/repos/$repositoryFullName/git/ref/heads/$branch',
        ),
      );
      refData = refResponse.data ?? const {};
    }

    final object = refData['object'];
    if (object is! Map || object['sha'] is! String) {
      throw const UnexpectedAppException('REF_SHA_MISSING');
    }
    final parentCommitSha = object['sha'] as String;

    final commitResponse = await _withTransientRetry(
      operation: 'consultar o commit atual',
      method: method,
      onProgress: onProgress,
      request: () => _client.get<Map<String, dynamic>>(
        '/repos/$repositoryFullName/git/commits/$parentCommitSha',
      ),
    );
    final commit = commitResponse.data ?? const {};
    final tree = commit['tree'];
    if (tree is! Map || tree['sha'] is! String) {
      throw const UnexpectedAppException('BASE_TREE_SHA_MISSING');
    }
    final baseTreeSha = tree['sha'] as String;

    final currentTreeResponse = await _withTransientRetry(
      operation: 'consultar a árvore atual',
      method: method,
      onProgress: onProgress,
      request: () => _client.get<Map<String, dynamic>>(
        '/repos/$repositoryFullName/git/trees/$baseTreeSha',
        queryParameters: const {'recursive': '1'},
      ),
    );
    final currentTreeData =
        currentTreeResponse.data ?? const <String, dynamic>{};
    if (currentTreeData['truncated'] == true) {
      throw const UnexpectedAppException('BASE_TREE_TRUNCATED');
    }

    final existingEntries = <String, _ExistingEntry>{};
    final currentTree = currentTreeData['tree'];
    if (currentTree is List) {
      for (final raw in currentTree.whereType<Map>()) {
        final path = raw['path'];
        final mode = raw['mode'];
        final type = raw['type'];
        final sha = raw['sha'];
        final size = (raw['size'] as num?)?.toInt();
        if (path is String &&
            mode is String &&
            type is String &&
            sha is String &&
            (type == 'blob' || type == 'commit')) {
          existingEntries[path] = _ExistingEntry(
            mode: mode,
            type: type,
            sha: sha,
            size: size,
          );
        }
      }
    }

    return _RepositorySnapshot(
      parentCommitSha: parentCommitSha,
      baseTreeSha: baseTreeSha,
      existingEntries: existingEntries,
    );
  }

  Future<_PreparedTree> _prepareTreeEntries({
    required ZipProjectPreview project,
    required String repositoryFullName,
    required Map<String, String> reusableBlobShas,
    required void Function(String path, String sha)? onBlobUploaded,
    required void Function(ProjectUploadProgress progress)? onProgress,
    required ProjectUploadMethod method,
    required Map<String, _ExistingEntry> existingEntries,
  }) async {
    final input = InputFileStream(project.path);
    final archive = ZipDecoder().decodeStream(input, verify: true);
    final treeEntries = <Map<String, dynamic>>[];
    final newPaths = <String>{};
    final changedPaths = <String>{};
    var inlineBytes = 0;
    var processed = 0;

    try {
      for (final entry in archive) {
        if (!entry.isFile || entry.isSymbolicLink) {
          continue;
        }
        final validated = LocalProjectService.validateArchivePath(entry.name);
        final gitPath = _stripCommonRoot(validated, project.commonRoot);
        if (gitPath.isEmpty) {
          continue;
        }
        newPaths.add(gitPath);

        List<int>? bytes;
        File? temporaryFile;
        int contentLength;
        String contentBlobSha;
        try {
          if (entry.size > _streamingFileThreshold) {
            temporaryFile = File(
              p.join(
                Directory.systemTemp.path,
                'github_manager_blob_${DateTime.now().microsecondsSinceEpoch}_$processed.tmp',
              ),
            );
            final output = OutputFileStream(temporaryFile.path);
            try {
              entry.writeContent(output);
            } finally {
              output.closeSync();
            }
            contentLength = await temporaryFile.length();
            contentBlobSha = await GitObjectHash.blobShaFile(temporaryFile);
          } else {
            bytes = entry.readBytes();
            if (bytes == null) {
              throw InvalidZipException(
                'Não foi possível ler $gitPath dentro do ZIP.',
                code: 'ZIP_ENTRY_READ_FAILED',
              );
            }
            contentLength = bytes.length;
            contentBlobSha = GitObjectHash.blobSha(bytes);
          }

          final mode = _gitMode(entry.mode);
          final existing = existingEntries[gitPath];
          if (existing != null &&
              existing.type == 'blob' &&
              existing.mode == mode &&
              (existing.size == null || existing.size == contentLength) &&
              existing.sha == contentBlobSha) {
            treeEntries.add({
              'path': gitPath,
              'mode': mode,
              'type': 'blob',
              'sha': existing.sha,
            });
            processed++;
            onProgress?.call(
              ProjectUploadProgress(
                phase: 'Arquivo já está atualizado',
                current: processed,
                total: project.fileCount,
                fileName: gitPath,
                kind: ProjectUploadProgressKind.unchanged,
                method: method,
              ),
            );
            continue;
          }

          changedPaths.add(gitPath);
          final checkpointSha = reusableBlobShas[gitPath];
          if (checkpointSha == contentBlobSha) {
            treeEntries.add({
              'path': gitPath,
              'mode': mode,
              'type': 'blob',
              'sha': checkpointSha,
            });
            processed++;
            onProgress?.call(
              ProjectUploadProgress(
                phase: 'Retomando arquivo já enviado',
                current: processed,
                total: project.fileCount,
                fileName: gitPath,
                kind: ProjectUploadProgressKind.resumed,
                method: method,
              ),
            );
            continue;
          }

          final text = bytes == null ? null : _tryDecodeText(bytes);
          final canInline = text != null &&
              contentLength <= _maxInlineFileBytes &&
              inlineBytes + contentLength <= _maxInlineTreeBytes;

          if (canInline) {
            treeEntries.add({
              'path': gitPath,
              'mode': mode,
              'type': 'blob',
              'content': text,
            });
            inlineBytes += contentLength;
          } else {
            onProgress?.call(
              ProjectUploadProgress(
                phase: 'Enviando arquivo para o GitHub',
                current: processed,
                total: project.fileCount,
                fileName: gitPath,
                kind: ProjectUploadProgressKind.transferStarted,
                method: method,
              ),
            );
            final blobResponse = await _withTransientRetry(
              operation: 'enviar $gitPath',
              method: method,
              onProgress: onProgress,
              request: () => temporaryFile != null
                  ? _client.postBase64File<Map<String, dynamic>>(
                      '/repos/$repositoryFullName/git/blobs',
                      temporaryFile,
                    )
                  : _client.post<Map<String, dynamic>>(
                      '/repos/$repositoryFullName/git/blobs',
                      data: {
                        'content': base64Encode(bytes!),
                        'encoding': 'base64',
                      },
                    ),
            );
            final sha = blobResponse.data?['sha'] as String?;
            if (sha == null || sha.isEmpty) {
              throw const UnexpectedAppException('BLOB_SHA_MISSING');
            }
            if (sha != contentBlobSha) {
              throw const UnexpectedAppException('BLOB_SHA_MISMATCH');
            }
            onBlobUploaded?.call(gitPath, sha);
            treeEntries.add({
              'path': gitPath,
              'mode': mode,
              'type': 'blob',
              'sha': sha,
            });
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        } finally {
          entry.clear();
          if (temporaryFile != null && await temporaryFile.exists()) {
            await temporaryFile.delete();
          }
        }

        processed++;
        onProgress?.call(
          ProjectUploadProgress(
            phase: 'Processando arquivos do projeto',
            current: processed,
            total: project.fileCount,
            fileName: gitPath,
            kind: ProjectUploadProgressKind.changed,
            method: method,
          ),
        );
      }
    } finally {
      archive.clearSync();
      input.closeSync();
    }

    final preservedInfrastructure = existingEntries.entries
        .where(
          (entry) =>
              !newPaths.contains(entry.key) &&
              isProtectedRepositoryInfrastructurePath(entry.key),
        )
        .toList(growable: false);

    for (final entry in preservedInfrastructure) {
      treeEntries.add({
        'path': entry.key,
        'mode': entry.value.mode,
        'type': entry.value.type,
        'sha': entry.value.sha,
      });
    }

    if (preservedInfrastructure.isNotEmpty) {
      onProgress?.call(
        ProjectUploadProgress(
          phase:
              'Protegendo ${preservedInfrastructure.length} workflow(s) do GitHub Actions',
          current: project.fileCount,
          total: project.fileCount,
          kind: ProjectUploadProgressKind.stage,
          method: method,
        ),
      );
    }

    final stalePaths = existingEntries.keys
        .where(
          (path) => shouldRemoveRepositoryPath(
            path: path,
            zipPaths: newPaths,
          ),
        )
        .toList()
      ..sort();

    return _PreparedTree(
      projectEntries: treeEntries,
      changedPaths: changedPaths,
      stalePaths: stalePaths,
    );
  }

  Future<ProjectUploadResult> _uploadViaContentsApi({
    required ZipProjectPreview project,
    required String repositoryFullName,
    required String branch,
    required String commitMessage,
    required _RepositorySnapshot snapshot,
    required void Function(ProjectUploadProgress progress)? onProgress,
  }) async {
    final candidates = <String, _ContentsCandidate>{};
    final newPaths = <String>{};
    final input = InputFileStream(project.path);
    final archive = ZipDecoder().decodeStream(input, verify: true);
    var processed = 0;

    try {
      for (final entry in archive) {
        if (!entry.isFile || entry.isSymbolicLink) continue;
        final validated = LocalProjectService.validateArchivePath(entry.name);
        final gitPath = _stripCommonRoot(validated, project.commonRoot);
        if (gitPath.isEmpty) continue;
        newPaths.add(gitPath);

        File? temporaryFile;
        List<int>? bytes;
        int contentLength;
        String contentBlobSha;
        try {
          if (entry.size > _streamingFileThreshold) {
            temporaryFile = File(
              p.join(
                Directory.systemTemp.path,
                'github_manager_contents_scan_${DateTime.now().microsecondsSinceEpoch}_$processed.tmp',
              ),
            );
            final output = OutputFileStream(temporaryFile.path);
            try {
              entry.writeContent(output);
            } finally {
              output.closeSync();
            }
            contentLength = await temporaryFile.length();
            contentBlobSha = await GitObjectHash.blobShaFile(temporaryFile);
          } else {
            bytes = entry.readBytes();
            if (bytes == null) {
              throw InvalidZipException(
                'Não foi possível ler $gitPath dentro do ZIP.',
                code: 'ZIP_ENTRY_READ_FAILED',
              );
            }
            contentLength = bytes.length;
            contentBlobSha = GitObjectHash.blobSha(bytes);
          }

          final mode = _gitMode(entry.mode);
          final existing = snapshot.existingEntries[gitPath];
          final unchanged = existing != null &&
              existing.type == 'blob' &&
              existing.mode == mode &&
              (existing.size == null || existing.size == contentLength) &&
              existing.sha == contentBlobSha;

          processed++;
          if (unchanged) {
            onProgress?.call(
              ProjectUploadProgress(
                phase: 'Arquivo já está atualizado',
                current: processed,
                total: project.fileCount,
                fileName: gitPath,
                kind: ProjectUploadProgressKind.unchanged,
                method: ProjectUploadMethod.contentsApi,
              ),
            );
          } else {
            candidates[gitPath] = _ContentsCandidate(
              path: gitPath,
              size: contentLength,
              mode: mode,
              existingSha: existing?.type == 'blob' ? existing?.sha : null,
              existingType: existing?.type,
            );
            onProgress?.call(
              ProjectUploadProgress(
                phase: 'Processando arquivos do projeto',
                current: processed,
                total: project.fileCount,
                fileName: gitPath,
                kind: ProjectUploadProgressKind.changed,
                method: ProjectUploadMethod.contentsApi,
              ),
            );
          }
        } finally {
          entry.clear();
          if (temporaryFile != null && await temporaryFile.exists()) {
            await temporaryFile.delete();
          }
        }
      }
    } finally {
      archive.clearSync();
      input.closeSync();
    }

    final stalePaths = snapshot.existingEntries.keys
        .where(
          (path) => shouldRemoveRepositoryPath(
            path: path,
            zipPaths: newPaths,
          ),
        )
        .toList()
      ..sort();

    if (stalePaths.isNotEmpty) {
      onProgress?.call(
        ProjectUploadProgress(
          phase: 'Removendo ${stalePaths.length} arquivo(s) antigo(s)',
          current: project.fileCount,
          total: project.fileCount,
          kind: ProjectUploadProgressKind.removed,
          affectedCount: stalePaths.length,
          method: ProjectUploadMethod.contentsApi,
        ),
      );
    }

    final operations = candidates.length + stalePaths.length;
    if (operations == 0) {
      return ProjectUploadResult(
        commitSha: snapshot.parentCommitSha,
        fileCount: project.fileCount,
        changed: false,
        method: ProjectUploadMethod.contentsApi,
      );
    }

    _validateContentsFallback(
      candidates: candidates.values,
      stalePaths: stalePaths,
      existingEntries: snapshot.existingEntries,
    );

    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Método individual habilitado para $operations alteração(ões)',
        current: project.fileCount,
        total: project.fileCount,
        kind: ProjectUploadProgressKind.recovery,
        method: ProjectUploadMethod.contentsApi,
      ),
    );

    var expectedHead = snapshot.parentCommitSha;
    var commitCount = 0;
    final pending = candidates.keys.toSet();
    final applyInput = InputFileStream(project.path);
    final applyArchive = ZipDecoder().decodeStream(applyInput, verify: true);
    final message = _commitMessage(project, commitMessage);

    try {
      for (final entry in applyArchive) {
        if (!entry.isFile || entry.isSymbolicLink) continue;
        final validated = LocalProjectService.validateArchivePath(entry.name);
        final gitPath = _stripCommonRoot(validated, project.commonRoot);
        if (!pending.contains(gitPath)) {
          entry.clear();
          continue;
        }

        final bytes = entry.readBytes();
        entry.clear();
        if (bytes == null) {
          throw InvalidZipException(
            'Não foi possível reler $gitPath para o método individual.',
            code: 'ZIP_ENTRY_READ_FAILED',
          );
        }

        onProgress?.call(
          ProjectUploadProgress(
            phase: 'Confirmando branch antes de atualizar: $gitPath',
            current: project.fileCount,
            total: project.fileCount,
            method: ProjectUploadMethod.contentsApi,
          ),
        );
        await _verifyBranchHead(
          repositoryFullName: repositoryFullName,
          branch: branch,
          expectedSha: expectedHead,
          method: ProjectUploadMethod.contentsApi,
          onProgress: onProgress,
        );
        onProgress?.call(
          ProjectUploadProgress(
            phase: 'Atualizando arquivo individual: $gitPath',
            current: project.fileCount,
            total: project.fileCount,
            method: ProjectUploadMethod.contentsApi,
          ),
        );

        final candidate = candidates[gitPath]!;
        final response = await _client.put<Map<String, dynamic>>(
          '/repos/$repositoryFullName/contents/${_encodeContentPath(gitPath)}',
          data: {
            'message': message,
            'content': base64Encode(bytes),
            'branch': branch,
            if (candidate.existingSha != null) 'sha': candidate.existingSha,
          },
        );
        final commit = response.data?['commit'];
        final commitSha = commit is Map ? commit['sha'] as String? : null;
        if (commitSha == null || commitSha.isEmpty) {
          throw const UnexpectedAppException('CONTENTS_COMMIT_SHA_MISSING');
        }
        expectedHead = commitSha;
        commitCount++;
        pending.remove(gitPath);
        onProgress?.call(
          ProjectUploadProgress(
            phase: 'Commit individual $commitCount/$operations criado: $gitPath',
            current: project.fileCount,
            total: project.fileCount,
            kind: ProjectUploadProgressKind.commitCreated,
            affectedCount: 1,
            method: ProjectUploadMethod.contentsApi,
          ),
        );
      }
    } finally {
      applyArchive.clearSync();
      applyInput.closeSync();
    }

    if (pending.isNotEmpty) {
      throw RepositoryFileException(
        'Não foi possível localizar novamente ${pending.length} arquivo(s) do ZIP para a recuperação individual.',
        code: 'UPLOAD_CONTENTS_FALLBACK_UNAVAILABLE',
      );
    }

    for (final stalePath in stalePaths) {
      onProgress?.call(
        ProjectUploadProgress(
          phase: 'Confirmando branch antes de remover: $stalePath',
          current: project.fileCount,
          total: project.fileCount,
          method: ProjectUploadMethod.contentsApi,
        ),
      );
      await _verifyBranchHead(
        repositoryFullName: repositoryFullName,
        branch: branch,
        expectedSha: expectedHead,
        method: ProjectUploadMethod.contentsApi,
        onProgress: onProgress,
      );
      onProgress?.call(
        ProjectUploadProgress(
          phase: 'Removendo arquivo individual: $stalePath',
          current: project.fileCount,
          total: project.fileCount,
          method: ProjectUploadMethod.contentsApi,
        ),
      );
      final existing = snapshot.existingEntries[stalePath]!;
      final response = await _client.delete<Map<String, dynamic>>(
        '/repos/$repositoryFullName/contents/${_encodeContentPath(stalePath)}',
        data: {
          'message': message,
          'sha': existing.sha,
          'branch': branch,
        },
      );
      final commit = response.data?['commit'];
      final commitSha = commit is Map ? commit['sha'] as String? : null;
      if (commitSha == null || commitSha.isEmpty) {
        throw const UnexpectedAppException('CONTENTS_DELETE_COMMIT_SHA_MISSING');
      }
      expectedHead = commitSha;
      commitCount++;
      onProgress?.call(
        ProjectUploadProgress(
          phase: 'Commit individual $commitCount/$operations criado: remoção de $stalePath',
          current: project.fileCount,
          total: project.fileCount,
          kind: ProjectUploadProgressKind.commitCreated,
          affectedCount: 1,
          method: ProjectUploadMethod.contentsApi,
        ),
      );
    }

    onProgress?.call(
      ProjectUploadProgress(
        phase: 'Concluído',
        current: project.fileCount,
        total: project.fileCount,
        method: ProjectUploadMethod.contentsApi,
      ),
    );
    return ProjectUploadResult(
      commitSha: expectedHead,
      fileCount: project.fileCount,
      changed: true,
      method: ProjectUploadMethod.contentsApi,
      commitCount: commitCount,
    );
  }

  void _validateContentsFallback({
    required Iterable<_ContentsCandidate> candidates,
    required List<String> stalePaths,
    required Map<String, _ExistingEntry> existingEntries,
  }) {
    final candidateList = candidates.toList(growable: false);
    final operations = candidateList.length + stalePaths.length;
    if (operations > _maxContentsFallbackOperations) {
      throw RepositoryFileException(
        'O método de arquivos individuais foi bloqueado por segurança: são $operations alterações. O limite é $_maxContentsFallbackOperations para evitar dezenas de commits e atualizações parciais.',
        code: 'UPLOAD_CONTENTS_FALLBACK_UNAVAILABLE',
      );
    }

    final tooLarge = candidateList
        .where((item) => item.size > _maxContentsFallbackFileBytes)
        .toList(growable: false);
    if (tooLarge.isNotEmpty) {
      throw RepositoryFileException(
        'O método individual não será usado porque ${tooLarge.first.path} ultrapassa ${_maxContentsFallbackFileBytes ~/ (1024 * 1024)} MB. A reconstrução da árvore é mais segura para arquivos grandes.',
        code: 'UPLOAD_CONTENTS_FALLBACK_TOO_LARGE',
      );
    }

    final nonBlobReplacement = candidateList
        .where((item) => item.existingType != null && item.existingType != 'blob')
        .toList(growable: false);
    if (nonBlobReplacement.isNotEmpty) {
      throw RepositoryFileException(
        'O método individual não será usado porque ${nonBlobReplacement.first.path} não é um arquivo comum no Git. Use a reconstrução da árvore.',
        code: 'UPLOAD_CONTENTS_FALLBACK_UNAVAILABLE',
      );
    }

    final executable = candidateList
        .where((item) => item.mode == '100755')
        .toList(growable: false);
    if (executable.isNotEmpty) {
      throw RepositoryFileException(
        'O método individual não será usado porque ${executable.first.path} é executável. A API de Contents pode perder esse modo de arquivo.',
        code: 'UPLOAD_CONTENTS_FALLBACK_EXECUTABLE',
      );
    }

    for (final stalePath in stalePaths) {
      if (existingEntries[stalePath]?.type != 'blob') {
        throw RepositoryFileException(
          'O método individual não será usado porque $stalePath não é um arquivo comum no Git. Use a reconstrução da árvore.',
          code: 'UPLOAD_CONTENTS_FALLBACK_UNAVAILABLE',
        );
      }
    }
  }

  Future<String> _createTree({
    required String repositoryFullName,
    required List<Map<String, dynamic>> entries,
    required ProjectUploadMethod method,
    required void Function(ProjectUploadProgress progress)? onProgress,
    String? baseTreeSha,
  }) async {
    onProgress?.call(
      ProjectUploadProgress(
        phase: method == ProjectUploadMethod.fullTree
            ? 'Reconstruindo árvore completa no GitHub'
            : 'Criando árvore incremental no GitHub',
        kind: method == ProjectUploadMethod.fullTree
            ? ProjectUploadProgressKind.recovery
            : ProjectUploadProgressKind.stage,
        method: method,
      ),
    );
    final response = await _withTransientRetry(
      operation: method == ProjectUploadMethod.fullTree
          ? 'reconstruir a árvore Git'
          : 'criar a árvore Git incremental',
      method: method,
      onProgress: onProgress,
      request: () => _client.post<Map<String, dynamic>>(
        '/repos/$repositoryFullName/git/trees',
        data: {
          if (baseTreeSha != null) 'base_tree': baseTreeSha,
          'tree': entries,
        },
      ),
    );
    final sha = response.data?['sha'] as String?;
    if (sha == null || sha.isEmpty) {
      throw const UnexpectedAppException('TREE_SHA_MISSING');
    }
    return sha;
  }

  Future<T> _withTransientRetry<T>({
    required Future<T> Function() request,
    required String operation,
    required ProjectUploadMethod method,
    required void Function(ProjectUploadProgress progress)? onProgress,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await request();
      } catch (error) {
        final delay = _transientRetryDelay(error, attempt);
        if (delay == null || attempt >= _maxTransientRetries) {
          rethrow;
        }
        attempt++;
        final recoveryReason = _recoveryErrorLabel(error);
        onProgress?.call(
          ProjectUploadProgress(
            phase:
                '$recoveryReason ao $operation • nova tentativa $attempt/$_maxTransientRetries em ${delay.inSeconds}s',
            kind: ProjectUploadProgressKind.recovery,
            method: method,
          ),
        );
        await Future<void>.delayed(delay);
      }
    }
  }

  Duration? _transientRetryDelay(Object error, int previousAttempts) {
    if (error is NetworkRequiredException) {
      return Duration(seconds: 2 << previousAttempts.clamp(0, 2).toInt());
    }
    if (error is GitHubRateLimitException && error.httpStatus == 429) {
      if (previousAttempts > 0) return null;
      return const Duration(seconds: 5);
    }
    if (error is GitHubHttpException) {
      final status = error.httpStatus;
      if (status == 408 || (status != null && status >= 500 && status <= 599)) {
        return Duration(seconds: 2 << previousAttempts.clamp(0, 2).toInt());
      }
    }
    return null;
  }

  String _recoveryErrorLabel(Object error) {
    if (error is AppException) {
      final parts = <String>[
        if (error.httpStatus != null) 'HTTP ${error.httpStatus}',
        if (error.technicalCode?.isNotEmpty == true) error.technicalCode!,
        if (error.endpoint?.trim().isNotEmpty == true) error.endpoint!.trim(),
      ];
      final apiMessage = error.apiMessage?.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (apiMessage?.isNotEmpty == true) {
        final compact = apiMessage!.length > 180
            ? '${apiMessage.substring(0, 177)}...'
            : apiMessage;
        parts.add('GitHub: $compact');
      }
      if (parts.isNotEmpty) return parts.join(' • ');
      if (error.message.trim().isNotEmpty) return error.message.trim();
    }
    return error.runtimeType.toString();
  }

  bool _shouldFallbackToFullTree(Object error) {
    if (error is! AppException) return false;
    if (error.technicalCode != 'GITHUB_VALIDATION') return false;
    return (error.endpoint ?? '').toLowerCase().contains('/git/trees');
  }

  Future<void> _verifyBranchHead({
    required String repositoryFullName,
    required String branch,
    required String expectedSha,
    required ProjectUploadMethod method,
    required void Function(ProjectUploadProgress progress)? onProgress,
  }) async {
    final endpoint = '/repos/$repositoryFullName/git/ref/heads/$branch';
    final response = await _withTransientRetry(
      operation: 'confirmar o estado da branch',
      method: method,
      onProgress: onProgress,
      request: () => _client.get<Map<String, dynamic>>(endpoint),
    );
    final object = response.data?['object'];
    final currentSha = object is Map ? object['sha'] as String? : null;
    if (currentSha == null || currentSha.isEmpty) {
      throw RepositoryFileException(
        'Não foi possível confirmar o estado atual da branch antes de publicar.',
        code: 'UPLOAD_BRANCH_HEAD_MISSING',
        endpoint: endpoint,
      );
    }
    if (currentSha != expectedSha) {
      throw RepositoryFileException(
        'A branch mudou enquanto o envio estava sendo preparado. O GitHub Manager interrompeu a publicação para não sobrescrever mudanças mais recentes.',
        code: 'UPLOAD_BRANCH_CHANGED',
        endpoint: endpoint,
        apiMessage:
            'SHA esperado ${_shortSha(expectedSha)} • SHA atual ${_shortSha(currentSha)}',
      );
    }
  }

  String _commitMessage(ZipProjectPreview project, String commitMessage) {
    final custom = commitMessage.trim();
    if (custom.isNotEmpty) return custom;
    return automaticCommitMessage(
      'Atualização',
      project: project.identityLabel,
      version: project.versionLabel,
    );
  }

  static String _encodeContentPath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  static String _stripCommonRoot(String path, String? root) {
    if (root == null || root.isEmpty) {
      return path;
    }
    final prefix = '$root/';
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  static String _gitMode(int mode) {
    final executable = mode & 0x49 != 0;
    return executable ? '100755' : '100644';
  }

  static String? _tryDecodeText(List<int> bytes) {
    if (bytes.contains(0)) {
      return null;
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }

  static String _shortSha(String sha) =>
      sha.length > 7 ? sha.substring(0, 7) : sha;
}

class _ExistingEntry {
  const _ExistingEntry({
    required this.mode,
    required this.type,
    required this.sha,
    required this.size,
  });

  final String mode;
  final String type;
  final String sha;
  final int? size;
}

class _RepositorySnapshot {
  const _RepositorySnapshot({
    required this.parentCommitSha,
    required this.baseTreeSha,
    required this.existingEntries,
  });

  final String parentCommitSha;
  final String baseTreeSha;
  final Map<String, _ExistingEntry> existingEntries;
}

class _PreparedTree {
  const _PreparedTree({
    required this.projectEntries,
    required this.changedPaths,
    required this.stalePaths,
  });

  final List<Map<String, dynamic>> projectEntries;
  final Set<String> changedPaths;
  final List<String> stalePaths;
}

class _ContentsCandidate {
  const _ContentsCandidate({
    required this.path,
    required this.size,
    required this.mode,
    required this.existingSha,
    required this.existingType,
  });

  final String path;
  final int size;
  final String mode;
  final String? existingSha;
  final String? existingType;
}
