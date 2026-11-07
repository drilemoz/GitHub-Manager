import 'package:github_manager/features/projects/domain/zip_project.dart';

part 'managed_upload_codec.dart';
part 'managed_upload_failure.dart';
part 'managed_upload_lifecycle.dart';
part 'managed_upload_report.dart';
part 'managed_upload_state.dart';

enum ManagedUploadBuildPolicy {
  automatic,
  skipNoWorkflow,
  skipByUser,
}

enum ManagedUploadStatus {
  queued,
  syncing,
  startingBuild,
  completed,
  noChanges,
  buildPending,
  failed,
  interrupted,
}

class ManagedUpload {
  ManagedUpload({
    required this.id,
    required this.repositoryFullName,
    required this.branch,
    required this.zipPath,
    String? sourceZipPath,
    required this.zipName,
    required this.projectName,
    required this.projectType,
    required this.archiveBytes,
    required this.uncompressedBytes,
    required this.fileCount,
    required this.folderCount,
    required this.importantFiles,
    required this.commonRoot,
    required this.status,
    required this.createdAt,
    this.packageName,
    this.applicationId,
    this.version,
    this.versionCode,
    this.archiveSha256,
    this.buildPolicy = ManagedUploadBuildPolicy.automatic,
    this.phase = 'Aguardando envio',
    this.current = 0,
    this.total = 0,
    this.currentFile,
    this.startedAt,
    this.completedAt,
    this.failedAt,
    this.commitSha,
    this.changed,
    this.workflowName,
    this.workflowPath,
    this.workflowRunId,
    this.dispatchTriggered,
    this.errorMessage,
    this.errorCode,
    this.errorHttpStatus,
    this.errorEndpoint,
    this.errorApiMessage,
    this.failureStage,
    this.failureOperation,
    this.failedFilePath,
    this.unchangedFiles = 0,
    this.changedFiles = 0,
    this.resumedFiles = 0,
    this.removedFiles = 0,
    this.uploadMethod = ProjectUploadMethod.incremental,
    this.fallbackCommitCount = 0,
    Map<String, String>? uploadedBlobShas,
    List<String>? changedFileSamples,
    List<String>? recoveryEvents,
    List<String>? logLines,
  }) : sourceZipPath = sourceZipPath ?? zipPath,
        uploadedBlobShas = Map<String, String>.from(
          uploadedBlobShas ?? const <String, String>{},
        ),
        changedFileSamples = List<String>.from(
          changedFileSamples ?? const <String>[],
        ),
        recoveryEvents = List<String>.from(
          recoveryEvents ?? const <String>[],
        ),
        logLines = logLines ?? <String>[];

  final String id;
  final String repositoryFullName;
  final String branch;
  String zipPath;
  final String sourceZipPath;
  final String zipName;
  final String projectName;
  final String projectType;
  final int archiveBytes;
  final int uncompressedBytes;
  final int fileCount;
  final int folderCount;
  final List<String> importantFiles;
  final String? commonRoot;
  final String? packageName;
  final String? applicationId;
  final String? version;
  final int? versionCode;
  final String? archiveSha256;
  ManagedUploadBuildPolicy buildPolicy;
  ManagedUploadStatus status;
  final DateTime createdAt;
  String phase;
  int current;
  int total;
  String? currentFile;
  DateTime? startedAt;
  DateTime? completedAt;
  DateTime? failedAt;
  String? commitSha;
  bool? changed;
  String? workflowName;
  String? workflowPath;
  int? workflowRunId;
  bool? dispatchTriggered;
  String? errorMessage;
  String? errorCode;
  int? errorHttpStatus;
  String? errorEndpoint;
  String? errorApiMessage;
  String? failureStage;
  String? failureOperation;
  String? failedFilePath;
  int unchangedFiles;
  int changedFiles;
  int resumedFiles;
  int removedFiles;
  ProjectUploadMethod uploadMethod;
  int fallbackCommitCount;
  final Map<String, String> uploadedBlobShas;
  final List<String> changedFileSamples;
  final List<String> recoveryEvents;
  final List<String> logLines;

  bool get shouldStartBuild => buildPolicy == ManagedUploadBuildPolicy.automatic;

  bool get isActive =>
      status == ManagedUploadStatus.queued ||
      status == ManagedUploadStatus.syncing ||
      status == ManagedUploadStatus.startingBuild;

  bool get canRetry =>
      status == ManagedUploadStatus.buildPending ||
      status == ManagedUploadStatus.failed ||
      status == ManagedUploadStatus.interrupted;

  bool get isBuildPending => status == ManagedUploadStatus.buildPending;

  bool get canRunBuildAnyway =>
      status == ManagedUploadStatus.noChanges &&
      commitSha != null &&
      commitSha!.isNotEmpty;

  bool get hasCheckpoint =>
      uploadedBlobShas.isNotEmpty || (commitSha?.isNotEmpty ?? false);

  bool get hasBuildCheckpoint {
    if (commitSha?.isNotEmpty != true) return false;
    if (status == ManagedUploadStatus.startingBuild ||
        status == ManagedUploadStatus.buildPending ||
        changed == true) {
      return true;
    }
    return phase.toLowerCase().contains('build');
  }

  String get checkpointLabel => _ManagedUploadState(this).checkpointLabel;
  int get analyzedFiles => unchangedFiles + changedFiles + resumedFiles;
  int get sentFiles => changedFiles;
  String get syncSummaryLabel => _ManagedUploadState(this).syncSummaryLabel;
  Duration? get elapsed => _ManagedUploadState(this).elapsed;
  String get elapsedLabel => _ManagedUploadState(this).elapsedLabel;
  String get buildTriggerLabel => _ManagedUploadState(this).buildTriggerLabel;
  double? get progress => _ManagedUploadState(this).progress;
  String get versionLabel => _ManagedUploadState(this).versionLabel;
  String get statusLabel => _ManagedUploadState(this).statusLabel;
  ZipProjectPreview toProjectPreview() =>
      _ManagedUploadState(this).toProjectPreview();

  String get failureOperationLabel =>
      _ManagedUploadFailureDiagnostics(this).failureOperationLabel;
  String get githubFailureResponse =>
      _ManagedUploadFailureDiagnostics(this).githubFailureResponse;
  int get recoveryOperationEstimate =>
      _ManagedUploadFailureDiagnostics(this).recoveryOperationEstimate;
  bool get canSuggestContentsRecovery =>
      _ManagedUploadFailureDiagnostics(this).canSuggestContentsRecovery;
  ProjectUploadMethod? get recommendedRecoveryMethod =>
      _ManagedUploadFailureDiagnostics(this).recommendedRecoveryMethod;
  bool get hasAlternativeRecoveryMethod =>
      _ManagedUploadFailureDiagnostics(this).hasAlternativeRecoveryMethod;
  bool get shouldRetrySameMethod =>
      _ManagedUploadFailureDiagnostics(this).shouldRetrySameMethod;
  String get recoveryRecommendationLabel =>
      _ManagedUploadFailureDiagnostics(this).recoveryRecommendationLabel;
  String get failureProgressExplanation =>
      _ManagedUploadFailureDiagnostics(this).failureProgressExplanation;
  String? get failureRepositoryImpact =>
      _ManagedUploadFailureDiagnostics(this).failureRepositoryImpact;
  String get failureMeaning =>
      _ManagedUploadFailureDiagnostics(this).failureMeaning;
  String get failureSuggestedAction =>
      _ManagedUploadFailureDiagnostics(this).failureSuggestedAction;
  bool get canShowBuildTriggerFix =>
      _ManagedUploadFailureDiagnostics(this).canShowBuildTriggerFix;
  String get buildTriggerFixSnippet =>
      _ManagedUploadFailureDiagnostics(this).buildTriggerFixSnippet;
  String get failureDiagnosticText =>
      _ManagedUploadFailureDiagnostics(this).failureDiagnosticText;

  List<String> get timelineLines => _ManagedUploadReport(this).timelineLines;
  String get technicalLog => _ManagedUploadReport(this).technicalLog;

  void resetFileSummary() => _ManagedUploadLifecycle(this).resetFileSummary();
  void recordProgress(ProjectUploadProgress progress) =>
      _ManagedUploadLifecycle(this).recordProgress(progress);
  void addLog(String text) => _ManagedUploadLifecycle(this).addLog(text);
  void markInterruptedByAppExit() =>
      _ManagedUploadLifecycle(this).markInterruptedByAppExit();
  void prepareAutomaticResume({required bool buildOnly}) =>
      _ManagedUploadLifecycle(this).prepareAutomaticResume(buildOnly: buildOnly);
  void resetForRetry({
    required bool buildOnly,
    ProjectUploadMethod? method,
  }) =>
      _ManagedUploadLifecycle(this).resetForRetry(
        buildOnly: buildOnly,
        method: method,
      );

  Map<String, dynamic> toJson() => _ManagedUploadCodec.toJson(this);

  factory ManagedUpload.fromJson(Map<String, dynamic> json) =>
      _ManagedUploadCodec.fromJson(json);
}
