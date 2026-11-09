/// One explicit Drive-folder to GitHub-repository association.
/// Authorization is tied to a Google account, not to a reusable raw token.
class DriveSyncLink {
  const DriveSyncLink({
    required this.folderId,
    required this.folderName,
    required this.repositoryFullName,
    required this.branch,
    this.automatic = false,
    this.lastCompletedFileId,
    this.lastCompletedModifiedTime,
    this.pendingUploadId,
    this.pendingFileId,
    this.pendingModifiedTime,
  });

  final String folderId;
  final String folderName;
  final String repositoryFullName;
  final String branch;
  final bool automatic;
  final String? lastCompletedFileId;
  final String? lastCompletedModifiedTime;
  final String? pendingUploadId;
  final String? pendingFileId;
  final String? pendingModifiedTime;

  String get key => '${repositoryFullName.toLowerCase()}@$branch';

  DriveSyncLink copyWith({
    bool? automatic,
    String? lastCompletedFileId,
    String? lastCompletedModifiedTime,
    String? pendingUploadId,
    String? pendingFileId,
    String? pendingModifiedTime,
  }) => DriveSyncLink(
    folderId: folderId,
    folderName: folderName,
    repositoryFullName: repositoryFullName,
    branch: branch,
    automatic: automatic ?? this.automatic,
    lastCompletedFileId: lastCompletedFileId ?? this.lastCompletedFileId,
    lastCompletedModifiedTime:
        lastCompletedModifiedTime ?? this.lastCompletedModifiedTime,
    pendingUploadId: pendingUploadId ?? this.pendingUploadId,
    pendingFileId: pendingFileId ?? this.pendingFileId,
    pendingModifiedTime: pendingModifiedTime ?? this.pendingModifiedTime,
  );

  Map<String, Object?> toJson() => {
    'folderId': folderId,
    'folderName': folderName,
    'repositoryFullName': repositoryFullName,
    'branch': branch,
    'automatic': automatic,
    'lastCompletedFileId': lastCompletedFileId,
    'lastCompletedModifiedTime': lastCompletedModifiedTime,
    'pendingUploadId': pendingUploadId,
    'pendingFileId': pendingFileId,
    'pendingModifiedTime': pendingModifiedTime,
  };

  static DriveSyncLink? fromJson(Object? source) {
    if (source is! Map) return null;
    final folderId = source['folderId'];
    final folderName = source['folderName'];
    final repositoryFullName = source['repositoryFullName'];
    final branch = source['branch'];
    if (folderId is! String || folderId.trim().isEmpty ||
        folderName is! String || repositoryFullName is! String ||
        !RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(repositoryFullName) ||
        branch is! String || branch.trim().isEmpty) return null;
    return DriveSyncLink(
      folderId: folderId,
      folderName: folderName,
      repositoryFullName: repositoryFullName,
      branch: branch,
      automatic: source['automatic'] == true,
      lastCompletedFileId: source['lastCompletedFileId'] is String
          ? source['lastCompletedFileId'] as String : null,
      lastCompletedModifiedTime: source['lastCompletedModifiedTime'] is String
          ? source['lastCompletedModifiedTime'] as String : null,
      pendingUploadId: source['pendingUploadId'] is String
          ? source['pendingUploadId'] as String : null,
      pendingFileId: source['pendingFileId'] is String
          ? source['pendingFileId'] as String : null,
      pendingModifiedTime: source['pendingModifiedTime'] is String
          ? source['pendingModifiedTime'] as String : null,
    );
  }
}

class DriveFileEntry {
  const DriveFileEntry({
    required this.id,
    required this.name,
    required this.mimeType,
    this.modifiedTime,
    this.size,
  });
  final String id;
  final String name;
  final String mimeType;
  final String? modifiedTime;
  final int? size;

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';
  bool get isZip => mimeType == 'application/zip' ||
      mimeType == 'application/x-zip-compressed' ||
      name.toLowerCase().endsWith('.zip');

  static DriveFileEntry? fromJson(Object? source) {
    if (source is! Map) return null;
    final id = source['id'];
    final name = source['name'];
    final mimeType = source['mimeType'];
    if (id is! String || id.isEmpty || name is! String ||
        mimeType is! String) return null;
    return DriveFileEntry(
      id: id,
      name: name,
      mimeType: mimeType,
      modifiedTime: source['modifiedTime'] is String
          ? source['modifiedTime'] as String : null,
      size: int.tryParse('${source['size'] ?? ''}'),
    );
  }
}

/// Fail closed: only internal, explicit project version newer than GitHub.
/// Unknown or same versions and destructive syncs require the manual ZIP flow.
class DriveAutomaticPolicy {
  static bool canPublish({
    required bool identityBlocked,
    required bool versionIsNewer,
    required bool versionIsInternal,
    required bool repositoryVersionKnown,
    required bool permissionsConclusive,
    required bool previewAvailable,
    required int deletionCount,
    required bool hasChanges,
  }) => !identityBlocked && versionIsNewer && versionIsInternal &&
      repositoryVersionKnown && permissionsConclusive && previewAvailable &&
      deletionCount == 0 && hasChanges;
}
