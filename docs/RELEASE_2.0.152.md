# GitHub Manager 2.0.152

- Build #140: 323 testes Flutter aprovados; APK de 65,4 MB compilado, mas a validação final informou certificado divergente sem mostrar o SHA-256 encontrado.
- Corrige regressão do verificador: suporta formatos `Signer #1` e `V2/V3/V4 Signer`, normaliza SHA-256 e exige exatamente o certificado oficial configurado.
- Verifica previamente a keystore restaurada, mostra o fingerprint público no diagnóstico e mantém o bloqueio de APK com assinatura inválida ou diferente.
- Mantém APK direto nos Artifacts e publicação oficial em Releases, atualizador próprio e SDK 36. Nova build e publicação dependem de CI.
