class ZipProjectPreview {
  const ZipProjectPreview({
    required this.path,
    required this.name,
    required this.archiveBytes,
    required this.uncompressedBytes,
    required this.fileCount,
    required this.folderCount,
    required this.projectType,
    required this.importantFiles,
    required this.commonRoot,
    this.projectName,
    this.packageName,
    this.applicationId,
    this.version,
    this.versionCode,
    this.versionSource,
    this.inferredVersion,
    this.hasWorkflowFiles = false,
    this.sha256,
    this.managedSnapshot = false,
  });

  final String path;
  final String name;
  final int archiveBytes;
  final int uncompressedBytes;
  final int fileCount;
  final int folderCount;
  final String projectType;
  final List<String> importantFiles;
  final String? commonRoot;
  final String? projectName;
  final String? packageName;
  final String? applicationId;
  final String? version;
  final int? versionCode;
  final String? versionSource;
  final String? inferredVersion;
  final bool hasWorkflowFiles;
  /// SHA-256 of the exact bytes approved in the preview.
  final String? sha256;
  /// True only for private selection copies created by LocalProjectService.
  final bool managedSnapshot;

  String get identityLabel =>
      projectName?.trim().isNotEmpty == true
          ? projectName!.trim()
          : packageName?.trim().isNotEmpty == true
              ? packageName!.trim()
              : name.replaceFirst(RegExp(r'\.zip$', caseSensitive: false), '');

  String? get versionLabel {
    final value = version?.trim();
    if (value == null || value.isEmpty) return null;
    if (versionCode == null || value.contains('+')) return value;
    return '$value+$versionCode';
  }

  String? get displayVersionLabel {
    final identified = versionLabel;
    if (identified != null) {
      final source = versionSource?.trim();
      return source == null || source.isEmpty ? identified : '$identified • $source';
    }
    final inferred = inferredVersion?.trim();
    if (inferred == null || inferred.isEmpty) return null;
    return '$inferred • pelo nome do ZIP';
  }
}


enum ProjectUploadMethod {
  incremental,
  fullTree,
  contentsApi,
}

extension ProjectUploadMethodLabel on ProjectUploadMethod {
  String get label => switch (this) {
        ProjectUploadMethod.incremental => 'Atualização incremental',
        ProjectUploadMethod.fullTree => 'Reconstrução da árvore',
        ProjectUploadMethod.contentsApi => 'Arquivos individuais',
      };

  String get shortLabel => switch (this) {
        ProjectUploadMethod.incremental => 'Incremental',
        ProjectUploadMethod.fullTree => 'Árvore completa',
        ProjectUploadMethod.contentsApi => 'Individual',
      };

  String get description => switch (this) {
        ProjectUploadMethod.incremental =>
          'Atualiza a árvore Git existente em um único commit.',
        ProjectUploadMethod.fullTree =>
          'Reconstrói a árvore final do projeto sem reaproveitar a árvore anterior.',
        ProjectUploadMethod.contentsApi =>
          'Atualiza poucos arquivos pela API de Contents. Pode criar mais de um commit.',
      };
}

enum ProjectUploadProgressKind {
  stage,
  unchanged,
  changed,
  resumed,
  transferStarted,
  removed,
  recovery,
  commitCreated,
}

class ProjectUploadProgress {
  const ProjectUploadProgress({
    required this.phase,
    this.current = 0,
    this.total = 0,
    this.fileName,
    this.kind = ProjectUploadProgressKind.stage,
    this.affectedCount = 0,
    this.method,
  });

  final String phase;
  final int current;
  final int total;
  final String? fileName;
  final ProjectUploadProgressKind kind;
  final int affectedCount;
  final ProjectUploadMethod? method;

  double? get fraction => total <= 0 ? null : current / total;

  bool get isFileActivity =>
      kind == ProjectUploadProgressKind.unchanged ||
      kind == ProjectUploadProgressKind.changed ||
      kind == ProjectUploadProgressKind.resumed ||
      kind == ProjectUploadProgressKind.transferStarted;
}

class ProjectUploadResult {
  const ProjectUploadResult({
    required this.commitSha,
    required this.fileCount,
    required this.changed,
    this.method = ProjectUploadMethod.incremental,
    this.commitCount = 0,
  });

  final String commitSha;
  final int fileCount;
  final bool changed;
  final ProjectUploadMethod method;
  final int commitCount;
}

class ProjectSyncPreview {
  const ProjectSyncPreview({
    required this.createdPaths,
    required this.modifiedPaths,
    required this.deletedPaths,
    required this.unchangedCount,
  });

  final List<String> createdPaths;
  final List<String> modifiedPaths;
  final List<String> deletedPaths;
  final int unchangedCount;

  int get createdCount => createdPaths.length;
  int get modifiedCount => modifiedPaths.length;
  int get deletedCount => deletedPaths.length;
  int get changedCount => createdCount + modifiedCount + deletedCount;
  bool get hasChanges => changedCount > 0;
}
