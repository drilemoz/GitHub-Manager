import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/projects/domain/project_safety_check.dart';
import 'package:github_manager/features/projects/domain/upload_identification_diagnosis.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/domain/repository_project_info.dart';

void main() {
  const zip = ZipProjectPreview(
    path: 'file.zip', name: 'file.zip', archiveBytes: 1,
    uncompressedBytes: 1, fileCount: 2, folderCount: 1,
    projectType: 'Flutter', importantFiles: [], commonRoot: null,
    projectName: 'Projeto A',
  );
  const remote = RepositoryProjectInfo(
    projectName: 'repo-test', version: null, technologies: [],
  );
  const repository = GitHubRepository(
    id: 3, name: 'repo-test', fullName: 'owner/repo-test',
    isPrivate: false, isArchived: false, defaultBranch: 'main',
    updatedAt: null, htmlUrl: 'https://github.com/owner/repo-test',
  );

  test('diferencia versões ausentes e nome alternativo e não copia token', () {
    final check = ProjectSafetyCheck.compare(
        project: zip, repository: repository, repositoryInfo: remote);
    final report = UploadIdentificationDiagnosis.report(
      project: zip, remote: remote, repository: repository,
      branch: 'main', check: check,
    );
    expect(report, contains('Versão do ZIP: não identificada'));
    expect(report, contains('Versão no GitHub: não identificada'));
    expect(report, contains('AndroidManifest.xml'));
    expect(report, contains('owner/repo-test / main'));
    expect(report.toLowerCase(), isNot(contains('authorization:')));
  });

  test('consulta não disponível produz orientação de conexão distinta', () {
    final check = ProjectSafetyCheck.compare(
        project: zip, repository: repository, repositoryInfo: remote);
    final items = UploadIdentificationDiagnosis.guidance(
      project: zip,
      remote: const RepositoryProjectInfo(
        projectName: 'repo-test', version: null, technologies: [],
        metadataIssue: 'Falha ao consultar a API.',
      ),
      repository: repository,
      check: check,
    );
    expect(items.first, contains('Falha ao consultar a API'));
    expect(items.join(' '), isNot(contains('Se o repositório estiver vazio')));
  });

  test('confirmação conserva detalhes técnicos recolhidos e avisos de remoção', () {
    final source = File('lib/features/repositories/presentation/repository_detail_screen_actions.dart')
        .readAsStringSync();
    expect(source, contains('upload_technical_details'));
    expect(source, contains('_UploadSyncSummary('));
    expect(source, contains('syncPreview.deletedCount > 0'));
    expect(source, contains('Copiar diagnóstico'));
    expect(source, contains('final mustBlock = check.blocked || syncPreview == null'));
    expect(source, contains('Envio bloqueado'));
    expect(source, contains('_confirmRemovalWithRepositoryName('));
    expect(source, isNot(contains('Forçar envio para este repositório?')));
  });
}
