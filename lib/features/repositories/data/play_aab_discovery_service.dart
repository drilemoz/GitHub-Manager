import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/features/builds/data/artifact_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/repositories/domain/play_aab_discovery.dart';

class PlayAabDiscoveryService {
  const PlayAabDiscoveryService(this.artifacts, this.client);

  final ArtifactService artifacts;
  final GitHubApiClient client;

  Future<PlayAabDiscoveryResult> search(String repositoryFullName) async {
    List<ReleaseAsset> releases = const [];
    List<ActionArtifact> actions = const [];
    var releasesChecked = false;
    var artifactsChecked = false;
    final warnings = <String>[];

    // Consultas independentes: falha de um endpoint não esconde os resultados
    // do outro. Não afirmar ausência total se alguma consulta falhar.
    Future<void> loadReleases() async {
      try {
        releases = await artifacts.listReleaseAssets(repositoryFullName);
        releasesChecked = true;
      } catch (_) {
        warnings.add('Não foi possível consultar Releases.');
      }
    }

    Future<void> loadArtifacts() async {
      try {
        actions = await artifacts.listArtifacts(repositoryFullName);
        artifactsChecked = true;
      } catch (_) {
        warnings.add('Não foi possível consultar Artifacts.');
      }
    }

    await Future.wait<void>([loadReleases(), loadArtifacts()]);

    // Run concluída com sucesso tem prioridade, sem confundir a existência de
    // um artifact com sucesso comprovado. Limitar chamadas para não exceder API.
    final success = <int>{};
    final candidateRuns = actions
        .where(PlayAabSelection.likelyArtifactAab)
        .map((item) => item.workflowRunId)
        .whereType<int>()
        .toSet()
        .take(6);
    for (final runId in candidateRuns) {
      try {
        final response = await client.get<Map<String, dynamic>>(
          '/repos/$repositoryFullName/actions/runs/$runId',
        );
        if (response.data?['status'] == 'completed' &&
            response.data?['conclusion'] == 'success') {
          success.add(runId);
        }
      } catch (_) {
        // Sem comprovação, manter como candidato não verificado.
      }
    }
    return PlayAabDiscoveryResult(
      candidates: PlayAabSelection.select(
        releases: releases,
        artifacts: actions,
        successfulRunIds: success,
      ),
      releasesChecked: releasesChecked,
      artifactsChecked: artifactsChecked,
      warnings: warnings,
    );
  }
}
