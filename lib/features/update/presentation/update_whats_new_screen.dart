import 'package:flutter/material.dart';

class UpdateWhatsNewScreen extends StatelessWidget {
  static const releaseNotesVersion = '2.0.132';

  const UpdateWhatsNewScreen({
    required this.versionLabel,
    required this.onContinue,
    this.requireConfirmation = false,
    super.key,
  });

  final String versionLabel;
  final Future<void> Function() onContinue;
  final bool requireConfirmation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.new_releases_rounded,
                          color: scheme.onPrimaryContainer,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Novidades da atualização',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.45,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'GitHub Manager $versionLabel',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Esta tela aparece automaticamente uma única vez depois de cada nova versão. Você pode rever as novidades depois em Configurações.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 24),
                    const _UpdateItem(
                      icon: Icons.pause_circle_outline_rounded,
                      title: 'Importação de Secrets .env',
                      description: 'Importe arquivos .env, .env.local, TXT, JSON ou XML, mesmo que o Android oculte arquivos iniciados por ponto. O app valida o conteúdo antes de salvar.',
                    ),
                    const SizedBox(height: 12),
                    const _UpdateItem(
                      icon: Icons.speed_rounded,
                      title: 'Excluir todos os Secrets',
                      description: 'Nova ação com confirmação digitada, contagem, progresso, resultado individual e opção de copiar relatório, sem revelar valores secretos.',
                    ),
                    const SizedBox(height: 12),
                    const _UpdateItem(
                      icon: Icons.shield_outlined,
                      title: 'Segurança preservada',
                      description: 'As operações afetam apenas Secrets do repositório selecionado, com checagem de permissão. Downloads, Builds e demais módulos permanecem inalterados.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('whats_new_continue'),
                  onPressed: () async => onContinue(),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Continuar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!requireConfirmation) return content;
    return BackButtonListener(
      onBackButtonPressed: () async => true,
      child: content,
    );
  }
}

class _UpdateItem extends StatelessWidget {
  const _UpdateItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
