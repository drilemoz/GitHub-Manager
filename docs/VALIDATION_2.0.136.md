# Validação GitHub Manager 2.0.136+200150

- `bash tool/check_version_sync.sh`: **aprovado** (versionName 2.0.136, versionCode 200150).
- JSON, YAML, XML: **parsing aprovado** em todos os arquivos disponíveis.
- Contrato estrutural: histórico das três versões em ordem; ledger SQLite com `db.transaction`; opt-in desativado por padrão; quatro categorias; filtros de idade; cancelamento nativo por canais opcionais sem cancelar foreground; nenhum pedido automático de permissão no início do download. **Conferido**.
- Simulação SQLite em duas conexões: persistência da chave única confirmada.
- Testes Dart/Flutter completos, `flutter analyze` e build Android: **pendentes** por ausência de Flutter SDK local.
