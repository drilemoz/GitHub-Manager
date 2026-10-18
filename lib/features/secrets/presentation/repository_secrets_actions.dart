part of 'repository_secrets_screen.dart';

mixin _RepositorySecretsActions on ConsumerState<RepositorySecretsScreen> {
  bool _working = false;

  Future<void> _refresh() async {
    ref.invalidate(repositorySecretsProvider(widget.repositoryFullName));
    await ref.read(repositorySecretsProvider(widget.repositoryFullName).future);
  }

  Future<void> _pasteInto(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    controller
      ..text = text.trim()
      ..selection = TextSelection.collapsed(offset: controller.text.length);
  }

  Future<void> _manualSecret() async {
    final allowed = await ensureRepositoryPermission(
      context,
      ref,
      repositoryFullName: widget.repositoryFullName,
      action: RepositoryCriticalAction.manageSecrets,
    );
    if (!allowed || !mounted) return;
    final name = TextEditingController();
    final value = TextEditingController();
    var obscure = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Adicionar ou substituir Secret'),
          content: AdaptiveDialogBody(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Nome',
                      hintText: 'KEYSTORE_PASSWORD',
                      suffixIcon: IconButton(
                        onPressed: () => _pasteInto(name),
                        tooltip: 'Colar',
                        icon: const Icon(Icons.content_paste_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: value,
                    obscureText: obscure,
                    minLines: 1,
                    maxLines: 5,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Novo valor',
                      helperText:
                          'Máximo 48 KB. O valor é criptografado no aparelho e nunca aparece nos diagnósticos.',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () => _pasteInto(value),
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
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    if (result == true && mounted && name.text.trim().isNotEmpty) {
      await _run(
        () => ref.read(repositorySecretsServiceProvider).putSecret(
              repositoryFullName: widget.repositoryFullName,
              name: name.text,
              value: value.text,
            ),
        successMessage: 'Secret salvo.',
      );
    }
    name.dispose();
    value.dispose();
  }

  Future<void> _pasteMany() async {
    final controller = TextEditingController();
    await _pasteInto(controller);
    if (!mounted) {
      controller.dispose();
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Colar vários Secrets'),
        content: AdaptiveDialogBody(
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 8,
            maxLines: 16,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText:
                  'TOKEN=valor\nKEYSTORE_PASSWORD: valor\nexport KEY_ALIAS=alias',
              helperText:
                  'Aceita NOME=valor, NOME: valor e export NOME=valor. Comentários com # ou // são ignorados.',
              suffixIcon: IconButton(
                onPressed: () => _pasteInto(controller),
                tooltip: 'Colar',
                icon: const Icon(Icons.content_paste_rounded),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Analisar'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      try {
        final values = RepositorySecretsService.parseText(controller.text);
        if (values.isEmpty) {
          throw const FormatException('Nenhum Secret válido encontrado.');
        }
        await _putMany(values);
      } catch (error) {
        if (mounted) _showError(error);
      }
    }
    controller.dispose();
  }

  Future<void> _importFile() async {
    try {
      final service = ref.read(repositorySecretsServiceProvider);
      final file = await service.pickImportFile();
      if (file == null || !mounted) return;
      final values = await service.parseImportFile(file);
      if (!mounted) return;
      if (values.isEmpty) {
        throw const FormatException('O arquivo não contém Secrets reconhecíveis.');
      }
      await _putMany(values);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _putMany(Map<String, String> values) async {
    if (_working) return;
    final allowed = await ensureRepositoryPermission(
      context,
      ref,
      repositoryFullName: widget.repositoryFullName,
      action: RepositoryCriticalAction.manageSecrets,
    );
    if (!allowed || !mounted) return;
    setState(() => _working = true);
    final SecretImportPlan plan;
    try {
      plan = await ref.read(repositorySecretsServiceProvider).prepareImport(
            repositoryFullName: widget.repositoryFullName,
            values: values,
          );
    } catch (error) {
      if (mounted) _showError(error);
      if (mounted) setState(() => _working = false);
      return;
    }
    if (mounted) setState(() => _working = false);
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Revisar ${plan.total} Secrets'),
        content: AdaptiveDialogBody(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryCard(plan: plan),
                const SizedBox(height: 12),
                const Text(
                  'O GitHub Manager validou nomes, tamanho e limite do repositório. Nenhum valor é exibido nesta tela.',
                ),
                const SizedBox(height: 12),
                ...plan.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          item.kind == SecretMutationKind.create
                              ? Icons.add_circle_outline_rounded
                              : Icons.sync_rounded,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          item.kind == SecretMutationKind.create
                              ? 'Criar'
                              : 'Substituir',
                        ),
                        const SizedBox(width: 8),
                        Text(_RepositorySecretsScreenState._formatBytes(item.utf8Bytes)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Criptografar e salvar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    try {
      final result = await ref.read(repositorySecretsServiceProvider).putMany(
            repositoryFullName: widget.repositoryFullName,
            values: values,
            preparedPlan: plan,
          );
      if (mounted) await _showBatchResult(result);
      if (mounted) {
        ref.invalidate(repositorySecretsProvider(widget.repositoryFullName));
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _showBatchResult(SecretBatchResult result) async {
    final colorScheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              result.allSucceeded
                  ? Icons.check_circle_rounded
                  : result.saved > 0
                      ? Icons.warning_amber_rounded
                      : Icons.error_outline_rounded,
              color: result.allSucceeded
                  ? colorScheme.primary
                  : colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.allSucceeded
                    ? 'Secrets salvos'
                    : result.saved > 0
                        ? 'Importação parcial'
                        : 'Falha ao salvar Secrets',
              ),
            ),
          ],
        ),
        content: AdaptiveDialogBody(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.saved} salvos • ${result.failed} falharam • ${result.total} analisados',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Os valores nunca são incluídos no resultado nem no diagnóstico copiável.',
                ),
                const SizedBox(height: 14),
                ...result.items.map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(vertical: -2),
                      leading: Icon(
                        item.success
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        color: item.success ? colorScheme.primary : colorScheme.error,
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        item.success
                            ? item.message
                            : [
                                item.message,
                                if (item.httpStatus != null) 'HTTP ${item.httpStatus}',
                                if (item.apiMessage?.isNotEmpty == true)
                                  'GitHub: ${item.apiMessage}',
                              ].join('\n'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: result.diagnosticText(
                    repositoryFullName: widget.repositoryFullName,
                  ),
                ),
              );
              if (dialogContext.mounted) {
                showCenteredNotice(dialogContext, 'Diagnóstico copiado.');
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar diagnóstico'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(RepositorySecret secret) async {
    final allowed = await ensureRepositoryPermission(
      context,
      ref,
      repositoryFullName: widget.repositoryFullName,
      action: RepositoryCriticalAction.manageSecrets,
    );
    if (!allowed || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Excluir ${secret.name}?'),
        content: const AdaptiveDialogBody(
          child: Text('O valor não poderá ser recuperado depois da exclusão.'),
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
    await _run(
      () => ref.read(repositorySecretsServiceProvider).deleteSecret(
            repositoryFullName: widget.repositoryFullName,
            name: secret.name,
          ),
      successMessage: 'Secret excluído.',
    );
  }

  int _deletingCompleted = 0;
  int _deletingTotal = 0;

  Future<void> _deleteAllSecrets() async {
    if (_working) return;
    final allowed = await ensureRepositoryPermission(
      context,
      ref,
      repositoryFullName: widget.repositoryFullName,
      action: RepositoryCriticalAction.manageSecrets,
    );
    if (!allowed || !mounted) return;

    // A lista é obtida novamente do GitHub. O lote usa somente estes nomes,
    // nunca um conjunto alterado silenciosamente depois da confirmação.
    final List<RepositorySecret> current;
    setState(() => _working = true);
    try {
      current = await ref.read(repositorySecretsServiceProvider).listSecrets(
            widget.repositoryFullName,
          );
    } catch (error) {
      if (mounted) _showError(error);
      if (mounted) setState(() => _working = false);
      return;
    }
    if (mounted) setState(() => _working = false);
    if (!mounted) return;
    if (current.isEmpty) {
      showCenteredNotice(context, 'Este repositório não possui Secrets para excluir.');
      await _refresh();
      return;
    }

    final confirmation = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Excluir todos os Secrets?'),
          content: AdaptiveDialogBody(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repositório: ${widget.repositoryFullName}\n'
                    '${current.length} Secrets serão excluídos permanentemente.',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Esta ação não pode ser desfeita. O GitHub não permite '
                    'recuperar valores de Secrets excluídos. Outros repositórios '
                    'não serão alterados.',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    current.map((item) => item.name).join(' • '),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: confirmation,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Digite EXCLUIR para confirmar',
                      hintText: 'EXCLUIR',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: confirmation.text.trim() == 'EXCLUIR'
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              icon: const Icon(Icons.delete_forever_outlined),
              label: Text('Excluir ${current.length} Secrets'),
            ),
          ],
        ),
      ),
    );
    confirmation.dispose();
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _deletingCompleted = 0;
      _deletingTotal = current.length;
    });
    SecretDeletionResult? result;
    try {
      result = await ref.read(repositorySecretsServiceProvider).deleteMany(
            repositoryFullName: widget.repositoryFullName,
            names: current.map((secret) => secret.name).toList(growable: false),
            onProgress: (completed, total) {
              if (mounted) {
                setState(() {
                  _deletingCompleted = completed;
                  _deletingTotal = total;
                });
              }
            },
          );
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _deletingCompleted = 0;
          _deletingTotal = 0;
        });
        // Invalida o cache mesmo em falha parcial.
        ref.invalidate(repositorySecretsProvider(widget.repositoryFullName));
      }
    }
    if (!mounted || result == null) return;
    await _showDeleteManyResult(result);
  }

  Future<void> _showDeleteManyResult(SecretDeletionResult result) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(result.allSucceeded
            ? 'Secrets excluídos'
            : result.deleted > 0
                ? 'Exclusão parcial'
                : 'Exclusão não concluída'),
        content: AdaptiveDialogBody(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.deleted} excluídos • ${result.failed} falharam • ${result.total} analisados',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 9),
                const Text('Valores dos Secrets nunca são consultados.'),
                const SizedBox(height: 10),
                ...result.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            item.success
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            size: 18,
                            color: item.success
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(item.success
                                ? item.name
                                : '${item.name}: ${item.message ?? 'Falha'}${item.httpStatus == null ? '' : ' • HTTP ${item.httpStatus}'}'),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(
                text: result.diagnosticText(
                  repositoryFullName: widget.repositoryFullName,
                ),
              ));
              if (dialogContext.mounted) {
                showCenteredNotice(dialogContext, 'Resultado copiado.');
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar resultado'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _replace(RepositorySecret secret) async {
    final allowed = await ensureRepositoryPermission(
      context,
      ref,
      repositoryFullName: widget.repositoryFullName,
      action: RepositoryCriticalAction.manageSecrets,
    );
    if (!allowed || !mounted) return;
    final controller = TextEditingController();
    var obscure = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Substituir ${secret.name}'),
          content: AdaptiveDialogBody(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Novo valor',
                helperText: 'Máximo 48 KB.',
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Substituir'),
            ),
          ],
        ),
      ),
    );
    if (result == true && mounted) {
      await _run(
        () => ref.read(repositorySecretsServiceProvider).putSecret(
              repositoryFullName: widget.repositoryFullName,
              name: secret.name,
              value: controller.text,
            ),
        successMessage: 'Secret substituído.',
      );
    }
    controller.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      await _refresh();
      if (mounted && successMessage != null) {
        showCenteredNotice(context, successMessage);
      }
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showError(Object error) {
    if (error is AppException &&
        (error.httpStatus != null ||
            error.endpoint?.isNotEmpty == true ||
            error.apiMessage?.isNotEmpty == true)) {
      _showDetailedError(error);
      return;
    }
    final message = error is GitHubPermissionException
        ? 'Permissão insuficiente. Token fine-grained: habilite Secrets: Read and write. Token clássico: use repo.'
        : error is FormatException
            ? error.message
            : error is AppException
                ? error.message
                : 'Não foi possível concluir a operação de Secrets.';
    showCenteredNotice(context, message);
  }

  Future<void> _showDetailedError(AppException error) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Não foi possível concluir'),
        content: AdaptiveDialogBody(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error is GitHubPermissionException
                      ? 'O token não possui a permissão necessária. Para Secrets, use Secrets: Read and write em token fine-grained ou repo em token clássico.'
                      : error.message,
                ),
                const SizedBox(height: 14),
                if (error.httpStatus != null) Text('HTTP: ${error.httpStatus}'),
                if (error.technicalCode != null)
                  Text('Código: ${error.technicalCode}'),
                if (error.endpoint?.isNotEmpty == true)
                  Text('Endpoint: ${error.endpoint}'),
                if (error.apiMessage?.isNotEmpty == true)
                  Text('GitHub: ${error.apiMessage}'),
                const SizedBox(height: 10),
                const Text(
                  'Nenhum valor de Secret é incluído nestes detalhes.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}
