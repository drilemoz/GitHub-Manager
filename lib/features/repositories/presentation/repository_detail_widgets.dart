part of 'repository_detail_screen.dart';


class _RepositoryApkInstallationStatus extends StatelessWidget {
  const _RepositoryApkInstallationStatus({required this.assessment});

  final ApkInstallationAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, accent, soft) = switch (assessment.state) {
      ApkInstallationState.install => (
        Icons.cancel_outlined,
        scheme.error,
        scheme.errorContainer.withValues(alpha: .32),
      ),
      ApkInstallationState.update => (
        Icons.system_update_alt_rounded,
        scheme.primary,
        scheme.primaryContainer.withValues(alpha: .24),
      ),
      ApkInstallationState.current => (
        Icons.verified_rounded,
        Colors.green.shade700,
        Colors.green.shade50,
      ),
      ApkInstallationState.newerInstalled => (
        Icons.phone_android_rounded,
        Colors.teal.shade700,
        Colors.teal.shade50,
      ),
      ApkInstallationState.noApk => (
        Icons.archive_outlined,
        scheme.error,
        scheme.errorContainer.withValues(alpha: .22),
      ),
      ApkInstallationState.unknown => (
        Icons.help_outline_rounded,
        scheme.tertiary,
        scheme.tertiaryContainer.withValues(alpha: .24),
      ),
    };
    final installed = assessment.installedVersion?.trim();
    final available = assessment.availableVersion?.trim();
    final installedLabel = switch (assessment.state) {
      ApkInstallationState.install => 'Não instalado',
      _ => installed?.isNotEmpty == true ? installed! : 'não confirmado',
    };
    final githubLabel = available?.isNotEmpty == true ? available! : 'não identificada';
    final title = switch (assessment.state) {
      ApkInstallationState.install => 'APK não instalado',
      ApkInstallationState.update => 'APK com atualização disponível',
      ApkInstallationState.current => 'APK atualizado',
      ApkInstallationState.newerInstalled => 'APK mais recente no aparelho',
      ApkInstallationState.noApk => 'APK indisponível',
      ApkInstallationState.unknown => 'Status do APK inconclusivo',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: .40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      assessment.label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusInfoChip(
                label: 'No aparelho',
                value: installedLabel,
                emphasized: assessment.state == ApkInstallationState.install,
                accent: assessment.state == ApkInstallationState.install ? scheme.error : null,
              ),
              _StatusInfoChip(label: 'GitHub', value: githubLabel),
              if (assessment.packageName?.isNotEmpty == true)
                _StatusInfoChip(label: 'Pacote', value: assessment.packageName!),
            ],
          ),
          if (assessment.detail != null) ...[
            const SizedBox(height: 10),
            Text(
              assessment.detail!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: assessment.state == ApkInstallationState.install
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                    fontWeight: assessment.state == ApkInstallationState.install
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusInfoChip extends StatelessWidget {
  const _StatusInfoChip({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.accent,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = accent ?? (emphasized ? scheme.error : scheme.onSurface);
    final background = emphasized
        ? scheme.errorContainer.withValues(alpha: .34)
        : scheme.surface.withValues(alpha: .72);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasized
              ? scheme.error.withValues(alpha: .28)
              : scheme.outlineVariant.withValues(alpha: .35),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: emphasized ? foreground : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _RepositoryHeader extends StatelessWidget {
  const _RepositoryHeader({
    required this.repository,
    required this.info,
    required this.runsFuture,
    required this.readOnly,
    required this.detailsLoading,
  });

  final GitHubRepository repository;
  final RepositoryProjectInfo info;
  final Future<List<RepositoryWorkflowRun>> runsFuture;
  final bool readOnly;
  final bool detailsLoading;

  Future<void> _showProjectInfo(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Informações do projeto',
                        style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ProjectInfoLine(label: 'Projeto', value: info.projectName),
                _ProjectInfoLine(
                  label: 'Versão',
                  value: info.version?.isNotEmpty == true ? 'v${info.version}' : 'Não identificada',
                ),
                _ProjectInfoLine(label: 'SDK Android', value: info.sdkLabel),
                _ProjectInfoLine(label: 'Repositório', value: repository.fullName),
                _ProjectInfoLine(label: 'Branch', value: repository.defaultBranch),
                _ProjectInfoLine(
                  label: 'Acesso',
                  value: repository.isPrivate ? 'Privado' : 'Público',
                ),
                if (readOnly)
                  const _ProjectInfoLine(label: 'Modo', value: 'Somente leitura'),
                const SizedBox(height: 10),
                Text(
                  'Tecnologias',
                  style: Theme.of(dialogContext).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 7),
                if (info.technologies.isEmpty)
                  Text(
                    'Nenhuma tecnologia identificada.',
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: info.technologies
                        .map((item) => TechnologyBadge(name: item))
                        .toList(growable: false),
                  ),
                const SizedBox(height: 12),
                FutureBuilder<List<RepositoryWorkflowRun>>(
                  future: runsFuture,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    final latest = data != null && data.isNotEmpty ? data.first : null;
                    final value = latest == null
                        ? 'Sem builds carregadas'
                        : latest.isRunning
                            ? 'Build em execução'
                            : latest.conclusion == 'success'
                                ? 'Última build concluída com sucesso'
                                : latest.conclusion == 'failure'
                                    ? 'Última build falhou'
                                    : 'Build ${latest.status}';
                    return _ProjectInfoLine(label: 'Build', value: value);
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Fechar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (info.version?.isNotEmpty == true)
                          _HeaderMetaChip(
                            icon: Icons.sell_outlined,
                            label: 'v${info.version}',
                            highlighted: true,
                          ),
                        if (info.targetSdk != null)
                          _HeaderMetaChip(
                            icon: Icons.android_outlined,
                            label: 'SDK ${info.targetSdk}',
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      info.projectName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ],
                ),
              ),
              _RepositoryHeaderShortcut(
                tooltip: 'APKs e artifacts',
                icon: Icons.android_rounded,
                onPressed: () => context.push(
                  '/repositories/${repository.fullName}/artifacts?readOnly=${readOnly ? '1' : '0'}',
                ),
              ),
              _RepositoryHeaderShortcut(
                tooltip: 'Commits',
                icon: Icons.commit_rounded,
                onPressed: () => context.push(
                  '/repositories/${repository.fullName}/commits?branch=${Uri.encodeQueryComponent(repository.defaultBranch)}&readOnly=${readOnly ? '1' : '0'}',
                ),
              ),
              if (!readOnly)
                _RepositoryHeaderShortcut(
                  tooltip: 'Diagnóstico do token',
                  icon: Icons.verified_user_outlined,
                  onPressed: () => context.push(
                    '/repositories/${repository.fullName}/permissions',
                  ),
                ),
              if (!readOnly)
                _RepositoryHeaderShortcut(
                  tooltip: 'Issues / Bugs',
                  icon: Icons.bug_report_outlined,
                  onPressed: () => context.push(
                    '/repositories/${repository.fullName}/bugs',
                  ),
                ),
              _RepositoryHeaderShortcut(
                tooltip: 'Informações do projeto',
                icon: Icons.help_outline_rounded,
                onPressed: () => _showProjectInfo(context),
              ),
            ],
          ),
          Text(
            repository.fullName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          if (info.targetSdk != null || info.minSdk != null || info.compileSdk != null) ...[
            const SizedBox(height: 7),
            Text(
              info.sdkLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
          if (repository.description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Text(
              repository.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (detailsLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 5),
            Text(
              'Atualizando versão e tecnologias…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderMetaChip extends StatelessWidget {
  const _HeaderMetaChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primaryContainer.withValues(alpha: .78)
            : scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? scheme.primary.withValues(alpha: .28)
              : scheme.outlineVariant.withValues(alpha: .26),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: highlighted ? scheme.primary : scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: highlighted ? scheme.primary : scheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class _RepositoryHeaderShortcut extends StatelessWidget {
  const _RepositoryHeaderShortcut({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        icon: Icon(icon, size: 20),
      );
}

class _ProjectInfoLine extends StatelessWidget {
  const _ProjectInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      );
}

class _BuildSafetyRow extends StatelessWidget {
  const _BuildSafetyRow({
    required this.label,
    required this.value,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      );
}

class _CompactQuickAction extends StatelessWidget {
  const _CompactQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final callback = enabled ? onTap : null;
    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    );
    return SizedBox(
      height: 46,
      child: filled
          ? FilledButton(
              onPressed: callback,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Tooltip(message: label, child: child),
            )
          : OutlinedButton(
              onPressed: callback,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                visualDensity: VisualDensity.compact,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .48),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Tooltip(message: label, child: child),
            ),
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .34),
          ),
        ),
        child: ListTile(
          onTap: onTap,
          dense: true,
          visualDensity: const VisualDensity(vertical: -1),
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      );
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

class _RepositoryOperationOverlay extends StatelessWidget {
  const _RepositoryOperationOverlay({
    required this.status,
    required this.branch,
  });

  final ValueListenable<String> status;
  final String? branch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: .18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preparando envio',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (branch?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Branch: $branch',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                        const SizedBox(height: 7),
                        ValueListenableBuilder<String>(
                          valueListenable: status,
                          builder: (_, value, __) => Text(value),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RepositoryLoadingView extends StatelessWidget {
  const _RepositoryLoadingView({required this.repositoryFullName});

  final String repositoryFullName;

  @override
  Widget build(BuildContext context) {
    final name = repositoryFullName.split('/').last;
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(
          pinned: true,
          title: Text(name.isEmpty ? 'Projeto' : name),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: .38),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Carregando projeto' : name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    repositoryFullName,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  const LinearProgressIndicator(minHeight: 3),
                  const SizedBox(height: 8),
                  Text(
                    'Carregando dados do GitHub… A tela será preenchida por partes.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
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
            children: const [
              _RepositoryLoadingTile(
                icon: Icons.menu_book_outlined,
                title: 'README',
              ),
              SizedBox(height: 7),
              _RepositoryLoadingTile(
                icon: Icons.folder_open_rounded,
                title: 'Arquivos',
              ),
              SizedBox(height: 7),
              _RepositoryLoadingTile(
                icon: Icons.play_circle_outline_rounded,
                title: 'Builds',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RepositoryLoadingTile extends StatelessWidget {
  const _RepositoryLoadingTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: const Text('Carregando…'),
          trailing: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

class _RepositoryErrorView extends StatelessWidget {
  const _RepositoryErrorView({
    required this.repositoryFullName,
    required this.message,
    required this.onRetry,
  });

  final String repositoryFullName;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final name = repositoryFullName.split('/').last;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverAppBar(title: Text(name.isEmpty ? 'Projeto' : name)),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 30),
                    const SizedBox(height: 12),
                    Text(
                      'Não foi possível concluir o carregamento',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(message),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Resumo dos arquivos que serão efetivamente sincronizados.
class _UploadSyncSummary extends StatelessWidget {
  const _UploadSyncSummary({required this.preview, required this.onViewFiles});

  final ProjectSyncPreview? preview;
  final VoidCallback? onViewFiles;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sync = preview;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Alterações no repositório',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (sync == null)
            const Text('Prévia indisponível nesta tentativa. Confira o destino antes do envio.')
          else ...[
            Row(children: [
              Expanded(child: _UploadCount(value: sync.createdCount,
                  caption: 'Novos', color: scheme.primary)),
              Expanded(child: _UploadCount(value: sync.modifiedCount,
                  caption: 'Alterados', color: scheme.onSurface)),
              Expanded(child: _UploadCount(value: sync.deletedCount,
                  caption: 'Removidos',
                  color: sync.deletedCount > 0 ? scheme.error : scheme.onSurface)),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onViewFiles,
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('Ver arquivos'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UploadCount extends StatelessWidget {
  const _UploadCount({required this.value, required this.caption,
      required this.color});
  final int value;
  final String caption;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: color, fontWeight: FontWeight.w800,
              )),
          Text(caption, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}
