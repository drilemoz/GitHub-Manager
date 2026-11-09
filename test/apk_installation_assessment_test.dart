import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/features/builds/domain/apk_installation_assessment.dart';

const _installed = InstalledAndroidApp(
  status: InstalledAppQueryStatus.installed,
  packageName: 'br.exemplo.vigia',
  versionName: '1.0.230',
  versionCode: 230,
);

void main() {
  test('retorna atualizar quando Android está atrás da Release', () {
    final result = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: _installed,
      availableVersion: '1.0.232',
      hasApk: true,
    );
    expect(result.state, ApkInstallationState.update);
    expect(result.installedVersion, '1.0.230');
    expect(result.availableVersion, '1.0.232');
  });

  test('versão igual sem versionCode remoto não deve afirmar atualização', () {
    final result = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: _installed,
      availableVersion: '1.0.230',
      hasApk: true,
    );
    expect(result.state, ApkInstallationState.versionMatches);
    expect(result.verifiedCodes, isFalse);
    expect(result.detail, contains('versionCode'));
  });

  test('versões e códigos confirmados realmente mostram atualizado', () {
    final result = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: _installed,
      availableVersion: '1.0.230',
      availableCode: 230,
      hasApk: true,
    );
    expect(result.state, ApkInstallationState.current);
    expect(result.verifiedCodes, isTrue);
  });

  test('não afirma atualização quando versão instalada é maior', () {
    final result = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: _installed,
      availableVersion: '1.0.228',
      hasApk: true,
    );
    expect(result.state, ApkInstallationState.newerInstalled);
  });

  test('versão visível igual mas código confirmado diferente recomenda atualizar', () {
    final result = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: _installed,
      availableVersion: '1.0.230',
      availableCode: 231,
      hasApk: true,
    );
    expect(result.state, ApkInstallationState.update);
    expect(result.verifiedCodes, isTrue);
  });

  test('sem package id nunca infere nome a partir do nome do repositório', () {
    final result = ApkInstallationAssessment.evaluate(
      applicationId: null,
      installed: _installed,
      availableVersion: '1.0.232',
      hasApk: true,
    );
    expect(result.state, ApkInstallationState.unknown);
  });

  test('filtro de visibilidade Android não equivale a app ausente', () {
    final result = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: const InstalledAndroidApp(
        status: InstalledAppQueryStatus.unknown,
        reason: 'package_visibility',
      ),
      availableVersion: '1.0.232',
      hasApk: true,
    );
    expect(result.state, ApkInstallationState.unknown);
  });

  test('ausência confirmada permite Instalar, fonte parcial não afirma Sem APK', () {
    final absent = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: const InstalledAndroidApp(
        status: InstalledAppQueryStatus.notInstalled,
      ),
      availableVersion: '1.0.232',
      hasApk: true,
    );
    expect(absent.state, ApkInstallationState.install);
    final partial = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: null,
      availableVersion: null,
      hasApk: false,
      sourcesComplete: false,
    );
    expect(partial.state, ApkInstallationState.unknown);
  });

  test('fontes incompletas não confirmam atualização plena', () {
    final result = ApkInstallationAssessment.evaluate(
      applicationId: 'br.exemplo.vigia',
      installed: _installed,
      availableVersion: '1.0.230',
      hasApk: true,
      sourcesComplete: false,
    );
    expect(result.state, ApkInstallationState.unknown);
  });

  test('parser do canal nativo preserva longVersionCode', () {
    final parsed = InstalledAndroidApp.fromMap({
      'status': 'installed',
      'packageName': 'br.exemplo.vigia',
      'versionName': '1.2.3',
      'versionCode': 3000000000,
    });
    expect(parsed.versionCode, 3000000000);
    expect(parsed.status, InstalledAppQueryStatus.installed);
  });
}
