import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/core/security/secure_storage_service.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';
import 'package:github_manager/features/projects/domain/project_safety_check.dart';
import 'package:github_manager/features/repositories/data/repository_project_info_service.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';

void main() {

  test('Termux Manager: STATUS.json confirma versão do projeto no ZIP', () async {
    final temp = await Directory.systemTemp.createTemp('gm-status-');
    addTearDown(() => temp.delete(recursive: true));

    final status = utf8.encode(jsonEncode(<String, dynamic>{
      'project': 'Termux Manager',
      'version': '0.1.0-alpha.5',
      'integration_build_number': 5,
      'app_name': 'Termux Manager',
      'application_id': 'com.termux',
      'confirmed_manager_manifest_version': '1.0.133',
      'confirmed_termux_app_version': '0.118.0',
      'build_apk_version_name_expected': '0.118.0+tm.5',
      'build_apk_version_code_expected': 118005,
    }));
    final readme = utf8.encode('# Termux Manager');
    final archive = Archive()
      ..addFile(ArchiveFile('STATUS.json', status.length, status))
      ..addFile(ArchiveFile('README.md', readme.length, readme));
    final zipped = ZipEncoder().encode(archive);
    final zip = File('${temp.path}/Termux-Manager-v0.1.0-alpha.5-Manager1.0.133.zip')
      ..writeAsBytesSync(zipped);

    final preview = await LocalProjectService().analyzeZip(zip.path);
    expect(preview.projectName, 'Termux Manager');
    expect(preview.version, '0.1.0-alpha.5');
    expect(preview.versionSource, 'STATUS.json');
    expect(preview.applicationId, 'com.termux');
    expect(preview.versionCode, isNull); // APK versionCode ≠ integração
    expect(preview.inferredVersion, isNull);
  });

  test('STATUS.json apenas dentro de subprojeto não suplanta a raiz', () async {
    final temp = await Directory.systemTemp.createTemp('gm-status-sub-');
    addTearDown(() => temp.delete(recursive: true));
    final pubspec = utf8.encode('name: principal\nversion: 2.3.4+234\n');
    final nested = utf8.encode('{"project":"Outro","version":"9.9.9"}');
    final archive = Archive()
      ..addFile(ArchiveFile('Projeto/pubspec.yaml', pubspec.length, pubspec))
      ..addFile(ArchiveFile('Projeto/example/STATUS.json', nested.length, nested));
    final zip = File('${temp.path}/Projeto.zip')
      ..writeAsBytesSync(ZipEncoder().encode(archive));

    final preview = await LocalProjectService().analyzeZip(zip.path);
    expect(preview.version, '2.3.4');
    expect(preview.versionSource, 'pubspec.yaml');
  });

  test('repositório com STATUS.json expõe versão de integração em resumo e detalhes', () async {
    final client = _FakeTermuxGitHubApiClient(statusOnly: true);
    final service = RepositoryProjectInfoService(client);
    const repo = GitHubRepository(
      id: 3,
      name: 'Termux-Manager',
      fullName: 'owner/TermuxManager',
      isPrivate: false,
      isArchived: false,
      defaultBranch: 'main',
      updatedAt: null,
      htmlUrl: 'https://github.com/owner/TermuxManager',
      language: 'Shell',
    );
    final summary = await service.loadSummary(repo, branch: 'develop');
    final info = await service.load(repo, branch: 'develop');
    expect(summary.projectName, 'Termux Manager');
    expect(summary.version, '0.1.0-alpha.5');
    expect(summary.versionSource, 'STATUS.json');
    expect(info.projectName, 'Termux Manager');
    expect(info.version, '0.1.0-alpha.5');
    expect(info.applicationId, 'com.termux');
    expect(info.versionSource, 'STATUS.json');
    expect(info.versionCode, isNull);
    expect(client.requestedRefs, everyElement('develop'));
    final fixtureZip = await _statusFixtureZip();
    addTearDown(() => File(fixtureZip).delete());
    final preview = await LocalProjectService().analyzeZip(fixtureZip);
    final safety = ProjectSafetyCheck.compare(
      project: preview,
      repository: repo,
      repositoryInfo: info,
    );
    expect(safety.versionComparison, ProjectVersionComparison.same);
    expect(safety.identitySource, 'applicationId');
  });

  test('Termux Manager lê versão do MANIFEST.json', () async {
    final temp = await Directory.systemTemp.createTemp('gm-termux-manifest-');
    addTearDown(() => temp.delete(recursive: true));

    final manifest = utf8.encode('''
{
  "name": "Termux Manager",
  "version": "1.0.84"
}
''');
    final manager = utf8.encode('#!/data/data/com.termux/files/usr/bin/bash\n');
    final archive = Archive()
      ..addFile(ArchiveFile('TermuxManager-v1.0.84/MANIFEST.json', manifest.length, manifest))
      ..addFile(ArchiveFile('TermuxManager-v1.0.84/manager.sh', manager.length, manager));
    final bytes = ZipEncoder().encode(archive);
    final zip = File('${temp.path}/TermuxManager-v1.0.84.zip')..writeAsBytesSync(bytes);

    final preview = await LocalProjectService().analyzeZip(zip.path);

    expect(preview.projectName, 'Termux Manager');
    expect(preview.projectType, 'Shell/Termux');
    expect(preview.version, '1.0.84');
    expect(preview.versionLabel, '1.0.84');
    expect(preview.inferredVersion, isNull);
  });

  test('Termux Manager usa VERSION do manager.sh quando não há manifesto', () async {
    final temp = await Directory.systemTemp.createTemp('gm-termux-shell-');
    addTearDown(() => temp.delete(recursive: true));

    final manager = utf8.encode('''
#!/data/data/com.termux/files/usr/bin/bash
TERMUX_MANAGER_VERSION="1.0.85"
echo ok
''');
    final archive = Archive()
      ..addFile(ArchiveFile('TermuxManager/manager.sh', manager.length, manager));
    final bytes = ZipEncoder().encode(archive);
    final zip = File('${temp.path}/TermuxManager.zip')..writeAsBytesSync(bytes);

    final preview = await LocalProjectService().analyzeZip(zip.path);

    expect(preview.version, '1.0.85');
    expect(preview.displayVersionLabel, '1.0.85 • manager.sh');
  });

  test('nome do ZIP vira apenas pista quando não há versão interna', () async {
    final temp = await Directory.systemTemp.createTemp('gm-termux-filename-');
    addTearDown(() => temp.delete(recursive: true));

    final manager = utf8.encode('#!/data/data/com.termux/files/usr/bin/bash\necho ok\n');
    final archive = Archive()
      ..addFile(ArchiveFile('TermuxManager/manager.sh', manager.length, manager));
    final bytes = ZipEncoder().encode(archive);
    final zip = File('${temp.path}/TermuxManager-v1.0.86.zip')..writeAsBytesSync(bytes);

    final preview = await LocalProjectService().analyzeZip(
      zip.path,
      displayName: 'TermuxManager-v1.0.86.zip',
    );

    expect(preview.version, isNull);
    expect(preview.inferredVersion, '1.0.86');
    expect(preview.displayVersionLabel, '1.0.86 • pelo nome do ZIP');
  });
  test('ZIP com subprojeto usa metadado da raiz efetiva', () async {
    final temp = await Directory.systemTemp.createTemp('gm-multi-project-');
    addTearDown(() => temp.delete(recursive: true));

    final rootPubspec = utf8.encode('name: principal\nversion: 2.0.82+200096\n');
    final examplePubspec = utf8.encode('name: example\nversion: 9.9.9+999\n');
    final mainDart = utf8.encode('void main(){}');
    final archive = Archive()
      ..addFile(ArchiveFile('Projeto/pubspec.yaml', rootPubspec.length, rootPubspec))
      ..addFile(ArchiveFile('Projeto/lib/main.dart', mainDart.length, mainDart))
      ..addFile(ArchiveFile('Projeto/example/pubspec.yaml', examplePubspec.length, examplePubspec));
    final bytes = ZipEncoder().encode(archive);
    final zip = File('${temp.path}/Projeto.zip')..writeAsBytesSync(bytes);

    final preview = await LocalProjectService().analyzeZip(zip.path);

    expect(preview.packageName, 'principal');
    expect(preview.version, '2.0.82');
    expect(preview.versionCode, 200096);
    expect(preview.versionSource, 'pubspec.yaml');
  });

  test('nome do ZIP preserva versão alpha completa', () async {
    final temp = await Directory.systemTemp.createTemp('gm-alpha-name-');
    addTearDown(() => temp.delete(recursive: true));

    final readme = utf8.encode('# projeto\n');
    final archive = Archive()
      ..addFile(ArchiveFile('Terras-Medias/README.md', readme.length, readme));
    final bytes = ZipEncoder().encode(archive);
    final zip = File('${temp.path}/Terras-Medias-v0.1.0-alpha.58-source.zip')
      ..writeAsBytesSync(bytes);

    final preview = await LocalProjectService().analyzeZip(
      zip.path,
      displayName: 'Terras-Medias-v0.1.0-alpha.58-source.zip',
    );

    expect(preview.inferredVersion, '0.1.0-alpha.58');
    expect(preview.displayVersionLabel, '0.1.0-alpha.58 • pelo nome do ZIP');
  });

  test('repositório Termux Manager lê versão do MANIFEST.json na branch escolhida', () async {
    final client = _FakeTermuxGitHubApiClient();
    final service = RepositoryProjectInfoService(client);
    const repository = GitHubRepository(
      id: 1,
      name: 'TermuxManager',
      fullName: 'owner/TermuxManager',
      isPrivate: false,
      isArchived: false,
      defaultBranch: 'main',
      updatedAt: null,
      htmlUrl: 'https://github.com/owner/TermuxManager',
      language: 'Shell',
    );

    final info = await service.load(repository, branch: 'develop');

    expect(info.projectName, 'Termux Manager');
    expect(info.version, '1.0.84');
    expect(client.requestedRefs, contains('develop'));
  });

}


class _FakeTermuxGitHubApiClient extends GitHubApiClient {
  _FakeTermuxGitHubApiClient({this.statusOnly = false}) : super(SecureStorageService());

  final bool statusOnly;

  final List<String> requestedRefs = <String>[];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) async {
    final ref = queryParameters?['ref'];
    if (ref is String) requestedRefs.add(ref);

    dynamic data;
    if (path == '/repos/owner/TermuxManager/contents') {
      data = <dynamic>[
        <String, dynamic>{
          'name': statusOnly ? 'STATUS.json' : 'MANIFEST.json',
          'path': statusOnly ? 'STATUS.json' : 'MANIFEST.json',
          'type': 'file',
        },
        <String, dynamic>{
          'name': 'manager.sh',
          'path': 'manager.sh',
          'type': 'file',
        },
      ];
    } else if (path == '/repos/owner/TermuxManager/contents/STATUS.json' && statusOnly) {
      final status = jsonEncode(<String, dynamic>{
        'project': 'Termux Manager',
        'version': '0.1.0-alpha.5',
        'app_name': 'Termux Manager',
        'application_id': 'com.termux',
        'confirmed_manager_manifest_version': '1.0.133',
        'confirmed_termux_app_version': '0.118.0',
        'build_apk_version_name_expected': '0.118.0+tm.5',
        'build_apk_version_code_expected': 118005,
      });
      data = <String, dynamic>{
        'encoding': 'base64',
        'content': base64.encode(utf8.encode(status)),
      };
    } else if (path == '/repos/owner/TermuxManager/contents/MANIFEST.json') {
      final manifest = jsonEncode(<String, dynamic>{
        'name': 'Termux Manager',
        'version': '1.0.84',
      });
      data = <String, dynamic>{
        'encoding': 'base64',
        'content': base64.encode(utf8.encode(manifest)),
      };
    } else if (path == '/repos/owner/TermuxManager/languages') {
      data = <String, dynamic>{'Shell': 1000};
    } else {
      throw StateError('Unexpected path: $path');
    }

    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: data as T,
      statusCode: 200,
    );
  }
}

Future<String> _statusFixtureZip() async {
  final path = '${Directory.systemTemp.path}/gm-status-contract-${DateTime.now().microsecondsSinceEpoch}.zip';
  final status = utf8.encode(jsonEncode({
    'project': 'Termux Manager',
    'version': '0.1.0-alpha.5',
    'app_name': 'Termux Manager',
    'application_id': 'com.termux',
  }));
  final archive = Archive()
    ..addFile(ArchiveFile('STATUS.json', status.length, status));
  await File(path).writeAsBytes(ZipEncoder().encode(archive));
  return path;
}
