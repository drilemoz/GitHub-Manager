# GitHub Manager 2.0.138+200152

Data: 06/11/2026.

## Entrega

- Nova tela **Armazenamento Actions**, acessível de Builds global e Builds do repositório, com seleção, tamanho e exclusão de artifacts por repositório.
- Protege as Releases: excluir uma execução do GitHub Actions remove os artifacts associados, inclusive ZIPs que podem conter APKs; APKs publicados como assets de Releases não são excluídos. Excluir artifacts na nova tela preserva a execução.
- O GitHub retorna HTTP 204 para exclusão aceita; o aplicativo reconsulta a listagem e informa IDs que ainda permanecem ou quando não foi possível confirmar.
- Consulta opcional ao relatório Billing de uso Actions do mês via `/users/{login}/settings/billing/usage/summary` (preview, pode exigir `Plan: read`). Unidades do relatório não são convertidas em saldo de armazenamento.
- Lista artifacts por repositório com até 100 páginas de 100 itens, lançando erro explícito se o volume exceder o limite verificável.
- Mensagens de confirmação de seleção múltipla e individuais esclarecem o alcance da exclusão; correção do total contabilizado após verificação.

## Segurança e limites

- Necessário token com permissões **Actions: write** (fine-grained) para excluir artifacts/execuções; PAT clássico com escopo `repo` em repos privados.
- Os artifacts podem ter nomes genéricos. A listagem do GitHub não revela quais arquivos estão dentro dos ZIPs: o app não afirma que todo artifact contém APK.
- A soma de `size_in_bytes` corresponde somente aos artifacts listados para o repositório selecionado; não inclui dados de outros repositórios, caches ou logs e não equivale ao medidor oficial da cota.
- Uso faturável é calculado ao longo do mês e pode continuar aparecendo após exclusões. APIs de cobrança podem responder 403/404; o painel de artifacts funciona independentemente.
- Nenhuma operação de exclusão real foi realizada nesta entrega. Compilação Flutter/Android e testes em aparelho exigem ambiente Flutter, indisponível nesta sessão.

## Referências

- https://docs.github.com/en/actions/how-tos/manage-workflow-runs/remove-workflow-artifacts
- https://docs.github.com/en/rest/actions/artifacts
- https://docs.github.com/en/rest/billing/usage
