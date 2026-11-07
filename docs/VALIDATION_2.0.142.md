# Validação da versão 2.0.142+200156

## Diagnóstico do workflow 131 da 2.0.141
- 292 testes passaram, 2 falharam. Etapa de teste interrompeu build antes do APK.
- `project_safety_check_test.dart:93`: falso positivo em `social-lite-0.1.1` causado por split `r'[/.]'` antes da remoção de versão.
- `upload_identification_diagnosis_test.dart`: expectativa legada de `Forçar envio para este repositório?` incompatível com a proteção deliberada que removeu o bypass.

## Correções
- `_packageProjectHint` remove versão antes de separar namespaces, com regressões para scoped npm/package e pacote divergente.
- Teste da confirmação verifica desabilitação sob risco, confirmação digitada de remoções e ausência de opção de forçar envio.

## Checks locais
- `bash tool/check_version_sync.sh`, parser YAML/JSON, integridade ZIP e inspeção de código.
- Pendentes: `flutter analyze`, `flutter test`, `flutter build apk`, testes no Android real. Flutter/Dart não disponíveis no ambiente.
