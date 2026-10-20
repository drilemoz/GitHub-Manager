import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Proprietário do SQLite local do GitHub Manager.
///
/// A instância [shared] é única por isolate. Isso significa que a UI inteira
/// compartilha uma conexão, enquanto o isolate do WorkManager recebe sua
/// própria instância estática e, consequentemente, sua própria conexão.
///
/// Evite criar/fechar conexões curtas para operações auxiliares. O banco deve
/// permanecer aberto durante a vida do isolate e só é fechado explicitamente
/// para reconstrução ou encerramento controlado.
class LocalDatabase {
  LocalDatabase._();

  static const int schemaVersion = 3;
  static const String databaseFileName = 'github_manager.db';

  static final LocalDatabase shared = LocalDatabase._();

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    final current = _database;
    if (current != null && current.isOpen) {
      return current;
    }

    final pending = _opening;
    if (pending != null) {
      return pending;
    }

    final opening = _open();
    _opening = opening;
    try {
      final opened = await opening;
      _database = opened;
      return opened;
    } finally {
      if (identical(_opening, opening)) {
        _opening = null;
      }
    }
  }

  Future<String> _databasePath() async {
    final root = await getDatabasesPath();
    return p.join(root, databaseFileName);
  }

  Future<Database> _open() async {
    final path = await _databasePath();
    return openDatabase(
      path,
      version: schemaVersion,
      // Uma conexão por isolate. A UI usa LocalDatabase.shared; o callback do
      // WorkManager executa em outro isolate e possui seu próprio singleton.
      singleInstance: true,
      onCreate: (db, version) => _ensureSchema(db),
      onUpgrade: (db, oldVersion, newVersion) => _ensureSchema(db),
      onOpen: _ensureSchema,
    );
  }

  /// Mantém o esquema local idempotente. Isso protege atualizações vindas de
  /// versões antigas que possuíam o mesmo número de banco, mas ainda não tinham
  /// todas as tabelas adicionadas depois.
  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_entries (
        cache_key TEXT PRIMARY KEY,
        json_value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS favorite_repositories (
        repository_id INTEGER PRIMARY KEY,
        full_name TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS operation_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_operation_logs_created_at '
      'ON operation_logs(created_at)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_events (
        event_key TEXT PRIMARY KEY,
        state TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS error_telemetry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        severity TEXT NOT NULL,
        message TEXT NOT NULL,
        stack_trace TEXT,
        context_json TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_error_telemetry_created_at '
      'ON error_telemetry(created_at)',
    );
  }

  /// Registro de notificações persistente compartilhado pelos isolates da UI e
  /// do WorkManager. A reserva é atômica na transação SQLite: apenas um emissor
  /// pode registrar um runId, mesmo durante consultas concorrentes.
  Future<bool> claimBuildNotification(int runId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'notification_events',
        columns: ['event_key'],
        where: 'event_key = ?',
        whereArgs: ['build:$runId'],
        limit: 1,
      );
      if (existing.isNotEmpty) return false;
      await txn.insert('notification_events', {
        'event_key': 'build:$runId',
        'state': 'claimed',
        'updated_at': now,
      });
      return true;
    });
  }

  Future<void> markBuildNotification(int runId, String state) async {
    final db = await database;
    await db.update(
      'notification_events',
      {'state': state, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'event_key = ?',
      whereArgs: ['build:$runId'],
    );
  }

  /// Migra IDs da lista legada (até 250) sem notificar builds antigas outra vez.
  Future<void> migrateLegacyBuildIds(Iterable<int> ids) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final id in ids) {
        await txn.insert(
          'notification_events',
          {'event_key': 'build:$id', 'state': 'sent', 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> putJson(String key, Object value) async {
    final db = await database;
    await db.insert(
      'cache_entries',
      {
        'cache_key': key,
        'json_value': jsonEncode(value),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> readJson(String key) async {
    final db = await database;
    final rows = await db.query(
      'cache_entries',
      columns: ['json_value'],
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final raw = rows.first['json_value']! as String;
    try {
      return jsonDecode(raw);
    } on FormatException {
      // Um valor local quebrado nunca deve inutilizar o aplicativo inteiro.
      await db.delete(
        'cache_entries',
        where: 'cache_key = ?',
        whereArgs: [key],
      );
      return null;
    }
  }

  Future<void> clearLegacyRemoteGitHubData() async {
    final db = await database;
    await db.delete(
      'cache_entries',
      where: 'cache_key IN (?, ?, ?)',
      whereArgs: const [
        'github.repositories',
        'github.profile',
        'followed.repositories.cache',
      ],
    );
  }

  Future<void> clearGitHubCache() async {
    final db = await database;
    await db.delete(
      'cache_entries',
      where: 'cache_key LIKE ?',
      whereArgs: ['github.%'],
    );
  }

  Future<Set<int>> readFavoriteRepositoryIds() async {
    final db = await database;
    final rows = await db.query(
      'favorite_repositories',
      columns: ['repository_id'],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => row['repository_id'])
        .whereType<int>()
        .toSet();
  }

  Future<void> setFavoriteRepository({
    required int repositoryId,
    required String fullName,
    required bool favorite,
  }) async {
    final db = await database;
    if (!favorite) {
      await db.delete(
        'favorite_repositories',
        where: 'repository_id = ?',
        whereArgs: [repositoryId],
      );
      return;
    }
    await db.insert(
      'favorite_repositories',
      {
        'repository_id': repositoryId,
        'full_name': fullName,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateFavoriteRepositoryName(
    int repositoryId,
    String fullName,
  ) async {
    final db = await database;
    await db.update(
      'favorite_repositories',
      {'full_name': fullName},
      where: 'repository_id = ?',
      whereArgs: [repositoryId],
    );
  }

  Future<void> removeFavoriteRepositoryByFullName(String fullName) async {
    final db = await database;
    await db.delete(
      'favorite_repositories',
      where: 'LOWER(full_name) = ?',
      whereArgs: [fullName.toLowerCase()],
    );
  }

  Future<void> reconcileFavoriteRepositories(Set<int> existingIds) async {
    final db = await database;
    final rows = await db.query(
      'favorite_repositories',
      columns: ['repository_id'],
    );
    final staleIds = rows
        .map((row) => row['repository_id'])
        .whereType<int>()
        .where((id) => !existingIds.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      await db.delete(
        'favorite_repositories',
        where: 'repository_id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<int> insertErrorTelemetry({
    required String source,
    required String severity,
    required String message,
    String? stackTrace,
    Map<String, Object?>? context,
  }) async {
    final db = await database;
    final id = await db.insert('error_telemetry', {
      'source': source,
      'severity': severity,
      'message': message,
      'stack_trace': stackTrace,
      'context_json': context == null ? null : jsonEncode(context),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    // Mantém a telemetria pequena e previsível mesmo em sessões com muitos
    // erros repetidos. Os registros mais antigos são descartados primeiro.
    await db.rawDelete('''
      DELETE FROM error_telemetry
      WHERE id NOT IN (
        SELECT id FROM error_telemetry
        ORDER BY created_at DESC, id DESC
        LIMIT 120
      )
    ''');
    return id;
  }

  Future<List<Map<String, Object?>>> readErrorTelemetry({int limit = 100}) async {
    final db = await database;
    final safeLimit = limit < 1 ? 1 : (limit > 120 ? 120 : limit);
    return db.query(
      'error_telemetry',
      orderBy: 'created_at DESC, id DESC',
      limit: safeLimit,
    );
  }

  Future<void> clearErrorTelemetry() async {
    final db = await database;
    await db.delete('error_telemetry');
  }

  Future<int> errorTelemetryCount() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM error_telemetry');
    if (rows.isEmpty) return 0;
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  /// Verifica o banco e recria qualquer tabela/índice ausente sem apagar
  /// token, preferências seguras ou dados que ainda estejam íntegros.
  Future<bool> repairSchema() async {
    final db = await database;
    await _ensureSchema(db);
    final rows = await db.rawQuery('PRAGMA quick_check');
    if (rows.isEmpty) return false;
    final value = rows.first.values.isEmpty
        ? null
        : rows.first.values.first?.toString().toLowerCase();
    return value == 'ok';
  }

  /// Último recurso para corrupção física do SQLite. Reconstrói somente o
  /// banco local do aplicativo. O token GitHub fica no armazenamento seguro e
  /// não é apagado.
  Future<void> rebuildLocalDatabase() async {
    await _close();
    final path = await _databasePath();
    await deleteDatabase(path);
    await database;
  }

  /// Fecha a conexão deste isolate somente durante manutenção interna.
  /// [shared] deve permanecer vivo durante toda a sessão do app.
  Future<void> _close() async {
    final pending = _opening;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // Se a abertura falhou, ainda limpamos as referências abaixo.
      }
    }

    final db = _database;
    _database = null;
    _opening = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}
