# GitHub Manager 2.0.143+200157

## Drive → GitHub (primeira etapa)

- Nova tela Configurações → Sincronização Google Drive.
- Google Sign-In 7.2.0 com autorização OAuth de leitura, navegação de pastas e vínculo explícito pasta → repositório → branch.
- Consulta ao ZIP único da pasta, download para snapshot privado, análise SHA-256, identificação de versão e comparação com o GitHub.
- Emissão de envio somente com versão interna nova, identidade confirmada, API e permissões conclusivas, prévia válida, sem exclusões; bloqueio sem bypass de mudanças destrutivas ou ambíguas.
- Reaproveitamento da fila de uploads existente com ID pendente persistido. Rechecagem quando o app está ativo ou volta ao primeiro plano (com opt-in).
- Não monitora com o aplicativo fechado e não altera/deleta arquivos no Drive.

## Dependências e validação

Google OAuth exige configurar credenciais Android (package/signature) e cliente web no Google Cloud e habilitar a API Google Drive. Nenhuma credencial foi inventada. Dependência nova ainda requer atualização real do pubspec.lock em Flutter. Sem SDK Flutter local, compilação, testes instrumentados Google/Drive e upload real permanecem pendentes.

## Riscos e próximos passos

- Testar a autenticação assinada e a API Drive no aparelho.
- Executar `flutter pub get` no Flutter da CI, salvar o `pubspec.lock` gerado e restaurar `--enforce-lockfile`.
- Validar os estados de uploads, concorrência de verificações e erros/revogações da conta.
- Depois de estabilizar a primeira etapa, implementar execução headless com WorkManager, credenciais silenciosas e notificações auditáveis.
