import 'package:flutter_test/flutter_test.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/repositories/domain/play_aab_discovery.dart';

ReleaseAsset release(String name, {int id = 1, DateTime? date}) => ReleaseAsset(
      id: id,
      name: name,
      sizeBytes: 1000,
      downloadUrl: 'https://example.invalid/release',
      tagName: 'v1.0.0',
      publishedAt: date,
      releaseId: 2,
      releaseName: 'Lançamento',
      targetCommitish: 'main',
    );

ActionArtifact artifact(String name, {
  int id = 1,
  int? runId,
  bool expired = false,
  DateTime? date,
}) => ActionArtifact(
      id: id,
      name: name,
      sizeBytes: 500,
      expired: expired,
      createdAt: date,
      workflowRunId: runId,
    );

void main() {
  test('AAB em Release é confirmado somente por extensão .aab', () {
    expect(PlayAabSelection.isReleaseAab(release('app-release.aab')), true);
    expect(PlayAabSelection.isReleaseAab(release('app-release.AAB')), true);
    expect(PlayAabSelection.isReleaseAab(release('app-release.apk')), false);
    expect(PlayAabSelection.isReleaseAab(release('bundle.zip')), false);
  });

  test('Artifact com nome sugestivo é candidato, não AAB confirmado', () {
    expect(PlayAabSelection.likelyArtifactAab(artifact('appbundle-release')), true);
    expect(PlayAabSelection.likelyArtifactAab(artifact('google-play-release')), true);
    expect(PlayAabSelection.likelyArtifactAab(artifact('app-release.aab')), true);
    expect(PlayAabSelection.likelyArtifactAab(artifact('app-release.apk')), false);
    expect(PlayAabSelection.likelyArtifactAab(artifact('build-logs')), false);
    expect(PlayAabSelection.likelyArtifactAab(artifact('playstore-release', expired: true)), false);
    expect(PlayAabSelection.likelyArtifactAab(artifact('output')), false);
  });

  test('Prioriza build confirmada e release, sem afirmar certeza em ZIP', () {
    final selected = PlayAabSelection.select(
      releases: [release('app-prod.aab', date: DateTime.utc(2026, 10, 1))],
      artifacts: [
        artifact('appbundle-release', id: 11, runId: 100,
            date: DateTime.utc(2026, 10, 3)),
        artifact('playstore-release', id: 12, runId: 101,
            date: DateTime.utc(2026, 10, 4)),
      ],
      successfulRunIds: {100},
    );
    expect(selected.length, 3);
    expect(selected.first.id, 11);
    expect(selected.first.successConfirmed, true);
    expect(selected.first.directlyConfirmed, false);
    expect(selected[1].origin, PlayAabOrigin.release);
    expect(selected.last.id, 12);
    expect(selected.last.confidenceLabel, contains('não verificado'));
  });

  test('Sem encontrar AAB não equivale a consulta completa', () {
    const partial = PlayAabDiscoveryResult(
      candidates: [], releasesChecked: false, artifactsChecked: true,
      warnings: ['Falha em Releases'],
    );
    expect(partial.complete, false);
    expect(partial.hasCandidates, false);
  });
}
