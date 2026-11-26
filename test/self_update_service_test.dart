import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/update/application/self_update_service.dart';

Map<String, dynamic> release(String version, int code, {bool draft = false,
    bool prerelease = false, bool testApk = false}) {
  final name = 'GitHub-Manager-$version-$code-${testApk ? 'test' : 'universal-release'}.apk';
  return {'tag_name': 'v$version', 'draft': draft, 'prerelease': prerelease,
    'assets': [{'id': code, 'name': name, 'state': 'uploaded', 'size': 100,
      'browser_download_url': 'https://github.com/$selfUpdateRepository/releases/download/v$version/$name'}]};
}

void main() {
  test('seleciona maior versionCode oficial estável, sem depender da ordem', () {
    final selected = SelfUpdateRelease.select([
      release('2.0.151', 200165), release('2.0.155', 200169, draft: true),
      release('2.0.153', 200167), release('2.0.154', 200168, testApk: true),
      release('2.0.156', 200170, prerelease: true),
    ], 200164, authenticated: false);
    expect(selected?.code, 200167);
    expect(selected?.version, '2.0.153');
  });
  test('ignora downgrade, mesma versão e URL fora do repositório', () {
    final external = release('2.0.152', 200166);
    (external['assets'] as List).first['browser_download_url'] = 'https://example.org/app.apk';
    expect(SelfUpdateRelease.select([release('2.0.150', 200164),
      release('2.0.151', 200165), external], 200165, authenticated: true), isNull);
  });
}
