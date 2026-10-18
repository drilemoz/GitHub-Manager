import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/features/secrets/data/repository_secrets_service.dart';

void main() {
  group('RepositorySecretsService parser', () {
    test('aceita env, dois-pontos e export no mesmo arquivo', () {
      final values = RepositorySecretsService.parseText('''
# arquivo de teste
KEYSTORE_BASE64=QUJDRA==
KEYSTORE_PASSWORD: senha-forte
export KEY_ALIAS=release_alias_teste
KEY_PASSWORD='senha-chave'
BASE64_COM_DOIS_PONTOS: QUJDRA==
''');

      expect(values.keys, containsAll(<String>[
        'KEYSTORE_BASE64',
        'KEYSTORE_PASSWORD',
        'KEY_ALIAS',
        'KEY_PASSWORD',
      ]));
      expect(values['KEY_ALIAS'], 'release_alias_teste');
      expect(values['BASE64_COM_DOIS_PONTOS'], 'QUJDRA==');
    });

    test('aceita nomes .env ocultos e variantes do Android', () {
      expect(RepositorySecretsService.isSupportedImportFileName('.env'), isTrue);
      expect(RepositorySecretsService.isSupportedImportFileName('.ENV'), isTrue);
      expect(RepositorySecretsService.isSupportedImportFileName('.env.local'), isTrue);
      expect(RepositorySecretsService.isSupportedImportFileName('release.ENV'), isTrue);
      expect(RepositorySecretsService.isSupportedImportFileName('secrets.txt'), isTrue);
      expect(RepositorySecretsService.isSupportedImportFileName('foto.jpg'), isFalse);
    });

    test('aceita UTF-8 BOM, CRLF e export com tabulação', () {
      final values = RepositorySecretsService.parseText(
        '\uFEFF# comentario\r\nexport\tKEY_ALIAS=teste\r\nKEY_PASSWORD="abc#123"\r\n',
      );
      expect(values['KEY_ALIAS'], 'teste');
      expect(values['KEY_PASSWORD'], 'abc#123');
    });

    test('detecta duplicidade após normalização', () {
      expect(
        () => RepositorySecretsService.parseText(
          'key_password=um\nKEY_PASSWORD=dois',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('duplicado'),
          ),
        ),
      );
    });


    test('rejeita linha não vazia sem separador', () {
      expect(
        () => RepositorySecretsService.parseText('TOKEN_SEM_SEPARADOR'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Linha 1 inválida'),
          ),
        ),
      );
    });

    test('rejeita nomes reservados GITHUB_', () {
      expect(
        () => RepositorySecretsService.parseText('GITHUB_TOKEN=valor'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('RepositorySecretsService validação', () {
    test('distingue criar e substituir sem estourar limite', () async {
      final gateway = _FakeGateway(existingNames: const ['EXISTENTE']);
      final service = RepositorySecretsService.withGateway(gateway);

      final plan = await service.prepareImport(
        repositoryFullName: 'owner/repo',
        values: const {
          'EXISTENTE': 'novo valor',
          'NOVA': 'valor',
        },
      );

      expect(plan.createCount, 1);
      expect(plan.updateCount, 1);
      expect(plan.finalCount, 2);
    });

    test('rejeita Secret acima de 48 KB em UTF-8', () async {
      final service = RepositorySecretsService.withGateway(_FakeGateway());
      final oversized = List.filled(
        (RepositorySecretsService.maxSecretBytes ~/ 2) + 1,
        'á',
      ).join();

      expect(
        () => service.prepareImport(
          repositoryFullName: 'owner/repo',
          values: {'GRANDE': oversized},
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('48 KB'),
          ),
        ),
      );
    });

    test('considera substituições ao validar limite de 100', () async {
      final existing = List.generate(100, (index) => 'SECRET_$index');
      final service = RepositorySecretsService.withGateway(
        _FakeGateway(existingNames: existing),
      );

      final replacePlan = await service.prepareImport(
        repositoryFullName: 'owner/repo',
        values: const {'SECRET_0': 'substituir'},
      );
      expect(replacePlan.finalCount, 100);

      expect(
        () => service.prepareImport(
          repositoryFullName: 'owner/repo',
          values: const {'SECRET_NOVA': 'criar'},
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('100'),
          ),
        ),
      );
    });
  });

  group('RepositorySecretsService lote e diagnóstico', () {
    test('continua lote após falha individual e não expõe valores', () async {
      final gateway = _FakeGateway(failNames: const {'FALHA'});
      final service = RepositorySecretsService.withGateway(gateway);
      const values = {
        'SUCESSO': 'valor-ultrassecreto-1',
        'FALHA': 'valor-ultrassecreto-2',
      };
      final plan = await service.prepareImport(
        repositoryFullName: 'owner/repo',
        values: values,
      );

      final result = await service.putMany(
        repositoryFullName: 'owner/repo',
        values: values,
        preparedPlan: plan,
      );

      expect(result.saved, 1);
      expect(result.failed, 1);
      expect(gateway.puts.length, 2);
      final diagnosis = result.diagnosticText(repositoryFullName: 'owner/repo');
      expect(diagnosis, contains('SUCESSO'));
      expect(diagnosis, contains('FALHA'));
      expect(diagnosis, contains('HTTP 403'));
      expect(diagnosis, isNot(contains('valor-ultrassecreto-1')));
      expect(diagnosis, isNot(contains('valor-ultrassecreto-2')));
    });

    test('payload usa sealed box, key_id e nunca envia texto puro', () async {
      final gateway = _FakeGateway();
      final service = RepositorySecretsService.withGateway(gateway);
      const values = {'TOKEN_TESTE': 'texto-puro-nao-pode-vazar'};
      final plan = await service.prepareImport(
        repositoryFullName: 'owner/repo',
        values: values,
      );

      final result = await service.putMany(
        repositoryFullName: 'owner/repo',
        values: values,
        preparedPlan: plan,
      );

      expect(result.allSucceeded, isTrue);
      final payload = gateway.puts.single.data;
      expect(payload['key_id'], 'test-key-id');
      expect(payload['encrypted_value'], isA<String>());
      expect(payload['encrypted_value'], isNot(contains(values['TOKEN_TESTE']!)));
      expect(base64.decode(payload['encrypted_value']! as String), isNotEmpty);
    });

    test('exclui em lote, remove duplicados e reporta falhas individuais', () async {
      final gateway = _FakeGateway(failDeleteNames: const {'FALHA'});
      final service = RepositorySecretsService.withGateway(gateway);
      final progress = <int>[];
      final result = await service.deleteMany(
        repositoryFullName: 'owner/repo',
        names: const ['UM', 'FALHA', 'um', 'DOIS'],
        onProgress: (completed, _) => progress.add(completed),
      );
      expect(result.total, 3);
      expect(result.deleted, 2);
      expect(result.failed, 1);
      expect(result.allSucceeded, isFalse);
      expect(progress, [1, 2, 3]);
      expect(gateway.deletedPaths, [
        '/repos/owner/repo/actions/secrets/UM',
        '/repos/owner/repo/actions/secrets/FALHA',
        '/repos/owner/repo/actions/secrets/DOIS',
      ]);
      final diagnostic = result.diagnosticText(repositoryFullName: 'owner/repo');
      expect(diagnostic, contains('FALHA'));
      expect(diagnostic, contains('HTTP 403'));
      expect(diagnostic, isNot(contains('encrypted_value')));
    });

    test('não inicia exclusão com nomes inválidos', () async {
      final gateway = _FakeGateway();
      final service = RepositorySecretsService.withGateway(gateway);
      await expectLater(
        service.deleteMany(
          repositoryFullName: 'owner/repo',
          names: const ['VALIDO', 'GITHUB_TOKEN'],
        ),
        throwsA(isA<FormatException>()),
      );
      expect(gateway.deletedPaths, isEmpty);
    });

    test('exclusão usa somente o nome, sem valor', () async {
      final gateway = _FakeGateway();
      final service = RepositorySecretsService.withGateway(gateway);

      await service.deleteSecret(
        repositoryFullName: 'owner/repo',
        name: 'TOKEN_TESTE',
      );

      expect(gateway.deletedPaths.single, endsWith('/TOKEN_TESTE'));
    });
  });
}

class _PutCall {
  const _PutCall(this.path, this.data);
  final String path;
  final Map<String, dynamic> data;
}

class _FakeGateway implements RepositorySecretsGateway {
  _FakeGateway({
    this.existingNames = const [],
    this.failNames = const {},
    this.failDeleteNames = const {},
  });

  final List<String> existingNames;
  final Set<String> failNames;
  final Set<String> failDeleteNames;
  final List<_PutCall> puts = [];
  final List<String> deletedPaths = [];

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    if (path.endsWith('/public-key')) {
      final publicKey = List<int>.generate(32, (index) => index + 1);
      return {
        'key': base64.encode(publicKey),
        'key_id': 'test-key-id',
      };
    }
    return {
      'total_count': existingNames.length,
      'secrets': existingNames
          .map(
            (name) => {
              'name': name,
              'created_at': '2026-08-27T00:00:00Z',
              'updated_at': '2026-08-27T00:00:00Z',
            },
          )
          .toList(),
    };
  }

  @override
  Future<int?> putJson(String path, Map<String, dynamic> data) async {
    puts.add(_PutCall(path, Map<String, dynamic>.from(data)));
    final name = Uri.decodeComponent(path.split('/').last);
    if (failNames.contains(name)) {
      throw GitHubPermissionException(
        httpStatus: 403,
        endpoint: path,
        apiMessage: 'Resource not accessible by personal access token',
      );
    }
    return 201;
  }

  @override
  Future<void> delete(String path) async {
    deletedPaths.add(path);
    if (failDeleteNames.contains(Uri.decodeComponent(path.split('/').last))) {
      throw GitHubPermissionException(
        httpStatus: 403,
        endpoint: path,
        apiMessage: 'Resource not accessible by personal access token',
      );
    }
  }
}
