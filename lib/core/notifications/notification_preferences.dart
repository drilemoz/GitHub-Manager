import 'package:github_manager/core/persistence/local_database.dart';

/// Preferências locais. Começam desligadas para evitar avisos inesperados.
/// Notificações de serviços foreground Android não são avisos opcionais:
/// continuam enquanto um envio/download estiver realmente em andamento.
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = false,
    this.buildSuccess = true,
    this.buildProblems = true,
    this.downloadSuccess = true,
    this.downloadProblems = true,
  });

  static const prefix = 'settings.optional_notifications.';

  final bool enabled;
  final bool buildSuccess;
  final bool buildProblems;
  final bool downloadSuccess;
  final bool downloadProblems;

  bool get watchBuilds => enabled && (buildSuccess || buildProblems);
  bool acceptsBuild(String conclusion) => enabled &&
      (conclusion == 'success' ? buildSuccess : buildProblems);
  bool get notifyDownloaded => enabled && downloadSuccess;
  bool get notifyDownloadError => enabled && downloadProblems;

  NotificationPreferences copyWith({
    bool? enabled,
    bool? buildSuccess,
    bool? buildProblems,
    bool? downloadSuccess,
    bool? downloadProblems,
  }) => NotificationPreferences(
        enabled: enabled ?? this.enabled,
        buildSuccess: buildSuccess ?? this.buildSuccess,
        buildProblems: buildProblems ?? this.buildProblems,
        downloadSuccess: downloadSuccess ?? this.downloadSuccess,
        downloadProblems: downloadProblems ?? this.downloadProblems,
      );

  static Future<NotificationPreferences> read({LocalDatabase? database}) async {
    final db = database ?? LocalDatabase.shared;
    Future<bool> flag(String key, bool fallback) async {
      final value = await db.readJson('$prefix$key');
      return value is bool ? value : fallback;
    }
    // O ajuste antigo é respeitado para as categorias de builds. O controle
    // principal é opt-in, inclusive em atualizações, para cessar ruído antigo.
    final legacy = await db.readJson('settings.build_notifications');
    final legacyBuilds = legacy is bool ? legacy : true;
    return NotificationPreferences(
      enabled: await flag('enabled', false),
      buildSuccess: await flag('build_success', legacyBuilds),
      buildProblems: await flag('build_problems', legacyBuilds),
      downloadSuccess: await flag('download_success', true),
      downloadProblems: await flag('download_problems', true),
    );
  }

  static Future<void> save(NotificationPreferences value, {LocalDatabase? database}) async {
    final db = database ?? LocalDatabase.shared;
    await db.putJson('${prefix}enabled', value.enabled);
    await db.putJson('${prefix}build_success', value.buildSuccess);
    await db.putJson('${prefix}build_problems', value.buildProblems);
    await db.putJson('${prefix}download_success', value.downloadSuccess);
    await db.putJson('${prefix}download_problems', value.downloadProblems);
  }
}
