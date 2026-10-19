import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/features/projects/domain/project_safety_check.dart';

enum ApkInstallationState {
  install,
  update,
  current,
  newerInstalled,
  unknown,
  noApk,
}

/// Comparação somente após localizar o pacote pelo applicationId real.
/// A versão do GitHub pode ter vindo de tag/nome do arquivo (estimativa).
class ApkInstallationAssessment {
  const ApkInstallationAssessment({
    required this.state,
    this.packageName,
    this.installedVersion,
    this.installedCode,
    this.availableVersion,
    this.availableCode,
    this.detail,
    this.verifiedCodes = false,
  });

  final ApkInstallationState state;
  final String? packageName;
  final String? installedVersion;
  final int? installedCode;
  final String? availableVersion;
  final int? availableCode;
  final String? detail;
  final bool verifiedCodes;

  String get label => switch (state) {
    ApkInstallationState.install => 'Instalar',
    ApkInstallationState.update => 'Atualizar',
    ApkInstallationState.current => 'Atualizado',
    ApkInstallationState.newerInstalled => 'Mais recente no aparelho',
    ApkInstallationState.noApk => 'Sem APK',
    ApkInstallationState.unknown => 'Não foi possível verificar',
  };

  static ApkInstallationAssessment evaluate({
    required String? applicationId,
    required InstalledAndroidApp? installed,
    required String? availableVersion,
    int? availableCode,
    required bool hasApk,
    bool sourcesComplete = true,
  }) {
    final packageName = applicationId?.trim();
    if (packageName == null || packageName.isEmpty) {
      return ApkInstallationAssessment(
        state: ApkInstallationState.unknown,
        availableVersion: availableVersion,
        detail: 'applicationId não identificado no repositório.',
      );
    }
    if (!hasApk) {
      return ApkInstallationAssessment(
        state: sourcesComplete ? ApkInstallationState.noApk : ApkInstallationState.unknown,
        packageName: packageName,
        detail: sourcesComplete ? 'Nenhum APK publicado encontrado.' : 'Consulta incompleta às fontes do GitHub.',
      );
    }
    if (installed == null || installed.status == InstalledAppQueryStatus.unknown) {
      return ApkInstallationAssessment(
        state: ApkInstallationState.unknown,
        packageName: packageName,
        availableVersion: availableVersion,
        detail: 'O Android não confirmou se este pacote está instalado (visibilidade limitada ou consulta indisponível).',
      );
    }
    if (installed.status == InstalledAppQueryStatus.notInstalled) {
      return ApkInstallationAssessment(
        state: ApkInstallationState.install,
        packageName: packageName,
        availableVersion: availableVersion,
        detail: 'O aplicativo não foi encontrado neste aparelho. Toque em Instalar para baixar a versão publicada no GitHub.',
      );
    }
    // Compara o código apenas quando AMBAS as fontes têm o valor da mesma
    // publicação. Não usa versionCode de HEAD como se fosse do APK da Release.
    final currentVersion = installed.versionName?.trim();
    final codesAvailable = installed.versionCode != null && availableCode != null;
    final comparison = ProjectSafetyCheck.compareVersions(
      currentVersion,
      installed.versionCode,
      availableVersion,
      availableCode,
    );
    final base = ApkInstallationAssessment(
      state: ApkInstallationState.unknown,
      packageName: packageName,
      installedVersion: currentVersion,
      installedCode: installed.versionCode,
      availableVersion: availableVersion,
      availableCode: availableCode,
      verifiedCodes: codesAvailable,
    );
    if (comparison == ProjectVersionComparison.older) {
      return ApkInstallationAssessment(
        state: ApkInstallationState.update,
        packageName: base.packageName,
        installedVersion: base.installedVersion,
        installedCode: base.installedCode,
        availableVersion: base.availableVersion,
        availableCode: base.availableCode,
        verifiedCodes: codesAvailable,
        detail: 'Versão disponível é mais recente. Confirme a assinatura na instalação.',
      );
    }
    if (!sourcesComplete &&
        (comparison == ProjectVersionComparison.same ||
         comparison == ProjectVersionComparison.newer)) {
      return ApkInstallationAssessment(
        state: ApkInstallationState.unknown,
        packageName: base.packageName,
        installedVersion: base.installedVersion,
        installedCode: base.installedCode,
        availableVersion: base.availableVersion,
        detail: 'Não foi possível consultar todas as fontes; pode existir um APK mais recente.',
      );
    }
    if (comparison == ProjectVersionComparison.newer) {
      return ApkInstallationAssessment(
        state: ApkInstallationState.newerInstalled,
        packageName: base.packageName,
        installedVersion: base.installedVersion,
        installedCode: base.installedCode,
        availableVersion: base.availableVersion,
        availableCode: base.availableCode,
        verifiedCodes: codesAvailable,
        detail: 'O aparelho possui uma versão mais recente que a publicação localizada.',
      );
    }
    if (comparison == ProjectVersionComparison.same) {
      return ApkInstallationAssessment(
        state: ApkInstallationState.current,
        packageName: base.packageName,
        installedVersion: base.installedVersion,
        installedCode: base.installedCode,
        availableVersion: base.availableVersion,
        availableCode: base.availableCode,
        verifiedCodes: codesAvailable,
        detail: codesAvailable
            ? 'Versão e versionCode coincidem.'
            : 'Versão visível coincide; versionCode do APK remoto não confirmado.',
      );
    }
    return ApkInstallationAssessment(
      state: ApkInstallationState.unknown,
      packageName: base.packageName,
      installedVersion: base.installedVersion,
      installedCode: base.installedCode,
      availableVersion: base.availableVersion,
      availableCode: base.availableCode,
      detail: 'Versões insuficientes para uma comparação segura.',
    );
  }
}
