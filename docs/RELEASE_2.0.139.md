# GitHub Manager 2.0.139+200153 — 6 de novembro de 2026

## Melhorias implementadas

1. **Limpeza com filtros e seleção prudente.** Por nome de artifact (possível APK), expiração, idade, data e tamanho. O atalho para artifacts anteriores preserva as execuções do artifact mais recente e do possível APK mais recente; dados de data/run ausentes não entram na seleção automática. Seleção e exclusão exigem confirmação.
2. **Resultados auditáveis.** A API distingue solicitação de DELETE aceita, ID anteriormente ausente (404), solicitação rejeitada e ausência efetivamente observada na listagem posterior. Em eventual consistência faz uma nova leitura breve. Se a verificação falhar, não confirma liberação da cota.
3. **Exclusão de execução mais leve.** Inventaria artifacts por run antes de excluí-lo e checa cada artifact pelo ID depois, evitando buscar 100 páginas de todos os artifacts do repositório para cada execução. Se o artifact permanecer visível, tenta DELETE direto e confere de novo. Não modifica releases.
4. **Interface responsiva.** Lista os artifacts em blocos de 80, mantendo a seleção ao filtrar. Evita enviar uma exclusão durante erro de consulta. Consulta o relatório de cobrança apenas sob demanda.
5. **Validações e avisos.** JSON de listagem inválido, IDs inválidos/duplicados e paginação interrompida causam erro explícito, não confirmação de lista vazia. Avisos detalhados são apresentados depois da exclusão de uma ou várias execuções.
6. **Regressões.** Testes novos/atualizados de IDs inválidos, 404, 403, eventual consistência, erros de leitura e seleção conservadora, além de verificações da exclusão de run sem varrer o repositório.

## Escopo e limitações

- Excluir uma **execução** do GitHub Actions apaga seus logs e artifacts associados, incluindo ZIPs que armazenem APKs/AABs. Arquivos publicados em **Releases**, commits e código-fonte não são afetados.
- Excluir um **artifact** apaga esse recurso, não o run. Um nome contendo "APK" apenas sugere o conteúdo; não prova que o ZIP contenha APK.
- Os tamanhos dos artifacts de um repositório não equivalem à ocupação total da conta. Uso faturável (por exemplo, GB-hours), caches, logs e armazenamento atual são grandezas diferentes. A cota oficial deve ser conferida no GitHub Billing.
- Necessário PAT fine-grained com Actions: write para excluir; API Billing em preview pode requerer Plan: read. Não foi executada operação de exclusão com token real.

## Validação pendente

- Rodar `flutter analyze --no-pub`, `flutter test --no-pub`, `flutter build apk --release --no-pub` na CI após `flutter pub get --enforce-lockfile`.
- Testar em conta de laboratório com artifact pequeno e execução concluída; verificar resultados após DELETE, 403, 404 e atraso da consistência; conferir Releases independentes.
