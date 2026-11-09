# GitHub Manager 2.0.145+200159

## Envio manual de ZIP com segurança configurável

A seção **Configurações → Envios** ganhou três controles:

1. **Permitir ZIP com identidade divergente** (desligado por padrão): ao ativar, uma divergência de nome do arquivo/pasta/metadados internos/repositório pode ser autorizada **apenas no envio manual**, após conferir a prévia e digitar exatamente `owner/repositório`. O aviso continua mostrando a causa e o risco de o Android ter retornado o arquivo errado.
2. **Confirmar muitas alterações**: digitar nome do repositório ao modificar 25, 100 (padrão) ou 250 arquivos novos + modificados, ou nunca pedir digitação por esse motivo (0).
3. **Confirmar exclusões de arquivos**: digitar nome ao remover pelo menos 1 (padrão), 5 ou 20 arquivos, ou desativar essa digitação adicional (0).

Se a divergência foi permitida, digitar o nome do repositório é obrigatório, independentemente das demais configurações. Uma única janela reúne os motivos quando mais de um limiar é atingido. Ela mostra o nome do ZIP selecionado, a identidade interna, SHA-256 e contagens de arquivos novos/modificados/removidos. A autorização não é gravada nem reaproveitada em envios posteriores.

## Ajuste da identificação do ZIP

A comparação foi corrigida para aceitar um qualificador simples **depois** da versão que integre o nome do projeto. Ex.: `AL-Sistemas-v2.0.7-VPS.zip` pode corresponder a `AL Sistemas VPS` internamente. Sufixos compostos de distribuição continuam tratados como não pertencentes ao nome, e projetos genuinamente diferentes continuam bloqueados por padrão.

## Barreiras preservadas

- A prévia de comparação GitHub × ZIP é obrigatória. Falha ao gerar a prévia impede envio mesmo com exceção habilitada.
- O ZIP é copiado para um snapshot gerenciado e sua integridade SHA-256 é validada antes do envio.
- As permissões do GitHub e a proteção contra remoção involuntária de `.github/workflows` permanecem ativas.
- **Sincronização automática pelo Google Drive permanece independente e bloqueia qualquer identidade ambígua, versões não novas e exclusões.** Essas preferências só se aplicam ao envio manual a partir do repositório.
- Alterar os limiares de digitação nunca oculta a prévia nem muda quais arquivos são substituídos/removidos.

## Testes e pendências

Foram acrescentados testes de defaults, serialização, confirmação por limiar e contrato de UI/Drive automático. Rodar CI Flutter: `flutter pub get`, `flutter analyze --no-fatal-warnings --no-fatal-infos`, `flutter test` e `flutter build apk` para comprovação final. O ambiente local não dispõe do SDK Flutter, portanto nenhum APK desta versão foi gerado localmente.
