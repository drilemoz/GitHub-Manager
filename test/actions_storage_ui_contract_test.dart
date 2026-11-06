import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storage panel exposes safe manual cleanup and explicit billing read', () {
    final source = File('lib/features/builds/presentation/actions_storage_screen.dart')
        .readAsStringSync();
    expect(source, contains('Selecionar anteriores'));
    expect(source, contains('Selecionar exibidos'));
    expect(source, contains('_ArtifactFilter.olderThanWeek'));
    expect(source, contains('_ArtifactOrder.largest'));
    expect(source, contains('StorageSelectionPolicy.selectOlderRunArtifacts'));
    expect(source, contains('A verificação posterior falhou'));
    expect(source, contains('Consultar relatório de uso'));
    final initState = source.split('void initState() {')[1]
        .split('Future<void> _loadRepositories()')[0];
    expect(initState, isNot(contains('_loadBilling()')));
    expect(source, contains('A cota oficial pode levar algum tempo para atualizar'));
  });
}
