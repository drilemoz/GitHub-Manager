import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/projects/domain/project_safety_check.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/domain/repository_project_info.dart';

void main() {
  const repository = GitHubRepository(
    id: 1,
    name: 'Social-Lite',
    fullName: 'owner/Social-Lite',
    isPrivate: false,
    isArchived: false,
    defaultBranch: 'main',
    updatedAt: null,
    htmlUrl: 'https://github.com/owner/Social-Lite',
  );

  ZipProjectPreview preview({
    String name = 'Social-Lite-0.1.1.zip',
    String? projectName,
    String? packageName,
    String? applicationId,
    String? version = '0.1.1',
    int? versionCode,
  }) =>
      ZipProjectPreview(
        path: '/tmp/$name',
        name: name,
        archiveBytes: 1,
        uncompressedBytes: 1,
        fileCount: 1,
        folderCount: 1,
        projectType: 'Android',
        importantFiles: const [],
        commonRoot: null,
        projectName: projectName,
        packageName: packageName,
        applicationId: applicationId,
        version: version,
        versionCode: versionCode,
      );

  RepositoryProjectInfo info({
    String projectName = 'Social-Lite',
    String? version = '0.1.0',
    String? packageName,
    String? applicationId,
    int? versionCode,
  }) =>
      RepositoryProjectInfo(
        projectName: projectName,
        version: version,
        technologies: const ['Android'],
        packageName: packageName,
        applicationId: applicationId,
        versionCode: versionCode,
      );

  test('versioned ZIP filename matches same repository without blocking', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(),
      repository: repository,
      repositoryInfo: info(),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isFalse);
    expect(result.identitySource, contains('ZIP'));
    expect(result.versionComparison, ProjectVersionComparison.newer);
  });


  test('versioned project metadata still matches repository name', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(projectName: 'social-lite-0.1.1'),
      repository: repository,
      repositoryInfo: info(projectName: 'Social-Lite'),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isFalse);
    expect(result.versionComparison, ProjectVersionComparison.newer);
  });

  test('versioned package clue from metadata does not create false mismatch', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(packageName: 'social-lite-0.1.1'),
      repository: repository,
      repositoryInfo: info(packageName: 'social-lite-0.1.0'),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isFalse);
  });

  test('namespaced versioned package clue is normalized before splitting', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(packageName: '@vendor/social-lite-0.1.1'),
      repository: repository,
      repositoryInfo: info(packageName: '@vendor/social-lite-0.1.0'),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isFalse);
  });

  test('different namespaced package is blocked when filename claims another project', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(packageName: '@vendor/uai-cortes-0.1.99'),
      repository: repository,
      repositoryInfo: info(packageName: '@vendor/social-lite-0.1.0'),
    );

    expect(result.blocked, isTrue);
    expect(result.identitySource, contains('pacote interno'));
  });

  test('GitHub Manager export suffix is ignored as a weak filename clue', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(
        name: 'Social-Lite-v0.1.1-20260826-212533-main.zip',
      ),
      repository: repository,
      repositoryInfo: info(),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isFalse);
  });

  test('accented display name matches repository without accents', () {
    const taticaRepository = GitHubRepository(
      id: 2,
      name: 'TaticaManager',
      fullName: 'owner/TaticaManager',
      isPrivate: false,
      isArchived: false,
      defaultBranch: 'main',
      updatedAt: null,
      htmlUrl: 'https://github.com/owner/TaticaManager',
    );

    final result = ProjectSafetyCheck.compare(
      project: preview(
        name: 'tatica-manager.zip',
        projectName: 'Tática Manager',
        packageName: null,
        applicationId: null,
      ),
      repository: taticaRepository,
      repositoryInfo: info(
        projectName: 'TaticaManager',
        packageName: null,
        applicationId: null,
      ),
    );

    expect(result.blocked, isFalse);
    expect(result.identitySource, 'metadados do projeto');
  });

  test('different applicationId becomes strong warning but remains sendable', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(applicationId: 'com.example.sociallite'),
      repository: repository,
      repositoryInfo: info(applicationId: 'com.example.other'),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isTrue);
    expect(result.identitySource, 'applicationId divergente');
  });

  test('unknown version becomes warning instead of newer version', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(version: null),
      repository: repository,
      repositoryInfo: info(version: '0.1.0'),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isTrue);
    expect(result.versionComparison, ProjectVersionComparison.unknown);
  });

  test('older version is allowed as explicit regression warning', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(version: '0.0.9'),
      repository: repository,
      repositoryInfo: info(version: '0.1.0'),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isTrue);
    expect(result.versionComparison, ProjectVersionComparison.older);
  });


  test('two divergent strong identities require high-risk override', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(
        applicationId: 'com.example.sociallite',
        packageName: 'social_lite',
      ),
      repository: repository,
      repositoryInfo: info(
        applicationId: 'com.example.other',
        packageName: 'other_project',
      ),
    );

    expect(result.blocked, isTrue);
    expect(result.warning, isTrue);
    expect(result.identitySource, contains('divergentes'));
  });

  test('explicit identity mismatch blocks automatic upload even without strong IDs', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(projectName: 'Nome Antigo'),
      repository: repository,
      repositoryInfo: info(projectName: 'Nome Novo'),
    );

    expect(result.blocked, isTrue);
    expect(result.warning, isTrue);
  });

  test('different weak filename never blocks by itself', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(name: 'arquivo-exportado-0.1.1.zip'),
      repository: repository,
      repositoryInfo: info(),
    );

    expect(result.blocked, isFalse);
    expect(result.warning, isTrue);
  });

  test('selected versioned filename cannot conceal another internal project', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(
        name: 'Social-Lite-v0.1.1-fonte-completo.zip',
        projectName: 'Uai Cortes',
        version: '0.1.99',
      ),
      repository: repository,
      repositoryInfo: info(),
    );
    expect(result.blocked, isTrue);
    expect(result.identitySource, contains('arquivo escolhido'));
  });

  test('qualificador VPS após versão é parte legítima do nome do projeto', () {
    const serverRepository = GitHubRepository(
      id: 51, name: 'alsistemas', fullName: 'drilemoz/alsistemas',
      isPrivate: false, isArchived: false, defaultBranch: 'main',
      updatedAt: null, htmlUrl: 'https://github.com/drilemoz/alsistemas',
    );
    final result = ProjectSafetyCheck.compare(
      project: preview(
        name: 'AL-Sistemas-v2.0.7-VPS.zip',
        projectName: 'AL Sistemas VPS',
        version: '2.0.7',
      ),
      repository: serverRepository,
      repositoryInfo: info(
        projectName: 'AL Sistemas VPS',
        version: '2.0.6',
      ),
    );
    expect(result.blocked, isFalse);
  });

  test('qualificador de ZIP não libera projeto genuinamente diferente', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(
        name: 'AL-Sistemas-v2.0.7-VPS.zip',
        projectName: 'Projeto Desconhecido',
        version: '2.0.7',
      ),
      repository: repository,
      repositoryInfo: info(),
    );
    expect(result.blocked, isTrue);
  });

  test('matching filename and internal identity continue normally', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(
        name: 'Social-Lite-v0.1.1-fonte-completo.zip',
        projectName: 'Social Lite',
      ),
      repository: repository,
      repositoryInfo: info(),
    );
    expect(result.blocked, isFalse);
  });

  test('internal pubspec package catches swapped ZIP without display metadata', () {
    final result = ProjectSafetyCheck.compare(
      project: preview(
        name: 'Social-Lite-v0.1.1.zip',
        packageName: 'uaicortes',
      ),
      repository: repository,
      repositoryInfo: info(),
    );
    expect(result.blocked, isTrue);
    expect(result.identitySource, contains('pacote interno'));
  });

  group('SemVer', () {
    test('versão estável é posterior ao prerelease da mesma versão', () {
      expect(
        ProjectSafetyCheck.compareVersions('1.0.0-alpha.2', null, '1.0.0', null),
        ProjectVersionComparison.older,
      );
      expect(
        ProjectSafetyCheck.compareVersions('1.0.0', null, '1.0.0-rc.9', null),
        ProjectVersionComparison.newer,
      );
    });

    test('identificadores numéricos de prerelease usam ordem numérica', () {
      expect(
        ProjectSafetyCheck.compareVersions('0.1.0-alpha.10', null, '0.1.0-alpha.2', null),
        ProjectVersionComparison.newer,
      );
    });

    test('versionCode não sobrepõe a precedência SemVer', () {
      expect(
        ProjectSafetyCheck.compareVersions('1.0.0-alpha.99', 999, '1.0.0', 1),
        ProjectVersionComparison.older,
      );
    });

    test('metadados de build após + não alteram precedência', () {
      expect(
        ProjectSafetyCheck.compareVersions('1.2.3+200095', null, '1.2.3+200094', null),
        ProjectVersionComparison.same,
      );
    });
  });

}
