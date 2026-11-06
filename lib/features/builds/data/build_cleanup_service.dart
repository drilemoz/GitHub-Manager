import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/features/builds/data/artifact_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';


enum BuildCleanupStage {
  preparing,
  inspectingArtifacts,
  inspectingReleaseApks,
  deletingRun,
  cleaningArtifacts,
  cleaningReleaseApks,
  completed,
}

class BuildCleanupProgress {
  const BuildCleanupProgress({
    required this.current,
    required this.total,
    required this.completed,
    required this.runId,
    required this.stage,
    required this.progress,
  });

  final int current;
  final int total;
  final int completed;
  final int runId;
  final BuildCleanupStage stage;
  final double progress;

  int get percent => (progress.clamp(0, 1) * 100).round();
}

class BuildCleanupResult {
  const BuildCleanupResult({
    required this.runId,
    required this.artifactsRemoved,
    required this.releaseApksRemoved,
    required this.warnings,
  });

  final int runId;
  final int artifactsRemoved;
  final int releaseApksRemoved;
  final List<String> warnings;

  int get relatedFilesRemoved => artifactsRemoved + releaseApksRemoved;
  bool get hasWarnings => warnings.isNotEmpty;
}

class BuildBulkCleanupResult {
  const BuildBulkCleanupResult({
    required this.deletedRunIds,
    required this.failedRunIds,
    required this.failureMessages,
    required this.artifactsRemoved,
    required this.releaseApksRemoved,
    required this.warnings,
  });

  final List<int> deletedRunIds;
  final List<int> failedRunIds;
  final Map<int, String> failureMessages;
  final int artifactsRemoved;
  final int releaseApksRemoved;
  final List<String> warnings;

  int get deletedCount => deletedRunIds.length;
  int get failedCount => failedRunIds.length;
  int get relatedFilesRemoved => artifactsRemoved + releaseApksRemoved;
  bool get hasFailures => failedRunIds.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Coordena a exclusão de uma build e das saídas que pertencem a ela.
///
/// O GitHub documenta que excluir um workflow run remove os artifacts ligados
/// à execução. Mesmo assim, o serviço verifica a lista depois da exclusão e
/// remove explicitamente qualquer artifact que ainda apareça. Releases são
/// independentes do workflow run: mesmo SHA não identifica qual execução
/// publicou um asset. Nunca apaga Releases automaticamente.
class BuildCleanupService {
  BuildCleanupService(this._client, this._artifacts);

  final GitHubApiClient _client;
  final ArtifactService _artifacts;

  Future<BuildCleanupResult> deleteBuild({
    required String repositoryFullName,
    required RepositoryWorkflowRun run,
    void Function(BuildCleanupStage stage)? onStage,
  }) async {
    final warnings = <String>[];
    List<ActionArtifact> linkedArtifacts = const <ActionArtifact>[];

    // Descobrimos os vínculos antes de apagar a execução, pois o endpoint
    // específico do run deixa de existir após a exclusão.
    onStage?.call(BuildCleanupStage.inspectingArtifacts);
    try {
      linkedArtifacts = await _artifacts.listArtifactsForRun(
        repositoryFullName: repositoryFullName,
        runId: run.id,
      );
    } catch (error) {
      warnings.add(
        'Não foi possível conferir previamente os artifacts da build: ${_message(error)}',
      );
    }

    // A associação por commit/versão pode ser compartilhada por mais de uma
    // execução. Não usamos essa heurística em nenhuma ação destrutiva.
    onStage?.call(BuildCleanupStage.inspectingReleaseApks);

    // Primeiro removemos a execução. Se isso falhar, nenhuma Release é tocada.
    onStage?.call(BuildCleanupStage.deletingRun);
    await _client.delete<void>(
      '/repos/$repositoryFullName/actions/runs/${run.id}',
    );

    final knownArtifactIds = linkedArtifacts.map((item) => item.id).toSet();
    final unresolvedArtifactIds = <int>{};
    var extraArtifactsRemoved = 0;
    var verified = false;

    // O GitHub deve remover os artifacts junto com o run. Fazemos uma
    // verificação adicional na coleção do repositório para cobrir atraso de
    // consistência ou comportamento inesperado da API.
    onStage?.call(BuildCleanupStage.cleaningArtifacts);
    try {
      final remaining = (await _artifacts.listArtifacts(repositoryFullName))
          .where((artifact) => artifact.workflowRunId == run.id)
          .toList(growable: false);
      for (final artifact in remaining) {
        try {
          await _artifacts.deleteArtifact(
            repositoryFullName: repositoryFullName,
            artifactId: artifact.id,
          );
          if (!knownArtifactIds.contains(artifact.id)) {
            extraArtifactsRemoved++;
          }
        } catch (error) {
          if (!_isNotFound(error)) {
            unresolvedArtifactIds.add(artifact.id);
            warnings.add(
              'O artifact ${artifact.name} ainda aparece no GitHub e não pôde ser removido: ${_message(error)}',
            );
          }
        }
      }
      // Só contabiliza artifacts como confirmados quando a consulta final
      // mostra que não há mais IDs associados ao run. A resposta 204 do
      // DELETE do run, isoladamente, não prova a limpeza da coleção.
      final afterCleanup = remaining.isEmpty
          ? remaining
          : (await _artifacts.listArtifacts(repositoryFullName))
              .where((artifact) => artifact.workflowRunId == run.id)
              .toList(growable: false);
      if (afterCleanup.isNotEmpty) {
        warnings.add(
          '${afterCleanup.length} artifact(s) ainda aparecem na API após a limpeza. Confira novamente antes de considerar o espaço liberado.',
        );
      }
      verified = afterCleanup.isEmpty && unresolvedArtifactIds.isEmpty;
    } catch (error) {
      warnings.add(
        'A build foi excluída, mas não foi possível confirmar a limpeza dos artifacts: ${_message(error)}',
      );
    }

    final removedArtifacts = verified
        ? knownArtifactIds.length + extraArtifactsRemoved
        : 0;

    // Releases continuam disponíveis e podem ser gerenciadas explicitamente
    // na tela de APKs/Releases do repositório.
    onStage?.call(BuildCleanupStage.cleaningReleaseApks);

    return BuildCleanupResult(
      runId: run.id,
      artifactsRemoved: removedArtifacts,
      releaseApksRemoved: 0,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  Future<BuildBulkCleanupResult> deleteBuilds({
    required String repositoryFullName,
    required Iterable<RepositoryWorkflowRun> runs,
    void Function(BuildCleanupProgress progress)? onProgress,
  }) async {
    final deletedIds = <int>[];
    final failedIds = <int>[];
    final failures = <int, String>{};
    final warnings = <String>[];
    var artifactsRemoved = 0;
    var releaseApksRemoved = 0;

    final uniqueRuns = <int, RepositoryWorkflowRun>{
      for (final run in runs) run.id: run,
    }.values.toList(growable: false);
    final total = uniqueRuns.length;

    const stageFraction = <BuildCleanupStage, double>{
      BuildCleanupStage.preparing: 0.0,
      BuildCleanupStage.inspectingArtifacts: 0.08,
      BuildCleanupStage.inspectingReleaseApks: 0.22,
      BuildCleanupStage.deletingRun: 0.42,
      BuildCleanupStage.cleaningArtifacts: 0.68,
      BuildCleanupStage.cleaningReleaseApks: 0.86,
      BuildCleanupStage.completed: 1.0,
    };

    void emit({
      required int index,
      required RepositoryWorkflowRun run,
      required BuildCleanupStage stage,
    }) {
      if (total == 0) return;
      final completedBefore = index;
      final currentFraction = stageFraction[stage] ?? 0;
      final overall = (completedBefore + currentFraction) / total;
      onProgress?.call(
        BuildCleanupProgress(
          current: index + 1,
          total: total,
          completed: stage == BuildCleanupStage.completed
              ? index + 1
              : index,
          runId: run.id,
          stage: stage,
          progress: overall.clamp(0.0, 1.0).toDouble(),
        ),
      );
    }

    for (var index = 0; index < uniqueRuns.length; index++) {
      final run = uniqueRuns[index];
      emit(index: index, run: run, stage: BuildCleanupStage.preparing);
      try {
        final result = await deleteBuild(
          repositoryFullName: repositoryFullName,
          run: run,
          onStage: (stage) => emit(index: index, run: run, stage: stage),
        );
        deletedIds.add(run.id);
        artifactsRemoved += result.artifactsRemoved;
        releaseApksRemoved += result.releaseApksRemoved;
        warnings.addAll(result.warnings);
      } catch (error) {
        failedIds.add(run.id);
        failures[run.id] = _message(error);
      } finally {
        emit(index: index, run: run, stage: BuildCleanupStage.completed);
      }
    }

    return BuildBulkCleanupResult(
      deletedRunIds: List<int>.unmodifiable(deletedIds),
      failedRunIds: List<int>.unmodifiable(failedIds),
      failureMessages: Map<int, String>.unmodifiable(failures),
      artifactsRemoved: artifactsRemoved,
      releaseApksRemoved: releaseApksRemoved,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static bool _isNotFound(Object error) =>
      error is AppException && error.httpStatus == 404;

  static String _message(Object error) =>
      error is AppException ? error.message : 'Não foi possível concluir a limpeza.';
}
