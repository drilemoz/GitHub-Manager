part of 'settings_screen.dart';

mixin _SettingsScreenActions on ConsumerState<SettingsScreen> {
  late ThemeMode _themeMode;
  Map<String, String>? _apiSettings;
  NotificationPreferences? _notificationPreferences;
  bool _savingNotifications = false;
  bool get _canChangeNotificationCategories =>
      _notificationPreferences?.enabled == true && !_savingNotifications;
  bool? _automaticUploadRecoveryEnabled;
  DownloadCleanupMode? _downloadCleanupMode;
  bool _updatingFullScreen = false;

  void initializeSettingsState() {
    _themeMode = AppThemeController.instance.value;
    _loadApiSettings();
    _loadNotificationSettings();
    _loadUploadRecoverySettings();
    _loadDownloadCleanupSettings();
  }

  Future<void> _loadDownloadCleanupSettings() async {
    var mode = DownloadCleanupMode.afterSuccess;
    try {
      mode = await DownloadCleanupSettings.read(
        database: ref.read(localDatabaseProvider),
      );
    } catch (_) {
      // Valor seguro: não remover nada antes de ter novo arquivo válido.
    }
    if (mounted) setState(() => _downloadCleanupMode = mode);
  }

  Future<void> _chooseDownloadCleanupMode() async {
    final chosen = await showDialog<DownloadCleanupMode>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Limpeza automática'),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in DownloadCleanupMode.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  mode == _downloadCleanupMode
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                ),
                title: Text(DownloadCleanupSettings.label(mode)),
                subtitle: Text(DownloadCleanupSettings.description(mode)),
                onTap: () => Navigator.pop(dialogContext, mode),
              ),
            const Text(
              'A opção afeta apenas os arquivos finais de cada projeto na '
              'pasta Downloads/GitHub. Downloads pausados e parciais são protegidos.',
            ),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (chosen == null || chosen == _downloadCleanupMode) return;
    try {
      await DownloadCleanupSettings.write(
        chosen,
        database: ref.read(localDatabaseProvider),
      );
      if (!mounted) return;
      setState(() => _downloadCleanupMode = chosen);
      showCenteredNotice(
        context,
        'Limpeza automática: ${DownloadCleanupSettings.label(chosen).toLowerCase()}.',
        kind: CenteredNoticeKind.success,
      );
    } catch (_) {
      if (!mounted) return;
      showCenteredNotice(
        context,
        'Não foi possível salvar a preferência de limpeza.',
        kind: CenteredNoticeKind.error,
      );
    }
  }

  Future<void> _loadApiSettings() async {
    final values = await ref.read(secureStorageProvider).readApiSettings();
    if (mounted) {
      setState(() => _apiSettings = values);
    }
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final preferences = await NotificationPreferences.read(
        database: ref.read(localDatabaseProvider),
      );
      if (mounted) setState(() => _notificationPreferences = preferences);
    } catch (_) {
      if (mounted) {
        setState(() => _notificationPreferences = const NotificationPreferences());
      }
    }
  }

  Future<void> _loadUploadRecoverySettings() async {
    var enabled = true;
    try {
      enabled = await UploadRecoverySettings.isAutomaticRecoveryEnabled(
        database: ref.read(localDatabaseProvider),
      );
    } catch (_) {
      // Preferência local auxiliar: uma falha de leitura não deve bloquear envios.
    }
    if (mounted) {
      setState(() => _automaticUploadRecoveryEnabled = enabled);
    }
  }

  Future<void> _setFullScreenEnabled(bool enabled) async {
    if (_updatingFullScreen) return;
    setState(() => _updatingFullScreen = true);
    try {
      await SystemUiSettings.instance.setEnabled(enabled);
    } catch (_) {
      if (mounted) {
        showCenteredNotice(
          context,
          'Não foi possível alterar ou salvar o modo de tela.',
          kind: CenteredNoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingFullScreen = false);
    }
  }

  Future<void> _setShowRepositoryDescriptions(bool enabled) async {
    try {
      await RepositoryDescriptionSettings.setEnabled(
        enabled,
        database: ref.read(localDatabaseProvider),
      );
      if (!mounted) return;
      ref.invalidate(showRepositoryDescriptionsProvider);
    } catch (_) {
      if (!mounted) return;
      showCenteredNotice(
        context,
        'Não foi possível salvar a preferência de descrições.',
        kind: CenteredNoticeKind.error,
      );
    }
  }

  Future<void> _setUploadAutomaticRecovery(bool enabled) async {
    try {
      await UploadRecoverySettings.setAutomaticRecoveryEnabled(
        enabled,
        database: ref.read(localDatabaseProvider),
      );
    } catch (_) {
      if (!mounted) return;
      showCenteredNotice(
        context,
        'Não foi possível salvar a preferência de recuperação.',
        kind: CenteredNoticeKind.error,
      );
      return;
    }
    if (!mounted) return;
    setState(() => _automaticUploadRecoveryEnabled = enabled);
    showCenteredNotice(
      context,
      enabled
          ? 'Recuperação automática de envios ativada.'
          : 'Recuperação automática de envios desativada.',
      kind: CenteredNoticeKind.success,
    );
  }

  Future<void> _setNotificationPreferences(NotificationPreferences next) async {
    if (_savingNotifications) return;
    setState(() => _savingNotifications = true);
    try {
      if (next.enabled && _notificationPreferences?.enabled != true &&
          !await BuildMonitorService.requestPermission()) {
        if (mounted) {
          showCenteredNotice(
            context,
            'O Android não concedeu a permissão para notificações.',
            kind: CenteredNoticeKind.error,
          );
        }
        return;
      }
      await NotificationPreferences.save(
        next,
        database: ref.read(localDatabaseProvider),
      );
      if (!next.enabled) {
        await AppNotificationService.cancelAllOptional();
      }
      await BuildMonitorService.refreshConfiguration();
      if (mounted) {
        setState(() => _notificationPreferences = next);
        showCenteredNotice(
          context,
          next.enabled ? 'Preferências de notificação salvas.' : 'Avisos opcionais desligados.',
          kind: CenteredNoticeKind.success,
        );
      }
    } catch (_) {
      if (mounted) {
        showCenteredNotice(
          context,
          'Não foi possível salvar as preferências de notificação.',
          kind: CenteredNoticeKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _savingNotifications = false);
    }
  }

  Future<void> _setTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await AppThemeController.instance.setMode(mode);
  }

  Future<void> _pasteInto(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }
    controller
      ..text = text.trim()
      ..selection = TextSelection.collapsed(offset: controller.text.length);
  }

  Future<void> _replaceGitHubToken() async {
    final controller = TextEditingController();
    var obscure = true;
    final token = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('GitHub API'),
          content: AdaptiveDialogBody(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cole um Personal Access Token fine-grained (github_pat_...) ou clássico (ghp_...). Ele será validado em /user antes de substituir o token atual.'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Personal Access Token',
                      hintText: 'github_pat_... ou ghp_...',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _pasteInto(controller),
                            tooltip: 'Colar',
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
                          IconButton(
                            onPressed: () => setDialogState(() => obscure = !obscure),
                            tooltip: obscure ? 'Exibir' : 'Ocultar',
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () => context.push('/setup'),
                    icon: const Icon(Icons.help_outline_rounded),
                    label: const Text('Abrir guia de configuração'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Testar e salvar')),
          ],
        ),
      ),
    );
    controller.dispose();
    if (token == null || token.isEmpty || !mounted) {
      return;
    }
    try {
      await ref.read(githubAuthRepositoryProvider).connectWithToken(token);
      ref.invalidate(githubConnectionProvider);
      ref.invalidate(githubProfileProvider);
      ref.invalidate(repositoriesProvider);
      if (mounted) {
        showCenteredNotice(context, 'Token validado e salvo.');
      }
    } catch (error) {
      if (mounted) {
        _showError(error);
      }
    }
  }

  Future<void> _showGitHubTokenBackup() async {
    final token = await ref.read(secureStorageProvider).readGitHubToken();
    if (!mounted) {
      return;
    }
    if (token == null || token.isEmpty) {
      showCenteredNotice(context, 'Nenhum token GitHub salvo neste aparelho.');
      return;
    }
    var visible = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Token GitHub atual'),
          content: AdaptiveDialogBody(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Esta é a chave/token GitHub salva neste aparelho. Ela dá acesso aos recursos autorizados no GitHub. Exiba ou copie somente quando necessário e não compartilhe publicamente.',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      visible ? token : '•' * 24,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => setDialogState(() => visible = !visible),
                        icon: Icon(
                          visible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        label: Text(visible ? 'Ocultar' : 'Exibir'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: token));
                          if (context.mounted) {
                            showCenteredNotice(context, 'Token copiado.');
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copiar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _disconnectGitHub() async {
    await ref.read(githubAuthRepositoryProvider).disconnect();
    ref.invalidate(githubConnectionProvider);
    ref.invalidate(githubProfileProvider);
    ref.invalidate(repositoriesProvider);
    if (mounted) {
      context.go('/');
    }
  }

  Future<void> _editProfile(GitHubProfile profile) async {
    final draft = await showGitHubProfileEditDialog(context, profile);
    if (draft == null || !mounted) return;
    try {
      await ref.read(githubProfileRepositoryProvider).updateProfile(
            name: draft.name,
            email: draft.email,
            blog: draft.blog,
            twitterUsername: draft.twitterUsername,
            company: draft.company,
            location: draft.location,
            bio: draft.bio,
            hireable: draft.hireable,
          );
      ref.invalidate(githubProfileProvider);
      if (mounted) {
        showCenteredNotice(
          context,
          'Perfil atualizado no GitHub.',
          kind: CenteredNoticeKind.success,
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _editApi() async {
    final current = _apiSettings ?? await ref.read(secureStorageProvider).readApiSettings();
    if (!mounted) {
      return;
    }
    final name = TextEditingController(text: current['name'] ?? 'Groq');
    final baseUrl = TextEditingController(text: current['baseUrl'] ?? 'https://api.groq.com/openai/v1');
    final apiKey = TextEditingController(text: current['apiKey'] ?? '');
    final model = TextEditingController(text: current['model'] ?? '');
    var provider = current['provider'] ?? 'groq';
    var obscure = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Configurar API'),
          content: AdaptiveDialogBody(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Para que serve? Esta integração foi preparada para recursos opcionais de IA, '
                      'como resumir logs e explicar erros de build em linguagem simples. '
                      'Na versão atual nenhuma função principal depende do Groq, então você pode deixar sem chave.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'groq', label: Text('Groq')),
                      ButtonSegment(value: 'custom', label: Text('Personalizada')),
                    ],
                    selected: {provider},
                    onSelectionChanged: (value) {
                      setDialogState(() {
                        provider = value.first;
                        if (provider == 'groq') {
                          name.text = 'Groq';
                          if (baseUrl.text.trim().isEmpty) {
                            baseUrl.text = 'https://api.groq.com/openai/v1';
                          }
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 14),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome da integração')),
                  const SizedBox(height: 10),
                  TextField(controller: baseUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Base URL')),
                  const SizedBox(height: 10),
                  TextField(
                    controller: apiKey,
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _pasteInto(apiKey),
                            tooltip: 'Colar',
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
                          IconButton(
                            onPressed: () => setDialogState(() => obscure = !obscure),
                            tooltip: obscure ? 'Exibir' : 'Ocultar',
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: model, decoration: const InputDecoration(labelText: 'Modelo padrão (opcional)')),
                  const SizedBox(height: 10),
                  const Text('A chave fica apenas no armazenamento seguro do Android; não é enviada ao repositório.'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      await ref.read(secureStorageProvider).writeApiSettings(
            provider: provider,
            name: name.text,
            baseUrl: baseUrl.text,
            apiKey: apiKey.text,
            model: model.text,
          );
      await _loadApiSettings();
      if (mounted) {
        showCenteredNotice(context, 'Configuração da API salva.');
      }
    }

    name.dispose();
    baseUrl.dispose();
    apiKey.dispose();
    model.dispose();
  }

  Future<void> _showCurrentWhatsNew() async {
    final version = await InstalledVersionBanner.versionLabel;
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => UpdateWhatsNewScreen(
          versionLabel: version,
          onContinue: () async {
            if (routeContext.mounted) Navigator.of(routeContext).pop();
          },
        ),
      ),
    );
  }

  Future<void> _repairLocalData() async {
    final database = ref.read(localDatabaseProvider);
    try {
      final healthy = await database.repairSchema();
      if (!mounted) return;
      ref.invalidate(favoriteRepositoryIdsProvider);
      ref.invalidate(repositoriesProvider);
      ref.invalidate(githubProfileProvider);
      if (healthy) {
        showCenteredNotice(
          context,
          'Dados locais verificados e estrutura reparada.',
          kind: CenteredNoticeKind.success,
        );
        return;
      }
    } catch (_) {
      // Abaixo oferecemos uma reconstrução apenas do SQLite local.
    }

    if (!mounted) return;
    final rebuild = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reconstruir dados locais?'),
        content: const Text(
          'O banco interno não passou na verificação. O GitHub Manager pode '
          'recriá-lo sem apagar seu token GitHub. Projetos fixados e outras '
          'preferências armazenadas somente nesse banco local podem ser perdidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reconstruir'),
          ),
        ],
      ),
    );
    if (rebuild != true || !mounted) return;

    try {
      await database.rebuildLocalDatabase();
      ref.invalidate(favoriteRepositoryIdsProvider);
      ref.invalidate(repositoriesProvider);
      ref.invalidate(followedRepositoriesProvider);
      ref.invalidate(githubProfileProvider);
      if (mounted) {
        showCenteredNotice(
          context,
          'Banco local reconstruído. O token GitHub foi preservado.',
          kind: CenteredNoticeKind.success,
        );
      }
    } catch (_) {
      if (mounted) {
        showCenteredNotice(
          context,
          'Não foi possível reparar os dados locais automaticamente.',
          kind: CenteredNoticeKind.error,
        );
      }
    }
  }

  Future<void> _copySupportText(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      showCenteredNotice(
        context,
        message,
        kind: CenteredNoticeKind.success,
      );
    }
  }

  void _showError(Object error) {
    final message = error is AppException ? error.message : 'Não foi possível concluir a operação.';
    showCenteredNotice(context, message);
  }

  Future<void> _showGitHubIntegration(GitHubProfile profile) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('GitHub'),
        content: AdaptiveDialogBody(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    foregroundImage: profile.avatarUrl.isEmpty ? null : NetworkImage(profile.avatarUrl),
                    child: profile.avatarUrl.isEmpty ? const Icon(Icons.person_outline_rounded) : null,
                  ),
                  title: Text(profile.name?.isNotEmpty == true ? profile.name! : profile.login),
                  subtitle: Text('@${profile.login}'),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'As permissões podem variar por repositório. Abra um repositório e toque em “Diagnóstico do token” para verificar Contents, Actions, Secrets, administração e exclusão sem alterar dados.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(context);
                    _editProfile(profile);
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar perfil permitido pela API'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _replaceGitHubToken();
                  },
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('Substituir token'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showGitHubTokenBackup();
                  },
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Exibir / copiar token atual'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _disconnectGitHub();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Desconectar GitHub'),
                ),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
      ),
    );
  }

}
