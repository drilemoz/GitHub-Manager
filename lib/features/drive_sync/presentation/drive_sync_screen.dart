import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/providers/core_providers.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/features/drive_sync/data/drive_sync_coordinator.dart';
import 'package:github_manager/features/drive_sync/data/drive_sync_store.dart';
import 'package:github_manager/features/drive_sync/data/google_drive_read_service.dart';
import 'package:github_manager/features/drive_sync/domain/drive_sync_link.dart';
import 'package:github_manager/features/projects/data/local_project_service.dart';
import 'package:github_manager/features/projects/presentation/project_providers.dart';
import 'package:github_manager/features/permissions/presentation/token_permission_providers.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';
import 'package:github_manager/features/uploads/presentation/upload_providers.dart';
import 'package:go_router/go_router.dart';

final googleDriveReadServiceProvider = Provider<GoogleDriveReadService>((ref) {
  final service = GoogleDriveReadService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final driveSyncStoreProvider = Provider<DriveSyncStore>(
    (ref) => DriveSyncStore(ref.watch(localDatabaseProvider)));

final driveSyncCoordinatorProvider = Provider<DriveSyncCoordinator>((ref) =>
    DriveSyncCoordinator(
      drive: ref.watch(googleDriveReadServiceProvider),
      store: ref.watch(driveSyncStoreProvider),
      repositories: ref.watch(repositoryServiceProvider),
      infoService: ref.watch(repositoryProjectInfoServiceProvider),
      uploadService: ref.watch(gitProjectUploadServiceProvider),
      permissionService: ref.watch(permissionPreflightServiceProvider),
      manager: ref.watch(uploadManagerProvider),
    ));

class DriveSyncScreen extends ConsumerStatefulWidget {
  const DriveSyncScreen({super.key});
  @override
  ConsumerState<DriveSyncScreen> createState() => _DriveSyncScreenState();
}

class _DriveSyncScreenState extends ConsumerState<DriveSyncScreen> {
  List<DriveSyncLink> _links = const [];
  List<GitHubRepository> _repositories = const [];
  String? _email;
  String? _configuredId;
  String? _signingSha1;
  String? _androidPackage;
  String? _busyKey;
  String? _message;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool clearMessage = true}) async {
    if (mounted) setState(() {
      _loading = true;
      if (clearMessage) _message = null;
    });
    try {
      final drive = ref.read(googleDriveReadServiceProvider);
      final configuredId = await drive.configuredWebClientId();
      String? loginError;
      if (configuredId != null &&
          GoogleDriveReadService.isValidWebClientId(configuredId)) {
        try {
          await drive.initialize();
        } catch (error) {
          loginError = _driveErrorMessage(error);
        }
      }
      Map<String, String> certificate = const {};
      try {
        certificate = await PlatformActions.getOwnSigningCertificate();
      } catch (_) {
        // SHA-1 helps registration, but lack of native bridge must not block UI.
      }
      if (!mounted) return;
      setState(() {
        _email = drive.email;
        _configuredId = configuredId;
        _signingSha1 = certificate['sha1'];
        _androidPackage = certificate['packageName'];
        if (loginError != null) _message = loginError;
      });
      final store = ref.read(driveSyncStoreProvider);
      final links = await store.read();
      final repositories = await ref.read(repositoryServiceProvider).listRepositories();
      if (!mounted) return;
      setState(() {
        _links = links;
        _repositories = repositories.where((item) => !item.isArchived).toList();
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Não foi possível carregar: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _driveErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.contains('clientConfigurationError') ||
        raw.contains('serverClientId must be provided')) {
      return 'OAuth Google incompleto. Confira o Client ID Web, o pacote '
          'Android, a SHA-1 do APK instalado e os usuários de teste no Google Cloud.';
    }
    if (raw.contains('canceled')) {
      return 'Login cancelado ou rejeitado pelo Google. Confira também '
          'a SHA-1 e a configuração OAuth do aplicativo Android.';
    }
    return raw.replaceFirst('Bad state: ', '');
  }

  Future<void> _configureOAuth() async {
    final drive = ref.read(googleDriveReadServiceProvider);
    final input = TextEditingController(text: _configuredId ?? '');
    String? error;
    try {
      final save = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Configurar login Google'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Cole o Client ID OAuth do tipo Aplicativo da Web. '
                      'Não use o ID do aplicativo Android nem uma API key.'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: input,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Client ID Web',
                      hintText: '123456-abc.apps.googleusercontent.com',
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                    onChanged: (_) {
                      if (error != null) setDialogState(() => error = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('No Google Cloud, crie também uma credencial '
                      'Android para o pacote e a SHA-1 exibidos nesta tela. '
                      'Ative a API Google Drive e adicione sua conta aos '
                      'usuários de teste enquanto o OAuth estiver em testes.'),
                  TextButton.icon(
                    onPressed: () => PlatformActions.openUri(
                      'https://console.cloud.google.com/apis/credentials'),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Abrir credenciais Google Cloud'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              FilledButton(onPressed: () {
                final value = input.text.trim();
                if (!GoogleDriveReadService.isValidWebClientId(value)) {
                  setDialogState(() => error = 'ID Web inválido. Confira o valor copiado.');
                  return;
                }
                Navigator.pop(context, value);
              }, child: const Text('Salvar')),
            ],
          ),
        ),
      );
      if (save == null) return;
      await drive.saveWebClientId(save);
      if (!mounted) return;
      setState(() {
        _configuredId = save;
        _message = drive.requiresRestart
            ? 'ID Web salvo. Feche e abra o GitHub Manager para ativar a nova '
                'configuração do login Google.'
            : 'ID Web salvo. Toque em Conectar para autorizar sua conta.';
      });
    } catch (exception) {
      if (mounted) setState(() => _message = _driveErrorMessage(exception));
    } finally {
      input.dispose();
    }
  }

  Future<void> _connect() async {
    if (_configuredId == null ||
        !GoogleDriveReadService.isValidWebClientId(_configuredId!)) {
      await _configureOAuth();
      return;
    }
    setState(() { _busyKey = 'connect'; _message = null; });
    try {
      final email = await ref.read(googleDriveReadServiceProvider).connect();
      if (mounted) setState(() => _email = email);
    } catch (error) {
      if (mounted) setState(() => _message = 'Conexão Google: ${_driveErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _addLink() async {
    final drive = ref.read(googleDriveReadServiceProvider);
    if (drive.email == null) { await _connect(); if (drive.email == null) return; }
    if (!mounted || _repositories.isEmpty) return;
    final folder = await showDialog<_DriveFolderSelection>(
      context: context, builder: (_) => _DriveFolderPicker(drive: drive));
    if (folder == null || !mounted) return;
    final chosen = await showDialog<DriveSyncLink>(
      context: context,
      builder: (dialogContext) => _DriveLinkDialog(
        folder: folder, repositories: _repositories));
    if (chosen == null || !mounted) return;
    final existing = _links.where((link) => link.key == chosen.key).toList();
    if (existing.isNotEmpty) {
      final ok = await showDialog<bool>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Trocar a pasta deste repositório?'),
          content: const Text('O vínculo existente e seu histórico de '
              'sincronização serão substituídos. Nenhum arquivo do Drive '
              'ou repositório será apagado agora.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Substituir vínculo')),
          ]));
      if (ok != true || !mounted) return;
    }
    try {
      await ref.read(driveSyncStoreProvider).upsert(chosen);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _message = 'Não foi possível salvar: $error');
    }
  }

  Future<void> _setAuto(DriveSyncLink link, bool enabled) async {
    if (enabled) {
      final ok = await showDialog<bool>(context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ativar envio automático?'),
          content: const Text('Quando você verificar esta pasta pelo aplicativo, '
              'uma versão estritamente mais nova pode entrar na fila sem '
              'outra confirmação, desde que identidade, permissões e '
              'prévia estejam seguras e não haja remoções. '
              'A verificação periódica com o app fechado ainda não está disponível.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Ativar')),
          ]));
      if (ok != true || !mounted) return;
    }
    await ref.read(driveSyncStoreProvider).upsert(link.copyWith(automatic: enabled));
    await _load();
  }

  Future<void> _remove(DriveSyncLink link) async {
    final ok = await showDialog<bool>(context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover vínculo?'),
        content: Text('Deixar de acompanhar ${link.repositoryFullName}? '
            'Não remove arquivos do Drive nem do GitHub.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remover')),
        ]));
    if (ok != true) return;
    await ref.read(driveSyncStoreProvider).delete(link);
    await _load();
  }

  Future<void> _check(DriveSyncLink link) async {
    if (_busyKey != null) return;
    setState(() { _busyKey = link.key; _message = 'Consultando o Drive e verificando o GitHub…'; });
    DriveSyncCandidate? candidate;
    var queued = false;
    try {
      candidate = await ref.read(driveSyncCoordinatorProvider).check(link);
      if (!mounted) return;
      if (candidate == null) {
        setState(() => _message = 'Nenhum ZIP encontrado na pasta ${link.folderName}.');
        return;
      }
      if (!candidate.canQueue) {
        setState(() => _message = '${link.repositoryFullName}: ${candidate!.reason}');
        return;
      }
      var approved = link.automatic;
      if (!approved) {
        approved = await showDialog<bool>(context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Publicar nova versão?'),
            content: Text('${candidate!.file.name}\n'
                'Versão: ${candidate.project?.versionLabel ?? "desconhecida"}\n'
                'Destino: ${link.repositoryFullName} (${link.branch})\n'
                '${candidate.syncPreview?.createdCount ?? 0} novos, '
                '${candidate.syncPreview?.modifiedCount ?? 0} modificados, '
                '${candidate.syncPreview?.deletedCount ?? 0} removidos.\n\n'
                'O GitHub Manager enviará os arquivos e iniciará a build '
                'conforme o workflow configurado.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Enviar ao GitHub')),
            ],
          )) ?? false;
      }
      if (!approved || !mounted) return;
      final upload = await ref.read(driveSyncCoordinatorProvider).queue(candidate);
      queued = true;
      if (!mounted) return;
      setState(() => _message = 'Envio ${upload.id} adicionado à fila. '
          'Acompanhe pela Central de Envios.');
      await _load(clearMessage: false);
    } catch (error) {
      if (mounted) setState(() => _message = 'Falha na verificação: $error');
    } finally {
      if (!queued && candidate?.project != null) {
        await LocalProjectService.discardPreviewPath(candidate!.project!.path);
      }
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _configuredId != null &&
        GoogleDriveReadService.isValidWebClientId(_configuredId!);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive'),
        actions: [
          IconButton(onPressed: _busyKey == null ? _load : null,
            tooltip: 'Atualizar conexão e vínculos',
            icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 30), children: [
        Text('Sincronização de projetos',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text('Conecte sua conta, vincule uma pasta do Drive ao repositório '
            'e confira o ZIP antes da publicação.',
          style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_email == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                color: _email == null ? scheme.onSurfaceVariant : scheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_email == null ? 'Drive desconectado' : 'Drive conectado',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800)),
                  Text(_email ?? 'Permissão somente de leitura',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
                ])),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busyKey == null && ready &&
                    !ref.read(googleDriveReadServiceProvider).requiresRestart
                    ? _connect : null,
                icon: const Icon(Icons.login_rounded),
                label: Text(_email == null ? 'Conectar conta' : 'Reautorizar'),
              ),
              OutlinedButton.icon(
                onPressed: _busyKey == null ? _configureOAuth : null,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Configurar OAuth'),
              ),
            ]),
            if (!ready || ref.read(googleDriveReadServiceProvider).requiresRestart) ...[
              const SizedBox(height: 10),
              Text(!ready
                  ? 'Configuração OAuth pendente. Informe o Client ID Web '
                    'para habilitar o login no Android.'
                  : 'O ID OAuth foi alterado. Feche e abra o app para ativar '
                    'a nova configuração.',
                style: TextStyle(color: scheme.error)),
            ],
          ]),
        ),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            initiallyExpanded: !ready,
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Configuração e diagnóstico OAuth'),
            subtitle: Text(ready ? 'Client ID Web informado' : 'Configure antes de conectar'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: [
              Align(alignment: Alignment.centerLeft, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pacote Android', style: Theme.of(context).textTheme.labelMedium),
                  SelectableText(_androidPackage ?? 'br.com.githubmanager.app'),
                  const SizedBox(height: 9),
                  Text('SHA-1 do certificado deste APK instalado',
                    style: Theme.of(context).textTheme.labelMedium),
                  Row(children: [
                    Expanded(child: SelectableText(_signingSha1 ??
                        'Não disponível neste aparelho')),
                    if (_signingSha1 != null) IconButton(
                      tooltip: 'Copiar SHA-1',
                      onPressed: () => Clipboard.setData(ClipboardData(text: _signingSha1!)),
                      icon: const Icon(Icons.copy_rounded)),
                  ]),
                  const SizedBox(height: 8),
                  const Text('No Google Cloud, registre um OAuth Android com '
                      'este pacote e esta SHA-1. Crie um OAuth do tipo Web '
                      'no mesmo projeto e cole seu Client ID em Configurar OAuth. '
                      'Ative Google Drive API e verifique a tela de consentimento.'),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => PlatformActions.openUri(
                      'https://console.cloud.google.com/apis/credentials'),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Credenciais no Google Cloud')),
                ],
              )),
            ],
          ),
        ),
        if (_loading) const Padding(padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator()),
        if (_message != null) Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(_message!),
          ),
        ),
        const SizedBox(height: 12),
        Text('Pastas vinculadas',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 9),
        FilledButton.tonalIcon(
          onPressed: _busyKey == null && _email != null && _repositories.isNotEmpty
              ? _addLink : null,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Vincular pasta a repositório')),
        if (_links.isEmpty) Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Text('Nenhuma pasta vinculada. Conecte o Drive e associe '
              'uma pasta para começar.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
        for (final link in _links)
          Card(child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(link.repositoryFullName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700)),
              Text('Pasta: ${link.folderName}'),
              Text('Branch: ${link.branch}'),
              if (link.lastCompletedFileId != null)
                const Text('Último ZIP registrado após publicação'),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enviar ao verificar'),
                subtitle: const Text('Somente versão nova, sem remoções'),
                value: link.automatic,
                onChanged: _busyKey != null ? null : (value) => _setAuto(link, value)),
              Wrap(spacing: 8, children: [
                FilledButton.icon(
                  onPressed: _busyKey == null ? () => _check(link) : null,
                  icon: const Icon(Icons.sync_rounded),
                  label: const Text('Verificar agora')),
                TextButton.icon(
                  onPressed: _busyKey == null ? () => _remove(link) : null,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Desvincular')),
              ]),
            ]))),
        const SizedBox(height: 14),
        Text('Proteção: versões iguais/antigas, identidade incerta, '
            'exclusões e permissões inconclusivas não são publicadas por '
            'esta integração. Use o envio manual nesses casos. '
            'A verificação com o aplicativo fechado ainda não está disponível.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant)),
        TextButton.icon(
          onPressed: () => context.push('/uploads'),
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Abrir Central de Envios')),
      ]),
    );
  }

}

class _DriveFolderSelection {
  const _DriveFolderSelection(this.id, this.name);
  final String id;
  final String name;
}

class _DriveFolderPicker extends StatefulWidget {
  const _DriveFolderPicker({required this.drive});
  final GoogleDriveReadService drive;
  @override
  State<_DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<_DriveFolderPicker> {
  final List<_DriveFolderSelection> _stack = [_DriveFolderSelection('root', 'Meu Drive')];
  late Future<List<DriveFileEntry>> _folders;
  @override
  void initState() { super.initState(); _refresh(); }
  void _refresh() { _folders = widget.drive.listChildren(_stack.last.id, foldersOnly: true); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Escolher pasta no Google Drive'),
    content: SizedBox(width: double.maxFinite, height: 340,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_stack.map((f) => f.name).join(' / '), maxLines: 2),
        const Divider(),
        if (_stack.length > 1)
          TextButton.icon(onPressed: () => setState(() { _stack.removeLast(); _refresh(); }),
            icon: const Icon(Icons.arrow_back), label: const Text('Voltar')),
        Expanded(child: FutureBuilder<List<DriveFileEntry>>(
          future: _folders,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Falha ao consultar pastas: ${snapshot.error}');
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final folders = snapshot.data!;
            if (folders.isEmpty) return const Center(child: Text('Nenhuma subpasta aqui.'));
            return ListView(children: [for (final folder in folders)
              ListTile(leading: const Icon(Icons.folder_outlined),
                title: Text(folder.name),
                onTap: () => setState(() { _stack.add(_DriveFolderSelection(folder.id, folder.name)); _refresh(); }))]);
          })),
      ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _stack.length == 1 ? null : () => Navigator.pop(context, _stack.last),
        child: const Text('Usar esta pasta')),
    ],
  );
}

class _DriveLinkDialog extends StatefulWidget {
  const _DriveLinkDialog({required this.folder, required this.repositories});
  final _DriveFolderSelection folder;
  final List<GitHubRepository> repositories;
  @override
  State<_DriveLinkDialog> createState() => _DriveLinkDialogState();
}

class _DriveLinkDialogState extends State<_DriveLinkDialog> {
  late GitHubRepository _repo = widget.repositories.first;
  late final TextEditingController _branch = TextEditingController(text: _repo.defaultBranch);
  @override
  void dispose() { _branch.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Vincular pasta'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Drive: ${widget.folder.name}'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _repo.fullName,
        decoration: const InputDecoration(labelText: 'Repositório GitHub'),
        items: [for (final repository in widget.repositories)
          DropdownMenuItem(value: repository.fullName, child: Text(repository.fullName,
            overflow: TextOverflow.ellipsis))],
        onChanged: (value) { if (value == null) return;
          setState(() { _repo = widget.repositories.firstWhere((r) => r.fullName == value);
            _branch.text = _repo.defaultBranch; }); },
      ),
      const SizedBox(height: 10),
      TextField(controller: _branch, decoration: const InputDecoration(
        labelText: 'Branch existente', hintText: 'main')),
      const SizedBox(height: 10),
      const Text('A sincronização exige que a branch já exista. '
          'O envio automático vem desativado por segurança.'),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: () {
        final branch = _branch.text.trim();
        if (branch.isEmpty || branch.contains('..') || branch.startsWith('/') ||
            branch.endsWith('/') || branch.contains(' ') || branch.contains('\\')) return;
        Navigator.pop(context, DriveSyncLink(
          folderId: widget.folder.id,
          folderName: widget.folder.name,
          repositoryFullName: _repo.fullName,
          branch: branch));
      }, child: const Text('Vincular')),
    ],
  );
}
