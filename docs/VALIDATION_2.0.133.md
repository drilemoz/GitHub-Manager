# Validação 2.0.133

## Ajustes realizados

- Redesign do cartão de status do APK instalado.
- Reorganização do cabeçalho com versão no topo e chip de SDK.
- Extração de `targetSdk`, `minSdk` e `compileSdk` em `RepositoryProjectInfoService`.
- Melhoria da detecção nativa de app instalado/ausente em `MainActivity.kt`.
- Inclusão de testes de contrato e de extração de SDK.

## Verificações locais

- Sincronização de versionamento para `2.0.133+200147`.
- Integridade estrutural do ZIP.
- Conferência manual dos arquivos alterados.

## Pendências

- `flutter test` não executado localmente (Flutter SDK indisponível).
- `flutter analyze` não executado localmente (Flutter SDK indisponível).
- Compilação Android pendente no GitHub Actions.
