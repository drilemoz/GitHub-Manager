# GitHub Manager 2.0.142+200156 — 6 de novembro de 2026

## Correções
- Ajusta a validação de nome de pacote para remover versões antes de separar namespaces. Evita que `social-lite-0.1.1` seja lido como pacote `1` e bloqueado erroneamente.
- Corrige teste que esperava diálogo de forçar envio, pois ele foi removido por segurança na 2.0.141.
- Acrescenta regressões para pacotes versionados com namespace `@vendor/` e para pacote realmente divergente.

## Proteções mantidas
- Cópia privada + SHA-256 do ZIP, prévia obrigatória, bloqueio por identidade divergente e confirmação de remoções pelo nome completo do repositório.

## Validação
- Logs do GitHub Actions workflow 131: 292 testes aprovados e 2 falhos na versão 2.0.141. Versão 2.0.142 preparada para reexecutar no CI.
- `flutter analyze`, `flutter test` e build Android não foram executados localmente por ausência do SDK Flutter/Dart.
