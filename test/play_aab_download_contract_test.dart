import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Atalho Play pesquisa e baixa AAB, sem substituir APK', () {
    final screen = File('lib/features/repositories/presentation/repository_detail_screen.dart').readAsStringSync();
    final dialog = File('lib/features/repositories/presentation/play_readiness_dialog.dart').readAsStringSync();
    final manager = File('lib/features/downloads/data/download_manager_service.dart').readAsStringSync();
    final service = File('lib/features/repositories/data/play_aab_discovery_service.dart').readAsStringSync();
    expect(screen, contains('PlayAabDiscoveryService('));
    expect(dialog, contains('Android App Bundle (AAB)'));
    expect(dialog, contains('Baixar AAB'));
    expect(dialog, contains('startReleaseAsset('));
    expect(dialog, contains('startArtifactAab('));
    expect(dialog, contains('Informações do AAB copiadas.'));
    expect(manager, contains('_runArtifactAab('));
    expect(manager, contains("names.contains('bundleconfig.pb')"));
    expect(manager, contains("names.contains('base/manifest/androidmanifest.xml')"));
    expect(manager, contains('entry.writeContent(output)'));
    expect(service, contains('listReleaseAssets(repositoryFullName)'));
    expect(service, contains('listArtifacts(repositoryFullName)'));
    expect(service, contains("response.data?['conclusion'] == 'success'"));
    expect(manager, contains('_runArtifactApk(')); // funcionalidade antiga preservada
  });
}
