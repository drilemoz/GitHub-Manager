import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rechecagem do APK local independe de haver publicação remota', () {
    final source = File('lib/features/repositories/presentation/repository_apk_status_provider.dart')
        .readAsStringSync();
    expect(source, contains('if (id != null && id.isNotEmpty)'));
    expect(source, isNot(contains('&& !latest.isEmpty')));
  });

  test('aplicativo não confunde igualdade de versionName com APK confirmado', () {
    final source = File('lib/features/builds/domain/apk_installation_assessment.dart')
        .readAsStringSync();
    expect(source, contains('ApkInstallationState.versionMatches'));
    expect(source, contains('codesAvailable ? ApkInstallationState.current'));
    final detail = File('lib/features/repositories/presentation/repository_detail_screen.dart')
        .readAsStringSync();
    expect(detail, contains('onRefresh: () => ref.invalidate(repositoryApkStatusProvider(repository))'));
  });
}
