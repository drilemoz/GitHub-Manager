import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/features/downloads/data/download_manager_service.dart';
import 'package:github_manager/features/builds/domain/action_artifact.dart';
import 'package:github_manager/features/repositories/data/play_aab_discovery_service.dart';
import 'package:github_manager/features/repositories/domain/play_aab_discovery.dart';
import 'package:github_manager/features/repositories/data/play_readiness_service.dart';
import 'package:github_manager/features/repositories/domain/github_repository.dart';
import 'package:github_manager/features/repositories/domain/play_readiness_report.dart';

Future<void> showPlayReadinessDialog({
  required BuildContext context,
  required GitHubRepository repository,
  required PlayReadinessService service,
  required PlayAabDiscoveryService aabService,
  required DownloadManagerService downloads,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _PlayReadinessDialog(
      repository: repository,
      service: service,
      aabService: aabService,
      downloads: downloads,
    ),
  );
}

class _PlayReadinessDialog extends StatefulWidget {
  const _PlayReadinessDialog({
    required this.repository,
    required this.service,
    required this.aabService,
    required this.downloads,
  });

  final GitHubRepository repository;
  final PlayReadinessService service;
  final PlayAabDiscoveryService aabService;
  final DownloadManagerService downloads;

  @override
  State<_PlayReadinessDialog> createState() => _PlayReadinessDialogState();
}

class _PlayReadinessDialogState extends State<_PlayReadinessDialog> {
  late Future<PlayReadinessReport> _future;
  late Future<PlayAabDiscoveryResult> _aabFuture;
  final Set<String> _startedAabDownloads = <String>{};
  bool _copying = false;
  int _revision = 0;
  String? _copyFeedback;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _revision++;
    _copying = false;
    _copyFeedback = null;
    _future = widget.service.inspect(widget.repository);
    _aabFuture = widget.aabService.search(widget.repository.fullName);
    _startedAabDownloads.clear();
  }

  Future<void> _copyReport(PlayReadinessReport report) async {
    if (_copying) return;
    final revision = _revision;
    setState(() {
      _copying = true;
      _copyFeedback = null;
    });
    try {
      await Clipboard.setData(ClipboardData(
        text: report.toCopyText(repositoryFullName: widget.repository.fullName),
      ));
      if (!mounted || revision != _revision) return;
      setState(() => _copyFeedback = 'Relatório copiado para a área de transferência.');
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() => _copyFeedback = 'Não foi possível copiar o relatório.');
    } finally {
      if (mounted && revision == _revision) setState(() => _copying = false);
    }
  }

  String _aabKey(PlayAabCandidate candidate) =>
      '${candidate.origin.name}:${candidate.id}';

  void _downloadAab(PlayAabCandidate candidate) {
    final key = _aabKey(candidate);
    if (_startedAabDownloads.contains(key)) return;
    try {
      if (candidate.origin == PlayAabOrigin.release) {
        widget.downloads.startReleaseAsset(
          title: 'Google Play • ${candidate.name}',
          fileName: candidate.name,
          repositoryFullName: widget.repository.fullName,
          assetId: candidate.id,
          isApk: false,
        );
      } else {
        widget.downloads.startArtifactAab(
          repositoryFullName: widget.repository.fullName,
          artifact: ActionArtifact(
            id: candidate.id,
            name: candidate.name,
            sizeBytes: candidate.sizeBytes,
            expired: false,
            createdAt: candidate.date,
            workflowRunId: candidate.runId,
          ),
        );
      }
      setState(() {
        _startedAabDownloads.add(key);
        _copyFeedback = 'Download iniciado. Acompanhe pela Central de Downloads.';
      });
    } catch (_) {
      setState(() => _copyFeedback = 'Não foi possível iniciar o download do AAB.');
    }
  }

  Future<void> _copyAabInfo(PlayAabCandidate candidate) async {
    try {
      await Clipboard.setData(ClipboardData(text: [
        'AAB para Google Play',
        'Repositório: ${widget.repository.fullName}',
        'Arquivo/candidato: ${candidate.name}',
        'Origem: ${candidate.sourceLabel}',
        'Identificação: ${candidate.confidenceLabel}',
        if (candidate.version != null) 'Versão/tag: ${candidate.version}',
        if (candidate.runId != null) 'Workflow run: ${candidate.runId}',
        if (candidate.date != null) 'Data: ${candidate.date!.toLocal().toIso8601String()}',
        'AAB não é instalável diretamente no Android.',
      ].join('\n')));
      if (mounted) setState(() => _copyFeedback = 'Informações do AAB copiadas.');
    } catch (_) {
      if (mounted) setState(() => _copyFeedback = 'Falha ao copiar informações do AAB.');
    }
  }

  Widget _buildAabLookup() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Android App Bundle (AAB)',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        FutureBuilder<PlayAabDiscoveryResult>(
          future: _aabFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _AuditMessage('Buscando AABs em Releases e Artifacts…');
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const _AuditMessage('Não foi possível buscar os AABs. Toque em Reavaliar para tentar novamente.');
            }
            return _PlayAabDiscoverySection(
              result: snapshot.data!,
              startedKeys: _startedAabDownloads,
              onDownload: _downloadAab,
              onCopy: _copyAabInfo,
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 5, 5),
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, color: scheme.primary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Preparação para Google Play',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            )),
                        Text(widget.repository.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Reavaliar',
                    onPressed: () => setState(_refresh),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<PlayReadinessReport>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAabLookup(),
                          const SizedBox(height: 16),
                          const _AuditMessage('Verificando arquivos do repositório para auditoria…'),
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(minHeight: 3),
                        ],
                      ),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildAabLookup(),
                          const Divider(height: 22),
                          const Text('Não foi possível consultar o código do projeto.'),
                          const SizedBox(height: 5),
                          const Text('Verifique rede, permissões, branch e limites da API. Nenhum resultado foi presumido.'),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => setState(_refresh),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Tentar novamente'),
                          ),
                        ],
                      ),
                    );
                  }
                  final report = snapshot.data!;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildAabLookup(),
                        const Divider(height: 25),
                        Text('Auditoria de publicação',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            )),
                        const SizedBox(height: 7),
                        Text('Branch: ${report.branch}', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 7),
                        if (!report.androidProject) ...[
                          _AuditMessage(report.note ?? 'Tipo do projeto não reconhecido.'),
                        ] else ...[
                          Text('Código: ${report.verified} indícios positivos • ${report.attention} pontos de atenção • ${report.unknown} não confirmados',
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          const _AuditMessage('Avaliação parcial do código-fonte. Não confirma aprovação nem publicação na Play Console.'),
                          if (report.note != null) ...[
                            const SizedBox(height: 8),
                            _AuditMessage(report.note!),
                          ],
                          const SizedBox(height: 14),
                          Text('Verificações técnicas', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 7),
                          for (final check in report.automatic) _PlayCheckTile(check: check),
                          const SizedBox(height: 12),
                          Text('Confirmar na Play Console', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 7),
                          for (final check in report.manual) _PlayCheckTile(check: check),
                        ],
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () => PlatformActions.openUri(
                            'https://support.google.com/googleplay/android-developer/answer/11926878?hl=pt-BR',
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: const Text('Requisitos oficiais de API'),
                        ),
                        TextButton.icon(
                          onPressed: () => PlatformActions.openUri(
                            'https://play.google.com/console/',
                          ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 17),
                          label: const Text('Abrir Play Console'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FutureBuilder<PlayReadinessReport>(
                          future: _future,
                          builder: (context, snapshot) {
                            final canCopy = snapshot.connectionState == ConnectionState.done &&
                                snapshot.hasData && !snapshot.hasError && !_copying;
                            return OutlinedButton.icon(
                              onPressed: canCopy
                                  ? () => _copyReport(snapshot.data!)
                                  : null,
                              icon: Icon(_copyFeedback?.startsWith('Relatório copiado') == true
                                  ? Icons.check_rounded
                                  : Icons.copy_rounded),
                              label: Text(_copyFeedback?.startsWith('Relatório copiado') == true
                                  ? 'Copiado'
                                  : 'Copiar relatório'),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                  if (_copyFeedback != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      _copyFeedback!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayAabDiscoverySection extends StatelessWidget {
  const _PlayAabDiscoverySection({
    required this.result,
    required this.startedKeys,
    required this.onDownload,
    required this.onCopy,
  });

  final PlayAabDiscoveryResult result;
  final Set<String> startedKeys;
  final void Function(PlayAabCandidate) onDownload;
  final Future<void> Function(PlayAabCandidate) onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!result.hasCandidates) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.complete
              ? 'AAB não encontrado nos Releases nem nos Artifacts pesquisados.'
              : 'AAB não localizado nas fontes consultadas. A busca foi parcial.'),
          const SizedBox(height: 5),
          const _AuditMessage('Artifacts com nomes genéricos podem conter um AAB, mas o GitHub não informa os arquivos internos na listagem. Confira a tela Artifacts.'),
          for (final warning in result.warnings) _AuditMessage(warning),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${result.candidates.length} resultado(s) • Releases e Artifacts',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 7),
        for (final candidate in result.candidates.take(5)) ...[
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(candidate.directlyConfirmed
                        ? Icons.inventory_2_outlined
                        : Icons.archive_outlined,
                        size: 19, color: scheme.primary),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(candidate.name,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          )),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('${candidate.sourceLabel}${candidate.version == null ? '' : ' • ${candidate.version}'}'
                    '${candidate.runId == null ? '' : ' • Build #${candidate.runId}'}',
                    style: Theme.of(context).textTheme.bodySmall),
                if (candidate.date != null)
                  Text('Publicado: ${candidate.date!.toLocal().toIso8601String().replaceFirst('T', ' ').substring(0, 16)}',
                      style: Theme.of(context).textTheme.bodySmall),
                Text(candidate.confidenceLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: startedKeys.contains('${candidate.origin.name}:${candidate.id}')
                            ? null
                            : () => onDownload(candidate),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(startedKeys.contains('${candidate.origin.name}:${candidate.id}')
                            ? 'Iniciado' : 'Baixar AAB'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copiar informações do AAB',
                      onPressed: () => onCopy(candidate),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
        ],
        if (result.candidates.length > 5)
          const _AuditMessage('Exibidos os cinco candidatos de maior prioridade.'),
        if (!result.complete)
          const _AuditMessage('Busca parcial: uma das fontes não pôde ser consultada.'),
        for (final warning in result.warnings) _AuditMessage(warning),
        const _AuditMessage('Artifacts são ZIPs: o app confirma e extrai o .aab no download. O AAB não pode ser instalado diretamente no Android.'),
      ],
    );
  }
}

class _AuditMessage extends StatelessWidget {
  const _AuditMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

class _PlayCheckTile extends StatelessWidget {
  const _PlayCheckTile({required this.check});
  final PlayCheck check;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (check.state) {
      PlayCheckState.verified => Icons.check_circle_outline_rounded,
      PlayCheckState.attention => Icons.warning_amber_rounded,
      PlayCheckState.unknown => Icons.help_outline_rounded,
    };
    final color = switch (check.state) {
      PlayCheckState.verified => scheme.primary,
      PlayCheckState.attention => scheme.error,
      PlayCheckState.unknown => scheme.onSurfaceVariant,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(check.title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(check.detail, style: Theme.of(context).textTheme.bodySmall),
                  if (check.evidence != null)
                    Text('Fonte: ${check.evidence}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
