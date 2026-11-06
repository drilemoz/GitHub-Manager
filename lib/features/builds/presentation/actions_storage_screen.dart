import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/features/builds/data/actions_storage_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/storage_selection_policy.dart';
import 'package:github_manager/features/builds/presentation/build_providers.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';
import 'package:go_router/go_router.dart';

enum _ArtifactFilter { all, possibleApk, expired, olderThanWeek }
enum _ArtifactOrder { newest, oldest, largest }

/// Limpeza seletiva do armazenamento de Artifacts, sem afetar Releases e fontes.
/// Uma listagem por vez: não faz centenas de chamadas ao abrir a tela.
class ActionsStorageScreen extends ConsumerStatefulWidget {
  const ActionsStorageScreen({super.key, this.initialRepository});

  final String? initialRepository;

  @override
  ConsumerState<ActionsStorageScreen> createState() => _ActionsStorageScreenState();
}

class _ActionsStorageScreenState extends ConsumerState<ActionsStorageScreen> {
  List<GitHubRepository> _repositories = const [];
  List<ActionArtifact> _artifacts = const [];
  final Set<int> _selected = <int>{};
  String? _repository;
  String? _error;
  String? _billingError;
  List<ActionsBillingItem>? _billing;
  bool _billingLoading = false;
  _ArtifactFilter _filter = _ArtifactFilter.all;
  _ArtifactOrder _order = _ArtifactOrder.newest;
  bool _loadingRepos = true;
  bool _loadingArtifacts = false;
  bool _deleting = false;
  int _deleted = 0;
  int _totalToDelete = 0;
  int _generation = 0;
  int _displayLimit = 80;
  String? _report;

  @override
  void initState() {
    super.initState();
    _loadRepositories();
  }

  Future<void> _loadRepositories() async {
    try {
      final repos = await ref.read(repositoryServiceProvider).listRepositories();
      if (!mounted) return;
      repos.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
      setState(() {
        _repositories = repos;
        _loadingRepos = false;
        _error = null;
      });
      if (repos.isNotEmpty) {
        final preferred = widget.initialRepository;
        final initial = repos.any((r) => r.fullName == preferred)
            ? preferred!
            : repos.first.fullName;
        _chooseRepository(initial);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRepos = false;
        _error = 'Não foi possível listar os repositórios: $error';
      });
    }
  }

  Future<void> _loadBilling() async {
    if (_billingLoading) return;
    setState(() {
      _billingLoading = true;
      _billingError = null;
    });
    try {
      final items = await ref.read(actionsStorageServiceProvider).billingUsageThisMonth();
      if (mounted) setState(() => _billing = items);
    } catch (_) {
      if (mounted) {
        setState(() => _billingError =
            'Relatório de cobrança indisponível. Confira a permissão Plan: read ou consulte o GitHub.');
      }
    } finally {
      if (mounted) setState(() => _billingLoading = false);
    }
  }

  List<ActionArtifact> _visibleArtifacts() {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final result = _artifacts.where((item) {
      switch (_filter) {
        case _ArtifactFilter.all:
          return true;
        case _ArtifactFilter.possibleApk:
          return item.likelyContainsApk;
        case _ArtifactFilter.expired:
          return item.expired;
        case _ArtifactFilter.olderThanWeek:
          return item.createdAt != null && item.createdAt!.isBefore(cutoff);
      }
    }).toList(growable: true);
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    result.sort((a, b) {
      switch (_order) {
        case _ArtifactOrder.newest:
          return (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch);
        case _ArtifactOrder.oldest:
          return (a.createdAt ?? epoch).compareTo(b.createdAt ?? epoch);
        case _ArtifactOrder.largest:
          return b.sizeBytes.compareTo(a.sizeBytes);
      }
    });
    return result;
  }

  Set<int> _olderArtifactIds() =>
      StorageSelectionPolicy.selectOlderRunArtifacts(_artifacts);

  void _chooseRepository(String? name) {
    if (name == null || _deleting) return;
    setState(() {
      _repository = name;
      _artifacts = const [];
      _selected.clear();
      _displayLimit = 80;
      _report = null;
      _error = null;
    });
    _loadArtifacts();
  }

  Future<void> _loadArtifacts() async {
    final name = _repository;
    if (name == null || _deleting) return;
    final generation = ++_generation;
    setState(() {
      _loadingArtifacts = true;
      _error = null;
    });
    try {
      final artifacts = await ref.read(actionsStorageServiceProvider).list(name);
      if (!mounted || generation != _generation) return;
      setState(() {
        _artifacts = artifacts;
        _selected.removeWhere((id) => !artifacts.any((a) => a.id == id));
        _loadingArtifacts = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = 'Não foi possível consultar os artifacts: $error';
        _loadingArtifacts = false;
      });
    }
  }

  Future<void> _deleteSelected() async {
    final repo = _repository;
    if (repo == null || _selected.isEmpty || _deleting) return;
    final total = _selected.length;
    final bytes = _artifacts.where((item) => _selected.contains(item.id))
        .fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Excluir $total artifact(s)?'),
        content: Text(
          'Repositório: $repo\n'
          'Arquivos selecionados: ${_bytes(bytes)}\n\n'
          'O GitHub apagará permanentemente os artifacts selecionados. '
          'Se um ZIP contiver APK ou AAB, esse arquivo também será perdido.\n\n'
          'As execuções, o código-fonte e os APKs publicados em Releases NÃO serão excluídos. '
          'Não é possível desfazer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Excluir artifacts'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final ids = _selected.toSet();
    setState(() {
      _deleting = true;
      _deleted = 0;
      _totalToDelete = total;
      _report = null;
    });
    try {
      final result = await ref.read(actionsStorageServiceProvider).deleteSelected(
        repository: repo,
        artifactIds: ids,
        onProgress: (done, count) {
          if (mounted) setState(() => _deleted = done);
        },
      );
      ref.invalidate(repositoryArtifactsProvider(repo));
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(result.remainingIds);
        _report = result.verified
            ? 'Ausência confirmada para ${result.absentIds.length} de ${result.requestedIds.length} IDs. '
                'Solicitações aceitas: ${result.acceptedIds.length}; já ausentes (HTTP 404): '
                '${result.alreadyAbsentIds.length}; falhas de solicitação: '
                '${result.requestFailedIds.length}; ainda visíveis: ${result.remainingIds.length}. '
                'Os ainda visíveis continuam selecionados para uma nova tentativa. '
                'A cota oficial pode levar algum tempo para atualizar.'
            : '${result.acceptedIds.length} solicitação(ões) aceita(s), '
                '${result.alreadyAbsentIds.length} ID(s) já ausente(s) e '
                '${result.requestFailedIds.length} falha(s). '
                'A verificação posterior falhou: não é possível afirmar o que já sumiu.';
      });
    } catch (error) {
      if (mounted) setState(() => _report = 'Falha na limpeza: $error');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
    if (mounted) await _loadArtifacts();
  }

  static String _bytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _artifacts.fold<int>(0, (sum, a) => sum + a.sizeBytes);
    final visibleArtifacts = _visibleArtifacts();
    final displayedArtifacts = visibleArtifacts.take(_displayLimit).toList(growable: false);
    final selectedBytes = _artifacts.where((a) => _selected.contains(a.id))
        .fold<int>(0, (sum, a) => sum + a.sizeBytes);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Armazenamento Actions'),
        actions: [
          IconButton(
            onPressed: _deleting || _loadingArtifacts ? null : _loadArtifacts,
            tooltip: 'Atualizar artifacts',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Exclusão de builds e APKs', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 8),
                const Text('Excluir uma execução concluída em Builds apaga a execução, os logs e seus artifacts. Se um artifact ZIP contém APK ou AAB, esse arquivo também deixa de estar disponível ali. APKs de Releases e código-fonte permanecem.'),
                const SizedBox(height: 8),
                const Text('Aqui você pode excluir somente artifacts e conservar as execuções. O nome do artifact não confirma quais arquivos estão dentro do ZIP.'),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _repository == null || _deleting ? null : () => context.push('/repositories/$_repository/builds'),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('Abrir execuções do repositório'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cota e consumo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 7),
                const Text('A soma dos artifacts abaixo é apenas do repositório escolhido; NÃO é a ocupação total nem o saldo da cota GitHub Actions.'),
                const SizedBox(height: 7),
                if (_billingLoading) const LinearProgressIndicator(),
                if (_billingError != null) Text(_billingError!),
                if (_billing == null && !_billingLoading) const Text(
                  'Consulta opcional. O GitHub pode exigir permissão adicional; nenhum dado de cobrança é alterado.',
                ),
                TextButton.icon(
                  onPressed: _billingLoading ? null : _loadBilling,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Consultar relatório de uso'),
                ),
                if (_billing != null) ...[
                  const Text('Relatório de consumo faturável neste mês (não equivale ao espaço atual):', style: TextStyle(fontWeight: FontWeight.w600)),
                  if (_billing!.isEmpty) const Text('Nenhum item Actions retornado pela API.'),
                  for (final item in _billing!) Text('• ${item.sku}: ${item.quantity.toStringAsFixed(2)} ${item.unit}'),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => PlatformActions.openUri('https://github.com/settings/billing'),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Ver cota oficial e orçamento no GitHub'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (_loadingRepos) const Center(child: CircularProgressIndicator()),
          if (!_loadingRepos && _repositories.isEmpty)
            const Text('Nenhum repositório disponível para este token.'),
          if (_repositories.isNotEmpty) DropdownButtonFormField<String>(
            key: const ValueKey('storage-repository'),
            value: _repository,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Repositório', border: OutlineInputBorder()),
            items: _repositories.map((repo) => DropdownMenuItem(
              value: repo.fullName,
              child: Text(repo.fullName, overflow: TextOverflow.ellipsis),
            )).toList(growable: false),
            onChanged: _deleting ? null : _chooseRepository,
          ),
          const SizedBox(height: 12),
          if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
          if (_loadingArtifacts) const Padding(
            padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()),
          ),
          if (_repository != null && !_loadingArtifacts && _error == null) ...[
            Text('${_artifacts.length} artifact(s) • ${_bytes(bytes)} (tamanho informado pela API)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${_selected.length} selecionado(s) • ${_bytes(selectedBytes)}',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              SizedBox(width: 184, child: DropdownButtonFormField<_ArtifactFilter>(
                value: _filter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Filtrar', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: _ArtifactFilter.all, child: Text('Todos')),
                  DropdownMenuItem(value: _ArtifactFilter.possibleApk, child: Text('Possíveis APKs')),
                  DropdownMenuItem(value: _ArtifactFilter.expired, child: Text('Expirados')),
                  DropdownMenuItem(value: _ArtifactFilter.olderThanWeek, child: Text('Mais de 7 dias')),
                ],
                onChanged: _deleting ? null : (next) {
                  if (next != null) setState(() { _filter = next; _displayLimit = 80; });
                },
              )),
              SizedBox(width: 184, child: DropdownButtonFormField<_ArtifactOrder>(
                value: _order,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ordenar', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: _ArtifactOrder.newest, child: Text('Mais recentes')),
                  DropdownMenuItem(value: _ArtifactOrder.oldest, child: Text('Mais antigos')),
                  DropdownMenuItem(value: _ArtifactOrder.largest, child: Text('Maiores arquivos')),
                ],
                onChanged: _deleting ? null : (next) {
                  if (next != null) setState(() { _order = next; _displayLimit = 80; });
                },
              )),
            ]),
            const SizedBox(height: 6),
            Text('${displayedArtifacts.length} exibido(s) de ${visibleArtifacts.length} filtrado(s). A seleção persiste ao mudar o filtro.'),
            Wrap(spacing: 8, runSpacing: 2, children: [
              TextButton(
                onPressed: _deleting || displayedArtifacts.isEmpty ? null : () =>
                    setState(() => _selected.addAll(displayedArtifacts.map((a) => a.id))),
                child: const Text('Selecionar exibidos'),
              ),
              TextButton(
                onPressed: _deleting || _olderArtifactIds().isEmpty ? null : () =>
                    setState(() => _selected.addAll(_olderArtifactIds())),
                child: const Text('Selecionar anteriores'),
              ),
              TextButton(
                onPressed: _deleting || _selected.isEmpty ? null : () => setState(_selected.clear),
                child: const Text('Limpar seleção'),
              ),
            ]),
            const Text('“Selecionar anteriores” preserva a execução mais recente e o grupo do provável APK mais recente. Confira os arquivos antes de excluir.'),
            if (_artifacts.isEmpty) const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Nenhum artifact encontrado. Os APKs em Releases, se existirem, não aparecem nesta lista.'),
            ),
            for (final artifact in displayedArtifacts) Card(
              child: CheckboxListTile(
                key: ValueKey('artifact-${artifact.id}'),
                value: _selected.contains(artifact.id),
                onChanged: _deleting ? null : (checked) => setState(() {
                  if (checked == true) { _selected.add(artifact.id); }
                  else { _selected.remove(artifact.id); }
                }),
                title: Text(artifact.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${_bytes(artifact.sizeBytes)} • '
                    '${artifact.expired ? 'Expirado' : 'Disponível'} • '
                    'run #${artifact.workflowRunId?.toString() ?? "não informado"}'),
                secondary: Icon(artifact.likelyContainsApk ? Icons.android_rounded : Icons.archive_outlined),
                isThreeLine: false,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            if (visibleArtifacts.length > _displayLimit) TextButton.icon(
              onPressed: _deleting ? null : () => setState(() => _displayLimit += 80),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text('Exibir mais (${visibleArtifacts.length - _displayLimit} restantes)'),
            ),
          ],
          if (_report != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_report!)),
          if (_deleting) ...[
            LinearProgressIndicator(value: _totalToDelete == 0 ? null : _deleted / _totalToDelete),
            Text('Excluindo $_deleted de $_totalToDelete…'),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _deleting || _loadingArtifacts || _error != null || _selected.isEmpty ? null : _deleteSelected,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text('Excluir ${_selected.length} artifact(s) selecionado(s)'),
          ),
          const SizedBox(height: 8),
          const Text('Exclusão irreversível. Necessário Actions: write (ou repo em PAT clássico). Caches são separados. O tamanho listado não equivale ao espaço faturável recuperado.'),
        ],
      ),
    );
  }
}
