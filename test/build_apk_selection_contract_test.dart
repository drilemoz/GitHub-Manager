import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('global Builds never picks the first APK silently', () {
    final source = File(
      'lib/features/builds/presentation/global_builds_screen.dart',
    ).readAsStringSync();

    expect(source, contains('showSmartApkPicker<_GlobalApkCandidate>'));
    expect(source, contains('SmartApkOption('));
    expect(File('lib/features/builds/presentation/smart_apk_picker.dart').readAsStringSync(), contains('Baixar opção sugerida'));
    expect(source, contains('apkRecommendationRank'));
    expect(source, contains('getAndroidDeviceInfo'));
    expect(source, isNot(contains('releaseApks.first')));
    expect(source, isNot(contains('apkArtifact = artifact;')));
  });

  test('repository APK shortcut usa provider compartilhado para última versão e instalação', () {
    final source = File(
      'lib/features/repositories/presentation/repository_detail_screen.dart',
    ).readAsStringSync();
    final actions = File(
      'lib/features/repositories/presentation/repository_detail_screen_actions.dart',
    ).readAsStringSync();

    expect(source, contains('onTap: () => _downloadLatestApk(repository)'));
    expect(source, contains('enabled: !_apkShortcutBusy'));
    expect(source, isNot(contains('latestApk != null')));
    // Desde a 2.0.125 as consultas são compartilhadas pelo provider para
    // alimentar tanto o botão APK quanto o estado instalado/atualizado.
    final statusProvider = File(
      'lib/features/repositories/presentation/repository_apk_status_provider.dart',
    ).readAsStringSync();
    expect(actions, contains('repositoryApkStatusProvider(repository).future'));
    expect(actions, contains('final latest = apkStatus.latest;'));
    expect(statusProvider, contains('service.listReleaseAssets(fullName)'));
    expect(statusProvider, contains('service.listArtifacts(fullName)'));
    expect(statusProvider, contains('Future.wait<void>([loadReleases(), loadArtifacts()])'));
    expect(statusProvider, contains('LatestApkShortcut.resolve('));
    expect(statusProvider, contains('ApkInstallationAssessment.evaluate('));
    expect(statusProvider, contains('releaseError = error;'));
    expect(statusProvider, contains('artifactError = error;'));
    expect(actions, contains('showSmartApkPicker<Object>'));
    expect(actions, contains('startReleaseAsset('));
    expect(actions, contains('startArtifactApk('));
    expect(File('lib/features/builds/presentation/smart_apk_picker.dart').readAsStringSync(),
        contains('if (!preferred.exactRun && runNumber > 0)'));
  });
}
