import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('descarta apenas a prévia não enfileirada com acesso anulável seguro', () {
    final watcher = File(
      'lib/features/drive_sync/presentation/drive_sync_foreground_watcher.dart',
    ).readAsStringSync();
    expect(watcher, contains('final preview = candidate?.project;'));
    expect(watcher, contains('if (!queued && preview != null)'));
    expect(watcher, contains('LocalProjectService.discardPreviewPath(preview.path)'));
    expect(watcher, isNot(contains('candidate.project.path')));
  });
}
