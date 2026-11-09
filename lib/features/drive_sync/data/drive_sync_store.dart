import 'package:github_manager/core/persistence/local_database.dart';
import 'package:github_manager/features/drive_sync/domain/drive_sync_link.dart';

class DriveSyncStore {
  DriveSyncStore(this.database);
  final LocalDatabase database;
  static const _key = 'drive_sync.links.v1';

  Future<List<DriveSyncLink>> read() async {
    final raw = await database.readJson(_key);
    if (raw is! List) return const [];
    return [for (final value in raw)
      if (DriveSyncLink.fromJson(value) case final DriveSyncLink link) link];
  }

  Future<void> upsert(DriveSyncLink link) async {
    final all = await read();
    // A branch has at most one source folder. No silent overwrite of another
    // binding: the UI explicitly confirms changes before calling upsert.
    all.removeWhere((existing) => existing.key == link.key);
    all.add(link);
    await database.putJson(_key, all.map((item) => item.toJson()).toList());
  }

  Future<void> delete(DriveSyncLink link) async {
    final all = await read();
    all.removeWhere((existing) => existing.key == link.key);
    await database.putJson(_key, all.map((item) => item.toJson()).toList());
  }
}
