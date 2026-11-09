import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/drive_sync/data/google_drive_read_service.dart';

void main() {
  test('aceita somente IDs OAuth do tipo Web', () {
    expect(GoogleDriveReadService.isValidWebClientId(
        '123456-abcde.apps.googleusercontent.com'), isTrue);
    expect(GoogleDriveReadService.isValidWebClientId(
        '  123456-abcde.apps.googleusercontent.com  '), isTrue);
    for (final invalid in ['', 'some-api-key',
      '123-abc.apps.googleusercontent.com.attacker.test',
      'http://123-abc.apps.googleusercontent.com',
      '123abc.apps.googleusercontent.com']) {
      expect(GoogleDriveReadService.isValidWebClientId(invalid), isFalse,
        reason: invalid);
    }
  });

  test('a tela permite corrigir OAuth sem apagar tokens nem Drive', () {
    final ui = File('lib/features/drive_sync/presentation/drive_sync_screen.dart')
        .readAsStringSync();
    final service = File('lib/features/drive_sync/data/google_drive_read_service.dart')
        .readAsStringSync();
    expect(ui, contains('Configurar OAuth'));
    expect(ui, contains('getOwnSigningCertificate'));
    expect(ui, contains('saveWebClientId'));
    expect(ui, contains('Credenciais no Google Cloud'));
    expect(service, contains('serverClientId: id'));
    expect(service, contains('configuredWebClientId()'));
    expect(service, contains('requiresRestart'));
    expect(service, contains('attemptLightweightAuthentication'));
    expect(service, contains('drive.readonly'));
    expect(service, isNot(contains("drive.file'")));
  });
}
