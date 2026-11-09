# GitHub Manager 2.0.148+200162

## Correção do workflow Android APK #137

- O `flutter analyze` do workflow #137 passou, mas `flutter test` parou com **316 testes aprovados e um reprovado** no `global_corner_radius_contract_test.dart`.
- A versão 2.0.147 havia introduzido raios de 12, 14 e 16 nos componentes redesenhados do Google Drive e da tela do repositório. O teste ainda exigia apenas 4, 99 ou 999 em todo o projeto.
- O contrato agora permite **somente** as ocorrências existentes nos dois arquivos redesenhados, contando quantidade exata por raio e arquivo. Outros componentes continuam exigindo 4 (ou os formatos pill 99/999).
- Corrigida a regex de `Radius.circular`, que antes também encontrava a substring dentro de `BorderRadius.circular` e contava o mesmo canto duas vezes.
- **Nenhuma alteração na lógica de upload, OAuth, verificação de APK ou na interface de produção.** Os componentes da 2.0.147 permanecem.
- Versão sincronizada para `2.0.148+200162`, incluindo Novidades, histórico, documentação e notas de release.

## Verificação

A estrutura dos arquivos, o contrato de raios, o versionamento canônico e a integridade do ZIP foram verificados localmente. `flutter analyze`, `flutter test` e `flutter build apk` devem ser executados no GitHub Actions. SDK Flutter indisponível no ambiente local.
