import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tela Secrets inclui exclusão global com confirmação forte', () {
    final screen = File(
      'lib/features/secrets/presentation/repository_secrets_screen.dart',
    ).readAsStringSync();
    final actions = File(
      'lib/features/secrets/presentation/repository_secrets_actions.dart',
    ).readAsStringSync();
    expect(screen, contains("label: const Text('Excluir todas')"));
    expect(actions, contains('Future<void> _deleteAllSecrets() async'));
    expect(actions, contains("confirmation.text.trim() == 'EXCLUIR'"));
    expect(actions, contains('deleteMany('));
    expect(actions, contains('onProgress: (completed, total)'));
    expect(actions, contains('Copiar resultado'));
  });

  test('seletor permite .env sem filtrar arquivos ocultos', () {
    final service = File(
      'lib/features/secrets/data/repository_secrets_service.dart',
    ).readAsStringSync();
    expect(service, contains('type: FileType.any'));
    expect(service, contains("name == '.env'"));
    expect(service, contains("name.startsWith('.env.')"));
    expect(service, contains('utf8.decode(bytes, allowMalformed: false)'));
  });
}
