import 'package:flutter/material.dart';
import 'package:github_manager/core/widgets/app_main_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/widgets/adaptive_dialog.dart';
import 'package:github_manager/core/widgets/centered_notice.dart';
import 'package:github_manager/features/permissions/domain/repository_permission_preflight.dart';
import 'package:github_manager/features/permissions/presentation/permission_preflight_guard.dart';
import 'package:github_manager/features/secrets/data/repository_secrets_service.dart';
import 'package:github_manager/features/secrets/domain/repository_secret.dart';
import 'package:github_manager/features/secrets/presentation/secrets_providers.dart';
import 'package:go_router/go_router.dart';

part 'repository_secrets_actions.dart';
part 'repository_secrets_widgets.dart';

class RepositorySecretsScreen extends ConsumerStatefulWidget {
  const RepositorySecretsScreen({required this.repositoryFullName, super.key});

  final String repositoryFullName;

  @override
  ConsumerState<RepositorySecretsScreen> createState() =>
      _RepositorySecretsScreenState();
}

class _RepositorySecretsScreenState extends ConsumerState<RepositorySecretsScreen>
    with _RepositorySecretsActions {

  @override
  Widget build(BuildContext context) {
    final secrets =
        ref.watch(repositorySecretsProvider(widget.repositoryFullName));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      bottomNavigationBar: const AppMainNavigation(selectedIndex: 0),
      appBar: AppBar(
        title: const Text('Secrets'),
        actions: [
          IconButton(
            onPressed: _working ? null : _refresh,
            tooltip: 'Atualizar',
            icon: _working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 3, 12, 5),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Valores protegidos • até 48 KB por Secret',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                Tooltip(
                  message:
                      'O GitHub exibe apenas nome e datas. Os valores não são mostrados nos diagnósticos.',
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 3, 10, 7),
            child: Row(
              children: [
                Expanded(
                  child: _SecretQuickAction(
                    icon: Icons.add_rounded,
                    label: 'Adicionar',
                    onPressed: _working ? null : _manualSecret,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _SecretQuickAction(
                    icon: Icons.file_upload_outlined,
                    label: 'Importar',
                    filled: true,
                    onPressed: _working ? null : _importFile,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _SecretQuickAction(
                    icon: Icons.content_paste_rounded,
                    label: 'Colar',
                    onPressed: _working ? null : _pasteMany,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: _SecretQuickAction(
                    icon: Icons.verified_user_outlined,
                    label: 'Permissões',
                    onPressed: () => context.push(
                      '/repositories/${widget.repositoryFullName}/permissions',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: secrets.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: error is GitHubPermissionException
                          ? scheme.errorContainer.withValues(alpha: .35)
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          error is GitHubPermissionException
                              ? 'Permissão insuficiente para listar Secrets.'
                              : error is AppException
                                  ? error.message
                                  : 'Não foi possível listar os Secrets.',
                        ),
                        if (error is GitHubPermissionException) ...[
                          const SizedBox(height: 7),
                          TextButton.icon(
                            onPressed: () => context.push(
                              '/repositories/${widget.repositoryFullName}/permissions',
                            ),
                            icon: const Icon(
                              Icons.verified_user_outlined,
                              size: 17,
                            ),
                            label: const Text('Diagnosticar'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              data: (items) {
                if (items.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 24, 12, 88),
                    children: [
                      Icon(
                        Icons.key_off_outlined,
                        size: 30,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Nenhum Secret cadastrado.',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 12, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${items.length} Secrets no repositório',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _working ? null : _deleteAllSecrets,
                            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                            label: const Text('Excluir todas'),
                          ),
                        ],
                      ),
                    ),
                    if (_deletingTotal > 0) ...[
                      LinearProgressIndicator(
                        value: _deletingCompleted / _deletingTotal,
                      ),
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          'Excluindo $_deletingCompleted de $_deletingTotal Secrets',
                        ),
                      ),
                    ],
                    Expanded(
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(10, 3, 10, 88),
                        itemCount: items.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 3),
                        itemBuilder: (context, index) {
                          final secret = items[index];
                          return Material(
                            color: scheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(4),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(vertical: -2),
                              contentPadding:
                                  const EdgeInsets.fromLTRB(10, 1, 2, 1),
                              leading: Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer
                                      .withValues(alpha: .5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  Icons.key_rounded,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                              ),
                              title: Text(
                                secret.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                'Atualizado ${_formatDate(secret.updatedAt)}',
                                maxLines: 1,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              trailing: PopupMenuButton<String>(
                                enabled: !_working,
                                tooltip: 'Ações',
                                onSelected: (action) {
                                  if (action == 'replace') {
                                    _replace(secret);
                                  } else if (action == 'delete') {
                                    _delete(secret);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'replace',
                                    child: Text('Substituir valor'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Excluir'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
}
