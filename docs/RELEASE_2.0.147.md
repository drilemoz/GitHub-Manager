# GitHub Manager 2.0.147+200161

## Correções

- Google Drive: configurar ID OAuth Web sem recompilar, visualizar SHA-1 do certificado da instalação atual e receber diagnóstico em vez de exceção bruta. Sem credenciais do próprio Google Cloud o login **não** funciona; não há chave fictícia.
- O Client ID Web pode ser fornecido por `--dart-define=GOOGLE_WEB_CLIENT_ID=...` em CI ou inserido no app; a credencial local prevalece. Depois de mudar o ID de uma sessão já inicializada, é necessário fechar e reabrir o aplicativo.
- Criar OAuth Android para `br.com.githubmanager.app` e SHA-1 do APK efetivamente instalado. Ativar Drive API, consentimento, conta de teste e permissões requeridas.
- APK: consulta local, botão atualizar, distinção entre versão igual não verificada e versão confirmada com `versionCode` remoto. Não pressupõe capacidade de enumerar todos os pacotes Android.
- Interface: cabeçalho responsivo, status com versões lado a lado, cartão de conexão e diagnóstico da conta Google.

## Segurança e limitações

Drive apenas leitura e envio pelo fluxo seguro existente. SHA-1 é impressão digital pública do certificado, não é uma chave privada. A versão remota continua sem código verificado até que o próprio APK seja inspecionado ou seja disponibilizado metadado confiável vinculado à publicação. Na ausência de visibilidade de pacote no Android 11+, não afirmar que o app foi desinstalado. APK e login ainda não foram validados em aparelho.
