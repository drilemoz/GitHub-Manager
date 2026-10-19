import 'package:flutter/material.dart';
import 'package:github_manager/core/widgets/app_main_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:github_manager/app/theme/app_theme_controller.dart';
import 'package:github_manager/core/background/build_monitor_service.dart';
import 'package:github_manager/core/errors/app_exception.dart';
import 'package:github_manager/core/providers/core_providers.dart';
import 'package:github_manager/core/platform/platform_actions.dart';
import 'package:github_manager/core/platform/system_ui_settings.dart';
import 'package:github_manager/core/widgets/adaptive_dialog.dart';
import 'package:github_manager/core/widgets/centered_notice.dart';
import 'package:github_manager/core/widgets/installed_version_banner.dart';
import 'package:github_manager/features/auth/presentation/auth_providers.dart';
import 'package:github_manager/features/home/domain/github_profile.dart';
import 'package:github_manager/features/home/presentation/github_profile_edit_dialog.dart';
import 'package:github_manager/features/home/presentation/home_providers.dart';
import 'package:github_manager/features/repositories/presentation/repository_providers.dart';
import 'package:github_manager/features/repositories/data/repository_description_settings.dart';
import 'package:github_manager/features/uploads/data/upload_recovery_settings.dart';
import 'package:github_manager/features/downloads/data/download_cleanup_settings.dart';
import 'package:github_manager/features/update/presentation/update_whats_new_screen.dart';
import 'package:go_router/go_router.dart';

part 'settings_widgets.dart';
part 'settings_screen_actions.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with _SettingsScreenActions {
  @override
  void initState() {
    super.initState();
    initializeSettingsState();
  }

















  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(githubProfileProvider);
    final api = _apiSettings;
    final descriptionPreference = ref.watch(showRepositoryDescriptionsProvider);
    return Scaffold(
      bottomNavigationBar: const AppMainNavigation(selectedIndex: 4),
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        children: [
          const _SectionTitle('Aparência'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Escuro')),
                ],
                selected: {_themeMode},
                onSelectionChanged: (value) => _setTheme(value.first),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ValueListenableBuilder<bool>(
              valueListenable: SystemUiSettings.instance,
              builder: (context, fullScreenEnabled, _) => SwitchListTile(
                secondary: const Icon(Icons.fullscreen_rounded),
                title: const Text('Tela inteira'),
                subtitle: const Text(
                  'Quando ativada, tenta ocultar as barras do Android. '
                  'Desative para manter as barras visíveis. '
                  'Versões recentes do Android podem limitar o modo imersivo.',
                ),
                value: fullScreenEnabled,
                onChanged: _updatingFullScreen ? null : _setFullScreenEnabled,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Página inicial'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notes_rounded),
              title: const Text('Mostrar descrição dos repositórios'),
              subtitle: const Text(
                'Exibir o texto completo da descrição abaixo do nome de cada repositório na Home, sem cortar linhas ou caracteres.',
              ),
              value: descriptionPreference.asData?.value ?? false,
              onChanged: descriptionPreference.isLoading
                  ? null
                  : _setShowRepositoryDescriptions,
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Notificações'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Avisar quando builds terminarem'),
              subtitle: const Text(
                'Enquanto o aplicativo está ativo, verifica builds recentes em intervalos curtos. '
                'Em segundo plano, o Android controla a frequência mínima das verificações. '
                'Toque no aviso para abrir a execução correspondente. Falhas têm prioridade sobre sucessos.',
              ),
              value: _buildNotificationsEnabled ?? true,
              onChanged: _buildNotificationsEnabled == null
                  ? null
                  : _setBuildNotifications,
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Envios'),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.health_and_safety_outlined),
              title: const Text('Recuperação automática de envios'),
              subtitle: const Text(
                'Se a atualização incremental for recusada na criação da árvore Git, tenta reconstruir a árvore completa. Erros temporários de rede e HTTP 5xx também podem ser repetidos com espera curta. O método de arquivos individuais nunca é iniciado automaticamente.',
              ),
              value: _automaticUploadRecoveryEnabled ?? true,
              onChanged: _automaticUploadRecoveryEnabled == null
                  ? null
                  : _setUploadAutomaticRecovery,
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Integrações'),
          profile.when(
            loading: () => const _IntegrationLoadingCard(title: 'GitHub'),
            error: (_, _) => _IntegrationCard(
              icon: Icons.code_rounded,
              title: 'GitHub',
              subtitle: 'Token não configurado ou inválido',
              status: 'Configurar',
              onTap: _replaceGitHubToken,
            ),
            data: (data) => _IntegrationCard(
              icon: Icons.code_rounded,
              title: 'GitHub',
              subtitle: '${data.name?.isNotEmpty == true ? data.name : data.login} • @${data.login}',
              status: 'Conectado',
              onTap: () => _showGitHubIntegration(data),
            ),
          ),
          const SizedBox(height: 8),
          _IntegrationCard(
            icon: Icons.auto_awesome_rounded,
            title: api?['name']?.isNotEmpty == true ? api!['name']! : 'Groq / API personalizada',
            subtitle: api == null
                ? 'Carregando configuração…'
                : 'IA opcional para futuros resumos e explicações de logs. '
                    'Hoje não é necessária para usar o GitHub Manager.',
            status: api?['apiKey']?.isNotEmpty == true ? 'Configurada' : 'Opcional',
            onTap: _editApi,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text(
              'A integração Groq está preparada para recursos de IA, como resumir logs e explicar erros de build. '
              'Nesta versão ela ainda não é usada automaticamente; você pode deixar sem chave.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Transferências'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Central de Envios'),
                  subtitle: const Text('Acompanhar envios, builds e tentativas interrompidas.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/uploads'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('Central de Downloads'),
                  subtitle: const Text('Acompanhar APKs, ZIPs, artifacts e logs.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/downloads'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Limpeza automática dos downloads'),
                  subtitle: Text(
                    _downloadCleanupMode == null
                        ? 'Carregando preferência…'
                        : '${DownloadCleanupSettings.label(_downloadCleanupMode!)} • '
                            'somente arquivos desta pasta gerenciados pelo aplicativo',
                  ),
                  trailing: const Icon(Icons.tune_rounded),
                  onTap: _downloadCleanupMode == null ? null : _chooseDownloadCleanupMode,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Informações do aparelho'),
          const _DeviceInformationCard(),
          const SizedBox(height: 18),
          const _SectionTitle('Ajuda e segurança'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_center_outlined),
                  title: const Text('Ajuda do aplicativo'),
                  subtitle: const Text(
                    'Guia geral, identidade do projeto, builds, APKs e solução de avisos.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/help'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: const Text('Assistente de configuração'),
                  subtitle: const Text('Rever token, permissões e teste de conexão.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/setup'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Chave / token GitHub atual'),
                  subtitle: const Text('Exibir, ocultar ou copiar o token salvo neste aparelho.'),
                  trailing: const Icon(Icons.visibility_outlined),
                  onTap: _showGitHubTokenBackup,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.monitor_heart_outlined),
                  title: const Text('Erros e telemetria'),
                  subtitle: const Text(
                    'Revisar crashes e falhas capturadas localmente, copiar ou exportar um relatório.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push('/settings/telemetry'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.build_circle_outlined),
                  title: const Text('Diagnóstico de dados locais'),
                  subtitle: const Text(
                    'Verificar e reparar o banco interno sem apagar o token GitHub.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _repairLocalData,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Versão instalada'),
          const _InstalledVersionCard(),
          const SizedBox(height: 18),
          const _SectionTitle('Sobre e novidades'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('GitHub Manager'),
                  subtitle: Text(
                    'Gerenciador GitHub para Android\n'
                    'Desenvolvedor: @AdriedsonLemos',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.new_releases_outlined),
                  title: const Text('Novidades desta versão'),
                  subtitle: const Text('Rever a tela exibida automaticamente após a atualização.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _showCurrentWhatsNew,
                ),
                const Divider(height: 1),
                ExpansionTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Últimas 3 mudanças'),
                  subtitle: const Text('Toque para expandir'),
                  initiallyExpanded: false,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: const [
                    _ChangeNote(
                      version: '2.0.135',
                      text: 'Reconhece STATUS.json do Termux Manager, corrige a leitura de caminhos GitHub e resolve dois testes do Android APK #124.',
                    ),
                    _ChangeNote(
                      version: '2.0.134',
                      text: 'Corrige a versão canônica do workflow Android APK #123 e restaura o histórico documental com teste de regressão.',
                    ),
                    _ChangeNote(
                      version: '2.0.133',
                      text: 'Melhora a detecção de app instalado, redesenha o card APK e mostra versão/SDK no topo do projeto.',
                    ),
                  ],
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text('Apoiar via Pix'),
                  subtitle: const Text('adriedson@outlook.com • toque para copiar'),
                  trailing: const Icon(Icons.copy_rounded),
                  onTap: () => _copySupportText(
                    'adriedson@outlook.com',
                    'Chave Pix copiada.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.feedback_outlined),
                  title: const Text('Fale conosco / Feedback'),
                  subtitle: const Text('adriedson@outlook.com • toque para copiar'),
                  trailing: const Icon(Icons.copy_rounded),
                  onTap: () => _copySupportText(
                    'adriedson@outlook.com',
                    'E-mail de contato copiado.',
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Text(
                    'GitHub Manager é um projeto independente. Não possui parceria, afiliação, endosso ou patrocínio do GitHub.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
