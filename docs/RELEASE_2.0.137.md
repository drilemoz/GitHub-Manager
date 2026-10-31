# GitHub Manager 2.0.137+200151

Data: 31/10/2026.

## Funcionalidade: encontrar e baixar AAB em Play

- A janela Play agora pesquisa AABs nos dois locais do GitHub: Releases (arquivos com extensão `.aab`) e Artifacts (nomes com indícios de bundle).
- Consulta o estado das execuções com candidatos para priorizar as que foram concluídas com sucesso. Não confunde o nome de um Artifact ZIP com AAB comprovado.
- Lista até cinco candidatos, com origem, data, tag, run ID quando disponibilizados pela API; permite copiar informações e iniciar o download pela Central de Downloads.
- Em Releases, o download é direto do asset. Em Artifacts, o ZIP é inspecionado, o AAB é extraído por streaming e a estrutura básica do bundle é conferida antes de salvar.
- Download do AAB dentro do gerenciador respeita pausa, retomada, histórico e limpeza por projeto.
- Exibe resultado parcial quando uma fonte falha e ressalva que AAB não instala no Android como APK. Auditoria Play original preservada, mesmo com erro de inspeção de código.

## Limitações

- Artifacts genéricos, sem indícios de AAB no nome, não podem ser inspecionados apenas pela listagem da API; use a tela tradicional de Artifacts. O nome sugere, não confirma, um AAB.
- Validação do ZIP/AAB verifica a estrutura reconhecível, não comprova assinatura, integridade de publicação ou aprovação da Play Console.
- Sem Flutter SDK local: falta executar `flutter test`, `flutter analyze` e build Android no GitHub Actions, além de testes em aparelho.
