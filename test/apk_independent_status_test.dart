import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/repositories/presentation/repository_apk_status_provider.dart';

void main() {
  test('identidade local conhecida apenas para repositório oficial', () {
    expect(ownRepositoryApplicationId('Drilemoz/GitHub-Manager'), 'br.com.githubmanager.app');
    expect(ownRepositoryApplicationId('other/GitHub-Manager'), isNull);
    expect(ownRepositoryApplicationId('drilemoz/Vigia-IA'), isNull);
  });
  test('consultas local e remota independentes e diagnóstico disponível', () {
    final source = File('lib/features/repositories/presentation/repository_apk_status_provider.dart').readAsStringSync();
    final local = source.split('final repositoryLocalApkProvider').last.split('final repositoryRemoteApkProvider').first;
    expect(local, contains('PlatformActions.getInstalledAppInfo(id)'));
    expect(local, isNot(contains('listArtifacts(')));
    expect(local, isNot(contains('listReleaseAssets(')));
    expect(local, contains("source: 'apk_local'"));
    final screen = File('lib/features/repositories/presentation/repository_detail_widgets.dart').readAsStringSync();
    expect(screen, contains('local.isLoading || remote.isLoading'));
    expect(screen, contains('Sem publicação'));
    expect(screen, contains('LinearProgressIndicator'));
  });
}
