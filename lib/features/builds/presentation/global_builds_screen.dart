import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/core/widgets/app_main_navigation.dart';
import 'package:github_manager/core/widgets/centered_notice.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/apk_variant.dart';
import 'package:github_manager/features/builds/presentation/smart_apk_picker.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/builds/domain/global_build_entry.dart';
import 'package:github_manager/features/builds/presentation/global_build_diagnostics.dart';
import 'package:github_manager/features/builds/presentation/build_providers.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';
import 'package:github_manager/features/downloads/presentation/download_providers.dart';
import 'package:go_router/go_router.dart';

enum _GlobalBuildFilter { all, running, success, failure }
enum _BuildPeriod { all, sevenDays, thirtyDays, ninetyDays }

class GlobalBuildsScreen extends ConsumerStatefulWidget {
  const GlobalBuildsScreen({super.key});

  @override
  ConsumerState<GlobalBuildsScreen> createState() => _GlobalBuildsScreenState();
}

class _GlobalBuildsScreenState extends ConsumerState<GlobalBuildsScreen>
    with WidgetsBindingObserver {
  _GlobalBuildFilter _filter = _GlobalBuildFilter.all;
  _BuildPeriod _period = _BuildPeriod.all;
  bool _showHistory = false;
  bool _searchOpen = false;
  bool _filtersExpanded = false;
  final Set<int> _apkSearches = <int>{};
  String _query = '';
  String? _branch;
  String? _workflow;
  bool _refreshing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedulePoll();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedulePoll();
      _refresh();
    } else {
      _pollTimer?.cancel();
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (!mounted) return;
    final state = ref.read(globalBuildsProvider);
    final running = state.asData?.value.runningCount ?? 0;
    final seconds = running > 0 || state.isLoading ? 15 : 60;
    _pollTimer = Timer(Duration(seconds: seconds), () async {
      if (!mounted) return;
      await _refresh();
      if (mounted) _schedulePoll();
    });
  }

  Future<void> _refresh({bool forceFull = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final service = ref.read(globalBuildsServiceProvider);
      final before = ref.read(globalBuildsProvider).asData?.value;
      final after = await service.load(forceFull: forceFull);
      if (mounted && (forceFull || !identical(before, after))) {
        ref.invalidate(globalBuildsProvider);
      }
    } catch (_) {
      // Um erro temporário não apaga os dados previamente apresentados.
      if (forceFull && mounted) {
        showCenteredNotice(
          context,
          'Não foi possível atualizar agora. Dados anteriores preservados.',
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  List<GlobalRepositoryBuildGroup> _filtered(GlobalBuildsSnapshot snapshot) {
    final source = _showHistory && snapshot.historyEntries.isNotEmpty
        ? snapshot.historyEntries
        : snapshot.entries;
    final query = _query.trim().toLowerCase();
    final days = switch (_period) {
      _BuildPeriod.all => null,
      _BuildPeriod.sevenDays => 7,
      _BuildPeriod.thirtyDays => 30,
      _BuildPeriod.ninetyDays => 90,
    };
    final since = days == null ? null : DateTime.now().subtract(Duration(days: days));
    final filtered = source.where((entry) {
      final run = entry.run;
      if (_branch != null && entry.branch != _branch) return false;
      if (_workflow != null && run.name != _workflow) return false;
      if (since != null && (entry.date == null || entry.date!.isBefore(since))) {
        return false;
      }
      if (query.isNotEmpty && ![
        entry.repository.name,
        entry.repository.fullName,
        entry.branch,
        run.name,
        run.title,
        run.headSha,
        run.detectedVersion ?? '',
        run.runNumber.toString(),
      ].any((value) => value.toLowerCase().contains(query))) {
        return false;
      }
      return switch (_filter) {
        _GlobalBuildFilter.all => true,
        _GlobalBuildFilter.running => entry.isRunning,
        _GlobalBuildFilter.success => entry.isSuccess,
        _GlobalBuildFilter.failure => entry.isFailure,
      };
    }).toList(growable: false);
    return GlobalBuildsSnapshot.groupEntries(filtered);
  }

  void _showDiagnosis(GlobalBuildEntry entry, {BuildContext? sheetContext}) {
    showDialog<void>(
      context: sheetContext ?? context,
      builder: (dialogContext) => GlobalBuildDiagnosisDialog(
        entry: entry,
        onOpenDetails: () {
          Navigator.of(dialogContext).pop();
          _openRun(entry, sheetContext: sheetContext);
        },
      ),
    );
  }

  Widget _buildAdvancedFilters(GlobalBuildsSnapshot snapshot) {
    final runs = snapshot.historyEntries.isNotEmpty
        ? snapshot.historyEntries : snapshot.entries;
    final branches = runs.map((entry) => entry.branch).toSet().toList()..sort();
    final workflows = runs.map((entry) => entry.run.name).toSet().toList()..sort();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 142,
          child: DropdownButtonFormField<String>(
            key: const ValueKey('builds-branch-filter'),
            value: branches.contains(_branch) ? _branch : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Branch', isDense: true),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todas')),
              ...branches.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (value) => setState(() => _branch = value == '' ? null : value),
          ),
        ),
        SizedBox(
          width: 168,
          child: DropdownButtonFormField<String>(
            key: const ValueKey('builds-workflow-filter'),
            value: workflows.contains(_workflow) ? _workflow : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Workflow', isDense: true),
            items: [
              const DropdownMenuItem(value: '', child: Text('Todos')),
              ...workflows.map((name) => DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (value) => setState(() => _workflow = value == '' ? null : value),
          ),
        ),
        SizedBox(
          width: 138,
          child: DropdownButtonFormField<_BuildPeriod>(
            key: const ValueKey('builds-period-filter'),
            value: _period,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Período', isDense: true),
            items: const [
              DropdownMenuItem(value: _BuildPeriod.all, child: Text('Todos')),
              DropdownMenuItem(value: _BuildPeriod.sevenDays, child: Text('7 dias')),
              DropdownMenuItem(value: _BuildPeriod.thirtyDays, child: Text('30 dias')),
              DropdownMenuItem(value: _BuildPeriod.ninetyDays, child: Text('90 dias')),
            ],
            onChanged: (value) => setState(() => _period = value ?? _BuildPeriod.all),
          ),
        ),
      ],
    );
  }

  Future<void> _downloadLogs(GlobalBuildEntry entry) async {
    ref.read(downloadManagerProvider).startWorkflowLogs(
          repositoryFullName: entry.repository.fullName,
          runId: entry.run.id,
          runTitle: '${entry.run.name}-${entry.run.runNumber}',
        );
    if (mounted) {
      showCenteredNotice(
        context,
        'Download dos logs iniciado. Acompanhe pela Central de Downloads.',
      );
    }
  }

  Future<void> _downloadApk(GlobalBuildEntry entry) async {
    // Impede requisições duplicadas e apresenta resposta imediatamente.
    if (!_apkSearches.add(entry.run.id)) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final loadingRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 26, height: 26,
                child: CircularProgressIndicator(strokeWidth: 3)),
            SizedBox(width: 18),
            Expanded(child: Text('Buscando APKs em artifacts e Releases…')),
          ],
        ),
      ),
    );
    navigator.push(loadingRoute);
    void closeLoading() {
      if (loadingRoute.isActive) navigator.removeRoute(loadingRoute);
    }

    try {
      final artifactService = ref.read(artifactServiceProvider);
      // Inicia as duas consultas em paralelo: uma fonte falhando não oculta a outra.
      var failedSources = 0;
      final artifactsFuture = artifactService.listArtifactsForRun(
        repositoryFullName: entry.repository.fullName,
        runId: entry.run.id,
      ).catchError((Object _) {
        failedSources++;
        return <ActionArtifact>[];
      });
      final releasesFuture = artifactService.findReleaseApksForBuild(
        repositoryFullName: entry.repository.fullName,
        run: entry.run,
      ).catchError((Object _) {
        failedSources++;
        return <ReleaseAsset>[];
      });
      AndroidDeviceInfo? deviceInfo;
      try {
        deviceInfo = await PlatformActions.getAndroidDeviceInfo();
      } catch (_) {
        // ABI desconhecida: o usuário ainda pode escolher o APK manualmente.
      }

      List<ActionArtifact> artifacts = const [];
      List<ActionArtifact> allRunArtifacts = const [];
      List<ReleaseAsset> releases = const [];
      try {
        allRunArtifacts = await artifactsFuture;
        artifacts = allRunArtifacts
            .where((item) => !item.expired && item.likelyContainsApk)
            .toList(growable: false);
      } catch (_) {
        failedSources++;
      }
      try {
        releases = (await releasesFuture)
            .where((item) => item.isApk)
            .toList(growable: false);
      } catch (_) {
        failedSources++;
      }
      if (!mounted) return;
      final candidates = <_GlobalApkCandidate>[
        ...releases.map(_GlobalApkCandidate.fromRelease),
        ...artifacts.map(_GlobalApkCandidate.fromArtifact),
      ];
      // APKs de Release têm associação por commit, não por ID de execução.
      if (candidates.isEmpty) {
        closeLoading();
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Nenhum APK encontrado'),
            content: Text(failedSources == 2
                ? 'Não foi possível consultar artifacts nem Releases. Verifique a conexão e as permissões do GitHub e tente novamente.'
                : failedSources == 1
                    ? 'Uma fonte de APKs não respondeu e a outra não encontrou arquivos. Tente novamente ou consulte a Central de Downloads.'
                    : entry.run.isRunning
                        ? 'A build ainda está em execução. O APK poderá aparecer após a publicação.'
                        : 'Esta execução não possui artifacts APK disponíveis ou Releases associadas. O artifact pode ter expirado.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Entendi')),
            ],
          ),
        );
        return;
      }
      // Opcional e sob demanda: não aumenta a carga da lista global de Builds.
      final manifest = await artifactService.loadBuildManifest(
        repositoryFullName: entry.repository.fullName,
        runId: entry.run.id,
        commitSha: entry.run.headSha,
        knownArtifacts: allRunArtifacts,
      );
      closeLoading();
      if (!mounted) return;
      if (failedSources > 0) {
        showCenteredNotice(context, 'Uma fonte de APKs não respondeu; mostrando os arquivos disponíveis.');
      }
      final supportedAbis = deviceInfo?.supportedAbis ?? const <String>[];
      candidates.sort((left, right) {
        final leftRank = apkRecommendationRank(left.name, supportedAbis);
        final rightRank = apkRecommendationRank(right.name, supportedAbis);
        if (leftRank != rightRank) return leftRank.compareTo(rightRank);
        if (left.artifact != null && right.artifact == null) return -1;
        if (left.artifact == null && right.artifact != null) return 1;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

      final selected = await showSmartApkPicker<_GlobalApkCandidate>(
        context: context,
        project: entry.repository.name,
        runNumber: entry.run.runNumber,
        version: entry.run.detectedVersion,
        deviceInfo: deviceInfo,
        manifest: manifest,
        options: [
          for (final candidate in candidates)
            SmartApkOption(
              value: candidate,
              name: candidate.name,
              bytes: candidate.sizeBytes,
              source: candidate.originLabel(entry.run.runNumber),
              exactRun: candidate.artifact != null,
              declaredAbi: candidate.artifact == null ? null :
                ([...?(manifest?.apks)].where((apk) => apk.fileName == candidate.name)
                  .map((apk) => apk.abi).firstOrNull),
            ),
        ],
      );
      if (selected == null || !mounted) return;
      if (!await _confirmGlobalApkCompatibility(selected, deviceInfo)) return;
      if (selected.release != null &&
          !await _confirmReleaseAssociation(selected.release!)) return;
      if (mounted) _startGlobalApkDownload(entry, selected, deviceInfo);
    } catch (_) {
      closeLoading();
      if (mounted) {
        showCenteredNotice(context, 'Falha ao consultar APKs. Confira a conexão e tente novamente.');
      }
    } finally {
      closeLoading();
      _apkSearches.remove(entry.run.id);
    }
  }

  Future<bool> _confirmReleaseAssociation(ReleaseAsset asset) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('APK publicado em Release'),
            content: Text(
              'O arquivo ${asset.name} pertence à Release ${asset.tagName}. '
              'O vínculo foi encontrado pelo commit/versão, não pelo ID da '
              'execução. Outra build pode ter publicado este APK. Deseja baixá-lo?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Baixar Release'),
              ),
            ],
          ),
        ) ?? false;
  }

  Future<bool> _confirmGlobalApkCompatibility(
    _GlobalApkCandidate candidate,
    AndroidDeviceInfo? deviceInfo,
  ) async {
    if (deviceInfo == null ||
        apkNameIsCompatible(candidate.name, deviceInfo.supportedAbis)) {
      return true;
    }
    final variant = ApkVariantInfo.fromName(candidate.name);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('APK possivelmente incompatível'),
            content: Text(
              'Este APK é ${variant.label}, mas este aparelho usa ${deviceInfo.primaryAbi} como arquitetura principal e suporta ${deviceInfo.supportedAbis.join(', ')}. Ele provavelmente não poderá ser instalado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Baixar mesmo assim'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _startGlobalApkDownload(
    GlobalBuildEntry entry,
    _GlobalApkCandidate candidate,
    AndroidDeviceInfo? deviceInfo,
  ) {
    final manager = ref.read(downloadManagerProvider);
    final release = candidate.release;
    final artifact = candidate.artifact;
    if (release != null) {
      manager.startReleaseAsset(
        title: '${release.tagName} • ${release.name}',
        fileName: release.name,
        repositoryFullName: entry.repository.fullName,
        assetId: release.id,
        isApk: true,
      );
    } else if (artifact != null) {
      manager.startArtifactApk(
        repositoryFullName: entry.repository.fullName,
        artifact: artifact,
        preferredAbi: deviceInfo?.primaryAbi,
        supportedAbis: deviceInfo?.supportedAbis,
      );
    }
    showCenteredNotice(
      context,
      'Download de ${candidate.variant.label} iniciado. Acompanhe pela Central de Downloads.',
      kind: CenteredNoticeKind.success,
    );
  }

  void _openRun(GlobalBuildEntry entry, {BuildContext? sheetContext}) {
    if (sheetContext != null) {
      Navigator.of(sheetContext).pop();
    }
    context.push(
      '/repositories/${entry.repository.fullName}/builds?branch=${Uri.encodeQueryComponent(entry.branch)}&runId=${entry.run.id}',
    );
  }

  Future<void> _showRepositoryBuilds(GlobalRepositoryBuildGroup group) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.repository.name,
                        style: Theme.of(sheetContext)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${group.buildCount} execução(ões) nesta seleção • ${group.branch}',
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    itemCount: group.entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final entry = group.entries[index];
                      final previous = group.entries.skip(index + 1).where(
                        (item) => item.run.workflowId == entry.run.workflowId &&
                            item.run.id != entry.run.id,
                      );
                      return _RepositoryBuildRunCard(
                        entry: entry,
                        previous: _showHistory && previous.isNotEmpty
                            ? previous.first : null,
                        onDiagnose: () => _showDiagnosis(entry, sheetContext: sheetContext),
                        onOpen: () => _openRun(entry, sheetContext: sheetContext),
                        onDownloadLogs: () => _downloadLogs(entry),
                        onDownloadApk: () => _downloadApk(entry),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final builds = ref.watch(globalBuildsProvider);
    return Scaffold(
      bottomNavigationBar: const AppMainNavigation(selectedIndex: 1),
      appBar: AppBar(
        title: const Text('Builds'),
        actions: [
          IconButton(
            tooltip: 'Armazenamento e limpeza de APKs/artifacts',
            onPressed: () => context.push('/builds/storage'),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            tooltip: _searchOpen ? 'Fechar busca' : 'Buscar builds',
            icon: Icon(_searchOpen ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) _query = '';
            }),
          ),
          IconButton(
            tooltip: 'Atualizar todos os repositórios',
            onPressed: () => _refresh(forceFull: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(forceFull: true),
        child: builds.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Não foi possível reunir as builds agora.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(error.toString()),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _refresh(forceFull: true),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Tentar novamente'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          data: (snapshot) {
            final groups = _filtered(snapshot);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                _GlobalBuildSummary(snapshot: snapshot),
                if (_searchOpen) ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('builds-search'),
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: 'Limpar pesquisa',
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () => setState(() {
                          _query = '';
                          _searchOpen = false;
                        }),
                      ),
                      border: const OutlineInputBorder(),
                      hintText: 'Projeto, workflow, branch, versão ou SHA',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  ChoiceChip(
                    label: const Text('Último commit'),
                    selected: !_showHistory,
                    onSelected: (_) => setState(() => _showHistory = false),
                  ),
                  ChoiceChip(
                    key: const ValueKey('builds-history'),
                    label: const Text('Histórico recente'),
                    selected: _showHistory,
                    onSelected: (_) => setState(() => _showHistory = true),
                  ),
                ]),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('builds-advanced-toggle'),
                    onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
                    icon: Icon(_filtersExpanded ? Icons.filter_list_off_rounded : Icons.filter_list_rounded),
                    label: Text(_filtersExpanded ? 'Ocultar filtros' :
                        (_branch != null || _workflow != null || _period != _BuildPeriod.all)
                            ? 'Filtros avançados • ativos' : 'Filtros avançados'),
                  ),
                ),
                if (_filtersExpanded) ...[
                  _buildAdvancedFilters(snapshot),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(
                        label: 'Todos',
                        selected: _filter == _GlobalBuildFilter.all,
                        onSelected: () =>
                            setState(() => _filter = _GlobalBuildFilter.all),
                      ),
                      _FilterChip(
                        label: 'Executando',
                        selected: _filter == _GlobalBuildFilter.running,
                        onSelected: () =>
                            setState(() => _filter = _GlobalBuildFilter.running),
                      ),
                      _FilterChip(
                        label: 'Sucesso',
                        selected: _filter == _GlobalBuildFilter.success,
                        onSelected: () =>
                            setState(() => _filter = _GlobalBuildFilter.success),
                      ),
                      _FilterChip(
                        label: 'Falhou',
                        selected: _filter == _GlobalBuildFilter.failure,
                        onSelected: () =>
                            setState(() => _filter = _GlobalBuildFilter.failure),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (groups.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Nenhuma build corresponde aos filtros. Tente outro período, branch ou workflow.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...groups.map(
                    (group) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _GlobalRepositoryBuildCard(
                        group: group,
                        showHistory: _showHistory,
                        onTap: () => _showRepositoryBuilds(group),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GlobalBuildSummary extends StatelessWidget {
  const _GlobalBuildSummary({required this.snapshot});

  final GlobalBuildsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Builds dos repositórios',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              '${snapshot.repositoryCount} projetos verificados • '
              '${snapshot.repositoriesWithBuilds} com builds • '
              'consulta dinâmica: 15 s (ativas) / 60 s (geral)',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 5),
            Text(
              'Dados consultados no GitHub em ${_formatTime(snapshot.loadedAt)} • '
              '${snapshot.historyEntries.isEmpty ? snapshot.entries.length : snapshot.historyEntries.length} execuções recentes carregadas',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (snapshot.unavailableRepositories > 0) ...[
              const SizedBox(height: 5),
              Text(
                '${snapshot.unavailableRepositories} projetos indisponíveis nesta consulta. Dados anteriores são preservados quando possível.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _GlobalRepositoryBuildCard extends StatelessWidget {
  const _GlobalRepositoryBuildCard({
    required this.group,
    required this.onTap,
    this.showHistory = false,
  });

  final bool showHistory;
  final GlobalRepositoryBuildGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = _groupStatus(group);
    final version = group.version;
    final count = group.buildCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('repository-build-${group.repository.fullName}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: scheme.surfaceContainerHighest,
                child: Icon(status.$1, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.repository.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      showHistory ? '$count ${count == 1 ? 'execução' : 'execuções'} no histórico' : '$count build${count == 1 ? '' : 's'} na versão mais recente',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${group.branch}${version == null ? '' : ' • $version'} • ${_formatDate(group.date)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(label: status.$2),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlobalApkCandidate {
  const _GlobalApkCandidate._({this.release, this.artifact});

  factory _GlobalApkCandidate.fromRelease(ReleaseAsset asset) =>
      _GlobalApkCandidate._(release: asset);

  factory _GlobalApkCandidate.fromArtifact(ActionArtifact artifact) =>
      _GlobalApkCandidate._(artifact: artifact);

  final ReleaseAsset? release;
  final ActionArtifact? artifact;

  String get name => release?.name ?? artifact!.name;
  int get sizeBytes => release?.sizeBytes ?? artifact!.sizeBytes;
  ApkVariantInfo get variant => ApkVariantInfo.fromName(name);

  String originLabel(int runNumber) => release != null
      ? 'Release ${release!.tagName}'
      : 'Artifact da execução #$runNumber';
}

class _RepositoryBuildRunCard extends StatelessWidget {
  const _RepositoryBuildRunCard({
    required this.entry,
    required this.onOpen,
    required this.onDownloadLogs,
    required this.onDownloadApk,
    this.previous,
    this.onDiagnose,
  });

  final GlobalBuildEntry? previous;
  final VoidCallback? onDiagnose;
  final GlobalBuildEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDownloadLogs;
  final VoidCallback onDownloadApk;

  @override
  Widget build(BuildContext context) {
    final run = entry.run;
    final status = _runStatus(run.status, run.conclusion);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          children: [
            InkWell(
              key: ValueKey('run-${run.id}'),
              onTap: onOpen,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  children: [
                    Icon(status.$1, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${run.detectedVersion == null ? run.name : 'Versão provável: ${run.detectedVersion}'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${run.name} • execução #${run.runNumber} • ${entry.branch} • ${_formatDate(entry.date)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _StatusPill(label: status.$2),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${run.shortSha} • ${_formatDuration(run)} • tentativa ${run.runAttempt}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (previous != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _comparisonText(entry, previous!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (onDiagnose != null)
                  OutlinedButton.icon(
                    key: ValueKey('diagnose-${run.id}'),
                    onPressed: onDiagnose,
                    icon: const Icon(Icons.bug_report_outlined, size: 18),
                    label: Text(entry.isFailure ? 'Diagnóstico' : 'Etapas'),
                  ),
                OutlinedButton.icon(
                  key: ValueKey('logs-${run.id}'),
                  onPressed: onDownloadLogs,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Log'),
                ),
                FilledButton.tonalIcon(
                  key: ValueKey('apk-${run.id}'),
                  onPressed: onDownloadApk,
                  icon: const Icon(Icons.android_rounded, size: 18),
                  label: const Text('APK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

(IconData, String) _groupStatus(GlobalRepositoryBuildGroup group) {
  if (group.isRunning) return (Icons.sync_rounded, 'Executando');
  if (group.isFailure) return (Icons.error_outline_rounded, 'Falhou');
  if (group.isSuccess) return (Icons.check_circle_outline_rounded, 'Sucesso');
  return (Icons.info_outline_rounded, 'Concluída');
}

(IconData, String) _runStatus(String status, String? conclusion) {
  if (status == 'queued' ||
      status == 'waiting' ||
      status == 'pending' ||
      status == 'requested') {
    return (Icons.schedule_rounded, 'Fila');
  }
  if (status == 'in_progress') {
    return (Icons.sync_rounded, 'Executando');
  }
  return switch (conclusion) {
    'success' => (Icons.check_circle_outline_rounded, 'Sucesso'),
    'cancelled' => (Icons.cancel_outlined, 'Cancelada'),
    'timed_out' => (Icons.timer_off_outlined, 'Tempo esgotado'),
    'skipped' => (Icons.skip_next_rounded, 'Ignorada'),
    'action_required' => (Icons.warning_amber_rounded, 'Ação necessária'),
    'startup_failure' => (Icons.error_outline_rounded, 'Falhou'),
    'stale' => (Icons.hourglass_disabled_rounded, 'Obsoleta'),
    'neutral' => (Icons.remove_circle_outline_rounded, 'Neutra'),
    'failure' => (Icons.error_outline_rounded, 'Falhou'),
    _ => conclusion == null
        ? (Icons.hourglass_top_rounded, 'Pendente')
        : (Icons.info_outline_rounded, 'Concluída'),
  };
}

String _formatDate(DateTime? date) {
  if (date == null) return 'data indisponível';
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}

String _formatTime(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

Duration? _runDuration(RepositoryWorkflowRun run, {DateTime? now}) {
  final start = run.startedAt ?? run.createdAt;
  if (start == null) return null;
  final end = run.isRunning ? (now ?? DateTime.now()) : run.updatedAt;
  if (end == null || end.isBefore(start)) return null;
  return end.difference(start);
}

String _formatDuration(RepositoryWorkflowRun run) {
  final duration = _runDuration(run);
  if (duration == null) return 'duração indisponível';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}min';
  if (minutes > 0) return '${minutes}min ${seconds}s';
  return '${seconds}s';
}

String _comparisonText(GlobalBuildEntry current, GlobalBuildEntry previous) {
  final old = _runDuration(previous.run);
  final newer = _runDuration(current.run);
  final delta = old == null || newer == null ? null : newer.inSeconds - old.inSeconds;
  final label = delta == null ? 'duração não comparável' :
      delta == 0 ? 'mesma duração' :
      delta > 0 ? '${delta}s mais lenta' : '${-delta}s mais rápida';
  return 'Anterior: #${previous.run.runNumber} • ${_runStatus(previous.run.status, previous.run.conclusion).$2} • $label';
}
