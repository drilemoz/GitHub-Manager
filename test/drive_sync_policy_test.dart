import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/drive_sync/domain/drive_sync_link.dart';

void main() {
  const safe = {
    'identityBlocked': false,
    'versionIsNewer': true,
    'versionIsInternal': true,
    'repositoryVersionKnown': true,
    'permissionsConclusive': true,
    'previewAvailable': true,
    'deletionCount': 0,
    'hasChanges': true,
  };

  bool permitted(Map<String, Object> params) => DriveAutomaticPolicy.canPublish(
    identityBlocked: params['identityBlocked'] as bool,
    versionIsNewer: params['versionIsNewer'] as bool,
    versionIsInternal: params['versionIsInternal'] as bool,
    repositoryVersionKnown: params['repositoryVersionKnown'] as bool,
    permissionsConclusive: params['permissionsConclusive'] as bool,
    previewAvailable: params['previewAvailable'] as bool,
    deletionCount: params['deletionCount'] as int,
    hasChanges: params['hasChanges'] as bool,
  );

  test('publicação exige todas as condições, não apenas nome do ZIP', () {
    expect(permitted(safe), isTrue);
    for (final key in safe.keys) {
      final changed = Map<String, Object>.from(safe);
      changed[key] = key == 'deletionCount' ? 1 : !(safe[key] as bool);
      expect(permitted(changed), isFalse, reason: 'Condição $key');
    }
  });

  test('vínculo persiste histórico, segurança e confirmação opt-in', () {
    const link = DriveSyncLink(folderId: 'folder-id', folderName: 'Pulso Bateria',
      repositoryFullName: 'owner/repo', branch: 'main');
    expect(link.automatic, isFalse);
    expect(link.key, 'owner/repo@main');
    final restored = DriveSyncLink.fromJson(link.copyWith(
      automatic: true, pendingUploadId: 'upload-1',
      pendingFileId: 'drive-file', pendingModifiedTime: '2026-11-09T10:00:00Z',
    ).toJson());
    expect(restored?.automatic, isTrue);
    expect(restored?.pendingUploadId, 'upload-1');
    expect(DriveSyncLink.fromJson({'folderId': 'x'}), isNull);
  });

  test('extensão ZIP não permite pasta Drive como projeto', () {
    const zip = DriveFileEntry(id: '1', name: 'v1.ZIP', mimeType: 'application/octet-stream');
    const folder = DriveFileEntry(id: '2', name: 'v2.zip',
        mimeType: 'application/vnd.google-apps.folder');
    expect(zip.isZip, isTrue);
    expect(folder.isFolder, isTrue);
  });
}
