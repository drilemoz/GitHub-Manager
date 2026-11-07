import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/core/providers/core_providers.dart';
import 'package:github_manager/core/widgets/adaptive_dialog.dart';
import 'package:github_manager/core/widgets/app_main_navigation.dart';
import 'package:github_manager/core/widgets/centered_notice.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/builds/domain/apk_installation_assessment.dart';
import 'package:github_manager/features/builds/domain/apk_variant.dart';
import 'package:github_manager/features/builds/domain/release_asset.dart';
import 'package:github_manager/features/builds/presentation/smart_apk_picker.dart';
import 'package:github_manager/features/builds/presentation/build_providers.dart';
import 'package:github_manager/features/downloads/presentation/download_center_button.dart';
import 'package:github_manager/features/downloads/presentation/download_providers.dart';
import 'package:github_manager/features/permissions/domain/repository_permission_preflight.dart';
import 'package:github_manager/features/permissions/presentation/permission_preflight_guard.dart';
import 'package:github_manager/features/permissions/presentation/token_permission_providers.dart';
import 'package:github_manager/features/projects/domain/project_safety_check.dart';
import 'package:github_manager/features/projects/domain/upload_identification_diagnosis.dart';
import 'package:github_manager/features/projects/domain/zip_project.dart';
import 'package:github_manager/features/projects/presentation/project_providers.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/domain/repository_git_models.dart';
import 'package:github_manager/features/repositories/domain/repository_project_info.dart';
import 'package:github_manager/features/repositories/presentation/repository_branch_selector.dart';
import 'package:github_manager/features/repositories/presentation/repository_management_dialogs.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';
import 'package:github_manager/features/repositories/presentation/repository_apk_status_provider.dart';
import 'package:github_manager/features/repositories/presentation/technology_badge.dart';
import 'package:github_manager/features/repositories/presentation/play_readiness_dialog.dart';
import 'package:github_manager/features/repositories/data/play_readiness_service.dart';
import 'package:github_manager/features/repositories/data/play_aab_discovery_service.dart';
import 'package:github_manager/features/uploads/domain/managed_upload.dart';
import 'package:github_manager/features/uploads/presentation/upload_center_button.dart';
import 'package:github_manager/features/uploads/presentation/upload_progress_dialog.dart';
import 'package:github_manager/features/uploads/presentation/upload_providers.dart';

part 'repository_detail_widgets.dart';
part 'repository_detail_screen_actions.dart';

class RepositoryDetailScreen extends ConsumerStatefulWidget {
  const RepositoryDetailScreen({
    required this.repositoryFullName,
    this.readOnly = false,
    super.key,
  });

  final String repositoryFullName;
  final bool readOnly;

  @override
  ConsumerState<RepositoryDetailScreen> createState() =>
      _RepositoryDetailScreenState();
}

class _RepositoryDetailScreenState extends ConsumerState<RepositoryDetailScreen>
    with _RepositoryDetailScreenActions, WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    initializeRepositoryDetailState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ao voltar do instalador do Android, atualiza a versão sem reiniciar o app.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.invalidate(repositoryApkStatusProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const AppMainNavigation(selectedIndex: 0),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<GitHubRepository>(
          future: _repositoryFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _RepositoryLoadingView(
                repositoryFullName: widget.repositoryFullName,
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _RepositoryErrorView(
                repositoryFullName: widget.repositoryFullName,
                message: _message(snapshot.error),
                onRetry: _retryRepositoryLoad,
              );
            }

            final repository = snapshot.data!;
            final infoAsync = ref.watch(repositoryProjectInfoProvider(repository));
            final info = infoAsync.maybeWhen(
              data: (value) => value,
              orElse: () => RepositoryProjectInfo(
                projectName: repository.name,
                version: null,
                technologies: [
                  if (repository.language != null) repository.language!,
                ],
              ),
            );

            final apkStatusAsync = ref.watch(repositoryApkStatusProvider(repository));
            final apkStatus = apkStatusAsync.asData?.value;
            final assessment = apkStatus?.assessment;

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  surfaceTintColor: Theme.of(context).colorScheme.surface,
                  scrolledUnderElevation: 2,
                  title: Text(
                    info.projectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    IconButton(
                      onPressed: () => _downloadProjectZip(repository, info),
                      tooltip: 'Baixar ZIP do projeto',
                      icon: const Icon(Icons.folder_zip_outlined),
                    ),
                    const UploadCenterButton(),
                    const DownloadCenterButton(),
                    if (!widget.readOnly)
                      IconButton(
                        onPressed: () => _manageRepository(repository),
                        tooltip: 'Gerenciar repositório',
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: _RepositoryHeader(
                      repository: repository,
                      info: info,
                      runsFuture: _runsFuture,
                      readOnly: widget.readOnly,
                      detailsLoading: infoAsync.isLoading,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 9, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        if (!widget.readOnly) ...[
                          Expanded(
                            child: _CompactQuickAction(
                              icon: Icons.cloud_upload_outlined,
                              label: 'Enviar',
                              filled: true,
                              onTap: () => _sendBuild(repository),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: _CompactQuickAction(
                            icon: widget.readOnly
                                ? Icons.call_split_rounded
                                : Icons.open_in_new_rounded,
                            label: widget.readOnly ? 'Fork' : 'GitHub',
                            filled: widget.readOnly,
                            onTap: widget.readOnly
                                ? () => _forkRepository(repository)
                                : () => PlatformActions.openUri(repository.htmlUrl),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CompactQuickAction(
                            icon: Icons.copy_rounded,
                            label: 'Copiar',
                            onTap: () => _copyLink(repository),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CompactQuickAction(
                            icon: _apkShortcutBusy
                                ? Icons.hourglass_top_rounded
                                : Icons.android_rounded,
                            label: _apkShortcutBusy
                                ? 'Buscando'
                                : switch (assessment?.state) {
                                    ApkInstallationState.install => 'Instalar',
                                    ApkInstallationState.update => 'Atualizar',
                                    ApkInstallationState.current => 'Atualizado',
                                    _ => 'APK',
                                  },
                            enabled: !_apkShortcutBusy,
                            onTap: () => _downloadLatestApk(repository),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CompactQuickAction(
                            icon: Icons.storefront_outlined,
                            label: 'Play',
                            onTap: () => showPlayReadinessDialog(
                              context: context,
                              repository: repository,
                              service: PlayReadinessService(
                                ref.read(githubApiClientProvider),
                              ),
                              aabService: PlayAabDiscoveryService(
                                ref.read(artifactServiceProvider),
                                ref.read(githubApiClientProvider),
                              ),
                              downloads: ref.read(downloadManagerProvider),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (assessment != null &&
                    (assessment.packageName != null || apkStatus!.latest.isEmpty == false))
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(14, 7, 14, 0),
                    sliver: SliverToBoxAdapter(
                      child: _RepositoryApkInstallationStatus(assessment: assessment),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'Projeto',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 7)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 22),
                  sliver: SliverList.list(
                    children: [
                      _WorkspaceTile(
                        icon: Icons.folder_open_rounded,
                        title: 'Arquivos',
                        subtitle: widget.readOnly
                            ? 'Navegar pelas pastas e visualizar arquivos'
                            : 'Navegar, editar, criar, excluir e enviar arquivos',
                        onTap: () => context.push(
                          '/repositories/${repository.fullName}/files?branch=${Uri.encodeQueryComponent(repository.defaultBranch)}&readOnly=${widget.readOnly ? '1' : '0'}',
                        ),
                      ),
                      const SizedBox(height: 7),
                      _WorkspaceTile(
                        icon: Icons.play_circle_outline_rounded,
                        title: 'Builds',
                        subtitle: 'Executar, acompanhar etapas, abrir logs e baixar APK',
                        onTap: () => context.push(
                          '/repositories/${repository.fullName}/builds?branch=${Uri.encodeQueryComponent(repository.defaultBranch)}&readOnly=${widget.readOnly ? '1' : '0'}',
                        ),
                      ),
                      if (!widget.readOnly) ...[
                        const SizedBox(height: 7),
                        _WorkspaceTile(
                          icon: Icons.cloud_upload_outlined,
                          title: 'Central de envios',
                          subtitle: 'Acompanhar sincronizações, fila, falhas e builds iniciadas',
                          onTap: () => context.push('/uploads'),
                        ),
                      ],
                      const SizedBox(height: 7),
                      _WorkspaceTile(
                        icon: Icons.menu_book_outlined,
                        title: 'README',
                        subtitle: 'Ler a apresentação e documentação do projeto',
                        onTap: () => context.push(
                          '/repositories/${repository.fullName}/readme?branch=${Uri.encodeQueryComponent(repository.defaultBranch)}',
                        ),
                      ),
                      if (!widget.readOnly) ...[
                        const SizedBox(height: 7),
                        _WorkspaceTile(
                          icon: Icons.key_rounded,
                          title: 'Secrets',
                          subtitle: 'Adicionar, importar, substituir e excluir Secrets',
                          onTap: () => context.push(
                            '/repositories/${repository.fullName}/secrets',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _message(Object? error) => error is TimeoutException
      ? 'O GitHub demorou para responder. Verifique a conexão e tente novamente.'
      : error is AppException
          ? error.message
          : 'Não foi possível carregar este repositório.';
}
