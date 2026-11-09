import 'package:github_manager/core/persistence/local_database.dart';

/// Preferências EXCLUSIVAS do envio manual de ZIP. A sincronização automática
/// do Google Drive continua fail-closed, independentemente destas opções.
///
/// Nunca substituem a prévia de diferenças, a validação do ZIP/SHA-256,
/// as permissões de escrita ou a confirmação do destino.
class UploadSafetySettings {
  const UploadSafetySettings({
    this.allowIdentityMismatchWithConfirmation = false,
    this.modifiedConfirmationThreshold = 100,
    this.deletionConfirmationThreshold = 1,
  });

  static const key = 'settings.manual_upload_safety_v1';
  static const modifiedOptions = <int>[0, 25, 100, 250];
  static const deletionOptions = <int>[0, 1, 5, 20];

  final bool allowIdentityMismatchWithConfirmation;

  /// Número de arquivos novos + modificados para pedir digitação. Zero
  /// desativa apenas essa confirmação adicional.
  final int modifiedConfirmationThreshold;

  /// Número de arquivos excluídos para pedir digitação. Zero desativa apenas
  /// essa confirmação adicional. A prévia de remoções permanece obrigatória.
  final int deletionConfirmationThreshold;

  bool requiresTypedConfirmation({
    required int modifiedCount,
    required int deletedCount,
    int createdCount = 0,
    required bool identityMismatch,
  }) =>
      identityMismatch ||
      (modifiedConfirmationThreshold > 0 &&
          modifiedCount + createdCount >= modifiedConfirmationThreshold) ||
      (deletionConfirmationThreshold > 0 &&
          deletedCount >= deletionConfirmationThreshold);

  List<String> confirmationReasons({
    required int modifiedCount,
    required int deletedCount,
    int createdCount = 0,
    required bool identityMismatch,
  }) => [
        if (identityMismatch)
          'O arquivo escolhido, a identidade interna ou o repositório não correspondem.',
        if (modifiedConfirmationThreshold > 0 &&
            modifiedCount + createdCount >= modifiedConfirmationThreshold)
          '${modifiedCount + createdCount} arquivo(s) serão criados ou modificados.',
        if (deletionConfirmationThreshold > 0 &&
            deletedCount >= deletionConfirmationThreshold)
          '$deletedCount arquivo(s) serão removidos do repositório.',
      ];

  UploadSafetySettings copyWith({
    bool? allowIdentityMismatchWithConfirmation,
    int? modifiedConfirmationThreshold,
    int? deletionConfirmationThreshold,
  }) =>
      UploadSafetySettings(
        allowIdentityMismatchWithConfirmation:
            allowIdentityMismatchWithConfirmation ??
                this.allowIdentityMismatchWithConfirmation,
        modifiedConfirmationThreshold:
            modifiedConfirmationThreshold ?? this.modifiedConfirmationThreshold,
        deletionConfirmationThreshold:
            deletionConfirmationThreshold ?? this.deletionConfirmationThreshold,
      );

  static UploadSafetySettings fromJson(Object? stored) {
    if (stored is! Map) return const UploadSafetySettings();
    final modified = stored['modifiedConfirmationThreshold'];
    final deletion = stored['deletionConfirmationThreshold'];
    return UploadSafetySettings(
      allowIdentityMismatchWithConfirmation:
          stored['allowIdentityMismatchWithConfirmation'] == true,
      modifiedConfirmationThreshold:
          modified is int && modifiedOptions.contains(modified) ? modified : 100,
      deletionConfirmationThreshold:
          deletion is int && deletionOptions.contains(deletion) ? deletion : 1,
    );
  }

  Map<String, Object> toJson() => {
        'allowIdentityMismatchWithConfirmation':
            allowIdentityMismatchWithConfirmation,
        'modifiedConfirmationThreshold': modifiedConfirmationThreshold,
        'deletionConfirmationThreshold': deletionConfirmationThreshold,
      };

  static Future<UploadSafetySettings> read({LocalDatabase? database}) async {
    final stored = await (database ?? LocalDatabase.shared).readJson(key);
    return fromJson(stored);
  }

  static Future<void> write(UploadSafetySettings settings,
      {LocalDatabase? database}) async {
    if (!modifiedOptions.contains(settings.modifiedConfirmationThreshold) ||
        !deletionOptions.contains(settings.deletionConfirmationThreshold)) {
      throw ArgumentError('Limites de confirmação inválidos.');
    }
    await (database ?? LocalDatabase.shared).putJson(key, settings.toJson());
  }

  static String modifiedLabel(int threshold) =>
      threshold == 0 ? 'Não exigir digitação' : 'A partir de $threshold arquivos';

  static String deletionLabel(int threshold) =>
      threshold == 0 ? 'Não exigir digitação' : 'A partir de $threshold arquivo(s)';
}
