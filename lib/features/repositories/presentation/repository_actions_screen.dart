import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/background/build_monitor_service.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/core/widgets/app_main_navigation.dart';
import 'package:github_manager/core/widgets/centered_notice.dart';
import 'package:github_manager/features/builds/presentation/smart_apk_picker.dart';
import 'package:github_manager/features/builds/data/build_cleanup_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/apk_variant.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/builds/presentation/build_providers.dart';
import 'package:github_manager/features/downloads/presentation/download_center_button.dart';
import 'package:github_manager/features/downloads/presentation/download_providers.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';
import 'package:github_manager/features/repositories/presentation/repository_branch_selector.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';
import 'package:github_manager/features/uploads/presentation/upload_center_button.dart';
import 'package:go_router/go_router.dart';

part 'repository_actions_widgets.dart';
part 'repository_actions_screen_controller.dart';
part 'repository_run_details.dart';
part 'repository_run_details_controller.dart';
part 'repository_run_details_widgets.dart';

class RepositoryActionsScreen extends ConsumerStatefulWidget {
  const RepositoryActionsScreen({
    required this.repositoryFullName,
    required this.defaultBranch,
    this.readOnly = false,
    this.initialRunId,
    super.key,
  });

  final String repositoryFullName;
  final String defaultBranch;
  final bool readOnly;
  final int? initialRunId;

  @override
  ConsumerState<RepositoryActionsScreen> createState() =>
      _RepositoryActionsScreenState();
}

class _RepositoryActionsScreenState extends ConsumerState<RepositoryActionsScreen>
    with WidgetsBindingObserver, _RepositoryActionsStateController {
  @override
  void initState() {
    super.initState();
    initializeRepositoryActionsState();
  }

  @override
  void didUpdateWidget(covariant RepositoryActionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRunId != widget.initialRunId ||
        oldWidget.defaultBranch != widget.defaultBranch) {
      _initialRunOpened = false;
      _branch = widget.defaultBranch;
      unawaited(_refresh(silent: true));
      final data = _currentData;
      if (data != null) _openInitialRunIfNeeded(data.allRuns);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleRepositoryActionsLifecycleState(state);
  }

  @override
  void dispose() {
    disposeRepositoryActionsState();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenTitle = _selectedWorkflow == null
        ? 'Builds'
        : 'Execuções — ${_selectedWorkflow!.name}';
    return Scaffold(
      bottomNavigationBar: const AppMainNavigation(selectedIndex: 0),
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                onPressed: _deletingSelected ? null : _clearRunSelection,
                tooltip: 'Cancelar seleção',
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          _deletingSelected
              ? _deletionTitle()
              : _selectionMode
                  ? _selectionTitle()
                  : screenTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_selectionMode && !widget.readOnly) ...[
            IconButton(
              onPressed: _deletingSelected
                  ? null
                  : () => _selectAllVisibleRuns(failedOnly: true),
              tooltip: 'Selecionar falhas',
              icon: const Icon(Icons.error_outline_rounded),
            ),
            IconButton(
              onPressed: _deletingSelected ? null : () => _selectAllVisibleRuns(),
              tooltip: 'Selecionar todas',
              icon: const Icon(Icons.select_all_rounded),
            ),
            IconButton(
              onPressed: _selectedRunIds.isEmpty || _deletingSelected
                  ? null
                  : _deleteSelectedRuns,
              tooltip: 'Excluir selecionadas',
              icon: _deletingSelected
                  ? SizedBox(
                      width: 38,
                      child: Text(
                        '${_deleteProgress?.percent ?? 0}%',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    )
                  : const Icon(Icons.delete_forever_outlined),
            ),
          ] else ...[
            if (!widget.readOnly)
              IconButton(
                onPressed: () => context.push('/builds/storage?repository=${Uri.encodeQueryComponent(widget.repositoryFullName)}'),
                tooltip: 'Gerenciar armazenamento de artifacts',
                icon: const Icon(Icons.inventory_2_outlined, size: 21),
              ),
            if (!widget.readOnly)
              IconButton(
                onPressed: () => setState(() => _selectionMode = true),
                tooltip: 'Selecionar execuções',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.checklist_rounded, size: 21),
              ),
            const UploadCenterButton(),
            const DownloadCenterButton(),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<RepositoryActionsData>(
          future: _future,
          builder: (context, snapshot) {
            final retained = snapshot.data ?? _currentData;
            if (snapshot.connectionState == ConnectionState.waiting && retained == null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 220),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }
            if (snapshot.hasError && retained == null) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(_message(snapshot.error!)),
                    ),
                  ),
                ],
              );
            }

            final data = retained!;
            final runs = data.runs;
            final runGroups = _groupRuns(runs);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 104),
              children: [
                if (!widget.readOnly && !_selectionMode) ...[
                  _ActionsQuickBar(
                    starting: _starting,
                    onRun: _runWorkflow,
                    onRefresh: () => _refresh(),
                    onArtifacts: () => context.push(
                      '/repositories/${widget.repositoryFullName}/artifacts?readOnly=${widget.readOnly ? '1' : '0'}',
                    ),
                    onDiagnostics: () => setState(() => _showDiagnostics = !_showDiagnostics),
                    onPermissions: () => context.push(
                      '/repositories/${widget.repositoryFullName}/permissions',
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: SizedBox(
                    width: double.infinity,
                    child: RepositoryBranchButton(
                      branch: _branch,
                      onPressed: _changeBranch,
                      compact: true,
                    ),
                  ),
                ),
                _WorkflowsPanel(
                  data: data,
                  selectedWorkflow: _selectedWorkflow,
                  onSelected: _selectWorkflow,
                ),
                if (_showDiagnostics || runs.isEmpty) ...[
                  const SizedBox(height: 7),
                  _ActionsDiagnosticCard(diagnostic: data.diagnostic),
                ],
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        data.selectedWorkflow == null
                            ? 'Todas as execuções'
                            : 'Execuções — ${data.selectedWorkflow!.name}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _refreshStatusLabel(),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (runs.isEmpty)
                  _EmptyRunsCard(diagnostic: data.diagnostic)
                else
                  ...runGroups.map(
                    (group) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RunGroupCard(
                        group: group,
                        selectionMode: _selectionMode,
                        selectedRunIds: _selectedRunIds,
                        onRunTap: _selectionMode
                            ? _toggleRunSelection
                            : _showRunDetails,
                        onRunLongPress: _handleRunLongPress,
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

  static List<_RunGroup> _groupRuns(List<RepositoryWorkflowRun> runs) {
    final grouped = <String, List<RepositoryWorkflowRun>>{};
    for (final run in runs) {
      final hasSha = run.headSha.trim().isNotEmpty;
      final key = run.event == 'push' && hasSha
          ? 'push:${run.headSha}'
          : 'run:${run.id}';
      grouped.putIfAbsent(key, () => <RepositoryWorkflowRun>[]).add(run);
    }

    final groups = grouped.values.map((items) {
      items.sort((a, b) {
        final aDate = a.createdAt ?? a.startedAt;
        final bDate = b.createdAt ?? b.startedAt;
        if (aDate == null && bDate == null) {
          return b.id.compareTo(a.id);
        }
        if (aDate == null) {
          return 1;
        }
        if (bDate == null) {
          return -1;
        }
        return bDate.compareTo(aDate);
      });
      return _RunGroup(List<RepositoryWorkflowRun>.unmodifiable(items));
    }).toList();

    groups.sort((a, b) {
      final aDate = a.latestAt;
      final bDate = b.latestAt;
      if (aDate == null && bDate == null) {
        return b.primary.id.compareTo(a.primary.id);
      }
      if (aDate == null) {
        return 1;
      }
      if (bDate == null) {
        return -1;
      }
      return bDate.compareTo(aDate);
    });

    return List<_RunGroup>.unmodifiable(groups);
  }

  String _selectionTitle() {
    final runs = _currentData?.runs ?? const <RepositoryWorkflowRun>[];
    final selected = runs.where((run) => _selectedRunIds.contains(run.id));
    final failures = selected.where((run) => run.conclusion == 'failure').length;
    if (failures == _selectedRunIds.length && failures > 0) {
      return '$failures falha(s) selecionada(s)';
    }
    return '${_selectedRunIds.length} selecionada(s)';
  }

  String _refreshStatusLabel() {
    final updated = _lastUpdatedAt;
    final cadence = _hasRunning ? '6 s' : '15 s';
    if (updated == null) return 'Atualizando • auto $cadence';
    final seconds = DateTime.now().difference(updated).inSeconds.abs();
    final when = seconds < 5
        ? 'Atualizado agora'
        : seconds < 60
            ? 'há ${seconds}s'
            : 'há ${seconds ~/ 60}min';
    return '$when • auto $cadence';
  }

  static String _statusLabel(RepositoryWorkflowRun run) {
    if (run.status != 'completed') {
      return switch (run.status) {
        'queued' => 'Na fila',
        'in_progress' => 'Em andamento',
        'waiting' => 'Aguardando',
        'pending' => 'Pendente',
        _ => run.status,
      };
    }
    return switch (run.conclusion) {
      'success' => 'Sucesso',
      'failure' => 'Falhou',
      'cancelled' => 'Cancelada',
      'skipped' => 'Ignorada',
      'timed_out' => 'Tempo esgotado',
      'action_required' => 'Ação necessária',
      _ => run.conclusion ?? 'Concluída',
    };
  }

  static String _formatDuration(RepositoryWorkflowRun run) {
    final start = run.startedAt ?? run.createdAt;
    if (start == null) {
      return '-';
    }
    final end = run.isRunning ? DateTime.now() : run.updatedAt ?? DateTime.now();
    final duration = end.difference(start).abs();
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}min';
    }
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}min ${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inSeconds}s';
  }

  static String _formatCompactDate(DateTime? value) {
    if (value == null) return 'sem data';
    final date = value.toLocal();
    const months = <String>[
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    String two(int value) => value.toString().padLeft(2, '0');
    final year = (date.year % 100).toString().padLeft(2, '0');
    return '${date.day} ${months[date.month - 1]} $year • ${two(date.hour)}:${two(date.minute)}';
  }

  static String _formatDate(DateTime? value) {
    if (value == null) {
      return 'data -';
    }
    final date = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  static String _formatSpan(DateTime? start, DateTime? end) {
    if (start == null) return '-';
    final effectiveEnd = end ?? DateTime.now();
    final duration = effectiveEnd.difference(start).abs();
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}min';
    }
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}min ${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inSeconds}s';
  }

  static String _jobStatus(RepositoryWorkflowJob job) {
    if (job.status != 'completed') {
      return switch (job.status) {
        'queued' => 'Na fila',
        'in_progress' => 'Em execução',
        'waiting' => 'Aguardando',
        _ => job.status,
      };
    }
    return switch (job.conclusion) {
      'success' => 'Concluído com sucesso',
      'failure' => 'Falhou',
      'cancelled' => 'Cancelado',
      'skipped' => 'Ignorado',
      _ => 'Concluído',
    };
  }

  static String _stepStatus(RepositoryWorkflowStep step) {
    if (step.status != 'completed') {
      return switch (step.status) {
        'queued' => 'Na fila',
        'in_progress' => 'Em andamento',
        'waiting' => 'Aguardando',
        _ => step.status,
      };
    }
    return switch (step.conclusion) {
      'success' => 'Concluída',
      'failure' => 'Falhou',
      'cancelled' => 'Cancelada',
      'skipped' => 'Ignorada',
      _ => 'Concluída',
    };
  }

  static String _stepExplanation(String name) {
    final value = name.toLowerCase();
    if (value.contains('set up job') || value.contains('setup job')) {
      return 'Preparando a máquina e o ambiente onde o workflow será executado.';
    }
    if (value.contains('complete job') ||
        value.contains('post job') ||
        value.contains('cleanup')) {
      return 'Finalizando o job e limpando recursos temporários.';
    }
    if (value.contains('checkout')) {
      return 'Baixando os arquivos do projeto para a máquina do GitHub Actions.';
    }
    if (value.contains('cache')) {
      return 'Restaurando ou salvando arquivos reutilizáveis para acelerar a build.';
    }
    if (value.contains('versão') || value.contains('version')) {
      return 'Lendo e conferindo a versão usada por esta execução.';
    }
    if (value.contains('ícone') || value.contains('icon')) {
      return 'Conferindo os recursos de ícone exigidos pelo aplicativo Android.';
    }
    if (value.contains('plataforma android') ||
        (value.contains('android') && value.contains('platform'))) {
      return 'Conferindo se a estrutura Android necessária está presente e versionada.';
    }
    if (value.contains('java')) {
      return 'Preparando o Java necessário para compilar o aplicativo Android.';
    }
    if (value.contains('flutter')) {
      return 'Preparando o Flutter para compilar o aplicativo.';
    }
    if (value.contains('depend') || value.contains('pub get')) {
      return 'Baixando as bibliotecas necessárias.';
    }
    if (value.contains('analis') || value.contains('analyze')) {
      return 'Verificando o código em busca de erros.';
    }
    if (value.contains('test')) {
      return 'Executando os testes automáticos.';
    }
    if (value.contains('gradle') || value.contains('wrapper')) {
      return 'Preparando o sistema de compilação do Android.';
    }
    if (value.contains('compil') ||
        value.contains('gerar apk') ||
        value.contains('build apk') ||
        value.contains('assemble')) {
      return 'Compilando o aplicativo Android.';
    }
    if (value.contains('assin') || value.contains('sign')) {
      return 'Assinando o APK.';
    }
    if (value.contains('artifact') ||
        value.contains('publicar') ||
        value.contains('upload')) {
      return 'Enviando o APK ou resultado para o GitHub.';
    }
    if (value.contains('valid')) {
      return 'Conferindo se os arquivos e configurações estão corretos.';
    }
    return 'Etapa técnica executada pelo GitHub Actions.';
  }
}
