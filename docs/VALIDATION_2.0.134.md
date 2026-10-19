# Validação 2.0.134+200148

## Origem

Android APK #123, 19/10/2026: etapa `bash tool/check_version_sync.sh` falhou com
`VERSIONING sem a versão canônica` antes da análise e testes Flutter.

## Correção

O `docs/VERSIONING.md` agora inclui o marcador canônico literal
`version: 2.0.134+200148`, exatamente como é exigido pelo shell script.
Registros 2.0.133 e 2.0.132 reintroduzidos no CHANGELOG e VERSIONING.
Teste novo `test/versioning_documentation_contract_test.dart` protege a
consistência entre pubspec, JSON, release notes e VERSIONING.

## Validação local

- `bash tool/check_version_sync.sh`: aprovado.
- JSON, YAML, XML e ZIP: validações estruturais.
- O `flutter test`, `flutter analyze` e o build Android aguardam nova execução no GitHub Actions.
