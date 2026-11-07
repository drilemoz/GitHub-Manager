# Validação da versão 2.0.141+200155

## Verificações realizadas

- `bash tool/check_version_sync.sh`: passou (`versionName=2.0.141`, `versionCode=200155`).
- JSON/YAML: leitura e parsing local sem erros.
- Conteúdo de ZIP: inspeção de estrutura e CRC completo.
- Código-fonte: conferência de chamadas e contratos dos guards SHA-256, modelo de fila, avisos de identidade e texto de UI.

## Testes acrescentados (a executar em CI Flutter)

- `verified_zip_selection_test.dart`: arquivos de mesmo tamanho com SHA-256 distinto, mudança do conteúdo após análise, ZIP estável.
- `verified_upload_ui_contract_test.dart`: vínculo do seletor à cópia, prévia obrigatória, bloqueios e histórico.
- `project_safety_check_test.dart`: divergências entre nome selecionado, identidade interna e pacote.
- `upload_manager_service_test.dart`: ZIP alterado não chama o executor de upload.

## Não executado aqui

- `flutter pub get`, `dart format`, `flutter analyze`, `flutter test`, `:app:assembleDebug` e teste físico de seleção Android/SAF. O SDK Flutter/Dart não está instalado.
- Não foi reproduzido o bug original do FilePicker em dispositivo; mitigação fail-closed baseada nos fatos observados.

## Riscos residuais

- SHA-256 prova que os bytes não mudaram depois da seleção, mas não comprova se o seletor Android devolveu o arquivo correto antes do snapshot. Metadados/pacotes e prévia procuram detectar essa troca. ZIPs sem identidade forte requerem cautela.
- Snapshot abandonado por encerramento brusco antes do enqueue pode permanecer em armazenamento privado. Seleção cancelada e snapshot copiado pela fila são limpos com validação de caminho.
