import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';

class RepositoryCard extends ConsumerWidget {
  const RepositoryCard({
    required this.repository,
    this.onTap,
    this.onMenu,
    this.onOpenExternal,
    this.onCopyLink,
    this.onFork,
    this.readOnly = false,
    this.isFavorite = false,
    super.key,
  });

  final GitHubRepository repository;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  final VoidCallback? onOpenExternal;
  final VoidCallback? onCopyLink;
  final VoidCallback? onFork;
  final bool readOnly;
  final bool isFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final showDescription =
        ref.watch(showRepositoryDescriptionsProvider).asData?.value ?? false;
    final description = repository.description?.trim() ?? '';
    final info = readOnly ? null : ref.watch(repositoryProjectSummaryProvider(repository));
    final projectName = info?.maybeWhen(
          data: (value) => value.projectName,
          orElse: () => repository.name,
        ) ??
        repository.name;
    final version = info?.maybeWhen(
      data: (value) => value.version,
      orElse: () => null,
    );

    final inheritedShape = Theme.of(context).cardTheme.shape;
    final inheritedSide = inheritedShape is RoundedRectangleBorder
        ? inheritedShape.side
        : BorderSide(color: scheme.outlineVariant);

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: inheritedSide,
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              letterSpacing: -.25,
                              color: scheme.onSurface,
                            ),
                        children: [
                          TextSpan(text: projectName),
                          if (version?.isNotEmpty == true)
                            TextSpan(
                              text: '  v$version',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          if (repository.sizeKb > 0)
                            TextSpan(
                              text: '  •  ${formatRepositorySize(repository.sizeKb)}',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          if (repository.isPrivate)
                            TextSpan(
                              text: '  •  Privado',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            )
                          else
                            TextSpan(
                              text: '  •  Público',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (isFavorite && !readOnly)
                    Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                    ),
                  if (repository.isArchived)
                    const Padding(
                      padding: EdgeInsets.only(left: 7),
                      child: Icon(Icons.archive_outlined, size: 16),
                    ),
                  if (readOnly && onFork != null)
                    IconButton(
                      onPressed: onFork,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Criar fork',
                      icon: const Icon(Icons.call_split_rounded, size: 20),
                    ),
                  IconButton(
                    onPressed: onMenu,
                    visualDensity: VisualDensity.compact,
                    tooltip: readOnly
                        ? 'Remover dos acompanhados'
                        : 'Gerenciar repositório',
                    icon: const Icon(Icons.more_vert_rounded, size: 21),
                  ),
                ],
              ),
              if (showDescription && description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  softWrap: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String formatRepositorySize(int sizeKb) {
  if (sizeKb <= 0) return '0 KB';
  if (sizeKb < 1024) return '$sizeKb KB';
  final sizeMb = sizeKb / 1024;
  if (sizeMb < 1024) {
    return '${_compactSizeNumber(sizeMb)} MB';
  }
  return '${_compactSizeNumber(sizeMb / 1024)} GB';
}

String _compactSizeNumber(double value) {
  if (value >= 100 || value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1).replaceFirst('.', ',');
}
