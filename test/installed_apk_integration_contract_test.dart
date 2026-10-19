import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('API nativa consulta pacote específico e respeita visibilidade Android', () {
    final kotlin = File(
      'android/app/src/main/kotlin/br/com/githubmanager/app/MainActivity.kt',
    ).readAsStringSync();
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(kotlin, contains('"getInstalledAppInfo"'));
    expect(kotlin, contains('getPackageInfo(packageName'));
    expect(kotlin, contains('info.longVersionCode'));
    expect(kotlin, contains('"package_visibility"'));
    expect(kotlin, contains('if (Build.VERSION.SDK_INT >= 30) "unknown" else "notInstalled"'));
    expect(kotlin, isNot(contains('"not_found_after_launcher_query"')));
    expect(manifest, contains('<queries>'));
    expect(manifest, contains('android.intent.category.LAUNCHER'));
    expect(manifest, isNot(contains('android.permission.QUERY_ALL_PACKAGES')));
  });

  test('atalho de APK exibe estado e permite escolha de outras versões', () {
    final detail = File(
      'lib/features/repositories/presentation/repository_detail_screen.dart',
    ).readAsStringSync();
    final actions = File(
      'lib/features/repositories/presentation/repository_detail_screen_actions.dart',
    ).readAsStringSync();
    expect(detail, contains('repositoryApkStatusProvider(repository)'));
    expect(detail, contains('_RepositoryApkInstallationStatus'));
    expect(actions, contains('Esta versão já está instalada'));
    expect(actions, contains('Escolher APK'));
    expect(actions, contains('showSmartApkPicker'));
    expect(actions, contains('manager.startReleaseAsset'));
  });
}
