import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('versão canônica documentada coincide com pubspec e JSON Android', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([0-9A-Za-z.-]+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    final name = match!.group(1)!;
    final code = match.group(2)!;
    final canonical = 'version: $name+$code';
    final versioning = File('docs/VERSIONING.md').readAsStringSync();
    expect(versioning, contains('`$canonical`'));
    final release = File('docs/RELEASE_$name.md');
    expect(release.existsSync(), isTrue);
    final changelog = File('CHANGELOG.md').readAsStringSync();
    expect(changelog, contains('## $name+$code'));
    final json = File('github-manager.json').readAsStringSync();
    expect(json, contains('"versionName": "$name"'));
    expect(json, contains('"versionCode": $code'));
  });
}
