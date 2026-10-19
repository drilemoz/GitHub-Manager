# GitHub Manager 2.0.134+200148

Data: 19/10/2026 • Android versionCode: 200148.

## Correção do workflow Android APK #123

A etapa **Validar versão canônica** parou com `VERSIONING sem a versão canônica`. A versão 2.0.133 havia sido registrada em `docs/VERSIONING.md` fora do formato literal `version: X+Y` exigido pelo validador. Este release registra `version: 2.0.134+200148` na documentação e restaura as entradas 2.0.133/2.0.132 que tinham saído do changelog/documentação.

## Validação

- `bash tool/check_version_sync.sh` deve retornar `versionName=2.0.134` e `versionCode=200148`.
- Teste de regressão adicionado: `test/versioning_documentation_contract_test.dart`.
- Build Android, `flutter analyze` e `flutter test` dependem do workflow GitHub Actions.

## Funcionalidades preservadas

- Detecção de aplicativo instalado, redesign do card APK e SDK Android;
- Importação de `.env` e exclusão em massa no módulo Secrets;
- Pausar/retomar e limpeza automática em Downloads.
