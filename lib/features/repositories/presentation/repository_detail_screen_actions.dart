part of 'repository_detail_screen.dart';

mixin _RepositoryDetailScreenActions on ConsumerState<RepositoryDetailScreen> {
  late Future<GitHubRepository> _repositoryFuture;
  late Future<List<RepositoryWorkflowRun>> _runsFuture;
  bool _apkShortcutBusy = false;

  void initializeRepositoryDetailState() {
    final cached = ref
        .read(repositoryServiceProvider)
        .cachedRepository(widget.repositoryFullName);
    _repositoryFuture = cached == null
        ? _loadRepository()
        : Future<GitHubRepository>.value(cached);
    _runsFuture = widget.readOnly
        ? Future<List<RepositoryWorkflowRun>>.value(const [])
        : _loadRuns();
    if (cached != null) {
      Future<void>.microtask(_refreshRepositoryInBackground);
    }
  }

  Future<void> _refreshRepositoryInBackground() async {
    try {
      final fresh = await _loadRepository();
      if (!mounted) return;
      setState(() => _repositoryFuture = Future<GitHubRepository>.value(fresh));
      ref.invalidate(repositoryProjectInfoProvider(fresh));
    } catch (_) {
      // O cache já permite usar a tela; uma atualização remota lenta não deve
      // substituir conteúdo válido por um spinner ou erro.
    }
  }

  Future<GitHubRepository> _loadRepository() async {
    final service = ref.read(repositoryServiceProvider);
    return service
        .getRepository(widget.repositoryFullName)
        .timeout(const Duration(seconds: 12));
  }

  void _retryRepositoryLoad() {
    final cached = ref
        .read(repositoryServiceProvider)
        .cachedRepository(widget.repositoryFullName);
    setState(() {
      _repositoryFuture = cached == null
          ? _loadRepository()
          : Future<GitHubRepository>.value(cached);
      _runsFuture = widget.readOnly
          ? Future<List<RepositoryWorkflowRun>>.value(const [])
          : _loadRuns();
    });
    if (cached != null) {
      Future<void>.microtask(_refreshRepositoryInBackground);
    }
  }

  Future<List<RepositoryWorkflowRun>> _loadRuns() => ref
      .read(repositoryGitServiceProvider)
      .listWorkflowRuns(widget.repositoryFullName)
      .timeout(
        const Duration(seconds: 12),
        onTimeout: () => const <RepositoryWorkflowRun>[],
      );

  Future<void> _refresh() async {
    if (!widget.readOnly) {
      ref.invalidate(repositoryArtifactsProvider(widget.repositoryFullName));
      ref.invalidate(repositoryReleaseAssetsProvider(widget.repositoryFullName));
    }
    ref.invalidate(repositoryApkStatusProvider);
    final repository = widget.readOnly
        ? ref.read(repositoryServiceProvider).getRepository(widget.repositoryFullName)
        : _loadRepository();
    final runs = widget.readOnly
        ? Future<List<RepositoryWorkflowRun>>.value(const [])
        : _loadRuns();
    setState(() {
      _repositoryFuture = repository;
      _runsFuture = runs;
    });
    final resolved = await repository;
    ref.invalidate(repositoryProjectInfoProvider(resolved));
    await Future.wait([runs]);
  }

  Future<void> _copyLink(GitHubRepository repository) async {
    await Clipboard.setData(ClipboardData(text: repository.htmlUrl));
    if (mounted) {
      showCenteredNotice(context, 'Link do repositório copiado.');
    }
  }

  Future<void> _forkRepository(GitHubRepository repository) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Criar fork na minha conta?'),
        content: Text(
          'O GitHub criará uma cópia de ${repository.fullName} na sua conta. '
          'A cópia aparecerá em Meus repositórios e poderá ser modificada normalmente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.call_split_rounded),
            label: const Text('Criar fork'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final fork = await ref
          .read(repositoryServiceProvider)
          .forkRepository(repository.fullName);
      if (!mounted) return;
      showCenteredNotice(context, fork.fullName.isEmpty
                ? 'Fork solicitado. O GitHub pode levar alguns segundos para criar a cópia.'
                : 'Fork criado: ${fork.fullName}');
    } catch (error) {
      if (mounted) _showError(error);
    }
  }


  /// Atalho direto: pesquisa releases e artifacts sob demanda, sem bloquear o
  /// botão baseado somente em artifacts do GitHub Actions.
  Future<void> _downloadLatestApk(GitHubRepository repository) async {
    if (_apkShortcutBusy) return;
    setState(() => _apkShortcutBusy = true);
    try {
      // A consulta alimenta tanto o status na tela quanto o atalho de APK.
      // O cache do provider evita duas pesquisas independentes seguidas.
      final apkStatus = await ref.read(
        repositoryApkStatusProvider(repository).future,
      );
      if (!mounted) return;
      final latest = apkStatus.latest;
      final releaseError = apkStatus.releaseError;
      final artifactError = apkStatus.artifactError;
      if (latest.isEmpty) {
        final bothUnavailable = releaseError != null && artifactError != null;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(bothUnavailable
                ? 'Não foi possível consultar os APKs'
                : 'Nenhum APK disponível'),
            content: Text(bothUnavailable
                ? 'O GitHub não respondeu às consultas de Releases e Artifacts. Confira sua conexão e as permissões do token.'
                : releaseError != null || artifactError != null
                    ? 'Nenhum APK encontrado na fonte acessível. Uma das consultas falhou, então o resultado pode estar incompleto.'
                    : 'Este repositório não possui APK publicado nas Releases nem artifact de APK válido. Builds que falharam antes da compilação não geram APK.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fechar'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  context.push('/repositories/${repository.fullName}/artifacts?readOnly=${widget.readOnly ? '1' : '0'}');
                },
                child: const Text('Ver todos os arquivos'),
              ),
            ],
          ),
        );
        return;
      }

      final assessment = apkStatus.assessment;
      if (assessment.state == ApkInstallationState.current ||
          assessment.state == ApkInstallationState.newerInstalled) {
        final continueDownload = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(assessment.state == ApkInstallationState.current
                    ? 'Esta versão já está instalada'
                    : 'O aparelho tem uma versão mais recente'),
                content: Text(
                  'Instalada: ${assessment.installedVersion ?? "desconhecida"}\n'
                  'GitHub: ${assessment.availableVersion ?? "não identificada"}\n\n'
                  '${assessment.detail ?? ""}\n\n'
                  'Deseja escolher um APK para baixar mesmo assim? '
                  'A atualização exige assinatura compatível e confirmação do Android.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Escolher APK'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!mounted || !continueDownload) return;
      }

      AndroidDeviceInfo? deviceInfo;
      try {
        deviceInfo = await PlatformActions.getAndroidDeviceInfo();
      } catch (_) {
        // O usuário ainda pode escolher o arquivo, sem sugestão de ABI.
      }
      if (!mounted) return;

      final options = <SmartApkOption<Object>>[
        for (final asset in latest.releaseAssets)
          SmartApkOption<Object>(
            value: asset,
            name: asset.name,
            bytes: asset.sizeBytes,
            source: 'Release ${asset.tagName}',
          ),
        for (final artifact in latest.artifacts)
          SmartApkOption<Object>(
            value: artifact,
            name: artifact.name,
            bytes: artifact.sizeBytes,
            source: 'Artifact da build',
            exactRun: artifact.workflowRunId != null,
          ),
      ];
      Object? selected;
      if (options.length == 1) {
        selected = options.single.value;
      } else {
        selected = await showSmartApkPicker<Object>(
          context: context,
          options: options,
          project: repository.name,
          runNumber: 0,
          version: latest.version,
          deviceInfo: deviceInfo,
        );
      }
      if (!mounted || selected == null) return;
      final selectedName = selected is ReleaseAsset
          ? selected.name
          : (selected as ActionArtifact).name;
      if (deviceInfo != null &&
          !apkNameIsCompatible(selectedName, deviceInfo.supportedAbis)) {
        final supportedAbisLabel = deviceInfo.supportedAbis.join(', ');
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('APK possivelmente incompatível'),
                content: Text(
                  'O arquivo ${ApkVariantInfo.fromName(selectedName).label} '
                  'não corresponde às arquiteturas informadas pelo seu Android '
                  '($supportedAbisLabel). Deseja baixá-lo mesmo assim?',
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
        if (!mounted || !confirmed) return;
      }

      final manager = ref.read(downloadManagerProvider);
      if (selected is ReleaseAsset) {
        manager.startReleaseAsset(
          title: '${selected.tagName} • ${selected.name}',
          fileName: selected.name,
          repositoryFullName: repository.fullName,
          assetId: selected.id,
          isApk: true,
        );
      } else if (selected is ActionArtifact) {
        manager.startArtifactApk(
          repositoryFullName: repository.fullName,
          artifact: selected,
          preferredAbi: deviceInfo?.primaryAbi,
          supportedAbis: deviceInfo?.supportedAbis,
        );
      }
      if (mounted) {
        showCenteredNotice(
          context,
          'Download iniciado. Acompanhe pela Central de Downloads.',
          kind: CenteredNoticeKind.success,
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _apkShortcutBusy = false);
    }
  }

  Future<void> _sendBuild(GitHubRepository repository) async {
    ZipProjectPreview? project;
    var queued = false;
    try {
      project = await ref.read(localProjectServiceProvider).pickAndAnalyzeZip();
      if (project == null || !mounted) return;

      final selectedBranch = await _chooseUploadBranch(repository);
      if (selectedBranch == null || !mounted) return;
      var targetBranch = selectedBranch;

      late final ManagedUploadBuildPolicy buildPolicy;
      while (true) {
        final preparation = await _prepareUpload(
          project: project,
          repository: repository,
          targetBranch: targetBranch,
        );
        if (preparation == null || !mounted) return;

        if (preparation.permissionDecision.blocked) {
          await presentRepositoryPermissionDecision(
            context,
            preparation.permissionDecision,
          );
          return;
        }

        final confirmation = await _confirmZip(
          project,
          repository,
          preparation.repositoryInfo!,
          targetBranch,
          preparation.branchHasApkWorkflow,
          preparation.syncPreview,
          preparation.rateLimit,
        );
        if (confirmation == null || !mounted) return;

        if (confirmation.changeBranch) {
          final changedBranch = await _chooseUploadBranch(
            repository,
            initialBranchName: targetBranch.name,
          );
          if (!mounted) return;
          if (changedBranch == null) continue;
          targetBranch = changedBranch;
          continue;
        }
        final confirmedPolicy = confirmation.buildPolicy;
        if (confirmedPolicy == null) return;
        buildPolicy = confirmedPolicy;
        break;
      }

      if (buildPolicy == ManagedUploadBuildPolicy.automatic) {
        final buildDecision = await _checkPermissionWithProgress(
          repositoryFullName: repository.fullName,
          action: RepositoryCriticalAction.sendBuild,
          label: 'Verificando permissão para iniciar a build…',
        );
        if (buildDecision == null || !mounted) return;
        final buildAllowed = await presentRepositoryPermissionDecision(
          context,
          buildDecision,
        );
        if (!buildAllowed || !mounted) return;
      }

      final manager = ref.read(uploadManagerProvider);
      final upload = manager.startBuild(
        project: project,
        repositoryFullName: repository.fullName,
        branch: targetBranch.name,
        buildPolicy: buildPolicy,
      );
      queued = true; // Queue owns the snapshot until its durable copy exists.
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => UploadProgressDialog(uploadId: upload.id),
      );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (!queued && project != null && project.managedSnapshot) {
        await LocalProjectService.discardPreviewPath(project.path);
      }
    }
  }

  Future<_UploadPreparation?> _prepareUpload({
    required ZipProjectPreview project,
    required GitHubRepository repository,
    required RepositoryBranch targetBranch,
  }) async {
    final status = ValueNotifier<String>('Verificando permissões da branch…');
    final overlay = _showOperationOverlay(status, targetBranch.name);
    try {
      final action = project.hasWorkflowFiles
          ? RepositoryCriticalAction.syncProjectWithWorkflows
          : RepositoryCriticalAction.syncProject;
      final decision = await ref
          .read(permissionPreflightServiceProvider)
          .check(repository.fullName, action)
          .timeout(const Duration(seconds: 15));
      if (decision.blocked) {
        return _UploadPreparation(permissionDecision: decision);
      }

      status.value = 'Analisando versão, arquivos e workflow…';
      final repositoryInfoFuture = ref
          .read(repositoryProjectInfoServiceProvider)
          .load(repository, branch: targetBranch.name)
          .timeout(const Duration(seconds: 18));
      final syncPreviewFuture = (() async {
        try {
          return await ref
              .read(gitProjectUploadServiceProvider)
              .previewZipSync(
                project: project,
                repositoryFullName: repository.fullName,
                branch: targetBranch.name,
              )
              .timeout(const Duration(seconds: 18));
        } catch (_) {
          return null;
        }
      })();
      final rateLimitFuture = (() async {
        try {
          return await ref
              .read(repositoryGitServiceProvider)
              .loadRateLimit()
              .timeout(const Duration(seconds: 10));
        } catch (_) {
          return null;
        }
      })();
      final workflowFuture = _detectBranchApkWorkflow(
        repository,
        targetBranch,
        project,
      ).timeout(const Duration(seconds: 12), onTimeout: () => null);

      final repositoryInfo = await repositoryInfoFuture;
      final syncPreview = await syncPreviewFuture;
      final rateLimit = await rateLimitFuture;
      final branchHasApkWorkflow = await workflowFuture;
      return _UploadPreparation(
        permissionDecision: decision,
        repositoryInfo: repositoryInfo,
        syncPreview: syncPreview,
        rateLimit: rateLimit,
        branchHasApkWorkflow: branchHasApkWorkflow,
      );
    } finally {
      overlay.remove();
      status.dispose();
    }
  }

  Future<RepositoryPermissionPreflightDecision?> _checkPermissionWithProgress({
    required String repositoryFullName,
    required RepositoryCriticalAction action,
    required String label,
  }) async {
    final status = ValueNotifier<String>(label);
    final overlay = _showOperationOverlay(status, null);
    try {
      return await ref
          .read(permissionPreflightServiceProvider)
          .check(repositoryFullName, action)
          .timeout(const Duration(seconds: 15));
    } finally {
      overlay.remove();
      status.dispose();
    }
  }

  OverlayEntry _showOperationOverlay(
    ValueNotifier<String> status,
    String? branch,
  ) {
    final entry = OverlayEntry(
      builder: (_) => _RepositoryOperationOverlay(
        status: status,
        branch: branch,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    return entry;
  }

  Future<RepositoryBranch?> _chooseUploadBranch(
    GitHubRepository repository, {
    String? initialBranchName,
  }) async {
    final preferenceKey =
        'uploads.last_branch.${repository.fullName.toLowerCase()}';
    dynamic stored;
    try {
      stored = await ref.read(localDatabaseProvider).readJson(preferenceKey);
    } catch (_) {
      // Preferência é best-effort: falha local não pode bloquear o envio.
    }
    if (!mounted) return null;

    final initial = initialBranchName?.trim().isNotEmpty == true
        ? initialBranchName!.trim()
        : stored is String && stored.trim().isNotEmpty
            ? stored.trim()
            : repository.defaultBranch.trim().isEmpty
                ? 'main'
                : repository.defaultBranch.trim();

    final selected = await showRepositoryBranchSelector(
      context: context,
      ref: ref,
      repositoryFullName: repository.fullName,
      currentBranch: initial,
      defaultBranch: repository.defaultBranch,
      emptyBranchName: repository.defaultBranch.trim().isEmpty
          ? 'main'
          : repository.defaultBranch.trim(),
      allowCreate: true,
    );
    if (selected != null) {
      try {
        await ref.read(localDatabaseProvider).putJson(preferenceKey, selected.name);
      } catch (_) {
        // Preferência é best-effort. O envio continua normalmente.
      }
    }
    return selected;
  }

  Future<bool?> _detectBranchApkWorkflow(
    GitHubRepository repository,
    RepositoryBranch targetBranch,
    ZipProjectPreview project,
  ) async {
    if (project.hasWorkflowFiles) return null;

    try {
      return await ref.read(repositoryGitServiceProvider).hasApkBuildWorkflow(
            repositoryFullName: repository.fullName,
            branch: targetBranch.name,
          );
    } catch (_) {
      // A confirmação pode continuar mesmo quando a inspeção de workflow está
      // temporariamente indisponível; a etapa pós-upload fará a validação real.
      return null;
    }
  }

  Future<_ConfirmZipResult?> _confirmZip(
    ZipProjectPreview project,
    GitHubRepository repository,
    RepositoryProjectInfo repositoryInfo,
    RepositoryBranch targetBranch,
    bool? branchHasApkWorkflow,
    ProjectSyncPreview? syncPreview,
    GitHubRateLimitSnapshot? rateLimit,
  ) {
    final check = ProjectSafetyCheck.compare(
      project: project,
      repository: repository,
      repositoryInfo: repositoryInfo,
    );
    final mustBlock = check.blocked || syncPreview == null;
    var buildPolicy = branchHasApkWorkflow == false
        ? ManagedUploadBuildPolicy.skipNoWorkflow
        : ManagedUploadBuildPolicy.automatic;

    return showDialog<_ConfirmZipResult>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        title: Text(mustBlock ? 'Envio bloqueado' : 'Conferir envio'),
        content: AdaptiveDialogBody(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.identityLabel,
                  style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  repository.fullName,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _BuildSafetyRow(
                  label: 'Arquivo escolhido no Android',
                  value: project.name,
                  icon: Icons.folder_zip_outlined,
                ),
                _BuildSafetyRow(
                  label: 'Integridade do ZIP (SHA-256)',
                  value: project.sha256 == null
                      ? 'Não verificada'
                      : project.sha256!.length > 16
                          ? '${project.sha256!.substring(0, 16)}…'
                          : project.sha256!,
                  icon: Icons.fingerprint_rounded,
                ),
                const SizedBox(height: 12),
                _BuildSafetyRow(
                  label: 'Branch de destino',
                  value: targetBranch.isProtected
                      ? '${targetBranch.name} • protegida'
                      : targetBranch.name,
                  icon: targetBranch.isProtected
                      ? Icons.lock_outline_rounded
                      : Icons.account_tree_outlined,
                  actionLabel: 'Alterar',
                  onAction: () => Navigator.pop(
                    dialogContext,
                    const _ConfirmZipResult.changeBranch(),
                  ),
                ),
                _BuildSafetyRow(
                  label: 'Versão: GitHub → ZIP',
                  value: '${repositoryInfo.versionLabel ?? 'Não identificada'}  →  ${project.versionLabel ?? 'Não identificada'}',
                  icon: Icons.compare_arrows_rounded,
                ),
                if (project.version == null && project.inferredVersion != null)
                  Text(
                    'Pista do nome do ZIP: ${project.inferredVersion}. Não usada na comparação.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                const SizedBox(height: 6),
                _UploadSyncSummary(preview: syncPreview,
                  onViewFiles: syncPreview == null
                      ? null : () => _showSyncPreview(dialogContext, syncPreview)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: mustBlock
                        ? Theme.of(dialogContext).colorScheme.errorContainer
                        : check.warning
                            ? Theme.of(dialogContext).colorScheme.tertiaryContainer
                            : Theme.of(dialogContext).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(mustBlock
                          ? Icons.block_rounded
                          : check.warning
                              ? Icons.warning_amber_rounded
                              : Icons.verified_rounded),
                      const SizedBox(width: 9),
                      Expanded(child: Text(
                          syncPreview == null
                              ? 'BLOQUEADO: não foi possível calcular as alterações. '
                                  'Nenhum envio é permitido sem conferir a prévia dos arquivos.'
                              : check.message,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
                if (check.warning || check.blocked ||
                    repositoryInfo.metadataIssue != null ||
                    repositoryInfo.nameSource == null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _showBuildSafetyHelp(
                        dialogContext, project, repositoryInfo, check,
                        repository: repository,
                        branch: targetBranch.name,
                      ),
                      icon: const Icon(Icons.build_outlined),
                      label: const Text('Diagnosticar / Como corrigir'),
                    ),
                  ),
                if (syncPreview != null && syncPreview.deletedCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(
                      'Atenção: ${syncPreview.deletedCount} arquivo(s) serão removidos. Confira a prévia.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 5),
                ExpansionTile(
                  key: const ValueKey('upload_technical_details'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: const Text('Detalhes técnicos e diagnóstico'),
                  leading: const Icon(Icons.info_outline_rounded),
                  children: [
                    _BuildSafetyRow(
                      label: 'Projeto detectado',
                      value: project.identityLabel,
                      icon: Icons.inventory_2_outlined,
                    ),
                    _BuildSafetyRow(
                      label: 'Identidade usada',
                      value: check.identitySource,
                      icon: Icons.fingerprint_rounded,
                    ),
                    _BuildSafetyRow(
                      label: 'Fonte do nome remoto',
                      value: repositoryInfo.nameSource ?? 'Nome do repositório (alternativa)',
                      icon: Icons.text_fields_rounded,
                    ),
                    _BuildSafetyRow(
                      label: 'Versão do ZIP',
                      value: project.displayVersionLabel ?? 'Não identificada',
                      icon: Icons.new_releases_outlined,
                    ),
                    _BuildSafetyRow(
                      label: 'Versão no GitHub',
                      value: repositoryInfo.displayVersionLabel ?? 'Não identificada',
                      icon: Icons.history_rounded,
                    ),
                    if (project.applicationId?.isNotEmpty == true ||
                        repositoryInfo.applicationId?.isNotEmpty == true)
                      _BuildSafetyRow(
                        label: 'Identidade Android',
                        value: '${project.applicationId ?? 'não identificada'} → ${repositoryInfo.applicationId ?? 'não identificada'}',
                        icon: Icons.android_rounded,
                      ),
                    _BuildSafetyRow(
                      label: 'Conteúdo do ZIP',
                      value: '${project.projectType} • ${project.fileCount} arquivos • ${project.folderCount} pastas',
                      icon: Icons.folder_zip_outlined,
                    ),
                    if (rateLimit != null)
                      _BuildSafetyRow(
                        label: 'API GitHub',
                        value: rateLimit.label,
                        icon: Icons.speed_rounded,
                      ),
                    Text(
                      project.hasWorkflowFiles
                          ? 'O ZIP contém workflows do GitHub Actions. Workflows existentes que não vierem no ZIP permanecem protegidos contra remoção acidental.'
                          : branchHasApkWorkflow == true
                              ? 'Workflow de APK detectado nesta branch.'
                              : branchHasApkWorkflow == false
                                  ? 'Esta branch não possui workflow de APK. O envio pode terminar sem build.'
                                  : 'A presença de workflow de APK será verificada após o envio.',
                    ),
                    TextButton.icon(
                      onPressed: () => _showBuildSafetyHelp(
                        dialogContext, project, repositoryInfo, check,
                        repository: repository,
                        branch: targetBranch.name,
                      ),
                      icon: const Icon(Icons.help_outline_rounded),
                      label: const Text('Abrir diagnóstico completo'),
                    ),
                  ],
                ),
                if (branchHasApkWorkflow == false)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(Icons.code_rounded),
                    title: Text('Build não utilizada neste projeto'),
                    subtitle: Text('Os arquivos serão enviados sem iniciar GitHub Actions.'),
                  )
                else
                  StatefulBuilder(
                    builder: (context, setBuildState) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: buildPolicy == ManagedUploadBuildPolicy.automatic,
                      onChanged: (value) => setBuildState(() {
                        buildPolicy = value == true
                            ? ManagedUploadBuildPolicy.automatic
                            : ManagedUploadBuildPolicy.skipByUser;
                      }),
                      title: const Text('Iniciar build após o envio'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: mustBlock
                ? null
                : () async {
                    if (syncPreview!.deletedCount > 0) {
                      final accepted = await _confirmRemovalWithRepositoryName(
                        dialogContext,
                        repository.fullName,
                        syncPreview!.deletedCount,
                      );
                      if (accepted != true || !dialogContext.mounted) return;
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext,
                          _ConfirmZipResult.submit(buildPolicy));
                    }
                  },
            icon: Icon(mustBlock || check.warning
                ? Icons.warning_amber_rounded : Icons.cloud_upload_outlined),
            label: Text(mustBlock
                ? 'Envio bloqueado'
                : (syncPreview?.deletedCount ?? 0) > 0
                    ? 'Conferir remoções'
                    : check.warning ? 'Enviar mesmo assim' : 'Enviar versão'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmRemovalWithRepositoryName(
    BuildContext parent,
    String fullName,
    int deletedCount,
  ) async {
    final typed = TextEditingController();
    try {
      return await showDialog<bool>(
        context: parent,
        builder: (dialog) => StatefulBuilder(
          builder: (context, refresh) => AlertDialog(
            title: const Text('Confirmar remoção de arquivos'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('O envio removerá $deletedCount arquivo(s) de $fullName. '
                    'Digite o nome completo do repositório para autorizar.'),
                const SizedBox(height: 12),
                TextField(
                  controller: typed,
                  onChanged: (_) => refresh(() {}),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'Repositório (owner/nome)',
                    hintText: fullName,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: typed.text.trim() == fullName
                    ? () => Navigator.pop(dialog, true) : null,
                child: const Text('Autorizar remoções'),
              ),
            ],
          ),
        ),
      );
    } finally {
      typed.dispose();
    }
  }

  Future<void> _showSyncPreview(
    BuildContext parentContext,
    ProjectSyncPreview preview,
  ) async {
    // Agrupa por diretório, mantendo acesso ao caminho integral e às remoções.
    Widget section(String title, List<String> paths, IconData icon,
        {bool expanded = false}) {
      if (paths.isEmpty) return const SizedBox.shrink();
      final grouped = <String, List<String>>{};
      for (final path in paths) {
        final parts = path.split('/');
        final directory = parts.length > 2
            ? parts.take(2).join('/')
            : parts.length == 2 ? parts.first : 'Raiz';
        grouped.putIfAbsent(directory, () => <String>[]).add(path);
      }
      return ExpansionTile(
        initiallyExpanded: expanded,
        leading: Icon(icon, size: 20),
        title: Text('$title (${paths.length})',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        children: [
          for (final group in grouped.entries)
            ExpansionTile(
              key: ValueKey('$title:${group.key}'),
              title: Text(group.key, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${group.value.length} arquivo(s)'),
              children: [
                for (final path in group.value)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 34, right: 12),
                    title: Text(path.split('/').last,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onLongPress: () async {
                      await Clipboard.setData(ClipboardData(text: path));
                      if (parentContext.mounted) {
                        showCenteredNotice(parentContext, 'Caminho copiado.');
                      }
                    },
                    trailing: IconButton(
                      tooltip: 'Copiar caminho completo',
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: path));
                        if (parentContext.mounted) {
                          showCenteredNotice(parentContext, 'Caminho copiado.');
                        }
                      },
                    ),
                  ),
              ],
            ),
        ],
      );
    }

    await showDialog<void>(
      context: parentContext,
      builder: (dialogContext) {
        final screen = MediaQuery.sizeOf(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 840,
              maxHeight: screen.height * .90,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                  child: Row(children: [
                    const Expanded(child: Text('Prévia das alterações',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20))),
                    IconButton(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(spacing: 7, runSpacing: 6, children: [
                    Chip(label: Text('${preview.createdCount} novos')),
                    Chip(label: Text('${preview.modifiedCount} alterados')),
                    Chip(
                      avatar: Icon(Icons.warning_amber_rounded,
                          size: 18, color: Theme.of(dialogContext).colorScheme.error),
                      label: Text('${preview.deletedCount} removidos'),
                    ),
                    Chip(label: Text('${preview.unchangedCount} iguais')),
                  ]),
                ),
                const Divider(height: 14),
                Expanded(
                  child: ListView(
                    children: [
                      // Remoções são sempre visíveis primeiro por segurança.
                      section('Removidos', preview.deletedPaths,
                          Icons.delete_outline_rounded, expanded: true),
                      section('Novos', preview.createdPaths,
                          Icons.add_circle_outline_rounded),
                      section('Alterados', preview.modifiedPaths,
                          Icons.edit_outlined),
                      if (!preview.hasChanges)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('O ZIP já corresponde ao conteúdo desta branch.'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Fechar'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBuildSafetyHelp(
    BuildContext parentContext,
    ZipProjectPreview project,
    RepositoryProjectInfo repositoryInfo,
    ProjectSafetyCheck check, {
    required GitHubRepository repository,
    required String branch,
  }) async {
    final guidance = UploadIdentificationDiagnosis.guidance(
      project: project,
      remote: repositoryInfo,
      repository: repository,
      check: check,
    );
    final report = UploadIdentificationDiagnosis.report(
      project: project,
      remote: repositoryInfo,
      repository: repository,
      branch: branch,
      check: check,
    );
    await showDialog<void>(
      context: parentContext,
      builder: (helpContext) => AlertDialog(
        title: const Text('Diagnóstico de identificação'),
        content: AdaptiveDialogBody(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('O que foi encontrado',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _BuildSafetyRow(
                  label: 'ZIP • ${project.identityLabel}',
                  value: project.displayVersionLabel ?? 'Versão interna não identificada',
                  icon: Icons.folder_zip_outlined,
                ),
                _BuildSafetyRow(
                  label: 'GitHub • ${repositoryInfo.projectName}',
                  value: repositoryInfo.displayVersionLabel ?? 'Versão não identificada na branch',
                  icon: Icons.cloud_outlined,
                ),
                _BuildSafetyRow(
                  label: 'Origem do nome remoto',
                  value: repositoryInfo.nameSource ?? 'Nome do repositório (alternativa)',
                  icon: Icons.text_fields_outlined,
                ),
                const SizedBox(height: 8),
                const Text('Como corrigir / O que conferir',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                ...guidance.asMap().entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('${entry.key + 1}. ${entry.value}'),
                    )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (helpContext.mounted) {
                showCenteredNotice(helpContext, 'Diagnóstico copiado (sem token).');
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar diagnóstico'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(helpContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  void _downloadProjectZip(
    GitHubRepository repository,
    RepositoryProjectInfo info,
  ) {
    ref.read(downloadManagerProvider).startRepositoryZip(
          repositoryFullName: repository.fullName,
          branch: repository.defaultBranch,
          projectName: info.projectName,
          version: info.version,
        );
    showCenteredNotice(context, 'Download do projeto iniciado em ZIP.');
  }

  Future<void> _manageRepository(GitHubRepository repository) async {
    final favoriteIds = await ref.read(favoriteRepositoryIdsProvider.future);
    if (!mounted) return;
    final isFavorite = favoriteIds.contains(repository.id);
    final action = await showRepositoryActionsSheet(
      context,
      repository,
      isFavorite: isFavorite,
    );
    if (action == null || !mounted) return;

    if (action == RepositoryAction.toggleFavorite) {
      try {
        await ref.read(repositoryServiceProvider).setRepositoryFavorite(
              repository,
              favorite: !isFavorite,
            );
        ref.invalidate(favoriteRepositoryIdsProvider);
        if (mounted) {
          showCenteredNotice(
            context,
            isFavorite
                ? '${repository.name} não ficará mais fixado no topo.'
                : '${repository.name} fixado no topo.',
            kind: CenteredNoticeKind.success,
          );
        }
      } catch (error) {
        if (mounted) _showError(error);
      }
    } else if (action == RepositoryAction.edit) {
      final result = await showEditRepositoryDialog(context, repository);
      if (result == null || !mounted) return;
      try {
        final updated = await ref.read(repositoryServiceProvider).updateRepository(
              fullName: repository.fullName,
              name: result.name,
              description: result.description,
              homepage: result.homepage,
              isPrivate: result.isPrivate,
              isArchived: result.isArchived,
            );
        if (!mounted) return;
        if (updated.fullName != widget.repositoryFullName) {
          context.go('/repositories/${updated.fullName}');
          return;
        }
        ref.invalidate(repositoryProjectInfoProvider(updated));
        showCenteredNotice(
          context,
          'Repositório ${updated.name} atualizado com sucesso.',
          kind: CenteredNoticeKind.success,
        );
      } catch (error) {
        if (mounted) _showError(error);
      }
    } else if (action == RepositoryAction.rename) {
      final newName = await showRenameRepositoryDialog(context, repository);
      if (newName == null || !mounted) return;
      try {
        final renamed = await ref.read(repositoryServiceProvider).renameRepository(
              fullName: repository.fullName,
              newName: newName,
            );
        ref
            .read(permissionPreflightServiceProvider)
            .invalidateRepository(repository.fullName);
        ref.invalidate(repositoryProjectInfoProvider(repository));
        ref.invalidate(favoriteRepositoryIdsProvider);
        if (!mounted) return;
        showCenteredNotice(
          context,
          'Repositório renomeado para ${renamed.name}.',
          kind: CenteredNoticeKind.success,
        );
        context.go('/repositories/${renamed.fullName}');
      } catch (error) {
        if (mounted) _showError(error);
      }
    } else if (action == RepositoryAction.delete) {
      final allowed = await ensureRepositoryPermission(
        context,
        ref,
        repositoryFullName: repository.fullName,
        action: RepositoryCriticalAction.deleteRepository,
      );
      if (!allowed || !mounted) return;
      final confirmed = await showDeleteRepositoryDialog(context, repository);
      if (confirmed != true || !mounted) return;
      try {
        await ref.read(repositoryServiceProvider).deleteRepository(repository.fullName);
        ref.invalidate(favoriteRepositoryIdsProvider);
        if (mounted) context.go('/');
      } catch (error) {
        if (mounted) _showError(error);
      }
    }
  }

  void _showError(Object error) {
    final message = error is TimeoutException
        ? 'O GitHub demorou para responder. Tente novamente.'
        : error is AppException
            ? error.message
            : 'Não foi possível concluir a operação.';
    showCenteredNotice(context, message);
  }

}

class _UploadPreparation {
  const _UploadPreparation({
    required this.permissionDecision,
    this.repositoryInfo,
    this.syncPreview,
    this.rateLimit,
    this.branchHasApkWorkflow,
  });

  final RepositoryPermissionPreflightDecision permissionDecision;
  final RepositoryProjectInfo? repositoryInfo;
  final ProjectSyncPreview? syncPreview;
  final GitHubRateLimitSnapshot? rateLimit;
  final bool? branchHasApkWorkflow;
}

class _ConfirmZipResult {
  const _ConfirmZipResult.submit(this.buildPolicy) : changeBranch = false;

  const _ConfirmZipResult.changeBranch()
      : buildPolicy = null,
        changeBranch = true;

  final ManagedUploadBuildPolicy? buildPolicy;
  final bool changeBranch;
}
