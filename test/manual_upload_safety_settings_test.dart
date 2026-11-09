import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/projects/data/upload_safety_settings.dart';

void main() {
  test('padrão é restritivo e confirma qualquer remoção', () {
    const settings = UploadSafetySettings();
    expect(settings.allowIdentityMismatchWithConfirmation, isFalse);
    expect(settings.requiresTypedConfirmation(
      modifiedCount: 2, deletedCount: 1, identityMismatch: false), isTrue);
    expect(settings.requiresTypedConfirmation(
      modifiedCount: 99, deletedCount: 0, identityMismatch: false), isFalse);
    expect(settings.requiresTypedConfirmation(
      modifiedCount: 100, deletedCount: 0, identityMismatch: false), isTrue);
  });

  test('muitas adições de arquivos também exigem confirmação', () {
    const settings = UploadSafetySettings();
    expect(settings.requiresTypedConfirmation(
      modifiedCount: 1, createdCount: 309,
      deletedCount: 0, identityMismatch: false), isTrue);
  });

  test('exceção de identidade SEMPRE exige digitação independentemente dos limiares', () {
    const settings = UploadSafetySettings(
      allowIdentityMismatchWithConfirmation: true,
      modifiedConfirmationThreshold: 0,
      deletionConfirmationThreshold: 0,
    );
    expect(settings.requiresTypedConfirmation(
      modifiedCount: 0, deletedCount: 0, identityMismatch: true), isTrue);
    expect(settings.requiresTypedConfirmation(
      modifiedCount: 500, deletedCount: 20, identityMismatch: false), isFalse);
  });

  test('confirmação de exclusão pode usar limiar escolhido', () {
    const settings = UploadSafetySettings(deletionConfirmationThreshold: 5);
    expect(settings.requiresTypedConfirmation(
      modifiedCount: 0, deletedCount: 4, identityMismatch: false), isFalse);
    expect(settings.requiresTypedConfirmation(
      modifiedCount: 0, deletedCount: 5, identityMismatch: false), isTrue);
    expect(settings.confirmationReasons(
      modifiedCount: 0, deletedCount: 5, identityMismatch: false),
      contains(contains('5 arquivo')));
  });

  test('preferências inválidas e legadas usam padrão conservador', () {
    expect(UploadSafetySettings.fromJson(null).allowIdentityMismatchWithConfirmation, isFalse);
    final value = UploadSafetySettings.fromJson({
      'allowIdentityMismatchWithConfirmation': 'true',
      'modifiedConfirmationThreshold': -25,
      'deletionConfirmationThreshold': 99,
    });
    expect(value.allowIdentityMismatchWithConfirmation, isFalse);
    expect(value.modifiedConfirmationThreshold, 100);
    expect(value.deletionConfirmationThreshold, 1);
  });

  test('serialização preserva as opções válidas', () {
    const settings = UploadSafetySettings(
      allowIdentityMismatchWithConfirmation: true,
      modifiedConfirmationThreshold: 25,
      deletionConfirmationThreshold: 20,
    );
    final decoded = UploadSafetySettings.fromJson(settings.toJson());
    expect(decoded.allowIdentityMismatchWithConfirmation, isTrue);
    expect(decoded.modifiedConfirmationThreshold, 25);
    expect(decoded.deletionConfirmationThreshold, 20);
  });
}
