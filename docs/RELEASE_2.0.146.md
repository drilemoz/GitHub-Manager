# GitHub Manager 2.0.146+200160

## Correção do Android APK #135

O workflow de compilação da versão 2.0.145 passou em `flutter analyze` e executou 311 testes, dos quais 310 passaram e 1 falhou. O teste `verified_upload_ui_contract_test.dart` verificava a expressão antiga `final mustBlock = check.blocked || syncPreview == null`, incompatível com as preferências de envio manual introduzidas na versão 2.0.145.

O contrato foi atualizado para conferir as garantias atuais:
- **Prévia obrigatória:** sem comparação de arquivos, envio bloqueado em qualquer configuração.
- **Divergência de identidade:** bloqueada por padrão; exceção somente se a preferência manual for habilitada.
- **Confirmação por digitação:** toda exceção de identidade exige digitar exatamente o nome completo do repositório, mesmo que os limiares de confirmação de alterações e remoções sejam desativados.
- **ZIP íntegro:** snapshot privado, verificação SHA-256 e bloqueio de alterações entre seleção e envio.
- **Drive automático:** a exceção de identidade do envio manual não altera sua política restritiva.

Nenhuma lógica de upload em produção foi alterada nesta versão. Incremento sequencial de versão e documentação sincronizados.

## Validação

O log do workflow #135 comprova análise Flutter concluída e 310 testes passando antes da falha de contrato. Nesta entrega foram feitas verificações locais de estrutura e integridade do ZIP e do versionamento. **Ainda não há teste Flutter, APK gerado ou instalação Android validada para a 2.0.146**. Executar o workflow Android APK novamente.
