import 'package:flutter/material.dart';

class UpdateWhatsNewScreen extends StatelessWidget {
  static const releaseNotesVersion = '2.0.148';

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
                      icon: Icons.cloud_done_outlined,
                      title: 'Correção dos testes visuais da versão 2.0.147',
                      description: 'O contrato de cantos reconhece somente os cartões redesenhados nas telas do projeto e do Drive, mantendo a validação global.',
                    ),
                    const SizedBox(height: 12),
                    const _UpdateItem(
                      icon: Icons.phone_android_rounded,
                      title: 'Verificação mais precisa de APKs instalados',
                      description: 'Versão visível igual não é mais apresentada como atualização confirmada sem versionCode remoto; consulte novamente com um toque.',
                    ),
                    const SizedBox(height: 12),
                    const _UpdateItem(
                      icon: Icons.dashboard_customize_outlined,
                      title: 'Tela do projeto reorganizada',
                      description: 'Nome do projeto, ações rápidas e comparação de versões têm mais espaço e melhor leitura.',
                    ),
                    const SizedBox(height: 12),
                    const _UpdateItem(
                      icon: Icons.shield_outlined,
                      title: 'Segurança preservada',
                      description: 'Google Drive permanece somente leitura; versões incertas, exclusões e permissões inconclusivas continuam protegidas.',
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
