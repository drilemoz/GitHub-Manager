import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/app/router/app_router.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/core/providers/core_providers.dart';
import 'package:github_manager/core/telemetry/app_telemetry_service.dart';
import 'package:github_manager/core/widgets/installed_version_banner.dart';
import 'package:github_manager/features/downloads/data/download_manager_service.dart';
import 'package:github_manager/features/downloads/domain/managed_download.dart';
import 'package:github_manager/features/downloads/presentation/download_providers.dart';
import 'package:github_manager/features/update/application/self_update_service.dart';

class SelfUpdateCoordinator {
  static bool _busy = false;

  static Future<void> check({bool manual = false}) async {
    if (_busy) return;
    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _busy = true;
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final manager = container.read(downloadManagerProvider);
      final service = SelfUpdateService(container.read(githubApiClientProvider));
      Future<SelfUpdateRelease?> lookup() async {
        final label = await InstalledVersionBanner.versionLabel;
        int? code = int.tryParse(label.split('+').last);
        try {
          final local = await PlatformActions.getInstalledAppInfo(selfUpdatePackage)
              .timeout(const Duration(seconds: 3));
          code = local.versionCode ?? code;
        } catch (_) {
          // A versão embutida no APK é o fallback local, sem rede.
        }
        if (code == null) throw StateError('Versão instalada não identificada');
        return service.check(code);
      }
      final future = lookup();
      if (manual && context.mounted) {
        await showDialog<void>(context: context, builder: (_) => _SelfUpdateDialog(
          future: future, manager: manager));
      } else {
        final release = await future;
        if (release != null && context.mounted &&
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
          await showDialog<void>(context: context, builder: (_) => _SelfUpdateDialog(
            future: Future.value(release), manager: manager));
        }
      }
    } catch (error, stackTrace) {
      await AppTelemetryService.instance.recordError(source: 'self_update.check',
        error: error, stackTrace: stackTrace);
    } finally {
      _busy = false;
    }
  }
}

class _SelfUpdateDialog extends StatefulWidget {
  const _SelfUpdateDialog({required this.future, required this.manager});
  final Future<SelfUpdateRelease?> future;
  final DownloadManagerService manager;
  @override
  State<_SelfUpdateDialog> createState() => _SelfUpdateDialogState();
}

class _SelfUpdateDialogState extends State<_SelfUpdateDialog> {
  ManagedDownload? _item;
  StreamSubscription<List<ManagedDownload>>? _subscription;
  bool _installing = false;
  String? _notice;

  void _download(SelfUpdateRelease release) {
    _subscription?.cancel();
    final existing = widget.manager.items.where((item) =>
      item.repositoryFullName == selfUpdateRepository &&
      item.fileName == release.fileName && item.isActive);
    final item = existing.isNotEmpty ? existing.first : release.authenticated
        ? widget.manager.startReleaseAsset(title: 'Atualização do GitHub Manager',
          fileName: release.fileName, repositoryFullName: selfUpdateRepository,
          assetId: release.assetId, isApk: true)
        : widget.manager.startPublicUrl(title: 'Atualização do GitHub Manager',
          fileName: release.fileName, repositoryFullName: selfUpdateRepository,
          url: release.url, isApk: true);
    setState(() { _item = item; _notice = null; });
    var opened = false;
    void onProgress() {
      if (!mounted) return;
      setState(() {});
      if (!opened && item.status == ManagedDownloadStatus.completed &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        opened = true;
        unawaited(_install());
      }
    }
    _subscription = widget.manager.stream.listen((_) => onProgress());
    onProgress();
  }

  Future<void> _install() async {
    final path = _item?.localPath;
    if (path == null || _installing) return;
    setState(() { _installing = true; _notice = null; });
    try {
      final result = await PlatformActions.installApk(path);
      if (mounted && result == 'permission_required') {
        setState(() => _notice = 'Autorize a instalação e toque em Instalar novamente.');
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Não foi possível abrir o instalador.');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SelfUpdateRelease?>(
    future: widget.future,
    builder: (context, snapshot) {
      final release = snapshot.data;
      final item = _item;
      final loading = snapshot.connectionState != ConnectionState.done;
      final complete = item?.status == ManagedDownloadStatus.completed;
      final active = item?.isActive == true;
      return AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: Text(loading ? 'Verificando atualização' : snapshot.hasError
          ? 'Consulta indisponível' : release == null ? 'Nenhuma atualização disponível'
          : 'Nova versão ${release.version}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (loading) const LinearProgressIndicator()
          else if (snapshot.hasError) const Text('Não foi possível consultar as Releases. Tente novamente em Opções.')
          else if (release == null) const Text('Nenhum APK oficial mais recente foi encontrado.')
          else ...[
            FutureBuilder<String>(future: InstalledVersionBanner.versionLabel,
              builder: (_, local) => Text('Instalada: ${local.data?.split('+').first ?? '—'}  •  Nova: ${release.version}')),
            const SizedBox(height: 12),
            if (item == null) const Text('Baixe o APK oficial. Seus dados e configurações serão preservados pela atualização do Android.')
            else if (active) ...[
              LinearProgressIndicator(value: item.progress),
              const SizedBox(height: 8),
              Text(item.progress == null ? 'Baixando…' : '${(item.progress! * 100).round()}%'),
            ] else if (complete) const Text('Download concluído. Confirme no instalador do Android.')
            else Text(item.errorMessage ?? 'Download interrompido. Você pode tentar novamente.'),
            if (_notice != null) Text(_notice!),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(),
            child: Text(active ? 'Em segundo plano' : release == null ? 'Fechar' : 'Depois')),
          if (release != null && !active)
            FilledButton.icon(onPressed: _installing ? null : complete ? _install : () => _download(release),
              icon: Icon(complete ? Icons.install_mobile_rounded : Icons.download_rounded),
              label: Text(complete ? 'Instalar' : item == null ? 'Atualizar' : 'Tentar novamente')),
        ],
      );
    },
  );
}
