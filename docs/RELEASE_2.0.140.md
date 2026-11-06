# GitHub Manager 2.0.140+200154 — 6 de novembro de 2026

## Motivo da versão

O workflow **GitHub Manager Android APK #129** finalizou 285 testes com sucesso e 1 com falha. O teste `system_ui_settings_contract_test.dart` esperava o histórico `2.0.139 → 2.0.138 → 2.0.137`, mas recebeu `2.0.139 → 2.0.137 → 2.0.138`. A etapa `flutter test` retornou código 1; o job não chegou à compilação do APK.

## Alterações

1. O painel **Configurações → Últimas 3 mudanças** exibe as versões `2.0.140 → 2.0.139 → 2.0.138`, da mais recente para a mais antiga, com texto de cada alteração alinhado.
2. `tool/check_version_sync.sh` verifica antecipadamente as três versões, sua quantidade e a ordenação decrescente em relação ao `pubspec.yaml`. Assim, um erro similar bloqueia o workflow antes do `flutter analyze` e dos testes.
3. Tela **Novidades desta versão**, `github-manager.json`, versionCode Android `200154`, README, CHANGELOG, VERSIONING e handoff atualizados.
4. Mantidos os mecanismos de listagem, seleção, exclusão verificável e filtros de artifacts introduzidos em 2.0.138/2.0.139, bem como a preservação de APKs publicados em Releases.

## Evidências e limitações

- A falha apontada é de **histórico de versão**, não de compilador Android nem de exclusão de artifacts.
- O relatório de 110 itens do `flutter analyze` não impediu a passagem da etapa de análise; a falha real é o único teste reprovado.
- O teste `system_ui_settings_contract_test.dart` é regressão dinâmica e continua sendo executado em CI.
- Validação estática/ZIP e script de versionamento podem ser executados localmente. Sem SDK Flutter/Dart, a suíte `flutter test` e a compilação Android ainda precisam ser validadas pelo GitHub Actions. Não afirmar APK gerado antes da execução.
