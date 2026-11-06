import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/features/builds/data/artifact_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';

/// Relatório de uso faturável; NÃO é a ocupação atual da cota de armazenamento.
class ActionsBillingItem {
  const ActionsBillingItem({
    required this.sku,
    required this.unit,
    required this.quantity,
  });

  final String sku;
  final String unit;
  final double quantity;
}

class ArtifactDeletionReport {
  const ArtifactDeletionReport({
    required this.deletedIds,
    required this.failedIds,
    required this.remainingIds,
    required this.verified,
  });

  final Set<int> deletedIds;
  final Set<int> failedIds;
  final Set<int> remainingIds;
  final bool verified;
  bool get hasUnresolved => !verified || remainingIds.isNotEmpty || failedIds.isNotEmpty;
}

class ActionsStorageService {
  const ActionsStorageService(this._client, this._artifacts);
  final GitHubApiClient _client;
  final ArtifactService _artifacts;

  /// Metadados dos artifacts armazenados em um único repositório (não caches,
  /// logs nem assets de Release). Não equivale ao medidor oficial da cota.
  Future<List<ActionArtifact>> list(String repository) =>
      _artifacts.listArtifacts(repository);

  /// A API de billing pode requerer PAT fine-grained com Plan: read e a
  /// plataforma de cobrança ampliada. Endpoint em preview; falhas não devem
  /// impedir a limpeza de artifacts.
  Future<List<ActionsBillingItem>> billingUsageThisMonth() async {
    final userResponse = await _client.get<Map<String, dynamic>>('/user');
    final username = userResponse.data?['login'];
    if (username is! String || username.isEmpty) {
      throw StateError('A API não retornou o login da conta.');
    }
    final now = DateTime.now();
    final usageResponse = await _client.get<Map<String, dynamic>>(
      '/users/${Uri.encodeComponent(username)}/settings/billing/usage/summary',
      queryParameters: {'year': now.year, 'month': now.month, 'product': 'Actions'},
    );
    final raw = usageResponse.data?['usageItems'];
    if (raw is! List) throw const FormatException('Relatório de consumo inválido.');
    return raw.whereType<Map>().map((item) {
      final values = Map<String, dynamic>.from(item);
      return ActionsBillingItem(
        sku: values['sku']?.toString() ?? 'Actions',
        unit: values['unitType']?.toString() ?? 'unidade não informada',
        quantity: (values['grossQuantity'] as num?)?.toDouble() ??
            (values['quantity'] as num?)?.toDouble() ?? 0,
      );
    }).where((item) => item.sku.isNotEmpty).toList(growable: false);
  }

  /// DELETE /actions/artifacts/{id} retorna 204 em caso de sucesso.
  /// Reconsulta após o lote e não afirma confirmação quando a API falha.
  Future<ArtifactDeletionReport> deleteSelected({
    required String repository,
    required Iterable<int> artifactIds,
    void Function(int done, int total)? onProgress,
  }) async {
    final selected = artifactIds.toSet();
    final deleted = <int>{};
    final failed = <int>{};
    var done = 0;
    for (final id in selected) {
      try {
        await _artifacts.deleteArtifact(repositoryFullName: repository, artifactId: id);
        deleted.add(id);
      } catch (_) {
        failed.add(id);
      }
      onProgress?.call(++done, selected.length);
    }
    try {
      final remaining = (await _artifacts.listArtifacts(repository))
          .map((artifact) => artifact.id).toSet().intersection(selected);
      return ArtifactDeletionReport(
        deletedIds: deleted.difference(remaining),
        failedIds: failed,
        remainingIds: remaining,
        verified: true,
      );
    } catch (_) {
      return ArtifactDeletionReport(
        deletedIds: deleted,
        failedIds: failed,
        remainingIds: const <int>{},
        verified: false,
      );
    }
  }
}
