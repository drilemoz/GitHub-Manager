# Validação 2.0.132

Verificações de fonte adicionadas para seletor sem filtro, validação de nomes `.env`, BOM, suporte de `export`, lote de exclusões incluindo HTTP 403 parcial, confirmação explícita e relatório sem valores.

Executar no CI: `flutter analyze --no-fatal-infos --no-fatal-warnings`, `flutter test` e `flutter build apk`; no aparelho validar seleção de `.env` oculto (Android 11+) e exclusão de lote de Secrets em repositório de teste, com falhas parciais e token autorizado.
