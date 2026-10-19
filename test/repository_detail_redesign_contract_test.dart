import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detalhe do repositório exibe chip de versão/SDK e card redesenhado do APK', () {
    final source = File(
      'lib/features/repositories/presentation/repository_detail_widgets.dart',
    ).readAsStringSync();

    expect(source, contains('_HeaderMetaChip'));
    expect(source, contains('SDK Android'));
    expect(source, contains('APK não instalado'));
    expect(source, contains("label: 'No aparelho'"));
  });
}
