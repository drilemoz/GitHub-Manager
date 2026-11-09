# Google Drive → GitHub Manager

## Estado da versão 2.0.143

Funciona quando o app está aberto ou volta ao primeiro plano. A consulta agendada é best-effort, a cada 30 minutos enquanto a UI está em execução, e na retomada (intervalo mínimo de 15 min). **Não há ainda um worker Android em segundo plano com app fechado.** A opção automática é desligada em cada novo vínculo; ao ativar, o próprio usuário aceita a publicação das versões seguras sem confirmação extra.

## Configuração necessária (desenvolvedor)

1. No Google Cloud, habilitar Google Drive API e configurar a tela de consentimento OAuth. Para uso pessoal em modo de teste, incluir sua conta entre os usuários de teste. O escopo `https://www.googleapis.com/auth/drive.readonly` é restrito. Para distribuição pública pode ser exigida verificação Google e avaliação adicional; não declarar conformidade antes da aprovação.
2. Criar um OAuth Client ID **Android** com pacote `br.com.githubmanager.app` e SHA-1 do certificado efetivamente usado para assinar o APK. Debug e Release são certificados diferentes. Não publicar a chave privada.
3. Criar também um OAuth Client ID **Web** no mesmo projeto Google Cloud. A integração Android do `google_sign_in` necessita do Web client ID como `serverClientId` quando não se usa `google-services.json`.
4. Compilar com `--dart-define=GOOGLE_WEB_CLIENT_ID=...` fornecendo o identificador Web OAuth (não é um secret de senha). Por exemplo: `flutter build apk --release --dart-define=GOOGLE_WEB_CLIENT_ID=SEU_ID.apps.googleusercontent.com`. Configure `GOOGLE_WEB_CLIENT_ID` nas **Variables** do repositório GitHub, em Settings → Secrets and variables → Actions → Variables. Os workflows android-apk e android-release passam esse valor ao Flutter. Sem isso a conexão pode falhar por configuração do cliente.
5. Abrir Configurações → Sincronização Google Drive → Conectar/Autorizar, escolher a pasta em `Meu Drive/Projetos/Nome do App` e associar ao repositório + branch existente. A pasta deve conter **exatamente um ZIP**, a versão canônica do projeto.
6. Tocar em `Verificar agora`; conferir a prévia e enviar. Opcionalmente ativar o switch para publicações seguras durante as verificações em primeiro plano.

## Segurança

A integração é só leitura no Drive. O app não salva access/refresh tokens no banco; utiliza as autorizações da conta gerenciada pelo Google Sign-In. O ZIP temporário é SHA-256-verified, limitado a 300 MB e analisado por `LocalProjectService`. Compara versão interna e identidade com `ProjectSafetyCheck`, e exige permission preflight conclusivo e `previewZipSync` sem remoções. Arquivos ZIP antigos/iguais, metadados ambíguos e exclusões são bloqueados nesta tela; o fluxo manual existente permanece para revisão. Vínculos, último arquivo confirmado e uploads pendentes ficam no banco SQLite local; um ID pendente só é marcado concluído após commit ou status final de upload. Falhas requerem inspeção na Central de Envios.

## Limitações

- `pubspec.lock` precisa ser regenerado com a dependência `google_sign_in` e registrado no repositório antes de restaurar `--enforce-lockfile` nos workflows.
- Sem certificado Android e cliente Web OAuth corretos, o login não funciona. Não se pode aproveitar automaticamente a conexão do Google Drive do ChatGPT.
- Android pode suspender temporizadores quando o aplicativo não está ativo; não é monitoramento de 24 horas.
- O download é de arquivo Drive armazenado, não Google Docs/Sheets nativos. Não acessa pastas compartilhadas por URL automaticamente; o usuário escolhe pastas a partir do Meu Drive.
- Conta trocada, token expirado ou permissão revogada interrompem a verificação até reconectar.
