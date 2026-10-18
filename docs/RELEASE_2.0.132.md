# GitHub Manager 2.0.132+200146

Data: 17/10/2026. Android versionCode: 200146.

## Novidades

1. Importação de Secrets via `.env` (incluindo `.ENV`, `.env.local` e `.env.production`) além de TXT, JSON e XML. O seletor não oculta mais extensões iniciadas por ponto; o aplicativo valida localmente o formato e conteúdo após a escolha. UTF-8 com BOM também é suportado.
2. Ação **Excluir todas** na lista de Secrets, com verificação de permissão, revisão do repositório e quantidade, confirmação por digitação de `EXCLUIR`, progresso e resultado individual.
3. Relatório de exclusões copiável com os nomes e resultados, **sem valores de Secrets**; falhas individuais não interrompem o restante da lista.

## Segurança e limitações

- Só elimina Secrets de Actions associados ao repositório escolhido; não remove Secrets de ambientes ou organizações.
- Exclusão é irreversível. GitHub não retorna valores de Secrets existentes; mantenha seus próprios backups protegidos.
- A autenticação precisa permitir Secrets (escrita). Conexão/permissão insuficiente pode gerar resultado parcial.
- Arquivos `.env` são lidos em memória localmente (limite 6 MiB) e os valores são enviados criptografados. Não incluir arquivos com credenciais no repositório.
- Suporte a `.env` é para pares simples NOME=valor e variantes; não tenta interpretar multiline do shell.
- Testes e build Android precisam ser confirmados no GitHub Actions.
