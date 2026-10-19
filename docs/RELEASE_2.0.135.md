# GitHub Manager 2.0.135+200149

Data: 19/10/2026 • Android versionCode: 200149.

## 1. Identificação segura de versão por STATUS.json

O módulo de envio de ZIP e o leitor de metadados de repositório passam a reconhecer `STATUS.json` na raiz efetiva. Para Termux Manager, `version: 0.1.0-alpha.5` identifica a **integração** e `application_id: com.termux` identifica o pacote Android. Os campos `confirmed_manager_manifest_version`, `confirmed_termux_app_version`, `build_apk_version_name_expected` e `build_apk_version_code_expected` NÃO substituem a versão principal usada na comparação de projetos. O APK pode possuir versão e versionCode distintos da integração.

A API GitHub é case-sensitive: a consulta de arquivos preserva agora o `path` real retornado pela listagem, como `STATUS.json` e `MANIFEST.json`.

## 2. Correção das falhas do Android APK #124

- `test/global_corner_radius_contract_test.dart`: 6dp e 20dp introduzidos no redesign do card estavam fora da norma interna de raios. Normalizado 4dp para retângulos e 99dp para pills.
- `test/installed_apk_integration_contract_test.dart`: a implementação Android 11+ havia removido a distinção entre invisibilidade e desinstalação. Recuperada resposta `unknown` com `package_visibility` quando `getPackageInfo` falha na API 30+, evitando falsa mensagem vermelha de app ausente. A mensagem vermelha é reservada a ausência confirmada.

## Verificações e limitações

- Sincronização canônica por `bash tool/check_version_sync.sh`.
- Testes de regressão adicionados para ZIP e API do GitHub com STATUS.json e subprojetos aninhados.
- A identificação de apps Android 11+ pode permanecer inconclusiva sem visibilidade de pacote; não solicita `QUERY_ALL_PACKAGES`.
- Validar `flutter analyze`, `flutter test`, compilação e testes no dispositivo via GitHub Actions (SDK indisponível localmente).
