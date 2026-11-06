import 'package:github_manager/features/builds/domain/action_artifact.dart';

/// Seleção prudente para limpeza manual. Não deduz o conteúdo interno dos ZIPs
/// nem exclui automaticamente nada. O usuário ainda revisa e confirma.
class StorageSelectionPolicy {
  const StorageSelectionPolicy._();

  /// Protege dois grupos: a execução mais recente com data conhecida e a
  /// execução do artifact mais recente cujo nome sugere APK. Isso evita
  /// selecionar o único instalador recente por engano quando a última build
  /// publicou apenas logs/metadados. Datas ou runs ausentes não são elegíveis
  /// à seleção automática; continuam disponíveis para seleção manual.
  static Set<int> selectOlderRunArtifacts(Iterable<ActionArtifact> artifacts) {
    final dated = artifacts.where((item) =>
        item.id > 0 && item.createdAt != null && item.workflowRunId != null)
        .toList()
      ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
    if (dated.length < 2) return <int>{};

    final newest = dated.first;
    ActionArtifact? newestLikelyApk;
    for (final artifact in dated) {
      if (artifact.likelyContainsApk && !artifact.expired) {
        newestLikelyApk = artifact;
        break;
      }
    }
    final protectedRuns = <int>{newest.workflowRunId!};
    if (newestLikelyApk != null) {
      protectedRuns.add(newestLikelyApk.workflowRunId!);
    }
    return dated.where((item) =>
        item.createdAt!.isBefore(newest.createdAt!) &&
        !protectedRuns.contains(item.workflowRunId))
        .map((item) => item.id)
        .toSet();
  }
}
