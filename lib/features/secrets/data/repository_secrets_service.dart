import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/features/secrets/domain/repository_secret.dart';
import 'package:pinenacl/x25519.dart' show PublicKey, SealedBox;
import 'package:xml/xml.dart';

abstract interface class RepositorySecretsGateway {
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  });

  Future<int?> putJson(String path, Map<String, dynamic> data);

  Future<void> delete(String path);
}

class GitHubRepositorySecretsGateway implements RepositorySecretsGateway {
  GitHubRepositorySecretsGateway(this._client);

  final GitHubApiClient _client;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      path,
      queryParameters: queryParameters,
    );
    return response.data ?? const <String, dynamic>{};
  }

  @override
  Future<int?> putJson(String path, Map<String, dynamic> data) async {
    final response = await _client.put<void>(path, data: data);
    return response.statusCode;
  }

  @override
  Future<void> delete(String path) async {
    await _client.delete<void>(path);
  }
}

class RepositorySecretsService {
  RepositorySecretsService(GitHubApiClient client)
      : this.withGateway(GitHubRepositorySecretsGateway(client));

  RepositorySecretsService.withGateway(this._gateway);

  static const int maxSecretBytes = 48 * 1024;
  static const int maxRepositorySecrets = 100;
  static const int maxImportFileBytes = 6 * 1024 * 1024;

  final RepositorySecretsGateway _gateway;

  Future<List<RepositorySecret>> listSecrets(String repositoryFullName) async {
    final data = await _gateway.getJson(
      '/repos/$repositoryFullName/actions/secrets',
      queryParameters: {'per_page': maxRepositorySecrets},
    );
    final raw = data['secrets'];
    if (raw is! List) return const [];

    final items = raw
        .whereType<Map>()
        .map((json) => RepositorySecret.fromJson(Map<String, dynamic>.from(json)))
        .toList(growable: false);
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  Future<SecretImportPlan> prepareImport({
    required String repositoryFullName,
    required Map<String, String> values,
  }) async {
    if (values.isEmpty) {
      throw const FormatException('Nenhum Secret válido encontrado.');
    }

    final normalized = <String, String>{};
    for (final entry in values.entries) {
      final name = _normalizeName(entry.key);
      if (normalized.containsKey(name)) {
        throw FormatException('Secret duplicado após normalização: $name.');
      }
      final bytes = utf8.encode(entry.value).length;
      if (bytes > maxSecretBytes) {
        throw FormatException(
          '$name possui ${_formatBytes(bytes)}. O limite do GitHub é 48 KB por Secret.',
        );
      }
      normalized[name] = entry.value;
    }

    final existing = await listSecrets(repositoryFullName);
    final existingNames = existing.map((secret) => secret.name.toUpperCase()).toSet();
    final finalNames = <String>{...existingNames, ...normalized.keys};
    if (finalNames.length > maxRepositorySecrets) {
      final newCount = normalized.keys.where((name) => !existingNames.contains(name)).length;
      throw FormatException(
        'Este lote criaria $newCount novo(s) Secret(s) e deixaria o repositório com '
        '${finalNames.length}. O GitHub permite no máximo $maxRepositorySecrets Secrets por repositório.',
      );
    }

    final items = normalized.entries
        .map(
          (entry) => SecretImportItem(
            name: entry.key,
            value: entry.value,
            kind: existingNames.contains(entry.key)
                ? SecretMutationKind.update
                : SecretMutationKind.create,
          ),
        )
        .toList(growable: false);

    return SecretImportPlan(
      items: items,
      existingCount: existing.length,
      finalCount: finalNames.length,
    );
  }

  Future<void> putSecret({
    required String repositoryFullName,
    required String name,
    required String value,
  }) async {
    final plan = await prepareImport(
      repositoryFullName: repositoryFullName,
      values: {name: value},
    );
    final result = await putMany(
      repositoryFullName: repositoryFullName,
      values: {name: value},
      preparedPlan: plan,
    );
    final failure = result.items.where((item) => !item.success).firstOrNull;
    if (failure != null) {
      throw GitHubSecretOperationException(
        failure.message,
        technicalCode: failure.technicalCode,
        httpStatus: failure.httpStatus,
        endpoint: failure.endpoint,
        apiMessage: failure.apiMessage,
      );
    }
  }

  Future<SecretBatchResult> putMany({
    required String repositoryFullName,
    required Map<String, String> values,
    SecretImportPlan? preparedPlan,
  }) async {
    final plan = preparedPlan ??
        await prepareImport(
          repositoryFullName: repositoryFullName,
          values: values,
        );

    final (Uint8List, String) key;
    try {
      key = await _getPublicKey(repositoryFullName);
    } catch (error) {
      return SecretBatchResult(
        items: plan.items
            .map((item) => _failureResult(item, error, publicKeyStage: true))
            .toList(growable: false),
      );
    }

    final results = <SecretWriteResult>[];
    for (final item in plan.items) {
      try {
        await _putEncrypted(
          repositoryFullName: repositoryFullName,
          name: item.name,
          value: item.value,
          publicKey: key.$1,
          keyId: key.$2,
        );
        results.add(
          SecretWriteResult(
            name: item.name,
            kind: item.kind,
            success: true,
            message: item.kind == SecretMutationKind.create
                ? 'criado com sucesso'
                : 'atualizado com sucesso',
          ),
        );
      } catch (error) {
        results.add(_failureResult(item, error));
      }
    }
    return SecretBatchResult(items: results);
  }

  Future<void> deleteSecret({
    required String repositoryFullName,
    required String name,
  }) =>
      _gateway.delete(
        '/repos/$repositoryFullName/actions/secrets/${Uri.encodeComponent(name)}',
      );

  /// Exclui somente os nomes aprovados pelo usuário, um de cada vez.
  /// Nenhuma falha individual cancela o restante do lote.
  Future<SecretDeletionResult> deleteMany({
    required String repositoryFullName,
    required List<String> names,
    void Function(int completed, int total)? onProgress,
  }) async {
    final unique = <String>{};
    for (final raw in names) {
      unique.add(_normalizeName(raw));
    }
    final results = <SecretDeletionItemResult>[];
    for (final name in unique) {
      try {
        await deleteSecret(repositoryFullName: repositoryFullName, name: name);
        results.add(SecretDeletionItemResult(name: name, success: true));
      } catch (error) {
        results.add(SecretDeletionItemResult(
          name: name,
          success: false,
          message: error is AppException
              ? error.message
              : 'Falha ao excluir este Secret.',
          httpStatus: error is AppException ? error.httpStatus : null,
        ));
      }
      onProgress?.call(results.length, unique.length);
    }
    return SecretDeletionResult(items: results);
  }

  // O seletor Android pode ocultar `.env` (arquivo sem nome-base) quando
  // usa filtros por extensão. Abrimos o SAF sem filtro e validamos localmente.
  Future<PlatformFile?> pickImportFile() => FilePicker.pickFile(
        type: FileType.any,
      );

  static bool isSupportedImportFileName(String fileName) {
    final name = fileName.trim().toLowerCase();
    return name == '.env' ||
        name.startsWith('.env.') ||
        name.endsWith('.env') ||
        name.endsWith('.txt') ||
        name.endsWith('.json') ||
        name.endsWith('.xml');
  }

  Future<Map<String, String>> parseImportFile(PlatformFile file) async {
    if (!isSupportedImportFileName(file.name)) {
      throw const FormatException(
        'Formato não suportado. Selecione .env, .env.local, .txt, .json ou .xml.',
      );
    }
    final fileLength = await file.length();
    if (fileLength > maxImportFileBytes) {
      throw FormatException(
        'O arquivo tem ${_formatBytes(fileLength)}. Para evitar consumo excessivo de memória, '
        'o limite de importação é ${_formatBytes(maxImportFileBytes)}.',
      );
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > maxImportFileBytes) {
      throw const FormatException('O arquivo de Secrets excede o limite seguro de importação.');
    }
    // UTF-8 com BOM aparece em .env exportados por editores Windows.
    final decoded = utf8.decode(bytes, allowMalformed: false);
    final text = decoded.startsWith('\uFEFF') ? decoded.substring(1) : decoded;
    final lower = file.name.toLowerCase();
    if (lower.endsWith('.json')) return parseJson(text);
    if (lower.endsWith('.xml')) return parseXml(text);
    return parseText(text);
  }

  static Map<String, String> parseText(String text) {
    final values = <String, String>{};
    final sourceLines = <String, int>{};
    final lines = const LineSplitter().convert(text);
    for (var index = 0; index < lines.length; index++) {
      final rawLine = lines[index];
      final line = rawLine.replaceFirst('\uFEFF', '').trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;

      final normalizedLine = line.replaceFirst(RegExp(r'^export\s+'), '');
      final equal = normalizedLine.indexOf('=');
      final colon = normalizedLine.indexOf(':');
      final candidates = <int>[equal, colon].where((index) => index > 0).toList();
      if (candidates.isEmpty) {
        throw FormatException(
          'Linha ${index + 1} inválida. Use NOME=valor ou NOME: valor.',
        );
      }
      final separator = candidates.reduce((a, b) => a < b ? a : b);

      final name = _normalizeName(normalizedLine.substring(0, separator));
      var value = normalizedLine.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      _addParsedValue(
        values,
        name,
        value,
        previousLocation: sourceLines[name] == null ? null : 'linha ${sourceLines[name]}',
        currentLocation: 'linha ${index + 1}',
      );
      sourceLines[name] = index + 1;
    }
    return values;
  }

  static Map<String, String> parseJson(String text) {
    final decoded = jsonDecode(text);
    final values = <String, String>{};
    if (decoded is Map) {
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is String || value is num || value is bool) {
          final name = _normalizeName(entry.key.toString());
          _addParsedValue(values, name, value.toString());
        }
      }
    } else if (decoded is List) {
      var index = 0;
      for (final item in decoded.whereType<Map>()) {
        index++;
        final name = item['name']?.toString();
        final value = item['value']?.toString();
        if (name != null && value != null) {
          _addParsedValue(
            values,
            _normalizeName(name),
            value,
            currentLocation: 'item $index',
          );
        }
      }
    }
    return values;
  }

  static Map<String, String> parseXml(String text) {
    final document = XmlDocument.parse(text);
    final values = <String, String>{};
    for (final node in document.descendants.whereType<XmlElement>()) {
      if (node.name.local.toLowerCase() != 'secret') continue;
      final name = node.getAttribute('name') ?? node.getElement('name')?.innerText;
      final value = node.getAttribute('value') ??
          node.getElement('value')?.innerText ??
          node.innerText;
      if (name != null && name.trim().isNotEmpty) {
        _addParsedValue(values, _normalizeName(name), value);
      }
    }
    if (values.isEmpty &&
        document.rootElement.children.whereType<XmlElement>().isNotEmpty) {
      for (final element in document.rootElement.children.whereType<XmlElement>()) {
        if (element.children.whereType<XmlElement>().isEmpty) {
          _addParsedValue(
            values,
            _normalizeName(element.name.local),
            element.innerText,
          );
        }
      }
    }
    return values;
  }

  static void _addParsedValue(
    Map<String, String> values,
    String name,
    String value, {
    String? previousLocation,
    String? currentLocation,
  }) {
    if (values.containsKey(name)) {
      final locations = [previousLocation, currentLocation]
          .whereType<String>()
          .where((item) => item.isNotEmpty)
          .join(' e ');
      throw FormatException(
        'Secret duplicado: $name${locations.isEmpty ? '' : ' ($locations)'}. '
        'Remova a duplicidade antes de importar.',
      );
    }
    values[name] = value;
  }

  Future<(Uint8List, String)> _getPublicKey(String repositoryFullName) async {
    final data = await _gateway.getJson(
      '/repos/$repositoryFullName/actions/secrets/public-key',
    );
    final key = data['key'] as String? ?? '';
    final keyId = data['key_id'] as String? ?? '';
    if (key.isEmpty || keyId.isEmpty) {
      throw const FormatException('Chave pública de Secrets indisponível.');
    }
    return (base64.decode(key), keyId);
  }

  Future<void> _putEncrypted({
    required String repositoryFullName,
    required String name,
    required String value,
    required Uint8List publicKey,
    required String keyId,
  }) async {
    final sealed = SealedBox(PublicKey(publicKey));
    final encrypted = sealed.encrypt(Uint8List.fromList(utf8.encode(value)));
    await _gateway.putJson(
      '/repos/$repositoryFullName/actions/secrets/${Uri.encodeComponent(name)}',
      {
        'encrypted_value': base64.encode(encrypted),
        'key_id': keyId,
      },
    );
  }

  static SecretWriteResult _failureResult(
    SecretImportItem item,
    Object error, {
    bool publicKeyStage = false,
  }) {
    if (error is GitHubPermissionException) {
      return SecretWriteResult(
        name: item.name,
        kind: item.kind,
        success: false,
        message: publicKeyStage
            ? 'sem permissão para ler a chave pública de Secrets; use Secrets: Read and write no token fine-grained ou repo no token clássico'
            : 'sem permissão para gravar; use Secrets: Read and write no token fine-grained ou repo no token clássico',
        technicalCode: error.technicalCode,
        httpStatus: error.httpStatus,
        endpoint: error.endpoint,
        apiMessage: error.apiMessage,
      );
    }
    if (error is AppException) {
      return SecretWriteResult(
        name: item.name,
        kind: item.kind,
        success: false,
        message: error.message,
        technicalCode: error.technicalCode,
        httpStatus: error.httpStatus,
        endpoint: error.endpoint,
        apiMessage: error.apiMessage,
      );
    }
    return SecretWriteResult(
      name: item.name,
      kind: item.kind,
      success: false,
      message: error is FormatException
          ? error.message
          : 'não foi possível salvar este Secret',
      technicalCode: error.runtimeType.toString(),
    );
  }

  static String _normalizeName(String raw) {
    final name = raw.trim().toUpperCase();
    if (!RegExp(r'^[A-Z_][A-Z0-9_]*$').hasMatch(name) || name.startsWith('GITHUB_')) {
      throw FormatException('Nome de Secret inválido: $raw');
    }
    return name;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
