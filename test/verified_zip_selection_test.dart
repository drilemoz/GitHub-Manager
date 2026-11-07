import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';

void main() {
  test('two valid ZIPs of equal size have different SHA-256 and are not interchangeable', () async {
    final dir = await Directory.systemTemp.createTemp('verified-zip-');
    addTearDown(() => dir.delete(recursive: true));
    final first = Archive()..addFile(ArchiveFile('Projeto/a.txt', 4, 'AAAA'.codeUnits));
    final second = Archive()..addFile(ArchiveFile('Projeto/a.txt', 4, 'BBBB'.codeUnits));
    final file = File('${dir.path}/projeto.zip');
    await file.writeAsBytes(ZipEncoder().encode(first));
    final preview = await LocalProjectService().analyzeZip(file.path);
    final secondFile = File('${dir.path}/outro.zip');
    await secondFile.writeAsBytes(ZipEncoder().encode(second));
    expect(await secondFile.length(), preview.archiveBytes);
    expect(await LocalProjectService.sha256OfFile(secondFile), isNot(preview.sha256));
    await file.writeAsBytes(await secondFile.readAsBytes());
    await expectLater(
      LocalProjectService.verifyFingerprint(preview),
      throwsA(isA<InvalidZipException>()),
    );
  });

  test('analyzed immutable ZIP matches recorded fingerprint', () async {
    final dir = await Directory.systemTemp.createTemp('verified-zip-');
    addTearDown(() => dir.delete(recursive: true));
    final archive = Archive()
      ..addFile(ArchiveFile('Meu-Site/index.php', 6, '<?php '.codeUnits));
    final zip = File('${dir.path}/Meu-Site-v1.0.66.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    final preview = await LocalProjectService().analyzeZip(zip.path);
    expect(preview.name, 'Meu-Site-v1.0.66.zip');
    expect(preview.sha256, hasLength(64));
    await LocalProjectService.verifyFingerprint(preview);
  });
}
