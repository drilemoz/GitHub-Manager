part of 'managed_upload.dart';

class _ManagedUploadCodec {
  const _ManagedUploadCodec._();

  static Map<String, dynamic> toJson(ManagedUpload item) => {
        'id': item.id,
        'repositoryFullName': item.repositoryFullName,
        'branch': item.branch,
        'zipPath': item.zipPath,
        'sourceZipPath': item.sourceZipPath,
        'zipName': item.zipName,
        'projectName': item.projectName,
        'projectType': item.projectType,
        'archiveBytes': item.archiveBytes,
        'archiveSha256': item.archiveSha256,
        'uncompressedBytes': item.uncompressedBytes,
        'fileCount': item.fileCount,
        'folderCount': item.folderCount,
        'importantFiles': item.importantFiles,
        'commonRoot': item.commonRoot,
        'packageName': item.packageName,
        'applicationId': item.applicationId,
        'version': item.version,
        'versionCode': item.versionCode,
        'buildPolicy': item.buildPolicy.name,
        'status': item.status.name,
        'createdAt': item.createdAt.toIso8601String(),
        'phase': item.phase,
        'current': item.current,
        'total': item.total,
        'currentFile': item.currentFile,
        'startedAt': item.startedAt?.toIso8601String(),
        'completedAt': item.completedAt?.toIso8601String(),
        'failedAt': item.failedAt?.toIso8601String(),
        'commitSha': item.commitSha,
        'changed': item.changed,
        'workflowName': item.workflowName,
        'workflowPath': item.workflowPath,
        'workflowRunId': item.workflowRunId,
        'dispatchTriggered': item.dispatchTriggered,
        'errorMessage': item.errorMessage,
        'errorCode': item.errorCode,
        'errorHttpStatus': item.errorHttpStatus,
        'errorEndpoint': item.errorEndpoint,
        'errorApiMessage': item.errorApiMessage,
        'failureStage': item.failureStage,
        'failureOperation': item.failureOperation,
        'failedFilePath': item.failedFilePath,
        'unchangedFiles': item.unchangedFiles,
        'changedFiles': item.changedFiles,
        'resumedFiles': item.resumedFiles,
        'removedFiles': item.removedFiles,
        'uploadMethod': item.uploadMethod.name,
        'fallbackCommitCount': item.fallbackCommitCount,
        'uploadedBlobShas': item.uploadedBlobShas,
        'changedFileSamples': item.changedFileSamples,
        'recoveryEvents': item.recoveryEvents,
        'logLines': item.logLines,
      };

  static ManagedUpload fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString();
    return ManagedUpload(
      id: json['id']?.toString() ?? '',
      repositoryFullName: json['repositoryFullName']?.toString() ?? '',
      branch: json['branch']?.toString() ?? 'main',
      zipPath: json['zipPath']?.toString() ?? '',
      sourceZipPath: json['sourceZipPath']?.toString() ??
          json['zipPath']?.toString() ??
          '',
      zipName: json['zipName']?.toString() ?? 'projeto.zip',
      projectName: json['projectName']?.toString() ?? 'Projeto',
      projectType: json['projectType']?.toString() ?? 'Projeto',
      archiveBytes: (json['archiveBytes'] as num?)?.toInt() ?? 0,
      archiveSha256: json['archiveSha256']?.toString(),
      uncompressedBytes: (json['uncompressedBytes'] as num?)?.toInt() ?? 0,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      folderCount: (json['folderCount'] as num?)?.toInt() ?? 0,
      importantFiles: (json['importantFiles'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: false) ??
          const <String>[],
      commonRoot: json['commonRoot']?.toString(),
      packageName: json['packageName']?.toString(),
      applicationId: json['applicationId']?.toString(),
      version: json['version']?.toString(),
      versionCode: (json['versionCode'] as num?)?.toInt(),
      buildPolicy: ManagedUploadBuildPolicy.values.firstWhere(
        (value) => value.name == json['buildPolicy']?.toString(),
        orElse: () => ManagedUploadBuildPolicy.automatic,
      ),
      status: ManagedUploadStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => ManagedUploadStatus.interrupted,
      ),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      phase: json['phase']?.toString() ?? 'Aguardando envio',
      current: (json['current'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      currentFile: json['currentFile']?.toString(),
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? ''),
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? ''),
      failedAt: DateTime.tryParse(json['failedAt']?.toString() ?? ''),
      commitSha: json['commitSha']?.toString(),
      changed: json['changed'] as bool?,
      workflowName: json['workflowName']?.toString(),
      workflowPath: json['workflowPath']?.toString(),
      workflowRunId: (json['workflowRunId'] as num?)?.toInt(),
      dispatchTriggered: json['dispatchTriggered'] as bool?,
      errorMessage: json['errorMessage']?.toString(),
      errorCode: json['errorCode']?.toString(),
      errorHttpStatus: (json['errorHttpStatus'] as num?)?.toInt(),
      errorEndpoint: json['errorEndpoint']?.toString(),
      errorApiMessage: json['errorApiMessage']?.toString(),
      failureStage: json['failureStage']?.toString(),
      failureOperation: json['failureOperation']?.toString(),
      failedFilePath: json['failedFilePath']?.toString(),
      unchangedFiles: (json['unchangedFiles'] as num?)?.toInt() ?? 0,
      changedFiles: (json['changedFiles'] as num?)?.toInt() ?? 0,
      resumedFiles: (json['resumedFiles'] as num?)?.toInt() ?? 0,
      removedFiles: (json['removedFiles'] as num?)?.toInt() ?? 0,
      uploadMethod: ProjectUploadMethod.values.firstWhere(
        (value) => value.name == json['uploadMethod']?.toString(),
        orElse: () => ProjectUploadMethod.incremental,
      ),
      fallbackCommitCount: (json['fallbackCommitCount'] as num?)?.toInt() ?? 0,
      uploadedBlobShas: (json['uploadedBlobShas'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          <String, String>{},
      changedFileSamples: (json['changedFileSamples'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: true) ??
          <String>[],
      recoveryEvents: (json['recoveryEvents'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: true) ??
          <String>[],
      logLines: (json['logLines'] as List?)
              ?.map((value) => value.toString())
              .toList(growable: true) ??
          <String>[],
    );
  }
}
