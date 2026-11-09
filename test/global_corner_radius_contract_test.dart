import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retângulos usam raio 4; telas redesenhadas têm exceções exatas', () {
    // A interface da versão 2.0.147 adotou raios maiores exclusivamente
    // nestes componentes. Quantidades fixas impedem que a exceção se
    // transforme em liberação global para novas telas.
    const redesignedCorners = <String, Map<int, int>>{
      'lib/features/drive_sync/presentation/drive_sync_screen.dart': {
        12: 1,
        16: 1,
      },
      'lib/features/repositories/presentation/repository_detail_widgets.dart': {
        12: 4,
        14: 2,
        16: 2,
      },
    };

    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final borderRadius = RegExp(r'BorderRadius\.circular\((\d+)\)');
    // \b evita contar BorderRadius.circular(...) uma segunda vez.
    final radius = RegExp(r'\bRadius\.circular\((\d+)\)');
    final actualCorners = <String, Map<int, int>>{};
    final violations = <String>[];

    for (final file in dartFiles) {
      final path = file.path.replaceAll('\\', '/');
      final content = file.readAsStringSync();
      final values = <int>[
        ...borderRadius.allMatches(content).map((m) => int.parse(m.group(1)!)),
        ...radius.allMatches(content).map((m) => int.parse(m.group(1)!)),
      ];
      for (final value in values) {
        if (value == 4 || value == 99 || value == 999) continue;
        if (redesignedCorners[path]?.containsKey(value) == true) {
          final counts = actualCorners.putIfAbsent(path, () => <int, int>{});
          counts[value] = (counts[value] ?? 0) + 1;
        } else {
          violations.add('$path: raio não autorizado $value');
        }
      }
    }

    expect(violations, isEmpty, reason: violations.join('\n'));
    for (final entry in redesignedCorners.entries) {
      expect(actualCorners[entry.key], entry.value,
          reason: 'Apenas os cantos previstos para ${entry.key} são aceitos.');
    }
    expect(actualCorners.keys.toSet(), redesignedCorners.keys.toSet());
  });
}
