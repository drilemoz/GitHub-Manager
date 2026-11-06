# Validação local — GitHub Manager 2.0.139+200153

Data: 2026-11-06.

## Verificações executadas

- `bash tool/check_version_sync.sh`: `versionName=2.0.139`, `versionCode=200153`, concluído sem falhas.
- JSON e YAML da árvore: analisados por bibliotecas locais (Python `json` / PyYAML), sem erro.
- Estrutura e chaves de código Dart alterado: verificação lexical de delimitadores, sem desequilíbrios detectados. **Não substitui o compilador/analyzer Dart.**
- Testes de regressão escritos/atualizados em `test/actions_storage_service_test.dart`, `test/build_cleanup_service_test.dart`, `test/storage_selection_policy_test.dart`, `test/artifact_lookup_for_cleanup_test.dart` e `test/actions_storage_ui_contract_test.dart`.
- Pacote ZIP verificado por CRC e presença dos arquivos essenciais após a criação.

## Pendente — não interpretar como aprovado

- `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` e `flutter build apk`: **não executados localmente** por falta do SDK Flutter/Dart.
- Exclusão real de artifacts/execuções por token GitHub: **não executada**; não foi alterado nenhum repositório do usuário.
- Teste Android da tela de armazenamento e avaliação de latência em repositórios com milhares de artifacts: **não executados**.

## Riscos e mitigação

- A remoção de um run apaga seus artifacts segundo a documentação do GitHub; recursos de Release são independentes. O resultado local depende da visibilidade da API após o DELETE.
- Uma resposta 204 indica aceitação do DELETE, **não** comprova liberação instantânea de espaço no faturamento. A tela distingue isso explicitamente.
- Falhas de GET ou listagem impedem o app de apresentar o arquivo como ausente confirmado. Paginação interrompida/duplicada é tratada como erro.
- O atalho Selecionar anteriores só seleciona artifacts com data e run conhecidos, protegendo a execução mais recente e o provável APK mais recente. Exige confirmação manual.
