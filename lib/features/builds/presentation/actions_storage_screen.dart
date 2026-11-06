import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/features/builds/data/actions_storage_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/presentation/build_providers.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';
import 'package:go_router/go_router.dart';

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
  bool _loadingRepos = true;
  bool _loadingArtifacts = false;
  bool _deleting = false;
  int _deleted = 0;
  int _totalToDelete = 0;
  int _generation = 0;
  String? _report;

  @override
  void initState() {
    super.initState();
    _loadRepositories();
    _loadBilling();
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
    try {
      final items = await ref.read(actionsStorageServiceProvider).billingUsageThisMonth();
      if (mounted) setState(() => _billing = items);
    } catch (_) {
      if (mounted) {
        setState(() => _billingError =
            'Relatório de cobrança indisponível (API em preview; pode exigir Plan: read).');
      }
    }
  }

  void _chooseRepository(String? name) {
    if (name == null || _deleting) return;
    setState(() {
      _repository = name;
      _artifacts = const [];
      _selected.clear();
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
          'O GitHub apagará permanentemente estes ZIPs do Actions. '
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
        _selected.clear();
        _report = result.verified
            ? '${result.deletedIds.length} artifact(s) não aparecem mais na consulta. '
                '${result.remainingIds.length} ainda aparecem; ${result.failedIds.length} falha(s) na exclusão. '
                'A atualização da cota oficial pode demorar.'
            : '${result.deletedIds.length} exclusão(ões) aceita(s) pela API, '
                'mas não foi possível verificar a listagem depois. Confira antes de repetir.';
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
                const Text('O que realmente é excluído', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const SizedBox(height: 8),
                const Text('Excluir uma execução em Builds elimina a execução, seus logs e TODOS os artifacts vinculados (incluindo ZIPs com APKs). Não exclui APKs de Releases nem código-fonte.'),
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
                if (_billing == null && _billingError == null) const LinearProgressIndicator(),
                if (_billingError != null) Text(_billingError!),
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
            Text('${_artifacts.length} artifact(s) • ${_bytes(bytes)} no repositório',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${_selected.length} selecionado(s) • ${_bytes(selectedBytes)}',
                style: Theme.of(context).textTheme.bodyMedium),
            Row(children: [
              TextButton(
                onPressed: _deleting || _artifacts.isEmpty ? null : () => setState(() => _selected.addAll(_artifacts.map((a) => a.id))),
                child: const Text('Selecionar todos'),
              ),
              TextButton(
                onPressed: _deleting || _selected.isEmpty ? null : () => setState(_selected.clear),
                child: const Text('Limpar seleção'),
              ),
            ]),
            if (_artifacts.isEmpty) const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Nenhum artifact encontrado. Os APKs em Releases, se existirem, não aparecem nesta lista.'),
            ),
            for (final artifact in _artifacts) Card(
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
          ],
          if (_report != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_report!)),
          if (_deleting) ...[
            LinearProgressIndicator(value: _totalToDelete == 0 ? null : _deleted / _totalToDelete),
            Text('Excluindo $_deleted de $_totalToDelete…'),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _deleting || _loadingArtifacts || _selected.isEmpty ? null : _deleteSelected,
            icon: const Icon(Icons.delete_forever_outlined),
            label: Text('Excluir ${_selected.length} artifact(s) selecionado(s)'),
          ),
          const SizedBox(height: 8),
          const Text('Exclusão irreversível. Necessário Actions: write no token (ou escopo repo em PAT clássico). Caches têm cota separada.'),
        ],
      ),
    );
  }
}
