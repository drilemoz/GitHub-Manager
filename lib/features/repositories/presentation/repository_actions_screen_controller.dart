part of 'repository_actions_screen.dart';

mixin _RepositoryActionsStateController on ConsumerState<RepositoryActionsScreen>, WidgetsBindingObserver {
  late Future<RepositoryActionsData> _future;
  late String _branch;
  RepositoryWorkflow? _selectedWorkflow;
  Timer? _timer;
  bool _hasRunning = false;
  bool _refreshing = false;
  DateTime? _lastUpdatedAt;
  bool _starting = false;
  bool _showDiagnostics = false;
  RepositoryActionsData? _currentData;
  final Set<int> _selectedRunIds = <int>{};
  bool _selectionMode = false;
  bool _deletingSelected = false;
  BuildCleanupProgress? _deleteProgress;
  bool _initialRunOpened = false;
  int? _initialRunLoadingId;

  void initializeRepositoryActionsState() {
    WidgetsBinding.instance.addObserver(this);
    _branch = widget.defaultBranch;
    unawaited(BuildMonitorService.watchRepository(widget.repositoryFullName));
    _future = _load();
    _future.then<void>(
      (_) {
        if (mounted) _scheduleAutoRefresh();
      },
      onError: (_) {
        if (mounted) _scheduleAutoRefresh();
      },
    );
  }

  Future<RepositoryActionsData> _load() async {
    final data = await ref.read(repositoryGitServiceProvider).loadActions(
          widget.repositoryFullName,
          workflow: _selectedWorkflow,
          branch: _branch,
        );
    _hasRunning = data.allRuns.any((run) => run.isRunning);
    _currentData = data;
    _lastUpdatedAt = DateTime.now();
    _openInitialRunIfNeeded(data.allRuns);
    return data;
  }


  void _openInitialRunIfNeeded(List<RepositoryWorkflowRun> runs) {
    final runId = widget.initialRunId;
    if (_initialRunOpened || runId == null) return;
    RepositoryWorkflowRun? target;
    for (final run in runs) {
      if (run.id == runId) {
        target = run;
        break;
      }
    }
    if (target == null) {
      if (_initialRunLoadingId != runId) unawaited(_loadNotListedRun(runId));
      return;
    }
    _initialRunOpened = true;
    final selected = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_showRunDetails(selected));
    });
  }

  Future<void> _loadNotListedRun(int runId) async {
    _initialRunLoadingId = runId;
    try {
      final run = await ref.read(repositoryGitServiceProvider).getWorkflowRunById(
        widget.repositoryFullName,
        runId,
      );
      if (!mounted || widget.initialRunId != runId) return;
      _initialRunOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showRunDetails(run));
      });
    } catch (_) {
      if (!mounted || widget.initialRunId != runId) return;
      _initialRunOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Não foi possível carregar esta execução. Ela pode ter sido excluída ou estar indisponível.',
          )),
        );
      });
    } finally {
      if (_initialRunLoadingId == runId) _initialRunLoadingId = null;
    }
  }

  Future<void> _refresh({
    bool silent = false,
    bool lightweight = false,
  }) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final data = lightweight ? await _pollRecentRuns() : await _load();
      if (mounted) {
        setState(() => _future = Future<RepositoryActionsData>.value(data));
      }
    } catch (_) {
      if (!silent) {
        rethrow;
      }
    } finally {
      _refreshing = false;
      if (mounted) _scheduleAutoRefresh();
    }
  }

  Future<RepositoryActionsData> _pollRecentRuns() async {
    final current = _currentData;
    if (current == null) return _load();
    if (_selectedWorkflow != null &&
        current.diagnostic.reason == 'fallback_workflow_especifico') {
      return _load();
    }
    final recent = await ref
        .read(repositoryGitServiceProvider)
        .listRecentWorkflowRuns(widget.repositoryFullName);
    final previousById = <int, RepositoryWorkflowRun>{
      for (final run in current.allRuns) run.id: run,
    };
    final allRuns = recent.map((run) {
      final previousVersion = previousById[run.id]?.buildVersion;
      if (run.buildVersion == null && previousVersion != null) {
        return run.withBuildVersion(previousVersion);
      }
      return run;
    }).toList(growable: false)
      ..sort((a, b) {
        final aDate = a.createdAt ?? a.startedAt;
        final bDate = b.createdAt ?? b.startedAt;
        if (aDate == null && bDate == null) return b.id.compareTo(a.id);
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
    final selected = _selectedWorkflow;
    final branchRuns = allRuns
        .where((run) => run.branch.trim() == _branch.trim())
        .toList(growable: false);
    final visibleRuns = selected == null
        ? branchRuns
        : branchRuns.where((run) => run.belongsTo(selected)).toList(growable: false);
    final oldDiagnostic = current.diagnostic;
    final data = RepositoryActionsData(
      workflows: current.workflows,
      allRuns: List<RepositoryWorkflowRun>.unmodifiable(allRuns),
      runs: List<RepositoryWorkflowRun>.unmodifiable(visibleRuns),
      selectedWorkflow: selected,
      diagnostic: RepositoryActionsDiagnostic(
        endpoint: oldDiagnostic.endpoint,
        httpStatus: oldDiagnostic.httpStatus,
        repositoryRunsReceived: allRuns.length,
        runsAfterFilter: visibleRuns.length,
        totalCountReported: oldDiagnostic.totalCountReported,
        reason: oldDiagnostic.reason,
        workflowId: selected?.id,
        workflowName: selected?.name,
        workflowPath: selected?.path,
        workflowState: selected?.state,
        fallbackEndpoint: oldDiagnostic.fallbackEndpoint,
        fallbackHttpStatus: oldDiagnostic.fallbackHttpStatus,
        fallbackRunsReceived: oldDiagnostic.fallbackRunsReceived,
      ),
    );
    _hasRunning = allRuns.any((run) => run.isRunning);
    final availableIds = allRuns.map((run) => run.id).toSet();
    _selectedRunIds.removeWhere((id) => !availableIds.contains(id));
    _selectionMode = _selectedRunIds.isNotEmpty;
    _currentData = data;
    _lastUpdatedAt = DateTime.now();
    return data;
  }

  void _scheduleAutoRefresh() {
    _timer?.cancel();
    if (!mounted) return;
    final interval = _hasRunning
        ? const Duration(seconds: 6)
        : const Duration(seconds: 15);
    _timer = Timer(interval, () {
      if (mounted) unawaited(_refresh(silent: true, lightweight: true));
    });
  }

  Future<void> _changeBranch() async {
    final selected = await showRepositoryBranchSelector(
      context: context,
      ref: ref,
      repositoryFullName: widget.repositoryFullName,
      currentBranch: _branch,
      defaultBranch: widget.defaultBranch,
      allowCreate: !widget.readOnly,
    );
    if (selected == null || selected.name == _branch || !mounted) return;
    _timer?.cancel();
    _branch = selected.name;
    _selectedWorkflow = null;
    _initialRunOpened = true;
    final next = _load();
    setState(() {
      _selectedRunIds.clear();
      _selectionMode = false;
      _future = next;
    });
    next.then<void>(
      (_) {
        if (mounted) _scheduleAutoRefresh();
      },
      onError: (_) {
        if (mounted) _scheduleAutoRefresh();
      },
    );
  }

  void _selectWorkflow(RepositoryWorkflow? workflow) {
    _timer?.cancel();
    _selectedWorkflow = workflow;
    final next = _load();
    setState(() {
      _selectedRunIds.clear();
      _selectionMode = false;
      _future = next;
    });
    next.then<void>(
      (_) {
        if (mounted) _scheduleAutoRefresh();
      },
      onError: (_) {
        if (mounted) _scheduleAutoRefresh();
      },
    );
  }

  void _clearRunSelection() {
    setState(() {
      _selectedRunIds.clear();
      _selectionMode = false;
    });
  }

  void _toggleRunSelection(RepositoryWorkflowRun run) {
    if (widget.readOnly || run.isRunning) return;
    setState(() {
      _selectionMode = true;
      if (!_selectedRunIds.add(run.id)) {
        _selectedRunIds.remove(run.id);
      }
      if (_selectedRunIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _handleRunLongPress(RepositoryWorkflowRun run) {
    if (widget.readOnly) return;
    if (!_selectionMode) {
      final hasFailures = (_currentData?.runs ?? const <RepositoryWorkflowRun>[])
          .any((item) => !item.isRunning && item.conclusion == 'failure');
      if (hasFailures) {
        _selectAllVisibleRuns(failedOnly: true);
        return;
      }
    }
    if (run.isRunning) return;
    _toggleRunSelection(run);
  }

  void _selectAllVisibleRuns({bool failedOnly = false}) {
    final data = _currentData;
    if (data == null || widget.readOnly) return;
    final candidates = data.runs.where(
      (run) =>
          !run.isRunning &&
          (!failedOnly || run.conclusion == 'failure'),
    );
    setState(() {
      _selectionMode = true;
      _selectedRunIds
        ..clear()
        ..addAll(candidates.map((run) => run.id));
      if (_selectedRunIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  String _deletionTitle() {
    final progress = _deleteProgress;
    if (progress == null) return 'Preparando exclusão…';
    return 'Excluindo ${progress.current} de ${progress.total} • ${progress.percent}%';
  }

  Future<void> _deleteSelectedRuns() async {
    if (_selectedRunIds.isEmpty || widget.readOnly || _deletingSelected) return;
    final count = _selectedRunIds.length;
    final selectedRuns = (_currentData?.runs ?? const <RepositoryWorkflowRun>[])
        .where((run) => _selectedRunIds.contains(run.id))
        .toList(growable: false);
    final failuresOnly = selectedRuns.length == count &&
        selectedRuns.every((run) => run.conclusion == 'failure');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          failuresOnly
              ? 'Excluir $count build(s) com falha?'
              : 'Excluir $count execução(ões)?',
        ),
        content: Text(
          failuresOnly
              ? 'Somente as execuções que falharam serão removidas permanentemente do GitHub Actions. '
                  'As execuções concluídas com sucesso serão mantidas. Os artifacts dessas execuções excluídas, inclusive ZIPs com APKs, também serão apagados. '
                  'APKs publicados em Releases e o código-fonte serão preservados. Esta ação não pode ser desfeita.'
              : 'As execuções selecionadas serão removidas permanentemente do GitHub Actions. '
                  'Todos os artifacts associados, inclusive ZIPs com APKs, serão apagados. '
                  'APKs publicados em Releases e o código-fonte serão preservados. Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _deletingSelected = true;
      _deleteProgress = null;
    });
    try {
      final result = await ref
          .read(buildCleanupServiceProvider)
          .deleteBuilds(
            repositoryFullName: widget.repositoryFullName,
            runs: selectedRuns,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _deleteProgress = progress);
            },
          );
      ref.invalidate(repositoryArtifactsProvider(widget.repositoryFullName));
      ref.invalidate(repositoryReleaseAssetsProvider(widget.repositoryFullName));
      if (!mounted) return;
      setState(() {
        _selectedRunIds
          ..clear()
          ..addAll(result.failedRunIds);
        _selectionMode = _selectedRunIds.isNotEmpty;
      });
      await _refresh(silent: true);
      if (!mounted) return;
      if (result.hasFailures || result.hasWarnings) {
        final lines = <String>[
          '${result.deletedCount} execução(ões) excluída(s).',
          '${result.artifactsRemoved} artifact(s) confirmado(s) como ausentes pela API.',
          'APKs e outros arquivos publicados em Releases foram preservados.',
          if (result.failedCount > 0)
            '${result.failedCount} execução(ões) NÃO excluída(s); seguem selecionadas.',
          if (result.failureMessages.isNotEmpty) ...[
            '',
            'Falhas de exclusão:',
            for (final entry in result.failureMessages.entries.take(8))
              '• Run ${entry.key}: ${entry.value}',
          ],
          if (result.warnings.isNotEmpty) ...[
            '',
            'Conferências pendentes:',
            for (final warning in result.warnings.take(12)) '• $warning',
            if (result.warnings.length > 12)
              '• E mais ${result.warnings.length - 12} aviso(s).',
          ],
        ];
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Resultado da limpeza de Builds'),
            content: SingleChildScrollView(
              child: SelectableText(lines.join('\n')),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      } else {
        showCenteredNotice(
          context,
          '${result.deletedCount} execução(ões) excluída(s) e '
          '${result.artifactsRemoved} artifact(s) confirmado(s) como ausentes. '
          'APKs de Releases preservados.',
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _deletingSelected = false;
          _deleteProgress = null;
        });
      }
    }
  }

  Future<void> _runWorkflow() async {
    try {
      setState(() => _starting = true);
      final service = ref.read(repositoryGitServiceProvider);
      final workflows = await service.listWorkflows(widget.repositoryFullName);
      if (!mounted) {
        return;
      }
      final active = workflows.where((item) => item.isActive).toList();
      if (active.isEmpty) {
        throw const RepositoryFileException(
          'Nenhum workflow ativo foi encontrado neste repositório.',
          code: 'NO_ACTIVE_WORKFLOW',
        );
      }
      final selected = await showModalBottomSheet<RepositoryWorkflow>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  'Executar workflow',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              ...active.map(
                (workflow) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: Text(workflow.name),
                    subtitle: Text(workflow.path),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(context, workflow),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) {
        return;
      }

      final supportsDispatch = await service.workflowSupportsDispatch(
        repositoryFullName: widget.repositoryFullName,
        branch: _branch,
        workflow: selected,
      );
      if (!supportsDispatch) {
        throw RepositoryFileException(
          '${selected.name} não possui workflow_dispatch e não pode ser iniciado manualmente.',
          code: 'WORKFLOW_DISPATCH_UNAVAILABLE',
        );
      }

      await service.dispatchWorkflow(
        repositoryFullName: widget.repositoryFullName,
        workflow: selected,
        ref: _branch,
      );
      if (mounted) {
        showCenteredNotice(context, '${selected.name} iniciado na branch $_branch.');
        _selectedWorkflow = selected;
        await Future<void>.delayed(const Duration(seconds: 2));
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _showRunDetails(RepositoryWorkflowRun run) async {
    if (!mounted) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _RunDetailsSheet(
        repositoryFullName: widget.repositoryFullName,
        run: run,
        onChanged: () => _refresh(silent: true),
        readOnly: widget.readOnly,
        onOpenArtifacts: () {
          if (mounted) {
            context.push('/repositories/${widget.repositoryFullName}/artifacts?readOnly=${widget.readOnly ? '1' : '0'}');
          }
        },
      ),
    );
  }

  void handleRepositoryActionsLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh(silent: true);
    }
  }

  void disposeRepositoryActionsState() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }


  String _message(Object error) {
    if (error is GitHubValidationException) {
      return 'O workflow não aceitou a execução manual. Confirme se ele possui workflow_dispatch.';
    }
    if (error is GitHubPermissionException) {
      return 'O token precisa da permissão Actions: write para executar, cancelar ou reexecutar builds.';
    }
    return error is AppException
        ? error.message
        : 'Não foi possível carregar as execuções.';
  }

  void _showError(Object error) {
    showCenteredNotice(context, _message(error));
  }

}
