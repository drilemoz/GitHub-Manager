part of 'repository_actions_screen.dart';

mixin _RunDetailsStateController on ConsumerState<_RunDetailsSheet> {
  late RepositoryWorkflowRun _run;
  late Future<List<RepositoryWorkflowJob>> _jobsFuture;
  Timer? _timer;
  bool _working = false;
  bool _lookingForApks = false;
  List<RepositoryWorkflowJob>? _currentJobs;

  @override
  void initState() {
    super.initState();
    _run = widget.run;
    _jobsFuture = _loadJobs();
    _updateTimer();
  }

  Future<List<RepositoryWorkflowJob>> _loadJobs() async {
    final jobs = await ref.read(repositoryGitServiceProvider).listWorkflowRunJobs(
          repositoryFullName: widget.repositoryFullName,
          runId: _run.id,
        );
    _currentJobs = jobs;
    return jobs;
  }

  void _updateTimer() {
    _timer?.cancel();
    if (_run.isRunning) {
      _timer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (mounted) {
          _refresh(silent: true);
        }
      });
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    try {
      final service = ref.read(repositoryGitServiceProvider);
      final runs = await service.listWorkflowRuns(widget.repositoryFullName);
      RepositoryWorkflowRun? latest;
      for (final item in runs) {
        if (item.id == _run.id) {
          latest = item;
          break;
        }
      }
      final jobsFuture = _loadJobs();
      if (mounted) {
        setState(() {
          if (latest != null) {
            _run = latest;
          }
          _jobsFuture = jobsFuture;
        });
        _updateTimer();
      }
      await jobsFuture;
      widget.onChanged();
    } catch (error) {
      if (!silent && mounted) {
        _showError(error);
      }
    }
  }

  Future<void> _cancel() async {
    setState(() => _working = true);
    try {
      await ref.read(repositoryGitServiceProvider).cancelWorkflowRun(
            repositoryFullName: widget.repositoryFullName,
            runId: _run.id,
          );
      await Future<void>.delayed(const Duration(seconds: 1));
      await _refresh();
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _rerun() async {
    setState(() => _working = true);
    try {
      await ref.read(repositoryGitServiceProvider).rerunWorkflowRun(
            repositoryFullName: widget.repositoryFullName,
            runId: _run.id,
          );
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      widget.onChanged();
    } catch (error) {
      if (mounted) {
        _showError(error);
        setState(() => _working = false);
      }
    }
  }

  Future<void> _deleteRun() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir execução permanentemente?'),
        content: Text(
          '${_run.name} #${_run.runNumber} será removida do GitHub Actions. '
          'Todos os artifacts da execução serão removidos, inclusive ZIPs que contêm APKs. APKs publicados em Releases serão preservados, pois várias builds podem usar o mesmo commit. '
          'Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    try {
      final result = await ref.read(buildCleanupServiceProvider).deleteBuild(
            repositoryFullName: widget.repositoryFullName,
            run: _run,
          );
      ref.invalidate(repositoryArtifactsProvider(widget.repositoryFullName));
      ref.invalidate(repositoryReleaseAssetsProvider(widget.repositoryFullName));
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onChanged();
      final removed = result.relatedFilesRemoved;
      showCenteredNotice(
        context,
        result.hasWarnings
            ? 'Build excluída • $removed artifact(s) removido(s). Alguns itens não puderam ser conferidos. Releases preservadas.'
            : 'Build excluída • $removed artifact(s) removido(s). Releases preservadas.',
      );
    } catch (error) {
      if (mounted) {
        _showError(error);
        setState(() => _working = false);
      }
    }
  }

  void _downloadLogs() {
    ref.read(downloadManagerProvider).startWorkflowLogs(
          repositoryFullName: widget.repositoryFullName,
          runId: _run.id,
          runTitle: '${_run.name}-${_run.runNumber}',
        );
    if (mounted) {
      showCenteredNotice(context, 'Download dos logs iniciado. Acompanhe pela Central de Downloads.');
    }
  }

  Future<void> _openRunApks() async {
    if (_working) return;
    setState(() { _working = true; _lookingForApks = true; });
    try {
      final service = ref.read(artifactServiceProvider);
      var failedSources = 0;
      final artifactsFuture = service.listArtifactsForRun(
        repositoryFullName: widget.repositoryFullName,
        runId: _run.id,
      ).catchError((Object _) {
        failedSources++;
        return <ActionArtifact>[];
      });
      final releasesFuture = service.findReleaseApksForBuild(
        repositoryFullName: widget.repositoryFullName,
        run: _run,
      ).catchError((Object _) {
        failedSources++;
        return <ReleaseAsset>[];
      });

      AndroidDeviceInfo? deviceInfo;
      try {
        deviceInfo = await PlatformActions.getAndroidDeviceInfo();
      } catch (_) {
        deviceInfo = null;
      }

      List<ActionArtifact> artifacts = const [];
      List<ActionArtifact> allRunArtifacts = const [];
      List<ReleaseAsset> releases = const [];
      try {
        allRunArtifacts = await artifactsFuture;
        artifacts = allRunArtifacts
            .where((artifact) => artifact.likelyContainsApk && !artifact.expired)
            .toList(growable: false);
      } catch (_) {
        failedSources++;
      }
      try {
        releases = (await releasesFuture)
            .where((asset) => asset.isApk)
            .toList(growable: false);
      } catch (_) {
        failedSources++;
      }
      final candidates = <_RunApkCandidate>[
        ...releases.map(_RunApkCandidate.fromRelease),
      ];
      // Uma Release associada pelo commit pode pertencer a outra execução.
      // Nunca substituir/suprimir um Artifact vinculado ao run por sua ABI.
      candidates.addAll(artifacts.map(_RunApkCandidate.fromArtifact));

      if (!mounted) return;
      if (candidates.isEmpty) {
        setState(() => _lookingForApks = false);
        final openAll = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Nenhum APK vinculado a esta execução'),
            content: Text(
              failedSources == 2
                  ? 'Falha ao consultar artifacts e Releases. Verifique conexão, permissões e tente novamente.'
                  : failedSources == 1
                      ? 'Uma das fontes não respondeu. Nenhum APK foi localizado na outra. Você pode consultar a lista geral.'
                      : 'O GitHub Manager não encontrou APKs vinculados à execução. Eles podem ter expirado ou não ter sido publicados. Você pode consultar a lista geral.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Fechar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Ver todos os APKs'),
              ),
            ],
          ),
        );
        if (openAll == true && mounted) {
          Navigator.of(context).pop();
          widget.onOpenArtifacts();
        }
        return;
      }

      if (failedSources > 0) {
        showCenteredNotice(context, 'Uma fonte de APKs não respondeu; exibindo os arquivos encontrados.');
      }
      final manifest = await service.loadBuildManifest(
        repositoryFullName: widget.repositoryFullName,
        runId: _run.id,
        commitSha: _run.headSha,
        knownArtifacts: allRunArtifacts,
      );
      if (!mounted) return;
      setState(() => _lookingForApks = false);
      final supportedAbis = deviceInfo?.supportedAbis ?? const <String>[];
      candidates.sort((left, right) {
        final leftRank = apkRecommendationRank(left.name, supportedAbis);
        final rightRank = apkRecommendationRank(right.name, supportedAbis);
        if (leftRank != rightRank) return leftRank.compareTo(rightRank);
        if (left.artifact != null && right.artifact == null) return -1;
        if (left.artifact == null && right.artifact != null) return 1;
        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

      final selected = await showSmartApkPicker<_RunApkCandidate>(
        context: context,
        project: widget.repositoryFullName.split('/').last,
        runNumber: _run.runNumber,
        version: _run.detectedVersion,
        deviceInfo: deviceInfo,
        manifest: manifest,
        options: [
          for (final candidate in candidates)
            SmartApkOption(
              value: candidate,
              name: candidate.name,
              bytes: candidate.sizeBytes,
              source: candidate.originLabel(_run.runNumber),
              exactRun: candidate.artifact != null,
              declaredAbi: candidate.artifact == null ? null :
                ([...?(manifest?.apks)].where((apk) => apk.fileName == candidate.name)
                  .map((apk) => apk.abi).firstOrNull),
            ),
        ],
      );
      if (selected == null || !mounted) return;
      if (!await _confirmApkCompatibility(selected, deviceInfo)) return;
      if (selected.release != null &&
          !await _confirmReleaseApkAssociation(selected.release!)) return;
      if (mounted) _startRunApkDownload(selected, deviceInfo);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() { _working = false; _lookingForApks = false; });
    }
  }

  Future<bool> _confirmReleaseApkAssociation(ReleaseAsset asset) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Associação de Release não exclusiva'),
            content: Text(
              '${asset.name} foi encontrado na Release ${asset.tagName} pelo '
              'commit/versão. Isso não comprova qual execução publicou o APK. '
              'Deseja baixar este arquivo mesmo assim?',
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

  Future<bool> _confirmApkCompatibility(
    _RunApkCandidate candidate,
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
              'Este APK é ${variant.label}, mas este aparelho informa ${deviceInfo.primaryAbi} como arquitetura principal e suporta ${deviceInfo.supportedAbis.join(', ')}. Ele provavelmente não poderá ser instalado. Deseja baixar mesmo assim?',
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

  void _startRunApkDownload(
    _RunApkCandidate candidate,
    AndroidDeviceInfo? deviceInfo,
  ) {
    final manager = ref.read(downloadManagerProvider);
    final release = candidate.release;
    final artifact = candidate.artifact;
    if (release != null) {
      manager.startReleaseAsset(
        title: '${release.tagName} • ${release.name}',
        fileName: release.name,
        repositoryFullName: widget.repositoryFullName,
        assetId: release.id,
        isApk: true,
      );
    } else if (artifact != null) {
      manager.startArtifactApk(
        repositoryFullName: widget.repositoryFullName,
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

  void _showError(Object error) {
    final message = error is GitHubPermissionException
        ? 'O token precisa de Actions: write para controlar builds.'
        : error is AppException
            ? error.message
            : 'Não foi possível atualizar esta execução.';
    showCenteredNotice(context, message);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

}
