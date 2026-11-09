import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual permite exceção somente com prévia e confirmação digitada', () {
    final source = File('lib/features/repositories/presentation/repository_detail_screen_actions.dart')
        .readAsStringSync();
    expect(source, contains('UploadSafetySettings.read('));
    expect(source, contains('check.blocked && !identityOverride'));
    expect(source, contains('final mustBlock = syncPreview == null ||'));
    expect(source, contains('identityMismatch: identityOverride'));
    expect(source, contains('typed.text.trim() == fullName'));
    expect(source, contains('barrierDismissible: false'));
    expect(source, contains('syncPreview.deletedCount'));
    expect(source, contains('preview.modifiedCount'));
    expect(source, contains('project.sha256'));
  });

  test('regras automáticas Google Drive permanecem independentes', () {
    final source = File('lib/features/drive_sync/data/drive_sync_coordinator.dart')
        .readAsStringSync();
    expect(source, contains('if (safety.blocked || safety.warning ||'));
    expect(source, isNot(contains('UploadSafetySettings')));
    final settings = File('lib/features/projects/data/upload_safety_settings.dart')
        .readAsStringSync();
    expect(settings, contains('settings.manual_upload_safety_v1'));
  });

  test('configurações expõem modos e deixam padrão estrito', () {
    final source = File('lib/features/settings/presentation/settings_screen.dart')
        .readAsStringSync();
    expect(source, contains('Permitir ZIP com identidade divergente'));
    expect(source, contains('Confirmar muitas alterações'));
    expect(source, contains('Confirmar exclusões de arquivos'));
  });
}
