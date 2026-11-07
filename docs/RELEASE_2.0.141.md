# GitHub Manager 2.0.141+200155 — 6 de novembro de 2026

## Proteção de sincronização ZIP (regressão no seletor Android)

- Captura uma cópia privada, exclusiva e verificada do ZIP escolhido antes de carregar branch, prévia ou iniciar upload. Compara SHA-256 e tamanho antes/depois da cópia para detectar troca de arquivo por cache do seletor.
- O fingerprint SHA-256 acompanha prévia, fila persistida, cópia durável e envio; arquivos de mesmo tamanho e conteúdo diferente são recusados. Tarefas antigas sem fingerprint exigem nova seleção antes de sincronizar (builds já criadas permanecem independentes).
- A confirmação exibe o nome do arquivo escolhido, o projeto identificado e o início do SHA-256. Mismatch entre filename versionado, pasta raiz versionada, metadados e repositório bloqueia a sincronização (sem botão para forçar) se não houver identificação forte coerente.
- Falha na prévia de alterações bloqueia a publicação, em vez de permitir enviar sem conhecer os arquivos atingidos. Remoções calculadas exigem informar exatamente `owner/repo` antes de autorizar.
- Arquivos temporários privados só são removidos por caminho canônico dentro de `verified_zip_selections`; após cancelar, limpeza imediata; após enfileirar, a cópia é removida somente quando o ZIP durável é verificado.
- Adiciona testes de ZIPs diferentes com mesmo tamanho, mudanças de fingerprint, divergência de nome/identidade e contrato de UI.

## Validação e limites

- Conferência estática de Dart, integridade ZIP, JSON e script de versionamento: executar localmente.
- **Ainda requer `flutter analyze`, `flutter test`, compilação Android e teste no aparelho** com o seletor de arquivos, app em segundo plano, renomeações e ZIPs de vários formatos antes de depender da proteção em produção. Esses testes não foram executados no ambiente sem Flutter/Dart.
- Um arquivo sem metadados/proveniência verificável não pode ser identificado exclusivamente por SHA-256; o hash garante identidade dos bytes após a seleção, não autoria do conteúdo.
