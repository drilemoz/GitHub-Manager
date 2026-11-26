# GitHub Manager 2.0.149+200163

- Mantém os projetos fixados no topo e ordena os demais pela data do último push (`pushed_at`), em vez da atualização geral (`updated_at`).
- Usa `updated_at` apenas quando não houver data de push; preserva os filtros, a ordenação por nome/tamanho e a ordem inversa de datas.
- Após um envio com alterações confirmadas, invalida listas e informações dos projetos antes de depender da conclusão da build. Envios sem mudanças não disparam a atualização.
- Adiciona regressões para datas divergentes, fixados, serialização e evento de atualização após push. Flutter/Dart e build Android não executados neste ambiente.

## Validação

Executar `flutter analyze`, `flutter test` e o workflow Android APK. Conferir os projetos fixados e os não fixados após um push real; a API pode demorar para refletir a alteração.
