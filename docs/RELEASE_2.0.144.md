# GitHub Manager 2.0.144+200158

## Correção do Android APK #133

A análise da versão 2.0.143 falhou no passo **Analisar código antes do APK** com quatro erros:

1. `drive_sync_foreground_watcher.dart:68`: a expressão `candidate?.project != null` não promovia `candidate`/`project`, causando dois erros `unchecked_use_of_nullable_value` ao acessar `candidate.project.path`. Captura-se `candidate?.project` em variável local, descarta-se a prévia apenas quando não enfileirada e ela existe.
2. `settings_screen.dart:395`: um `_ChangeNote()` vazio não informava `version` nem `text`, gerando dois erros `missing_required_argument`. A entrada incompleta foi removida e o histórico passou a mostrar apenas 2.0.144, 2.0.143 e 2.0.142, na ordem correta.

## Preservação da segurança

A política de publicação conservadora do Drive permanece inalterada. Uma prévia colocada na fila não deve ser descartada pelo watcher. Não foram modificadas as regras de permissão, versão, identidade ou proibição de remoções automáticas.

## Validação

- Conferir `bash tool/check_version_sync.sh` e o teste do histórico de Configurações.
- Reexecutar no GitHub Actions `flutter pub get`, `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`, `flutter test` e `flutter build apk` para validar a compilação real.
- O log #133 contém 131 diagnósticos no total, incluindo avisos de estilo que não bloqueiam a análise com os parâmetros atuais. O workflow parou antes de executar os testes e o build APK. Nenhum APK foi gerado nesta correção local.
