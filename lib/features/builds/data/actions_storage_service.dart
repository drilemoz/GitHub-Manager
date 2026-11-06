import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/network/github_api_client.dart';
import 'package:github_manager/features/builds/data/artifact_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';

/// Uso faturável (ex.: GB-hours), não o espaço livre em tempo real.
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

/// Separa resposta ao DELETE da confirmação de ausência na listagem.
/// "acceptedIds" não prova liberação imediata da cota; "absentIds" significa
/// apenas que esses IDs não foram vistos na consulta completa posterior.
class ArtifactDeletionReport {
  const ArtifactDeletionReport({
    required this.requestedIds,
    required this.acceptedIds,
    required this.alreadyAbsentIds,
    required this.requestFailedIds,
    required this.absentIds,
    required this.remainingIds,
    required this.verified,
  });

  final Set<int> requestedIds;
  final Set<int> acceptedIds;
  final Set<int> alreadyAbsentIds;
  final Set<int> requestFailedIds;
  final Set<int> absentIds;
  final Set<int> remainingIds;
  final bool verified;

  /// Compatibilidade com consumidores anteriores: removidos são apenas IDs
  /// cuja solicitação foi aceita E cuja ausência foi confirmada.
  Set<int> get deletedIds => acceptedIds.intersection(absentIds);
  Set<int> get failedIds => verified
      ? requestFailedIds.intersection(remainingIds)
      : requestFailedIds;
  bool get hasUnresolved => !verified || remainingIds.isNotEmpty || failedIds.isNotEmpty;
}

class ActionsStorageService {
  const ActionsStorageService(this._client, this._artifacts);
  final GitHubApiClient _client;
  final ArtifactService _artifacts;

  /// Metadados de apenas um repositório (não inclui caches nem Releases).
  Future<List<ActionArtifact>> list(String repository) =>
      _artifacts.listArtifacts(repository);

  /// API em preview; falhas não impedem a limpeza de artifacts.
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

  /// A consulta pode demorar a refletir uma exclusão recém-aceita pelo GitHub.
  /// Uma segunda consulta é feita somente quando ainda aparecem itens cujo
  /// DELETE retornou sucesso, evitando loops agressivos e falsa confirmação.
  Future<ArtifactDeletionReport> deleteSelected({
    required String repository,
    required Iterable<int> artifactIds,
    void Function(int done, int total)? onProgress,
  }) async {
    final selected = artifactIds.where((id) => id > 0).toSet();
    final accepted = <int>{};
    final alreadyAbsent = <int>{};
    final failed = <int>{};
    var done = 0;
    for (final id in selected) {
      try {
        await _artifacts.deleteArtifact(
          repositoryFullName: repository,
          artifactId: id,
        );
        accepted.add(id);
      } catch (error) {
        if (error is AppException && error.httpStatus == 404) {
          alreadyAbsent.add(id);
        } else {
          failed.add(id);
        }
      }
      onProgress?.call(++done, selected.length);
    }

    Set<int> remaining = <int>{};
    var verified = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
      try {
        remaining = (await _artifacts.listArtifacts(repository))
            .map((artifact) => artifact.id)
            .toSet()
            .intersection(selected);
        verified = true;
      } catch (_) {
        // Uma falha de leitura NÃO desfaz a resposta ao DELETE e NÃO permite
        // inferir ausência. A interface exibe a confirmação como pendente.
        verified = false;
        break;
      }
      if (remaining.intersection(accepted).isEmpty) break;
    }
    return ArtifactDeletionReport(
      requestedIds: Set<int>.unmodifiable(selected),
      acceptedIds: Set<int>.unmodifiable(accepted),
      alreadyAbsentIds: Set<int>.unmodifiable(alreadyAbsent),
      requestFailedIds: Set<int>.unmodifiable(failed),
      absentIds: Set<int>.unmodifiable(
        verified ? selected.difference(remaining) : <int>{},
      ),
      remainingIds: Set<int>.unmodifiable(verified ? remaining : <int>{}),
      verified: verified,
    );
  }
}
