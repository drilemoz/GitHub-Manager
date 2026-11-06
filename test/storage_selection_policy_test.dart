import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/storage_selection_policy.dart';

void main() {
  ActionArtifact artifact(int id, int runId, int day, String name, {
    bool expired = false,
  }) => ActionArtifact(
    id: id,
    name: name,
    sizeBytes: 100,
    expired: expired,
    createdAt: DateTime.utc(2026, 11, day),
    workflowRunId: runId,
  );

  test('protects newest run and most recent likely APK group', () {
    final selected = StorageSelectionPolicy.selectOlderRunArtifacts([
      artifact(11, 101, 5, 'logs'), // Mais recente, sem APK.
      artifact(12, 100, 4, 'android-apk'), // Último APK provável.
      artifact(13, 100, 4, 'build-info'),
      artifact(14, 99, 3, 'android-apk'),
      artifact(15, 99, 3, 'build-info'),
    ]);
    expect(selected, {14, 15});
  });

  test('does not select files with incomplete dates or run associations', () {
    final items = [
      artifact(11, 101, 5, 'android-apk'),
      artifact(12, 99, 3, 'logs'),
      const ActionArtifact(id: 13, name: 'old', sizeBytes: 10,
          expired: false, createdAt: null, workflowRunId: 98),
      ActionArtifact(id: 14, name: 'old', sizeBytes: 10,
          expired: false, createdAt: DateTime.utc(2026, 11, 2)),
    ];
    expect(StorageSelectionPolicy.selectOlderRunArtifacts(items), {12});
  });

  test('same-timestamp items are not automatically selected', () {
    final selected = StorageSelectionPolicy.selectOlderRunArtifacts([
      artifact(11, 101, 5, 'android-apk'),
      artifact(12, 100, 5, 'logs'),
    ]);
    expect(selected, isEmpty);
  });
}
