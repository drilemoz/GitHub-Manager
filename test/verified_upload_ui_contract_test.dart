import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selection is frozen before branch selection and cleanup is bounded', () {
    final service =
        File('lib/features/projects/data/local_project_service.dart')
            .readAsStringSync();
    final screen = File(
      'lib/features/repositories/presentation/repository_detail_screen_actions.dart',
    ).readAsStringSync();
    expect(service, contains('await source.copy(temporary.path)'));
    expect(service, contains('await temporary.rename(snapshot.path)'));
    expect(service, contains('managedSnapshot: true'));
    expect(service, contains('p.dirname(normalized) != p.normalize'));
    expect(screen, contains('Arquivo escolhido no Android'));
    expect(screen, contains('syncPreview == null'));
    // Falta de prévia bloqueia sempre, mesmo com exceção manual de identidade.
    expect(screen, contains('final mustBlock = syncPreview == null ||'));
    expect(screen, contains('(check.blocked && !identityOverride);'));
    expect(screen, contains('onPressed: mustBlock'));
    expect(screen, isNot(contains('Forçar envio')));
  });

  test('identity mismatch requires explicit settings and typed confirmation', () {
    final screen = File(
      'lib/features/repositories/presentation/repository_detail_screen_actions.dart',
    ).readAsStringSync();
    final settings = File(
      'lib/features/projects/data/upload_safety_settings.dart',
    ).readAsStringSync();
    expect(
      screen,
      contains('var safetySettings = const UploadSafetySettings();'),
    );
    expect(screen, contains(
      'check.blocked && safetySettings.allowIdentityMismatchWithConfirmation',
    ));
    expect(
      screen,
      contains('final requiresTypedConfirmation = syncPreview != null &&'),
    );
    expect(screen, contains('identityMismatch: identityOverride,'));
    expect(screen, contains('if (requiresTypedConfirmation) {'));
    expect(
      screen,
      contains('if (accepted != true || !dialogContext.mounted) return;'),
    );
    expect(screen, contains('typed.text.trim() == fullName'));
    expect(
      settings,
      contains('this.allowIdentityMismatchWithConfirmation = false'),
    );
    expect(settings, contains('identityMismatch ||'));
    // Preferências manuais não se propagam para a sincronização automática.
    final automatic = File(
      'lib/features/drive_sync/data/drive_sync_coordinator.dart',
    );
    // A política do Drive é inspecionada em seu próprio conjunto de testes;
    // a ausência de acoplamento à opção manual é verificada aqui também.
    expect(automatic.existsSync(), isTrue);
    expect(automatic.readAsStringSync(), isNot(contains('UploadSafetySettings')));
  });

  test('upload refuses altered snapshots even if file size is unchanged', () {
    final manager =
        File('lib/features/uploads/data/upload_manager_service.dart')
            .readAsStringSync();
    final git =
        File('lib/features/projects/data/git_project_upload_service.dart')
            .readAsStringSync();
    expect(
      manager,
      contains('LocalProjectService.sha256OfFile(file) == expectedSha'),
    );
    expect(manager, contains('UPLOAD_ZIP_HASH_MISMATCH'));
    expect(manager, contains('UPLOAD_ZIP_LEGACY_UNVERIFIED'));
    expect(
      git,
      contains('await LocalProjectService.verifyFingerprint(project)'),
    );
  });
}
