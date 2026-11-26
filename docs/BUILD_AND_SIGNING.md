# Build e assinatura oficial

O novo GitHub Manager possui identidade própria e definitiva.

## Identidade Android

- applicationId: `br.com.githubmanager.app`
- versão atual: `2.0.154+200168`
- build: Release AOT universal

## Secrets obrigatórios

Os dois workflows que geram APK restauram a mesma keystore através de:

- `KEYSTORE_BASE64`
- `KEYSTORE_PASSWORD`
- `KEY_ALIAS`
- `KEY_PASSWORD`

Não existem Secrets de teste no fluxo oficial. A chave oficial atual usa o alias `github_manager_release`.

## Certificado

O SHA-256 público do certificado oficial está em `android/release-signing.properties` e corresponde à nova keystore criada especificamente para GitHub Manager.
Depois da compilação, o GitHub Actions extrai o certificado do APK e compara com esse valor. Uma chave diferente faz a build falhar.

## Regra permanente

Nunca substituir a keystore oficial. Se os Secrets forem apagados do GitHub, recriá-los usando o backup original da mesma keystore.

## Verificação a partir da 2.0.152

Os workflows usam `tool/verify_official_signing.py` antes e depois da compilação. O verificador aceita formatos de saída por esquema e mantém o SHA-256 fixado. Se a keystore realmente divergir, restaure a chave original: não altere o fingerprint nem publique um APK incompatível.
