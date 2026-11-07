import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';
import 'package:github_manager/features/uploads/data/upload_manager_service.dart';
import 'package:github_manager/features/uploads/domain/managed_upload.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('github-manager-upload-test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('queues uploads sequentially and ignores active duplicate', () async {
    var activeUploads = 0;
    var maxConcurrent = 0;
    var uploadCount = 0;

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      uploadCount++;
      activeUploads++;
      if (activeUploads > maxConcurrent) maxConcurrent = activeUploads;
      onProgress?.call(
        ProjectUploadProgress(
          phase: 'Enviando',
          current: 1,
          total: project.fileCount,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 25));
      activeUploads--;
      return ProjectUploadResult(
        commitSha: 'abcdef${uploadCount}1234567890',
        fileCount: project.fileCount,
        changed: true,
      );
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      onStatus?.call('Build encontrada');
      return RepositoryBuildLaunchResult(
        commitSha: commitSha,
        runs: const [],
        workflow: null,
        dispatchTriggered: false,
      );
    }

    final history = File('${temp.path}/history.json');
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => history,
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
    );
    addTearDown(manager.dispose);

    final firstZip = File('${temp.path}/first.zip')..writeAsBytesSync([1]);
    final secondZip = File('${temp.path}/second.zip')..writeAsBytesSync([2]);
    final first = manager.startBuild(
      project: _preview(firstZip.path, 'First'),
      repositoryFullName: 'owner/first',
      branch: 'main',
    );
    final duplicate = manager.startBuild(
      project: _preview(firstZip.path, 'First'),
      repositoryFullName: 'owner/first',
      branch: 'main',
    );
    manager.startBuild(
      project: _preview(secondZip.path, 'Second'),
      repositoryFullName: 'owner/second',
      branch: 'main',
    );

    expect(duplicate.id, first.id);
    expect(manager.items, hasLength(2));

    await manager.waitUntilIdle();

    expect(maxConcurrent, 1);
    expect(uploadCount, 2);
    expect(
      manager.items.every((item) => item.status == ManagedUploadStatus.completed),
      isTrue,
    );
  });

  test('restored upload reuses checkpoint and continues build when already synced', () async {
    final zip = File('${temp.path}/resume.zip')..writeAsBytesSync([1, 2, 3]);
    final history = File('${temp.path}/history.json');
    final original = ManagedUpload(
      id: 'resume-1',
      repositoryFullName: 'owner/resume',
      branch: 'main',
      zipPath: zip.path,
      zipName: 'resume.zip',
      projectName: 'Resume',
      projectType: 'Flutter',
      archiveBytes: 3,
      uncompressedBytes: 3,
      fileCount: 2,
      folderCount: 0,
      importantFiles: const ['pubspec.yaml'],
      commonRoot: null,
      packageName: 'resume',
      applicationId: 'br.com.test.resume',
      version: '1.0.0',
      versionCode: 1,
      status: ManagedUploadStatus.syncing,
      createdAt: DateTime(2026, 8, 27),
      current: 1,
      total: 2,
      uploadedBlobShas: const {'assets/big.bin': 'checkpoint-sha'},
    );
    await history.writeAsString(jsonEncode([original.toJson()]));

    Map<String, String>? receivedCheckpoint;
    var builds = 0;

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      receivedCheckpoint = Map<String, String>.from(reusableBlobShas);
      onProgress?.call(
        const ProjectUploadProgress(
          phase: 'Retomando arquivo já enviado',
          current: 1,
          total: 2,
          fileName: 'assets/big.bin',
        ),
      );
      return const ProjectUploadResult(
        commitSha: 'abcdef0123456789',
        fileCount: 2,
        changed: false,
      );
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      builds++;
      return RepositoryBuildLaunchResult(
        commitSha: commitSha,
        runs: const [],
        workflow: null,
        dispatchTriggered: false,
      );
    }

    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => history,
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
      restoreHistory: true,
    );
    addTearDown(manager.dispose);

    await manager.waitUntilIdle();

    expect(receivedCheckpoint, {'assets/big.bin': 'checkpoint-sha'});
    expect(builds, 1);
    final restored = manager.find('resume-1');
    expect(restored, isNotNull);
    expect(restored!.status, ManagedUploadStatus.completed);
    expect(restored.uploadedBlobShas, isEmpty);
    expect(restored.logLines.join(' '), contains('Retomada automática'));
  });

  test('restores build checkpoint even when the ZIP is no longer available', () async {
    final history = File('${temp.path}/build-history.json');
    final original = ManagedUpload(
      id: 'build-resume-1',
      repositoryFullName: 'owner/build-resume',
      branch: 'main',
      zipPath: '${temp.path}/missing-managed.zip',
      sourceZipPath: '${temp.path}/missing-source.zip',
      zipName: 'missing.zip',
      projectName: 'Build Resume',
      projectType: 'Flutter',
      archiveBytes: 10,
      uncompressedBytes: 20,
      fileCount: 3,
      folderCount: 1,
      importantFiles: const ['pubspec.yaml'],
      commonRoot: null,
      status: ManagedUploadStatus.syncing,
      createdAt: DateTime(2026, 8, 27),
      current: 3,
      total: 3,
      commitSha: '1234567890abcdef',
      changed: true,
    );
    await history.writeAsString(jsonEncode([original.toJson()]));

    var uploads = 0;
    var builds = 0;

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      uploads++;
      throw StateError('Upload should not run for a commit checkpoint');
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      builds++;
      expect(commitSha, '1234567890abcdef');
      return RepositoryBuildLaunchResult(
        commitSha: commitSha,
        runs: const [],
        workflow: null,
        dispatchTriggered: false,
      );
    }

    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => history,
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
      restoreHistory: true,
    );
    addTearDown(manager.dispose);

    await manager.waitUntilIdle();

    expect(uploads, 0);
    expect(builds, 1);
    final restored = manager.find('build-resume-1');
    expect(restored, isNotNull);
    expect(restored!.status, ManagedUploadStatus.completed);
    expect(
      restored.logLines.join(' '),
      contains('commit já existente'),
    );
  });

  test('no-change upload can run current commit build without reuploading', () async {
    var uploadCount = 0;
    var buildCount = 0;

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      uploadCount++;
      return ProjectUploadResult(
        commitSha: 'abcdef0123456789',
        fileCount: project.fileCount,
        changed: false,
      );
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      buildCount++;
      return RepositoryBuildLaunchResult(
        commitSha: commitSha,
        runs: const [],
        workflow: null,
        dispatchTriggered: true,
        workflowRunId: 99,
      );
    }

    final zip = File('${temp.path}/same.zip')..writeAsBytesSync([1]);
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => File('${temp.path}/history.json'),
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
    );
    addTearDown(manager.dispose);

    final item = manager.startBuild(
      project: _preview(zip.path, 'Same'),
      repositoryFullName: 'owner/same',
      branch: 'main',
    );
    await manager.waitUntilIdle();

    expect(item.status, ManagedUploadStatus.noChanges);
    expect(item.canRunBuildAnyway, isTrue);
    expect(buildCount, 0);

    await manager.runBuildAnyway(item.id);
    await manager.waitUntilIdle();

    expect(uploadCount, 1);
    expect(buildCount, 1);
    expect(item.status, ManagedUploadStatus.completed);
    expect(item.workflowRunId, 99);
  });

  test('upload failure preserves GitHub response and exact operation', () async {
    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      onProgress?.call(
        ProjectUploadProgress(
          phase: 'Removendo 2 arquivo(s) antigo(s)',
          current: project.fileCount,
          total: project.fileCount,
          kind: ProjectUploadProgressKind.removed,
          affectedCount: 2,
        ),
      );
      throw const GitHubValidationException(
        httpStatus: 422,
        endpoint: '/repos/owner/repo/git/trees',
        apiMessage: 'Validation Failed | Tree • campo sha • código invalid',
      );
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      throw StateError('Build should not start after upload failure');
    }

    final zip = File('${temp.path}/failure.zip')..writeAsBytesSync([1]);
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => File('${temp.path}/failure-history.json'),
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
    );
    addTearDown(manager.dispose);

    final item = manager.startBuild(
      project: _preview(zip.path, 'Failure'),
      repositoryFullName: 'owner/repo',
      branch: 'main',
    );
    await manager.waitUntilIdle();

    expect(item.status, ManagedUploadStatus.failed);
    expect(item.failureOperation, 'Removendo 2 arquivo(s) antigo(s)');
    expect(item.errorCode, 'GITHUB_VALIDATION');
    expect(item.errorHttpStatus, 422);
    expect(item.errorEndpoint, '/repos/owner/repo/git/trees');
    expect(item.errorApiMessage, contains('Validation Failed'));
    expect(item.failureRepositoryImpact, contains('branch não foi alterada'));
    expect(item.timelineLines.join(' '), contains('Falha durante'));
  });

  test('missing APK workflow completes project upload without build warning', () async {
    var uploadCount = 0;

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      uploadCount++;
      return ProjectUploadResult(
        commitSha: 'abcdef0123456789',
        fileCount: project.fileCount,
        changed: true,
      );
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      throw const RepositoryFileException(
        'Nenhum workflow de APK encontrado.',
        code: 'APK_WORKFLOW_NOT_FOUND',
      );
    }

    final zip = File('${temp.path}/no-workflow.zip')..writeAsBytesSync([1]);
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => File('${temp.path}/no-workflow-history.json'),
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
    );
    addTearDown(manager.dispose);

    final item = manager.startBuild(
      project: _preview(zip.path, 'NoWorkflow'),
      repositoryFullName: 'owner/repo',
      branch: 'dev',
    );
    await manager.waitUntilIdle();

    expect(uploadCount, 1);
    expect(item.status, ManagedUploadStatus.completed);
    expect(item.branch, 'dev');
    expect(item.phase, 'Projeto atualizado • Sem workflow de build');
    expect(item.errorCode, isNull);
    expect(item.canRetry, isFalse);
    expect(item.logLines.join(' '), contains('envio concluído sem build'));
  });

  test('pre-detected no-workflow project skips Actions entirely', () async {
    var buildCount = 0;

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      return ProjectUploadResult(
        commitSha: 'abcdef0123456789',
        fileCount: project.fileCount,
        changed: true,
      );
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      buildCount++;
      throw StateError('Actions should not be queried for this project');
    }

    final zip = File('${temp.path}/scripts-only.zip')..writeAsBytesSync([1]);
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => File('${temp.path}/scripts-history.json'),
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
    );
    addTearDown(manager.dispose);

    final item = manager.startBuild(
      project: _preview(zip.path, 'ScriptsOnly'),
      repositoryFullName: 'owner/scripts',
      branch: 'main',
      buildPolicy: ManagedUploadBuildPolicy.skipNoWorkflow,
    );
    await manager.waitUntilIdle();

    expect(buildCount, 0);
    expect(item.status, ManagedUploadStatus.completed);
    expect(item.phase, 'Projeto atualizado • Sem workflow de build');
    expect(item.buildTriggerLabel, 'Não utilizada neste projeto');
  });

  test('user can upload without starting a detected build', () async {
    var buildCount = 0;

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async =>
        ProjectUploadResult(
          commitSha: 'abcdef0123456789',
          fileCount: project.fileCount,
          changed: true,
        );

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      buildCount++;
      throw StateError('Build should have been skipped');
    }

    final zip = File('${temp.path}/skip-build.zip')..writeAsBytesSync([1]);
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => File('${temp.path}/skip-build-history.json'),
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
    );
    addTearDown(manager.dispose);

    final item = manager.startBuild(
      project: _preview(zip.path, 'SkipBuild'),
      repositoryFullName: 'owner/app',
      branch: 'develop',
      buildPolicy: ManagedUploadBuildPolicy.skipByUser,
    );
    await manager.waitUntilIdle();

    expect(buildCount, 0);
    expect(item.status, ManagedUploadStatus.completed);
    expect(item.phase, 'Projeto atualizado • Build não solicitada');
    expect(item.buildTriggerLabel, 'Não solicitada');
  });

  test('build launch problem keeps successful upload and retries build only', () async {
    var uploadCount = 0;
    var buildCount = 0;

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      uploadCount++;
      return ProjectUploadResult(
        commitSha: 'abcdef0123456789',
        fileCount: project.fileCount,
        changed: true,
      );
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      buildCount++;
      if (buildCount == 1) {
        throw const RepositoryFileException(
          'Workflow de APK sem gatilho utilizável.',
          code: 'APK_WORKFLOW_TRIGGER_MISSING',
        );
      }
      return RepositoryBuildLaunchResult(
        commitSha: commitSha,
        runs: const [],
        workflow: null,
        dispatchTriggered: false,
      );
    }

    final zip = File('${temp.path}/build-pending.zip')..writeAsBytesSync([1]);
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => File('${temp.path}/build-pending-history.json'),
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
    );
    addTearDown(manager.dispose);

    final item = manager.startBuild(
      project: _preview(zip.path, 'BuildPending'),
      repositoryFullName: 'owner/repo',
      branch: 'main',
    );
    await manager.waitUntilIdle();

    expect(item.status, ManagedUploadStatus.buildPending);
    expect(item.commitSha, 'abcdef0123456789');
    expect(item.errorCode, 'APK_WORKFLOW_TRIGGER_MISSING');
    expect(item.canRetry, isTrue);
    expect(uploadCount, 1);

    await manager.retry(item.id);
    await manager.waitUntilIdle();

    expect(uploadCount, 1);
    expect(buildCount, 2);
    expect(item.status, ManagedUploadStatus.completed);
  });

  test('retry alternative switches tree validation from incremental to full tree', () async {
    final methods = <ProjectUploadMethod>[];
    final automaticFlags = <bool>[];

    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      methods.add(method);
      automaticFlags.add(allowAutomaticRecovery);
      if (methods.length == 1) {
        throw const GitHubValidationException(
          httpStatus: 422,
          endpoint: '/repos/owner/repo/git/trees',
          apiMessage: 'Validation Failed',
        );
      }
      return ProjectUploadResult(
        commitSha: 'abcdef0123456789',
        fileCount: project.fileCount,
        changed: false,
        method: method,
      );
    }

    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async {
      throw StateError('Build should not run in this test');
    }

    final zip = File('${temp.path}/recovery.zip')..writeAsBytesSync([1]);
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => File('${temp.path}/recovery-history.json'),
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
      automaticRecoveryEnabled: () async => true,
    );
    addTearDown(manager.dispose);

    final item = manager.startBuild(
      project: _preview(zip.path, 'Recovery'),
      repositoryFullName: 'owner/repo',
      branch: 'main',
    );
    await manager.waitUntilIdle();

    expect(item.status, ManagedUploadStatus.failed);
    expect(item.recommendedRecoveryMethod, ProjectUploadMethod.fullTree);

    await manager.retryAlternative(item.id);
    await manager.waitUntilIdle();

    expect(methods, [ProjectUploadMethod.incremental, ProjectUploadMethod.fullTree]);
    expect(automaticFlags, [true, false]);
    expect(item.uploadMethod, ProjectUploadMethod.fullTree);
    expect(item.status, ManagedUploadStatus.noChanges);
  });

  test('wrong fingerprint blocks queued upload before touching GitHub', () async {
    var uploadCalls = 0;
    Future<ProjectUploadResult> upload({
      required ZipProjectPreview project,
      required String repositoryFullName,
      required String branch,
      required String commitMessage,
      void Function(ProjectUploadProgress progress)? onProgress,
      required Map<String, String> reusableBlobShas,
      void Function(String path, String sha)? onBlobUploaded,
      required ProjectUploadMethod method,
      required bool allowAutomaticRecovery,
    }) async {
      uploadCalls++;
      throw StateError('Must never call GitHub for altered ZIP');
    }
    Future<RepositoryBuildLaunchResult> ensure({
      required String repositoryFullName,
      required String branch,
      required String commitSha,
      void Function(String status)? onStatus,
      required int verificationAttempts,
      required Duration verificationDelay,
      required Duration postDispatchDelay,
    }) async => throw StateError('No build expected');

    final zip = File('${temp.path}/source.zip')..writeAsBytesSync([9]);
    final manager = UploadManagerService.forTest(
      uploadZip: upload,
      ensureBuild: ensure,
      historyFileFactory: () async => File('${temp.path}/fingerprint-history.json'),
      queueDirectoryFactory: () async => Directory('${temp.path}/queue'),
    );
    addTearDown(manager.dispose);
    final item = manager.startBuild(
      project: _preview(zip.path, 'Wrong', sha256: List<String>.filled(64, '0').join()),
      repositoryFullName: 'owner/repo',
      branch: 'main',
    );
    await manager.waitUntilIdle();
    expect(item.status, ManagedUploadStatus.failed);
    expect(item.errorCode, 'UPLOAD_ZIP_HASH_MISMATCH');
    expect(uploadCalls, 0);
  });

}

ZipProjectPreview _preview(String path, String name, {String? sha256}) => ZipProjectPreview(
      path: path,
      name: '$name.zip',
      archiveBytes: 1,
      sha256: sha256,
      uncompressedBytes: 1,
      fileCount: 1,
      folderCount: 0,
      projectType: 'Flutter',
      importantFiles: const ['pubspec.yaml'],
      commonRoot: null,
      projectName: name,
      packageName: name.toLowerCase(),
      applicationId: 'br.com.test.${name.toLowerCase()}',
      version: '1.0.0',
      versionCode: 1,
    );

