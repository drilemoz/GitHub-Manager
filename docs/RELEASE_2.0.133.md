# GitHub Manager 2.0.133+200147

Data: 19/10/2026. VersionCode Android: 200147.

## O que mudou

- **Detecção de app instalado melhorada:** a consulta nativa agora trata melhor a ausência do pacote e deixa de cair em muitos falsos “não foi possível verificar”.
- **Card APK redesenhado:** o estado do app instalado foi reorganizado em um cartão mais visual, com destaque de cores por estado. Quando o app não estiver instalado, o aviso aparece em **vermelho**.
- **Versão e SDK no topo do projeto:** a versão foi movida para um chip acima do nome do app e o card do repositório pode mostrar o **SDK Android** detectado.
- **Informações de SDK:** o app passa a identificar e exibir `targetSdk`, `minSdk` e `compileSdk` quando essas pistas estiverem disponíveis no Gradle ou em metadados do projeto.
- **Janela de informações do projeto:** agora também exibe a linha **SDK Android**.

## Observações

- A identificação do SDK continua heurística e depende do que estiver declarado estaticamente no repositório.
- A confirmação final do build Android, `flutter test` e `flutter analyze` ainda depende do GitHub Actions ou de um ambiente com Flutter SDK.
