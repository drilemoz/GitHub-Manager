part of 'managed_upload.dart';

class _ManagedUploadState {
  const _ManagedUploadState(this.item);

  final ManagedUpload item;

  String get checkpointLabel {
    if (item.commitSha?.isNotEmpty == true) {
      return 'Commit salvo • retomada direta da build disponível';
    }
    if (item.uploadedBlobShas.isNotEmpty) {
      return '${item.uploadedBlobShas.length} arquivo(s) já enviado(s) no checkpoint';
    }
    return 'Checkpoint preparado';
  }

  String get syncSummaryLabel {
    if (item.fileCount <= 0) return 'Sem arquivos contabilizados';
    if (item.analyzedFiles <= 0) return '${item.fileCount} arquivos no ZIP';
    final parts = <String>[
      '${item.analyzedFiles} analisados',
      if (item.sentFiles > 0) '${item.sentFiles} enviados',
      if (item.unchangedFiles > 0) '${item.unchangedFiles} já atualizados',
      if (item.resumedFiles > 0) '${item.resumedFiles} retomados',
      if (item.removedFiles > 0) '${item.removedFiles} removidos',
    ];
    return parts.join(' • ');
  }

  Duration? get elapsed {
    final start = item.startedAt;
    if (start == null) return null;
    final end = item.completedAt ?? item.failedAt ?? DateTime.now();
    final value = end.difference(start);
    return value.isNegative ? Duration.zero : value;
  }

  String get elapsedLabel {
    final value = elapsed;
    if (value == null) return '—';
    final seconds = value.inSeconds;
    if (seconds < 60) return '${seconds}s';
    final minutes = value.inMinutes;
    final remainingSeconds = seconds % 60;
    if (minutes < 60) return '${minutes}min ${remainingSeconds}s';
    final hours = value.inHours;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}min';
  }

  String get buildTriggerLabel {
    if (item.buildPolicy == ManagedUploadBuildPolicy.skipNoWorkflow) {
      return 'Não utilizada neste projeto';
    }
    if (item.buildPolicy == ManagedUploadBuildPolicy.skipByUser) {
      return 'Não solicitada';
    }
    if (item.workflowRunId == null && item.workflowName == null) {
      return 'Não iniciada';
    }
    if (item.dispatchTriggered == true) return 'Iniciada manualmente';
    if (item.dispatchTriggered == false) {
      return 'Iniciada automaticamente pelo push';
    }
    return 'Iniciada';
  }

  double? get progress {
    if (item.status == ManagedUploadStatus.startingBuild) return null;
    if (item.total <= 0) return null;
    return (item.current / item.total).clamp(0, 1).toDouble();
  }

  String get versionLabel {
    final value = item.version?.trim();
    if (value == null || value.isEmpty) return 'Não identificada';
    if (item.versionCode == null || value.contains('+')) return value;
    return '$value+${item.versionCode}';
  }

  String get statusLabel => switch (item.status) {
        ManagedUploadStatus.queued => 'Na fila',
        ManagedUploadStatus.syncing => 'Enviando',
        ManagedUploadStatus.startingBuild => 'Iniciando build',
        ManagedUploadStatus.completed => 'Concluído',
        ManagedUploadStatus.noChanges => 'Sem alterações',
        ManagedUploadStatus.buildPending => 'Build pendente',
        ManagedUploadStatus.failed => 'Falhou',
        ManagedUploadStatus.interrupted => 'Interrompido',
      };

  ZipProjectPreview toProjectPreview() => ZipProjectPreview(
        path: item.zipPath,
        name: item.zipName,
        archiveBytes: item.archiveBytes,
        sha256: item.archiveSha256,
        uncompressedBytes: item.uncompressedBytes,
        fileCount: item.fileCount,
        folderCount: item.folderCount,
        projectType: item.projectType,
        importantFiles: List<String>.from(item.importantFiles),
        commonRoot: item.commonRoot,
        projectName: item.projectName,
        packageName: item.packageName,
        applicationId: item.applicationId,
        version: item.version,
        versionCode: item.versionCode,
      );
}
