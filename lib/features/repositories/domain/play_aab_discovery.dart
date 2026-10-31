import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';

enum PlayAabOrigin { release, artifact }

/// A Release declara um arquivo .aab. Um Artifact apenas sugere seu conteúdo
/// pelo nome; somente a inspeção do ZIP baixado confirma o bundle.
class PlayAabCandidate {
  const PlayAabCandidate({
    required this.origin,
    required this.name,
    required this.id,
    required this.date,
    required this.sizeBytes,
    this.version,
    this.runId,
    this.successConfirmed = false,
  });

  final PlayAabOrigin origin;
  final String name;
  final int id;
  final DateTime? date;
  final int sizeBytes;
  final String? version;
  final int? runId;
  final bool successConfirmed;

  bool get directlyConfirmed => origin == PlayAabOrigin.release;
  String get sourceLabel => origin == PlayAabOrigin.release ? 'Release' : 'GitHub Actions';
  String get confidenceLabel => directlyConfirmed
      ? 'Arquivo .aab identificado'
      : successConfirmed
          ? 'Build bem-sucedida; conteúdo do ZIP ainda não verificado'
          : 'Possível AAB; conteúdo do ZIP ainda não verificado';
}

class PlayAabDiscoveryResult {
  const PlayAabDiscoveryResult({
    required this.candidates,
    required this.releasesChecked,
    required this.artifactsChecked,
    this.warnings = const [],
  });

  final List<PlayAabCandidate> candidates;
  final bool releasesChecked;
  final bool artifactsChecked;
  final List<String> warnings;
  bool get complete => releasesChecked && artifactsChecked;
  bool get hasCandidates => candidates.isNotEmpty;
}

abstract final class PlayAabSelection {
  static bool isReleaseAab(ReleaseAsset item) =>
      item.id > 0 && item.name.toLowerCase().endsWith('.aab');

  static bool likelyArtifactAab(ActionArtifact item) {
    if (item.expired || item.id <= 0) return false;
    final name = item.name.toLowerCase();
    if (RegExp(r'(^|[-_. ])(debug|test|symbols|mapping|logs?|apk)([-_. ]|$)')
        .hasMatch(name)) return false;
    return name.endsWith('.aab') ||
        RegExp(r'(^|[-_. ])(aab|appbundle|app-bundle|playstore|play-store|googleplay|google-play)([-_. ]|$)')
            .hasMatch(name) ||
        name.contains('bundle-release');
  }

  static List<PlayAabCandidate> select({
    required List<ReleaseAsset> releases,
    required List<ActionArtifact> artifacts,
    Set<int> successfulRunIds = const {},
  }) {
    final items = <PlayAabCandidate>[
      for (final asset in releases.where(isReleaseAab))
        PlayAabCandidate(
          origin: PlayAabOrigin.release,
          name: asset.name,
          id: asset.id,
          date: asset.publishedAt,
          sizeBytes: asset.sizeBytes,
          version: asset.tagName.isEmpty ? null : asset.tagName,
        ),
      for (final artifact in artifacts.where(likelyArtifactAab))
        PlayAabCandidate(
          origin: PlayAabOrigin.artifact,
          name: artifact.name,
          id: artifact.id,
          date: artifact.createdAt,
          sizeBytes: artifact.sizeBytes,
          runId: artifact.workflowRunId,
          successConfirmed: successfulRunIds.contains(artifact.workflowRunId),
        ),
    ];
    items.sort((a, b) {
      // Sucesso comprovado ou arquivo .aab direto têm precedência sobre
      // Artifacts apenas sugeridos pelo nome.
      final aConfident = a.directlyConfirmed || a.successConfirmed;
      final bConfident = b.directlyConfirmed || b.successConfirmed;
      if (aConfident != bConfident) return aConfident ? -1 : 1;
      final byDate = (b.date ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.date ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (byDate != 0) return byDate;
      return b.id.compareTo(a.id);
    });
    return items;
  }
}
