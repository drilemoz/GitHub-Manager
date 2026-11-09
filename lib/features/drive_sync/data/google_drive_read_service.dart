import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:github_manager/features/drive_sync/domain/drive_sync_link.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Read-only Google Drive API v3 access. No refresh/access token is persisted.
/// Google Sign-In manages session authorization through the Android account.
class GoogleDriveReadService {
  GoogleDriveReadService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(
    baseUrl: 'https://www.googleapis.com/drive/v3',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static const _scope = 'https://www.googleapis.com/auth/drive.readonly';
  static const _scopes = <String>[_scope];
  static const _webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
  static const _savedClientIdKey = 'google_drive_web_oauth_client_id';
  static final _clientIdPattern = RegExp(
    r'^[0-9]+-[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$',
  );

  /// OAuth client IDs are public identifiers, not Google access tokens.
  /// The Web client is needed by google_sign_in_android without Firebase.
  static bool isValidWebClientId(String value) =>
      _clientIdPattern.hasMatch(value.trim());


  final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool _initialized = false;
  String? _activeClientId;
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  GoogleSignInAccount? _user;
  Future<void>? _initialization;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;

  String? get email => _user?.email;

  Future<String?> configuredWebClientId() async {
    final custom = (await _storage.read(key: _savedClientIdKey))?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return _webClientId.trim().isEmpty ? null : _webClientId.trim();
  }

  bool get requiresRestart => _activeClientId != null && _changedClientId;
  bool _changedClientId = false;

  /// If OAuth is not configured, don't poison the cached GoogleSignIn singleton.
  /// The user can configure a client ID in this screen before first login.
  Future<void> saveWebClientId(String value) async {
    final id = value.trim();
    if (!isValidWebClientId(id)) {
      throw const FormatException('Informe um ID OAuth do tipo Aplicativo da Web, '
          'terminado em .apps.googleusercontent.com.');
    }
    await _storage.write(key: _savedClientIdKey, value: id);
    if (_activeClientId != null) _changedClientId = id != _activeClientId;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    final pending = _initialization;
    if (pending != null) return pending;
    final future = _initialize();
    _initialization = future;
    try {
      await future;
      _initialized = true;
    } finally {
      if (!_initialized) _initialization = null;
    }
  }

  Future<void> _initialize() async {
    final id = await configuredWebClientId();
    if (id == null || !isValidWebClientId(id)) {
      throw StateError('Google Drive não configurado: informe o ID OAuth Web '
          'em Configurar conexão. Sem esse ID o Android não pode abrir o login Google.');
    }
    _activeClientId = id;
    await _signIn.initialize(serverClientId: id);
    _subscription = _signIn.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn():
          _user = event.user;
        case GoogleSignInAuthenticationEventSignOut():
          _user = null;
      }
    });
    try {
      _user = await _signIn.attemptLightweightAuthentication();
    } catch (_) {
      // Login silencioso é opcional. O botão Conectar inicia autorização
      // interativa e apresenta o erro real ao usuário se a conta não servir.
      _user = null;
    }
  }

  /// Must be invoked by a visible user gesture (OAuth consent).
  Future<String> connect() async {
    if (requiresRestart) {
      throw StateError('O ID OAuth foi alterado. Feche e abra o app para '
          'reinicializar o login Google com o novo ID.');
    }
    await initialize();
    if (_user == null) {
      _user = await _signIn.authenticate();
    }
    await _user!.authorizationClient.authorizeScopes(_scopes);
    return _user!.email;
  }

  Future<void> disconnect() async {
    await initialize();
    await _signIn.disconnect();
    _user = null;
  }

  Future<Map<String, String>> _headers() async {
    await initialize();
    final current = _user;
    if (current == null) {
      throw StateError('Conecte sua conta Google antes de consultar o Drive.');
    }
    final authorization = await current.authorizationClient
        .authorizationForScopes(_scopes);
    if (authorization == null) {
      throw StateError('A autorização do Drive expirou ou foi revogada. '
          'Toque em Conectar Google para autorizar novamente.');
    }
    return {'Authorization': 'Bearer ${authorization.accessToken}'};
  }

  Future<List<DriveFileEntry>> listChildren(
    String folderId, {required bool foldersOnly}) async {
    if (folderId.isEmpty) throw ArgumentError('Pasta do Drive vazia.');
    final headers = await _headers();
    final all = <DriveFileEntry>[];
    String? next;
    do {
      final q = "'${folderId.replaceAll("'", r"\'")}' in parents and trashed = false" +
          (foldersOnly ? " and mimeType = 'application/vnd.google-apps.folder'" : '');
      final response = await _dio.get<Map<String, dynamic>>('/files',
        options: Options(headers: headers),
        queryParameters: {
          'q': q,
          'fields': 'nextPageToken,incompleteSearch,files(id,name,mimeType,modifiedTime,size)',
          'pageSize': 1000,
          if (next != null) 'pageToken': next,
          'orderBy': foldersOnly ? 'name' : 'modifiedTime desc',
        },
      );
      final data = response.data;
      if (data == null || data['incompleteSearch'] == true) {
        throw StateError('Listagem do Drive incompleta. Não é seguro escolher a versão.');
      }
      final entries = data['files'];
      if (entries is! List) throw StateError('Resposta inesperada da API Drive.');
      for (final item in entries) {
        final parsed = DriveFileEntry.fromJson(item);
        if (parsed != null) all.add(parsed);
      }
      next = data['nextPageToken'] as String?;
      if (all.length > 5000) {
        throw StateError('Pasta com arquivos demais. Organize os ZIPs antes de sincronizar.');
      }
    } while (next != null && next.isNotEmpty);
    return all;
  }

  Future<DriveFileEntry?> latestZip(String folderId) async {
    final files = await listChildren(folderId, foldersOnly: false);
    final zips = files.where((f) => f.isZip && !f.isFolder).toList();
    if (zips.isEmpty) return null;
    if (zips.length != 1) {
      throw StateError('Há ${zips.length} ZIPs nesta pasta. '
          'Mantenha exatamente uma versão por projeto no Drive.');
    }
    zips.sort((a, b) {
      final byTime = (b.modifiedTime ?? '').compareTo(a.modifiedTime ?? '');
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return zips.first;
  }

  /// Downloads into a private, random filename; only validated ZIPs enter the
  /// existing upload queue. Partial or failed downloads are always deleted.
  Future<ZipProjectPreview> downloadAndAnalyze(DriveFileEntry entry) async {
    if (!entry.isZip || entry.isFolder) {
      throw StateError('O item selecionado não é um arquivo ZIP do Drive.');
    }
    if (entry.size != null &&
        (entry.size! <= 0 || entry.size! > LocalProjectService.maxArchiveBytes)) {
      throw StateError('ZIP vazio ou superior ao limite de 300 MB.');
    }
    final root = await getApplicationSupportDirectory();
    final folder = Directory(p.join(root.path, 'verified_zip_selections'));
    await folder.create(recursive: true);
    final nonce = List<int>.generate(16, (_) => Random.secure().nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final snapshot = File(p.join(folder.path, 'selection_$nonce.zip'));
    final partial = File('${snapshot.path}.part');
    try {
      final headers = await _headers();
      final response = await _dio.get<ResponseBody>(
        '/files/${Uri.encodeComponent(entry.id)}',
        queryParameters: const {'alt': 'media'},
        options: Options(headers: headers, responseType: ResponseType.stream),
      );
      final stream = response.data?.stream;
      if (stream == null) throw StateError('Drive não retornou o conteúdo do ZIP.');
      final sink = partial.openWrite();
      var bytes = 0;
      try {
        await for (final chunk in stream) {
          bytes += chunk.length;
          if (bytes > LocalProjectService.maxArchiveBytes) {
            throw StateError('ZIP maior que 300 MB; download interrompido.');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (bytes == 0 || (entry.size != null && entry.size != bytes)) {
        throw StateError('Tamanho do ZIP baixado não confere com o Drive.');
      }
      await partial.rename(snapshot.path);
      return await LocalProjectService().analyzeZip(snapshot.path,
        displayName: entry.name, managedSnapshot: true);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      if (await snapshot.exists()) await snapshot.delete();
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _dio.close(force: true);
  }
}
