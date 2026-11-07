import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection is frozen before branch selection and cleanup is bounded', () {
    final service = File('lib/features/projects/data/local_project_service.dart').readAsStringSync();
    final screen = File('lib/features/repositories/presentation/repository_detail_screen_actions.dart').readAsStringSync();
    expect(service, contains('await source.copy(temporary.path)'));
    expect(service, contains('await temporary.rename(snapshot.path)'));
    expect(service, contains('managedSnapshot: true'));
    expect(service, contains('p.dirname(normalized) != p.normalize'));
    expect(screen, contains('Arquivo escolhido no Android'));
    expect(screen, contains('syncPreview == null'));
    expect(screen, contains('final mustBlock = check.blocked || syncPreview == null'));
    expect(screen, isNot(contains('Forçar envio')));
  });

  test('upload refuses altered snapshots even if file size is unchanged', () {
    final manager = File('lib/features/uploads/data/upload_manager_service.dart').readAsStringSync();
    final git = File('lib/features/projects/data/git_project_upload_service.dart').readAsStringSync();
    expect(manager, contains('LocalProjectService.sha256OfFile(file) == expectedSha'));
    expect(manager, contains('UPLOAD_ZIP_HASH_MISMATCH'));
    expect(manager, contains('UPLOAD_ZIP_LEGACY_UNVERIFIED'));
    expect(git, contains('await LocalProjectService.verifyFingerprint(project)'));
  });
}
