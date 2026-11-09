import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/core/providers/core_providers.dart';
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
      await drive.initialize();
      final store = ref.read(driveSyncStoreProvider);
      final links = await store.read();
      final repositories = await ref.read(repositoryServiceProvider).listRepositories();
      if (!mounted) return;
      setState(() {
        _email = drive.email;
        _links = links;
        _repositories = repositories.where((item) => !item.isArchived).toList();
      });
    } catch (error) {
      if (mounted) setState(() => _message = 'Não foi possível carregar: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    setState(() { _busyKey = 'connect'; _message = null; });
    try {
      final email = await ref.read(googleDriveReadServiceProvider).connect();
      if (mounted) setState(() => _email = email);
    } catch (error) {
      if (mounted) setState(() => _message = 'Conexão Google: $error');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Sincronização Google Drive'), actions: [
        IconButton(onPressed: _busyKey == null ? _load : null,
          tooltip: 'Atualizar', icon: const Icon(Icons.refresh_rounded))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Primeira etapa: conecte o Google Drive e associe cada '
            'pasta a um repositório. Os ZIPs são lidos, nunca alterados no Drive. '
            'Os envios usam a fila e as verificações de segurança do GitHub Manager.'),
        const SizedBox(height: 12),
        Card(child: ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(_email ?? 'Google Drive desconectado'),
          subtitle: const Text('Acesso somente de leitura. OAuth Google exigido.'),
          trailing: FilledButton.tonal(onPressed: _busyKey == null ? _connect : null,
            child: Text(_email == null ? 'Conectar' : 'Autorizar')),
        )),
        if (_loading) const LinearProgressIndicator(),
        if (_message != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
            child: SelectableText(_message!)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busyKey == null && _repositories.isNotEmpty ? _addLink : null,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Vincular pasta a repositório')),
        const SizedBox(height: 14),
        for (final link in _links)
          Card(child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(link.repositoryFullName, style: Theme.of(context).textTheme.titleMedium),
              Text('Pasta: ${link.folderName}'),
              Text('Branch: ${link.branch}'),
              if (link.lastCompletedFileId != null)
                const Text('Último ZIP registrado após publicação'),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enviar automaticamente ao verificar'),
                subtitle: const Text('Somente versão nova, sem remoções e com validação conclusiva'),
                value: link.automatic,
                onChanged: _busyKey != null ? null : (value) => _setAuto(link, value)),
              Wrap(spacing: 8, children: [
                FilledButton.icon(onPressed: _busyKey == null ? () => _check(link) : null,
                  icon: const Icon(Icons.sync_rounded), label: const Text('Verificar agora')),
                TextButton.icon(onPressed: _busyKey == null ? () => _remove(link) : null,
                  icon: const Icon(Icons.link_off_rounded), label: const Text('Desvincular')),
              ]),
            ]))),
        const SizedBox(height: 12),
        const Text('Segurança: versões antigas/iguais, identidade incerta, '
            'permissões não confirmadas e exclusões no GitHub nunca são '
            'publicadas por esta integração. Nesses casos, utilize o envio '
            'manual com revisão. A execução em segundo plano ainda será '
            'implementada em uma etapa posterior.'),
        TextButton.icon(onPressed: () => context.push('/uploads'),
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
