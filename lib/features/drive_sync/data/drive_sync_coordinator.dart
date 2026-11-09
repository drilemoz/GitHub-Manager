import 'package:github_manager/features/drive_sync/data/drive_sync_store.dart';
import 'package:github_manager/features/drive_sync/data/google_drive_read_service.dart';
import 'package:github_manager/features/drive_sync/domain/drive_sync_link.dart';
import 'package:github_manager/features/projects/data/git_project_upload_service.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';
import 'package:github_manager/features/projects/domain/project_safety_check.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:github_manager/features/repositories/data/repository_project_info_service.dart';
import 'package:github_manager/features/repositories/data/repository_service.dart';
import 'package:github_manager/features/permissions/data/permission_preflight_service.dart';
import 'package:github_manager/features/permissions/domain/repository_permission_preflight.dart';
import 'package:github_manager/features/permissions/domain/repository_permission_report.dart';
import 'package:github_manager/features/uploads/data/upload_manager_service.dart';
import 'package:github_manager/features/uploads/domain/managed_upload.dart';

class DriveSyncCandidate {
  const DriveSyncCandidate({
    required this.link,
    required this.file,
    required this.project,
    required this.reason,
    required this.canQueue,
    this.syncPreview,
  });
  final DriveSyncLink link;
  final DriveFileEntry file;
  final ZipProjectPreview? project;
  final String reason;
  final bool canQueue;
  final ProjectSyncPreview? syncPreview;
}

/// Never grants permissions or confirms destructive uploads on behalf of a
/// background job. All checks must be conclusive before enqueueing a ZIP.
class DriveSyncCoordinator {
  DriveSyncCoordinator({
    required this.drive,
    required this.store,
    required this.repositories,
    required this.infoService,
    required this.uploadService,
    required this.permissionService,
    required this.manager,
  });
  final GoogleDriveReadService drive;
  final DriveSyncStore store;
  final RepositoryService repositories;
  final RepositoryProjectInfoService infoService;
  final GitProjectUploadService uploadService;
  final PermissionPreflightService permissionService;
  final UploadManagerService manager;

  bool _running = false;

  /// Reconcile a queued file on the next check after process restart. A
  /// completed Git commit is acknowledged even if starting its build failed.
  Future<DriveSyncLink> _reconcile(DriveSyncLink link) async {
    if (link.pendingUploadId == null) return link;
    await manager.ready;
    ManagedUpload? pending;
    for (final item in manager.items) {
      if (item.id == link.pendingUploadId) { pending = item; break; }
    }
    if (pending == null) {
      // Never re-publish blindly when history has been lost.
      throw StateError('O histórico da sincronização anterior não está disponível. '
          'Verifique o GitHub e refaça o vínculo se necessário.');
    }
    if (pending.isActive) {
      throw StateError('Esta versão já está na fila de envio.');
    }
    if (pending.commitSha != null && pending.commitSha!.isNotEmpty ||
        pending.status == ManagedUploadStatus.noChanges ||
        pending.status == ManagedUploadStatus.completed) {
      final updated = DriveSyncLink(
        folderId: link.folderId, folderName: link.folderName,
        repositoryFullName: link.repositoryFullName, branch: link.branch,
        automatic: link.automatic,
        lastCompletedFileId: link.pendingFileId,
        lastCompletedModifiedTime: link.pendingModifiedTime,
      );
      await store.upsert(updated);
      return updated;
    }
    throw StateError('O envio anterior falhou ou foi interrompido. '
        'Revise-o na Central de Envios antes de tentar novamente.');
  }

  Future<DriveSyncCandidate?> check(DriveSyncLink link) async {
    if (_running) throw StateError('Outra sincronização já está em andamento.');
    _running = true;
    try {
      final current = await _reconcile(link);
      final latest = await drive.latestZip(current.folderId);
      if (latest == null) return null;
      if (current.lastCompletedFileId == latest.id &&
          current.lastCompletedModifiedTime == latest.modifiedTime) {
        return DriveSyncCandidate(link: current, file: latest, project: null,
          reason: 'Este ZIP já foi sincronizado.', canQueue: false);
      }
      final project = await drive.downloadAndAnalyze(latest);
      try {
        final repo = await repositories.getRepository(current.repositoryFullName);
        if (repo.isArchived) {
          return DriveSyncCandidate(link: current, file: latest, project: project,
            reason: 'Repositório arquivado.', canQueue: false);
        }
        final repoInfo = await infoService.load(repo, branch: current.branch);
        final safety = ProjectSafetyCheck.compare(
          project: project, repository: repo, repositoryInfo: repoInfo);
        final permission = await permissionService.check(
          current.repositoryFullName,
          project.hasWorkflowFiles
              ? RepositoryCriticalAction.syncProjectWithWorkflows
              : RepositoryCriticalAction.syncProject,
        );
        // An empty diagnostics result must never be interpreted as "write OK".
        // The current GitHub API only confirms classic PAT write scopes by
        // inference. Fine-grained PATs remain unknown and require the manual
        // upload route until an explicit grant check is available.
        final report = await permissionService.getReport(current.repositoryFullName);
        final contentWrite = [
          for (final area in report.capabilities)
            if (area.area == RepositoryPermissionArea.contents) area.write,
        ];
        final writingDiagnosed = contentWrite.length == 1 &&
            (contentWrite.single?.verdict == PermissionVerdict.allowed ||
                contentWrite.single?.verdict == PermissionVerdict.inferred);
        // Strict fail-closed preflight. Even a manual action from this screen
        // cannot circumvent the regular import's warnings/deletion approval.
        if (safety.blocked || safety.warning ||
            safety.versionComparison != ProjectVersionComparison.newer ||
            safety.identitySource == 'não confirmada' ||
            safety.identitySource == 'nome do ZIP (pista)' ||
            project.version == null || project.versionSource == null ||
            repoInfo.version == null || repoInfo.metadataIssue != null ||
            !writingDiagnosed || permission.blocked || permission.unknown.isNotEmpty ||
            permission.diagnosticUnavailable) {
          return DriveSyncCandidate(
            link: current, file: latest, project: project,
            reason: safety.blocked || safety.warning
                ? safety.message
                : 'Versão interna, identidade ou permissões não foram '
                  'confirmadas. Use o envio manual para revisar o ZIP.',
            canQueue: false,
          );
        }
        final preview = await uploadService.previewZipSync(
          project: project, repositoryFullName: current.repositoryFullName,
          branch: current.branch);
        final permitted = DriveAutomaticPolicy.canPublish(
          identityBlocked: safety.blocked || safety.warning ||
              safety.identitySource == 'não confirmada' ||
              safety.identitySource == 'nome do ZIP (pista)', 
          versionIsNewer: safety.versionComparison == ProjectVersionComparison.newer,
          versionIsInternal: project.version != null && project.versionSource != null,
          repositoryVersionKnown: repoInfo.version != null && repoInfo.metadataIssue == null,
          permissionsConclusive: writingDiagnosed && !permission.blocked &&
              permission.unknown.isEmpty && !permission.diagnosticUnavailable,
          previewAvailable: true,
          deletionCount: preview.deletedCount,
          hasChanges: preview.hasChanges,
        );
        return DriveSyncCandidate(
          link: current, file: latest, project: project,
          reason: permitted ? 'Versão nova verificada e pronta para publicação.'
              : preview.deletedCount > 0
                  ? '${preview.deletedCount} remoções detectadas. '
                    'A sincronização pelo Drive foi bloqueada. '
                    'Use o envio manual para confirmar as remoções.'
                  : 'Nenhuma alteração segura para enviar.',
          canQueue: permitted, syncPreview: preview,
        );
      } catch (_) {
        await LocalProjectService.discardPreviewPath(project.path);
        rethrow;
      }
    } finally {
      _running = false;
    }
  }

  Future<ManagedUpload> queue(DriveSyncCandidate candidate) async {
    if (!candidate.canQueue || candidate.project == null) {
      throw StateError('A atualização não passou na verificação de segurança.');
    }
    final project = candidate.project!;
    await LocalProjectService.verifyFingerprint(project);
    final item = manager.startBuild(
      project: project,
      repositoryFullName: candidate.link.repositoryFullName,
      branch: candidate.link.branch,
    );
    // Record the pending id to avoid duplicate sends. Never mark synced until
    // the manager confirms the commit on GitHub.
    await store.upsert(DriveSyncLink(
      folderId: candidate.link.folderId,
      folderName: candidate.link.folderName,
      repositoryFullName: candidate.link.repositoryFullName,
      branch: candidate.link.branch,
      automatic: candidate.link.automatic,
      lastCompletedFileId: candidate.link.lastCompletedFileId,
      lastCompletedModifiedTime: candidate.link.lastCompletedModifiedTime,
      pendingUploadId: item.id,
      pendingFileId: candidate.file.id,
      pendingModifiedTime: candidate.file.modifiedTime,
    ));
    return item;
  }
}
