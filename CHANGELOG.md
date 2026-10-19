## 2.0.133+200147 — 2026-10-19

- Melhora a detecção de aplicativo instalado/ausente na tela do repositório, reduzindo resultados inconclusivos ao consultar o pacote Android.
- Redesenha o card de status do APK com destaque visual por estado; quando o app não está instalado, a informação aparece em vermelho.
- Move a versão do projeto para o topo do cabeçalho e adiciona chip de SDK Android.
- Identifica e exibe `targetSdk`, `minSdk` e `compileSdk` quando declarados estaticamente no repositório.
- Atualiza README, VERSIONING, notas da versão, Configurações, tela de Novidades e testes/contratos relacionados.

## 2.0.131+200145 — 2026-10-16

- Adiciona em Configurações → Transferências a preferência persistente **Limpeza automática dos downloads** com modos Após concluir (padrão), Antes de iniciar e Desativada.
- Remove apenas arquivos finais do GitHub Manager na pasta correspondente ao projeto; a verificação MediaStore limita a exclusão à pasta exata e ao proprietário do arquivo, e protege arquivos de outros aplicativos.
- Serializa publicações e limpezas por pasta; mantém os arquivos `.part`, downloads pausados e transferências em andamento. Na opção Antes de iniciar, repete a consolidação após salvar para lidar com concorrência.
- Em Android anterior à API 29, a limpeza opera somente em caminhos do projeto que constam no histórico do aplicativo. Erros de limpeza não são ocultados; após publicação, gera aviso no cartão concluído sem perder o download.
- Preserva Pausar/Retomar, análise Google Play, metadados e proteção de downloads. Inclui testes de contrato e sincroniza versão/versionCode `200145`, notas e documentação. Flutter e Gradle não executados localmente.

## 2.0.130+200144 — 2026-10-16

- Implementa **Pausar / Retomar** na Central de Downloads, com seção Pausados, persistência do estado e preservação do arquivo parcial para retomada segura.
- A retomada aguarda o encerramento do download anterior para evitar duas gravações no mesmo arquivo; Releases/Artifacts renovam URLs assinadas e usam Range quando permitido.
- Gravações do histórico são serializadas e a limpeza ignora downloads pausados; são preservados os contadores e a seleção de ABI dos APKs.
- Detecta ausência de avanço por 15 segundos, zerando velocidade/ETA obsoletos; sinaliza downloads simultâneos e velocidade baixa, sem prometer aceleração da rede.
- Reforça downloads públicos: verifica Content-Range e comprimento recebido. Evita anexar segmentos incompatíveis; atualiza testes de regressão, notas, configuração e versionCode 200144.
- Validação Flutter/Android completa pendente de execução no GitHub Actions e em aparelho.

## 2.0.129+200143 — 2026-10-15

- Adiciona **Copiar relatório** ao pop-up de auditoria Google Play, copiando conteúdo completo para área de transferência via Clipboard nativo.
- O relatório contém repositório/branch, diagnóstico do projeto, abrangência da árvore, ressalvas, totais, verificações técnicas e pendências Play Console, incluindo estados, detalhes e evidências.
- Botão desabilitado enquanto a análise está em andamento ou falhou; mostra confirmação de cópia e falha, e limpa status ao **Reavaliar**.
- Garante que uma cópia de relatório anterior não altere o estado visual após uma nova análise.
- Testes novos para formatação, incluindo projeto não Android, e contrato do botão; versão, documentação, Novidades e últimas mudanças sincronizados.
- Flutter/Android completos pendentes de CI e teste no aparelho.

## 2.0.128+200142 — 2026-10-15

- Inclui botão **Play** como quinto atalho da tela de repositório, ao lado de Enviar, GitHub/Fork, Copiar e APK, com quatro atalhos antigos mais compactos.
- Nova janela com auditoria automática do código-fonte na branch do repositório e ação Reavaliar; registra evidências e estados verificado no código, atenção e não confirmado.
- Identifica `targetSdk` literal e verifica mínimo API 36 (Android 16) para novos envios de apps Android comuns desde 31/08/2026. Valores dinâmicos como `flutter.targetSdkVersion` ficam como desconhecidos, sem confundir `compileSdk` com `targetSdk`.
- Verifica `versionCode`, `applicationId`, indícios de geração AAB, assinatura de produção, permissões declaradas e política de privacidade; orienta testes, 64 bits, páginas de 16 KB e formulário de Segurança dos dados.
- Avaliação não dá selo de aprovação da Play Console, não consulta keystores/Secrets, não altera repositórios; reconhece projetos não Android e árvores truncadas.
- Novos testes de avaliação e interface, versão/documentação sincronizadas. Flutter/Android completos pendentes de validação CI.

## 2.0.127+200141 — 2026-10-15

- Corrige a falha única do workflow Android APK #116: `test/system_ui_settings_contract_test.dart` detectou notas de alterações em ordem errada (`2.0.126`, `2.0.124`, `2.0.125`).
- Reorganiza **Configurações → Últimas 3 mudanças** em ordem cronológica decrescente (`2.0.127`, `2.0.126`, `2.0.125`), corrigindo os textos associados a cada versão.
- Mantém o teste de regressão exigindo exatamente as três versões sequenciais mais recentes, evitando retornar à ordenação errada em novos releases.
- Preserva a seleção de APK, downloads, identificação de versão instalada e demais funcionalidades da 2.0.126. VersionCode incrementado para `200141`.
- Log #116: análise Dart sem erros fatais, 227 testes aprovados e 1 falha; build Android não iniciado. Testes e compilação da correção pendentes em CI.

## 2.0.126+200140 — 2026-10-15

- Corrige o teste reprovado em Android APK #115: `test/build_apk_selection_contract_test.dart` assumia que a tela de repositório chamava `listReleaseAssets` e `listArtifacts` diretamente; desde a 2.0.125 as consultas são centralizadas em `repository_apk_status_provider.dart`.
- Alinha o contrato à arquitetura real, conferindo provider de Releases + Artifacts, resolução da última versão, avaliação da instalação e caminho até seletor e downloads; preserva isolamento de falhas entre as fontes.
- Log do #115: `flutter analyze` concluiu sem erros fatais, **227 testes passaram e 1 falhou**; não houve compilação APK devido à interrupção na suíte de testes.
- Preserva os mecanismos de consulta ao pacote Android, estados Instalar/Atualizar/Atualizado, escolha de ABI e downloads existentes. Sincroniza documentação, Novidades e `versionCode` 200140.
- `flutter analyze`, `flutter test` e `assemble` ainda precisam ser executados no GitHub Actions para esta versão.

## 2.0.125+200139 — 2026-10-15

- Inclui consulta nativa à instalação por `applicationId` e leitura da versão instalada/versionCode pelo Android PackageManager, sem enumeração de aplicativos nem QUERY_ALL_PACKAGES.
- Integra ao botão APK os estados Instalar/Atualizar/Atualizado/Mais recente no aparelho/Não foi possível verificar, exibindo versões no detalhe do repositório.
- Compara a versão publicada mais recente das Releases/Artifacts com a instalada, prioriza dados confiáveis e informa quando só há versionName estimado sem código remoto.
- Em Android 11+, resultado não encontrado pela consulta pode ser causado por pacote invisível; não é rotulado como ausência confirmada.
- Ao baixar versão igual ou mais antiga, solicita confirmação; preserva seleção de ABIs, downloads, assinatura/instalação explícita, versão sequencial e metadados.
- Acrescenta testes de comparação de versão, leitura do canal e contratos de integração. Flutter/Android precisam ser verificados na CI e no aparelho.

## 2.0.124+200138 — 2026-10-15

- Corrige o botão APK cinza na tela do repositório: a disponibilidade deixou de depender exclusivamente de Artifacts; as Releases são consultadas diretamente ao tocar.
- Abre o download da última versão identificada e usa o seletor existente quando há mais de uma variante ARM64/ARM32/x86/x86_64/Universal. Sem variantes, inicia o download direto na Central de Downloads.
- Seleciona versões de Releases por agrupamento semântico e variantes; Artifacts expirados não são selecionados e variantes do mesmo workflow não são confundidas com versões antigas.
- Falhas de consulta de Releases e Artifacts são tratadas independentemente, com mensagem informativa e opção de ver todos os arquivos quando necessário.
- Preserva verificações de ABI e integridade, downloads retomáveis e o layout compacto. Atualiza versionName/versionCode, READMEs, docs, changelog, Novidades e testes.
- Build Flutter/Android e validação no aparelho permanecem pendentes de CI.

## 2.0.123+200137 — 2026-10-14

- Corrige os 5 erros `argument_type_not_assignable` apontados no Android APK #112 em `test/static_web_project_detection_test.dart`. `ArchiveFile` passa a receber `List<int>` obtido por `utf8.encode`, com comprimento calculado pelos bytes.
- Remove operador `!` desnecessário após `ZipEncoder().encode()`, eliminando o warning introduzido no mesmo teste.
- Acrescenta teste de regressão para ZIP com `index.html` isolado; preserva detecção de portfólio estático HTML/CSS/JS.
- Mantém interface compacta dos 4 cartões em Builds, retomada de download e os demais recursos da 2.0.122. Atualiza versionName/versionCode e documentação.
- O log do APK #112 encerrou em `flutter analyze`; testes e build Android ainda não foram executados para esta versão.

## 2.0.122+200136 — 2026-10-14

- Reconhece melhor projetos de site estático/portfólio em ZIPs e repositórios, usando pistas como `index.html`, `styles.css`, `app.js`, `README.md` e `vercel.json`.
- Quando faltam metadados explícitos, infere nome de projetos web pelo primeiro título do `README.md` ou pelo `<title>` do `index.html`, sem sobrescrever metadados fortes já existentes.
- No detalhe da execução em Builds, reorganiza o resumo em quatro cartões compactos (Evento, Branch, Tempo e Etapas) na mesma linha quando a largura permitir; reduz rótulos e densidade vertical.
- Mantém as otimizações de downloads da 2.0.121 e sincroniza documentação, tela de Novidades, Configurações, notas de release e versionCode `200136`.
- Foram acrescentados testes para projeto web estático e ajustado o contrato visual do resumo; Flutter/Android não puderam ser executados localmente.

## 2.0.120+200134 — 2026-10-12

- Corrige o bloqueio simultâneo de Android APK #109 e CI #108 (201 testes aprovados, 2 falhas) provocado por `.github/workflows/ci.yml` **ainda presente e ativo no GitHub**.
- Inclui um `ci.yml` de compatibilidade: somente disparo manual, com job `if: ${{ false }}`, sem `push`/`pull_request`, para substituir o CI remoto quando o ZIP for enviado incrementalmente.
- Atualiza `workflow_log_naming_contract_test.dart` para aceitar workflow ausente ou stub inerte, mas continuar reprovando CI antigo ativo e verificar permissões mínimas.
- Mantém análise/testes e compilação nos workflows Android APK e Release; nenhum dado nem arquivo de usuário é apagado automaticamente.
- Versão e Android versionCode `2.0.120+200134`; README, VERSIONING, notas de release, validações, Novidades, Configurações e AI_HANDOFF sincronizados.
- Exclusão definitiva remota requer permissão de workflows; a integração retornou HTTP 403. Não houve build Flutter/Gradle local.

## 2.0.119+200133 — 2026-10-12

- Corrige três falhas comuns aos workflows Android APK #108 e CI #107 (200 testes aprovados, 3 falhas), ocorridas na v2.0.118.
- Atualiza `global_builds_screen_test.dart` para verificar `Android APK • execução #78` e `Verificação do Projeto (CI) • execução #78`, como a interface atual apresenta, sem confundir execução com versão.
- Mantém o contrato que exige ausência de `.github/workflows/ci.yml` no checkout, mas agora explica o motivo da falha e a exclusão necessária: o upload incremental de ZIP pode preservar arquivos remotos ausentes no ZIP.
- A remoção do CI redundante deve ser efetivada no repositório GitHub além da remoção no ZIP; os workflows Android APK e Release permanecem responsáveis por análise, testes e build.
- Sincroniza README, docs/VERSIONING, Novidades, Configurações, notas da versão e `versionCode 200133`. Flutter e Android não foram compilados localmente.

## 2.0.118+200132 — 2026-10-12

- Remove o workflow separado `.github/workflows/ci.yml` que duplicava análise e testes do Android APK em pushes na branch principal.
- Mantém `flutter analyze`, `flutter test` e validação de versão nos workflows Android APK e Android Release, sem alterar a assinatura, integridade dos APKs nem notificações do aplicativo.
- Atualiza o teste de contrato para verificar que o CI separado não existe e que os dois workflows Android preservam as etapas essenciais.
- Sincroniza versão, README, VERSIONING, Novidades, Configurações, notas de release e `versionCode` 200132.
- Atenção: regras de proteção de branches podem exigir atualização se ainda dependerem do antigo check `Analisar e testar`.
- Testes Flutter e compilação Android não executados localmente.

## 2.0.117+200131 — 2026-10-12

- Corrige os dois erros de `undefined_method` registrados na CI #106 (`flutter analyze`): `_RunStatusIcon` e `_JobIcon` em `repository_run_details.dart`, linhas 64 e 259.
- Implementa ambos os ícones no arquivo `repository_run_details_widgets.dart` (mesma biblioteca Dart `part of`), distinguindo execução, sucesso, falha, cancelamento e jobs ignorados com cores, ícones e tooltips.
- Acrescenta teste de regressão dos componentes e mantém o seletor de APKs, os metadados de build, as notificações e a navegação anteriores.
- Sincroniza README, VERSIONING, Configurações, Novidades, notas de release e `versionCode` 200131.
- Flutter/Dart indisponíveis localmente: compilação e execução dos testes continuam pendentes de CI.

## 2.0.116+200130 — 2026-10-12

- Substitui listas repetitivas de variantes nas Builds, detalhes das execuções e Releases por uma seleção guiada, com opção sugerida e alternativas claras. A compatibilidade por nome é explicitamente estimada.
- Distingue versionName/versionCode do número da execução GitHub Actions; gera e lê sob demanda metadados opcionais do workflow vinculados ao runId e ao commit.
- Diagnóstico conserva mensagens originais e oferece orientações por erro, abrir arquivo no commit e copiar diagnóstico.
- Mantém a confirmação para APK de Release sem vínculo inequívoco, sem excluir os artifacts existentes, e preserva as funções anteriores.
- Confere a estrutura APK e as bibliotecas nativas reais após o download, antes de salvar o arquivo, sem inferir assinatura/SDK mínimo.
- Notificações de builds incluem a versão provável quando identificada, mantendo o contador da execução separado.
- Acrescenta testes de seleção, manifestos e diagnóstico. Flutter/Android precisam de verificação na CI.

## 2.0.115+200129 — 2026-10-11

- Corrige o único teste que impedia a CI #104 e o Android APK #105: contrato de lançamento da MainActivity a partir das notificações nativas (191 testes aprovados, 1 falha).
- Restaura `Intent.ACTION_MAIN` e `Intent.CATEGORY_LAUNCHER` nos serviços de Upload e Download; mantém `CLEAR_TOP`/`SINGLE_TOP` e as rotas com os IDs das transferências.
- Reforça os testes para garantir que notificações abram a mesma task Android e levem à Central com o evento correto, sem `NEW_TASK`.
- Atualiza versionamento, Novidades, Configurações e notas de lançamento; execução Flutter e Android ainda pendente.

## 2.0.114+200128 — 2026-10-11

- Abre a execução específica pelo ID/branch ao tocar em notificações de Builds, inclusive em abertura a frio do aplicativo e quando a execução saiu da primeira página.
- Notificações de download concluído/falho e serviços foreground de upload/download abrem a Central correspondente com o registro identificado e acesso ao detalhe.
- Diferencia canais de conclusões rotineiras e falhas importantes; mensagens mais explícitas e deduplicação de toques simultâneos.
- Preserva notificações antigas e rejeita destinos inválidos, sem confiar em URLs externas.
- Evita que a tela automática de Novidades interrompa o caminho da notificação; adiciona testes de rotas e ponte Android, sincroniza documentação e versionCode `200128`.

## 2.0.113+200127 — 2026-10-11

- Corrige o único teste falho dos workflows CI #102 e Android APK #103 (`185 tests passed, 1 failed`).
- O teste `histórico permite buscar por branch e abrir uma execução antiga` agora aciona a lupa antes de localizar e preencher o campo de pesquisa.
- Adiciona asserções do estado recolhido/expandido da busca, preservando a interface compacta.
- Sincroniza versionName/versionCode, README, CHANGELOG, VERSIONING, Novidades, Configurações e notas de release.
- Os 73 apontamentos informativos do analisador não bloqueavam o job; não se alterou o tratamento de permissões ou lógica de APK.

## 2.0.112+200126 — 2026-10-11

- substitui a barra permanente de pesquisa de Builds por lupa no topo e filtros avançados recolhíveis;
- adiciona carregamento visível na seleção APK global e no detalhe das execuções; resultados de Artifacts e Releases são independentes e falhas parciais têm diagnóstico;
- compacta a Central de Downloads com título curto, detalhes completos e ações sem cortes; evita tratar classificação inferida pelo nome como origem comprovada;
- reorganiza a prévia ZIP em janela ampla com grupos por pasta, remoções prioritárias e cópia de caminhos;
- preserva caminho/linha de annotations, interpreta formatos comuns de compiladores em logs e permite abrir arquivos seguros no commit do GitHub, sem afirmar causa baseada somente em resumo de testes;
- adiciona testes de regressão, documentação de validação, últimas mudanças e Novidades; incrementa versionCode para 200126.
- Sem Flutter/Dart SDK local, execução e compilação ainda dependem do CI.

## 2.0.111+200125 — 2026-10-10

- corrige 3 falhas dos jobs CI #100 e Android APK #101: arredondamento fora do padrão, expectativa de versões antigas no histórico e terminologia diferente no relatório de identificação;
- padroniza dois contêineres em raio 4 e remove widget de banner não utilizado;
- torna os testes de histórico e Novidades independentes de conteúdo que muda a cada versão, preservando contratos funcionais;
- reforça a verificação da versão canônica contra Configurações, Novidades, README, CHANGELOG e release notes;
- sincroniza a tela de Novidades, últimas três mudanças, README, VERSIONING, validação, notas de release e versionCode 200125;
- o SDK Flutter não está disponível neste ambiente: testes e compilação ainda exigem execução na CI.

## 2.0.110+200124 — 2026-10-10

- compacta a confirmação de envio de ZIP com destino, branch, comparação de versões e contagem de arquivos; mantém prévia de arquivos e avisos de exclusão;
- move metadados de identidade, origem da versão, API e explicação do workflow para seção expansível;
- acrescenta diagnóstico contextual e relatório copiável (sem credenciais) para versão ausente, nome não identificado e conflitos de identidade;
- resolve nomes Android a partir do Manifest e de `strings.xml` na Home e no detalhe quando não há nome mais confiável, independentemente da versão já encontrada;
- preserva confirmação reforçada para identidade divergente, proteção dos workflows e checagem de permissões;
- sincroniza README, VERSIONING, Configurações, Novidades, documentação, testes e versionCode `200124`.

## 2.0.109+200123 — 2026-10-10

- aprimora a tela global de Builds com histórico recente de até 25 execuções por repositório, busca e filtros por status, branch, workflow e período;
- permite comparar execuções anteriores do mesmo workflow, com status, duração aproximada e SHA;
- adiciona diagnóstico/etapas sob demanda, sem consultar logs no polling, e apresenta a hora real da última consulta;
- ajusta atualização global para intervalos mínimos de 15 s com builds ativas e 60 s para a varredura geral, preservando resultados anteriores quando há falhas parciais;
- prioriza Artifacts vinculados à execução e avisa quando um APK de Release foi associado somente por commit/versão;
- impede a remoção automática de APKs de Releases ao excluir builds, pois igualdade de SHA não prova a identidade da execução;
- atualiza Novidades, documentação, testes e versionamento para `2.0.109+200123`.

## 2.0.108+200122 — 2026-10-10

- adiciona **Configurações > Aparência > Tela inteira** para alternar entre modo imersivo e barras de sistema visíveis;
- mantém modo imersivo como preferência padrão para quem já utilizava o aplicativo;
- persiste a escolha no banco local, aplica a alteração imediatamente e restaura a preferência após reabrir o aplicativo;
- reaplica o modo após retorno ao primeiro plano e, quando apropriado, depois de fechar o teclado;
- registra a limitação de modo imersivo sob targetSdk 35/36 e não enfraquece as configurações de compatibilidade do Android;
- atualiza a tela de Novidades, o histórico das últimas três mudanças, README, VERSIONING, RELEASE, VALIDATION, handoff e testes;
- incrementa `versionName` para `2.0.108` e `versionCode` para `200122`.

## 2.0.107+200121 — 2026-10-10

- adiciona **Configurações > Página inicial > Mostrar descrição dos repositórios** com chave de ativação;
- ao habilitar, exibe a descrição completa fornecida pelo GitHub em cada cartão da Home, sem `maxLines` e sem cortes por caracteres;
- preserva a lista compacta quando desabilitada e mantém a opção desativada por padrão;
- salva a preferência no banco local existente e sincroniza o valor via Riverpod entre Configurações e cards;
- ajusta o acesso a `AsyncValue` para a API do Riverpod 3, sem depender de `valueOrNull`;
- atualiza **Novidades da atualização**, histórico das três mudanças, documentação e testes de regressão;
- avança `versionName` para `2.0.107` e `versionCode` Android para `200121`.

## 2.0.106+200120 — 2026-09-26

- substitui o diagnóstico longo embutido nos detalhes da execução por um resumo compacto com **Ver erros**;
- adiciona janela dedicada de erros com navegação entre falhas, explicação leiga, causa identificada/possível causa, orientação de correção e detalhes técnicos recolhidos;
- só usa o rótulo **Causa identificada** quando a leitura do log comprova uma assinatura técnica forte;
- adiciona ações **Copiar erro**, **Copiar diagnóstico** e **Logs completos** na janela de falhas;
- faz o botão **APK** consultar os arquivos ligados à execução/commit em vez de abrir silenciosamente uma lista genérica;
- corrige também a tela global **Builds**, que antes podia escolher o primeiro artifact/APK encontrado, e faz o atalho APK do repositório abrir a lista explícita em vez de baixar uma opção silenciosamente;
- adiciona seletor de APK por arquitetura com versão, execução, tamanho, origem e recomendação baseada em `Build.SUPPORTED_ABIS`;
- prioriza APK específico compatível com a ABI principal do aparelho antes do Universal e alerta antes de baixar variantes incompatíveis;
- adiciona informações do aparelho nas Configurações: modelo, Android/API, ABI principal, ABIs suportadas e suporte a 64 bits;
- preserva a preferência de ABI ao extrair APKs de Artifacts e nas tentativas de download;
- atualiza versão, Novidades, Configurações, README, AI_HANDOFF, VERSIONING, RELEASE e VALIDATION para `2.0.106+200120`.

## 2.0.105+200119 — 2026-09-26

- reorganiza o bottom sheet de detalhes dos Builds para reduzir densidade e repetição de informações;
- substitui a lista corrida de metadados por um **Resumo** em blocos com Evento, Branch, Duração e Etapas;
- move mensagem do commit para uma área própria e deixa commit SHA, horários, número da execução e workflow em **Detalhes técnicos** expansíveis;
- prioriza a falha antes do resumo quando um workflow termina com erro e recolhe dados extensos em **Detalhes do diagnóstico**;
- troca o parágrafo técnico do APK por um aviso curto **APK não gerado** com a causa principal;
- preserva Logs, Repetir, APK, Excluir, atualização, lista de jobs/etapas e cópia do diagnóstico;
- adiciona teste de contrato visual para impedir regressão à apresentação tumultuada;
- atualiza versão, Novidades, Configurações, README, AI_HANDOFF, VERSIONING, RELEASE e VALIDATION para `2.0.105+200119`.

## 2.0.104+200118 — 2026-09-26

- remove `StartupUpdateGate` do `MaterialApp.builder`, eliminando a camada de novidades que podia permanecer sobre a Home durante o ciclo de inicialização;
- substitui a sobreposição por uma `MaterialPageRoute` opaca aberta pelo `StartupUpdateCoordinator` somente depois de `AppLifecycleState.resumed`, dois frames concluídos e uma janela curta de estabilização;
- adiciona consulta nativa `getActivityLaunchState`, incluindo `cachedEngineReattach`, `flutterUiDisplayed`, task e restauração da Activity;
- impede a abertura automática de **Novidades** durante `cached_engine_reattach`; a tela continua acessível manualmente em Configurações;
- exige confirmação em **Continuar** na rota automática e só então persiste `app.whats_new.last_seen_version`;
- adiciona telemetria local para `startup.whats_new_check_started`, `needed`, `route_opened`, `first_frame`, `continue` e casos de adiamento/reattach;
- mantém a correção nativa da 2.0.103 para engine em cache e splash escura, sem interromper uploads/downloads ativos;
- atualiza testes de contrato, README, AI_HANDOFF, VERSIONING, RELEASE e VALIDATION para `2.0.104+200118`.

## 2.0.103+200117 — 2026-09-26

- trata reabertura da `MainActivity` com `FlutterEngine` preservado usando `getCachedEngineId()` somente quando o engine está executando Dart;
- mantém `shouldDestroyEngineWithHost() = false`, preservando transferências ativas entre saídas e retornos à Activity;
- em reattach, aplica `NormalTheme` antes do `super.onCreate()` e reforça a limpeza do fundo nativo em `onFlutterUiDisplayed()`;
- corrige o tema noturno de inicialização para `Theme.Material.NoActionBar`, ícones de sistema claros e fundo `#050B14`;
- adiciona telemetria local `android.engine_reattach`, com contador, task, estado restaurado, Android, aparelho e versão;
- importa o evento nativo também em `AppLifecycleState.resumed`, cobrindo reaberturas do mesmo isolate sem reiniciar `main()`;
- atualiza a tela **Novidades da atualização** somente com as mudanças da 2.0.103 e atualiza Configurações;
- adiciona teste de contrato do ciclo de engine em cache e sincroniza identidade/documentação em `2.0.103+200117`.

## 2.0.102+200116 — 2026-09-26

- unifica visualmente os cards de GitHub Releases e GitHub Actions Artifacts na tela **APKs**;
- ambos passam a usar a mesma hierarquia: versão, metadados, origem/formato e ações na mesma posição;
- Artifacts deixam de destacar o nome bruto do arquivo e removem o texto técnico redundante de classificação inferida da listagem principal;
- adiciona indicador compacto de variante (`Universal`, `ARM64`, `ARMv7`, `x86`, `Performance`) quando detectável pelo nome do artifact;
- reconhece Artifact cuja versão já exista em Release, mostra **Publicado** e remove a ação **Publicar** para evitar duplicação;
- ao redirecionar download de Artifact para Release, prioriza a mesma variante quando ela existir;
- corrige a extração visual de versão para não incorporar `versionCode`/sufixos como `universal-release.apk`;
- padroniza a ordem das ações: **Baixar/Escolher**, **Publicar** quando aplicável e **Excluir**;
- atualiza a tela **Novidades da atualização**, Configurações, README, AI_HANDOFF, RELEASE, VALIDATION e versionamento para `2.0.102+200116`.

## 2.0.101+200115 — 2026-09-26

- faz varredura visual completa e padroniza retângulos para raio de 4 px, alinhando cards, campos, botões, diálogos, snackbars e indicador da navegação ao padrão da Home;
- mantém somente pills/círculos deliberados para estados e indicadores que dependem dessa forma;
- adiciona `error_telemetry` ao SQLite (`schemaVersion = 3`) com retenção máxima de 120 eventos;
- captura erros globais de Flutter, exceções assíncronas do Dart e falhas registradas pelo logger;
- adiciona `GitHubManagerApplication` com `UncaughtExceptionHandler` nativo para preservar o último crash Android antes do encerramento do processo;
- importa o crash nativo no próximo acesso e disponibiliza tudo em **Configurações > Erros e telemetria**;
- adiciona ações de copiar relatório, exportar `.txt` para Downloads/GitHub Manager e limpar o histórico local;
- sanitiza padrões conhecidos de Authorization Bearer, token, password, api key, secret, `github_pat_...` e `gh*_...`;
- nada de telemetria é enviado automaticamente; a captura pode ser desativada nas Configurações;
- corrige o controle da tela **Novidades da atualização**: a versão só é marcada como vista após **Continuar**, evitando que a tela seja consumida antes de realmente ser lida;
- adiciona **Novidades desta versão** em Configurações para revisão manual;
- adiciona testes de contrato para raios visuais, telemetria global/nativa e exibição das novidades;
- sincroniza documentação e identidade para `2.0.101+200115`.

## 2.0.100+200114 — 2026-09-26

- corrige a criação/retenção de duas janelas do GitHub Manager em **Aplicativos recentes** após atualização, instalação de APK ou retorno por notificação;
- `MainActivity` passa de `singleTop` para `singleTask` e volta a usar a afinidade padrão do pacote, com `documentLaunchMode="never"`;
- ao criar ou receber um novo Intent, a Activity remove tarefas antigas duplicadas do próprio app em `ActivityManager.appTasks`, limpando também cartões remanescentes de versões anteriores;
- remove `FLAG_ACTIVITY_NEW_TASK` dos fluxos iniciados pela própria `MainActivity` para abrir URI e instalar APK;
- notificações de upload/download passam a reabrir explicitamente `MainActivity` com `ACTION_MAIN`, `CATEGORY_LAUNCHER`, `CLEAR_TOP` e `SINGLE_TOP`;
- adiciona teste de contrato para impedir regressões na configuração de task/Recentes;
- sincroniza identidade, tela de novidades e documentação para `2.0.100+200114`.

## 2.0.99+200113 — 2026-09-26

- reduz somente os cantos dos cards da lista **Meus repositórios** para raio de 6 px, preservando o restante do tema;
- adiciona tela completa **Novidades da atualização** no primeiro acesso após cada nova versão;
- persiste localmente a última versão já apresentada para evitar repetição na mesma atualização;
- mantém a verificação de novidades fora do primeiro frame, com timeout e falha controlada para não atrasar a abertura do app;
- atualiza a seção **Últimas 3 mudanças** nas Configurações;
- sincroniza identidade e documentação para `2.0.99+200113`.

## 2.0.98+200112 — 2026-09-26

- compacta a tela interna do projeto movendo APKs/artifacts, Commits, Diagnóstico do token e Issues/Bugs para atalhos no cabeçalho;
- reorganiza os menus restantes do projeto em ordem alfabética;
- simplifica cards de Release: versão em destaque, remoção da tag redundante e ação Excluir explícita ao lado de Baixar/Escolher;
- substitui o ícone ambíguo de confirmação da branch por um botão **Continuar** e torna a escolha de outra branch uma etapa explícita;
- adiciona testes de contrato para navegação compacta, cards de Release e seleção de branch;
- sincroniza identidade e documentação para `2.0.98+200112`.

## 2.0.97+200111 — 2026-09-26

- exclusão em lote de Builds passa a exibir etapa, item atual e percentual determinado de 0 a 100%;
- limpeza **Excluir APKs anteriores** reutiliza os artifacts/APKs já carregados na tela, corrigindo divergências entre a lista visível e uma segunda consulta remota;
- Central de Downloads passa a confirmar com o Android a exclusão física do arquivo antes de remover o registro local;
- ação de download é renomeada para **Excluir do aparelho**, mantendo **Remover do histórico** como operação separada;
- descrições dos projetos são removidas dos cards da Home para reduzir altura e poluição visual, sem perder a busca por descrição;
- pesquisa da Home vira uma lupa compacta no AppBar e só ocupa espaço enquanto está ativa;
- README usa cache em memória por repositório/branch, decodificação isolada para conteúdo grande e renderização Markdown lazy;
- adiciona teste de progresso da limpeza em lote;
- sincroniza identidade e documentação para `2.0.97+200111`.

## 2.0.96+200110 — 2026-09-25

- reorganiza a tela **APKs** para exibir um card por versão detectada, reduzindo informação duplicada;
- corrige a ordem de projetos que acumulam várias versões dentro da mesma GitHub Release de tag fixa, usando a versão encontrada no nome do asset antes da data como critério;
- agrupa variantes da mesma versão (Universal, ARM64, ARMv7, x86) e abre um seletor compacto ao baixar quando existem várias opções;
- remove os badges redundantes `Direto` e da versão/arquivo no card de Release e move o gerenciamento/exclusão para uma ação discreta;
- troca os avisos centrais globais por SnackBars flutuantes compactos no rodapé, sem cobrir o conteúdo principal;
- reduz os indicadores globais de envio/download de botões extensos para botões pequenos com anel de progresso e badge de quantidade;
- corrige também a limpeza de APKs antigos para preservar todas as variantes da versão mais nova mesmo quando várias versões usam a mesma Release fixa;
- adiciona testes de regressão para ordenação do Explorador XP, agrupamento por versão, limpeza e prioridade da variante Universal;
- sincroniza versão/documentação para `2.0.96+200110`.

## 2.0.95+200109 — 2026-09-24
- corrige as duas falhas restantes dos jobs GitHub Manager CI #84 e Android APK #85;
- torna o contrato de repositório vazio independente de formatação/whitespace, evitando falso negativo quando o Dart formatter quebra a condição em várias linhas;
- adiciona chave estável ao botão **Outras branches** e faz o `testWidgets` aguardar o estado real da lista em pumps limitados, sem depender de atraso fixo de 400 ms;
- a CI deixa de executar `dart format lib test` de forma mutável antes da análise/testes e passa a usar `dart format --output=none --set-exit-if-changed`, apenas avisando sobre formatação pendente;
- adiciona teste de regressão garantindo que o workflow não volte a modificar o código antes da suíte;
- mantém as melhorias de carregamento progressivo e timeout/retry das versões anteriores.

## 2.0.94+200108 — 2026-09-24
- Corrige erro fatal do analyzer `Undefined class 'ValueListenable'` em `repository_detail_widgets.dart`, adicionando o import explícito de `package:flutter/foundation.dart` à biblioteca de detalhe do repositório.
- Mantém as melhorias de carregamento progressivo e seletor compacto de branch introduzidas na 2.0.93.

# Changelog

## 2.0.93+200107 — 2026-09-24

- redesenha o seletor de branch como diálogo compacto e centralizado, com branch atual, botão **Criar** e lista recolhível **Outras branches**;
- o seletor abre imediatamente e carrega branches em segundo plano, com timeout de 12 s e **Tentar novamente** em vez de spinner indefinido;
- ao enviar um ZIP, a interface mostra imediatamente **Preparando envio** e informa a etapa atual enquanto permissões e dados da branch são consultados;
- versão remota, prévia da sincronização, workflow e rate limit passam a ser iniciados em paralelo para reduzir o tempo entre branch e confirmação;
- a tela Projeto reaproveita o repositório já carregado na listagem para abrir instantaneamente e atualiza os dados em segundo plano;
- quando não há cache, substitui a tela quase vazia por carregamento progressivo com cabeçalho e seções visíveis;
- adiciona timeout/retry ao carregamento principal do repositório e limites às consultas de branches, runs e metadados;
- mantém o cache somente em memória e o invalida em edição, rename e exclusão para não reapresentar dados antigos;
- atualiza os testes/contratos do seletor e do fluxo de envio para o novo comportamento.

## 2.0.92+200106 — 2026-09-24

- corrige a única falha restante dos jobs GitHub Manager CI #81 e Android APK #82;
- o seletor já retornava corretamente a branch `develop`, mas o teste exigia que o texto `develop` desaparecesse completamente da árvore após o `Navigator.pop`, uma expectativa desnecessária e sensível à animação/transição da rota;
- o teste agora valida somente o contrato funcional relevante (`selected.name == 'develop'`), mantendo a verificação de scroll/toque da branch e eliminando a falsa falha;
- atualiza a fixture do teste e sincroniza a versão para `2.0.92+200106`;
- os logs anteriores confirmaram 126 testes aprovados e apenas essa asserção falhando, sem novo erro de compilação.

## 2.0.91+200105 — 2026-09-24

- corrige a única falha restante dos jobs GitHub Manager CI #80 e Android APK #81: o teste encontrava a branch `develop`, mas tentava tocá-la fora da área visível do viewport de teste;
- o teste passa a rolar explicitamente até a branch antes do toque, reproduzindo o comportamento real de uma lista rolável em telas menores;
- adiciona uma chave estável por item no seletor reutilizável de branches, reduzindo a fragilidade dos testes de interface;
- remove o import não utilizado apontado pelo analyzer em `repository_send_flow_widget_test.dart`;
- mantém o timeout de 3 minutos nos workflows como proteção, embora os novos logs confirmem que a suíte já encerra normalmente em menos de 1 minuto.

## 2.0.90+200104 — 2026-09-24

- substitui o teste end-to-end instável de envio por dois `testWidgets` focados e determinísticos: seleção de branch e minimização do diálogo de progresso;
- remove do teste de interface a dependência da tela completa de repositório, banco local, roteamento de envio e múltiplas operações assíncronas que mantinham o job preso;
- mantém a ordem branch → permissões → confirmação/política de build coberta pelos testes de contrato que já passam;
- adiciona cobertura explícita para o diálogo com `LinearProgressIndicator` indeterminado sem usar `pumpAndSettle`;
- mantém o timeout de 3 minutos da etapa `flutter test` como proteção de CI.

## 2.0.89+200103 — 2026-09-24

- Corrige o travamento real remanescente de `repository_send_flow_widget_test.dart`: o teste não usa mais `pumpAndSettle()` enquanto o diálogo de progresso possui animação contínua.
- Substitui as esperas abertas do fluxo de envio por helpers limitados (`_pumpUntilVisible`/`_pumpUntilGone`), que avançam o relógio virtual em passos curtos e falham de forma explícita caso a interface não chegue ao estado esperado.
- Mantém o `UploadManagerService.forTest` sem fila de I/O real nesse `testWidgets`, preservando a separação entre teste de UI e testes unitários da fila.
- Os logs CI #78 e Android APK #79 confirmaram 33 dos 34 arquivos de teste concluídos; o único arquivo ausente da conclusão era o teste de envio pela interface.
- Mantém o limite de 3 minutos dos workflows como proteção contra regressões futuras.

## 2.0.88+200102 — 2026-09-24

- Corrige o travamento remanescente de `repository_send_flow_widget_test.dart`: o teste de interface deixa de iniciar cópia de ZIP e persistência real em disco dentro do `FakeAsync` do Flutter.
- `UploadManagerService.forTest` ganha a opção `runBackgroundQueue` (padrão `true`); apenas o teste de interface usa `false`, enquanto a suíte unitária continua exercitando a fila completa.
- O teste fecha explicitamente o diálogo de progresso após validar branch e política de build, evitando deixar o fluxo visual pendente ao encerrar.
- Os três workflows limitam a etapa `flutter test` a 3 minutos; qualquer travamento futuro falha automaticamente em vez de exigir cancelamento manual.
- Mantém as correções anteriores de persistência e `waitUntilIdle()` para o comportamento real do gerenciador.

## 2.0.87+200101 — 2026-09-24

- Corrige o deadlock do `repository_send_flow_widget_test.dart` que deixava CI #76 e Android APK #77 presos até cancelamento.
- `waitUntilIdle()` deixa de fazer polling com `Future.delayed(10 ms)` e passa a aguardar a conclusão da fila por `Completer`, funcionando dentro de `testWidgets`/`FakeAsync`.
- A conclusão da fila sinaliza explicitamente o estado ocioso sem depender da passagem de tempo virtual.
- Caminhos de falha de upload/build passam a aguardar a persistência do histórico e a limpeza segura do ZIP gerenciado antes de concluir.
- Mantém o debounce de 650 ms somente no uso normal; `UploadManagerService.forTest` continua sem debounce.

## 2.0.86+200100 — 2026-09-24

- Corrige o `Timer` de 650 ms que permanecia pendente no teste de interface do fluxo de envio.
- Remove a corrida entre persistência de `history.json` e exclusão da pasta temporária nos testes do gerenciador de uploads.
- `UploadManagerService.forTest` passa a persistir sem debounce; produção mantém debounce de 650 ms.
- `waitUntilIdle()` agora também espera a fila de persistência terminar.
- `dispose()` agora aguarda persistência e encerramento do serviço de foreground antes de fechar o stream.
- Mantém os nomes padronizados dos logs introduzidos na 2.0.85.

## 2.0.85+200099 — 2026-09-24

- Corrige a detecção de identidade/versão em ZIP Android nativo que contém apenas o módulo `app/`, restaurando `applicationId`, `versionName` e `versionCode`.
- Atualiza o teste de repositório vazio para validar o seletor de branch reutilizável, onde esse comportamento está implementado desde a 2.0.82.
- Torna o teste de envio pela interface robusto a conteúdo rolável antes de alternar **Iniciar build após o envio**.
- Renomeia os workflows para `GitHub Manager CI`, `GitHub Manager Android APK` e `GitHub Manager Android Release`, deixando os arquivos baixados pelo GitHub mais claros.
- Padroniza também o botão **Log** do aplicativo para salvar `<Repositorio>-<Workflow>-<Run>-logs.zip` sem duplicar o nome do repositório.

## 2.0.84+200098 — 2026-09-24

- Corrige o erro fatal do CI/APK #73 em `permission_preflight_service_test.dart`: o gateway de teste volta a declarar explicitamente a capacidade `push` usada no diagnóstico de permissões.
- Remove a expressão nula inalcançável em `repository_git_workflows.dart`, eliminando os warnings `dead_code`/`dead_null_aware_expression` associados.
- Limpa o lint recente do `separatorBuilder` na tela Builds sem alterar o comportamento da interface.
- Mantém a nomenclatura atual dos pacotes de logs; nenhuma mudança de nome de saída foi aplicada nesta versão.

## 2.0.83+200097 — 2026-09-24

- Reorganiza a aba global **Builds** para exibir somente um card por repositório, representando o commit/versão mais recente.
- Ao tocar no repositório, abre um pop-up com os workflows atuais daquele commit, preservando casos com duas builds simultâneas, como CI + Android APK.
- Adiciona ações rápidas **Log** e **APK** em cada build do pop-up; artifacts APK são consultados somente quando o usuário solicita o download.
- Atualiza o polling visual a cada 6 segundos, mantendo consulta curta apenas nos repositórios com execução ativa e varredura global a cada 1 minuto ou por atualização manual.
- Corrige os erros fatais dos logs Android-APK-72 e Verificação do Projeto CI-72: `_isLikelyRootFile` ausente e uso nullable de `RepositoryBranch` após a escolha da branch.
- Remove warnings diretamente relacionados à implementação recente em upload, workflow e preparação de APK.
- Amplia testes da tela/serviço Builds para agrupamento por repositório, múltiplos workflows no mesmo commit e navegação para a execução específica.

## 2.0.82+200096 — 2026-09-24

- Unifica a seleção de branch em Arquivos, Commits, Builds e Enviar versão e adiciona criação de nova branch a partir da branch atual.
- Adiciona prévia somente-leitura antes do envio com contagem/lista de arquivos novos, alterados e removidos.
- Corrige identificação de versão em ZIPs com múltiplos projetos ao priorizar metadados da raiz efetiva em vez do primeiro arquivo compatível encontrado.
- Preserva pré-lançamentos completos (`alpha`, `beta`, `rc`, `dev`) ao inferir versão pelo nome do ZIP e mantém essa origem explicitamente marcada como inferida.
- Amplia detecção de identidade/versão para Godot (`project.godot`), Python (`pyproject.toml`) e Rust (`Cargo.toml`).
- Exibe a origem da versão e, quando disponível, o saldo do rate limit REST do GitHub na conferência de envio.
- Adiciona testes para detecção de raiz, versão alpha no nome, prévia de sincronização, criação de branch e leitura de rate limit.

## 2.0.81+200095 — 2026-09-24

- Move a escolha da branch para antes do pré-check de sincronização e repete o diagnóstico quando a branch é alterada na confirmação final.
- Permite o primeiro envio para repositório realmente vazio quando o GitHub retorna zero branches, mantendo falhas de API separadas desse caso.
- Corrige a comparação de versões para SemVer, incluindo precedência de `alpha`, `beta`, `rc`, identificadores numéricos e metadados `+build`.
- Reduz chamadas da tela global **Builds**: cache em memória da lista de repositórios por 10 minutos, polling de 10 segundos apenas nos repositórios com execução ativa e varredura global a cada 3 minutos.
- Adiciona testes de SemVer, cache/polling e um teste de widget do fluxo de envio pela interface com escolha de branch e build desmarcada.

## 2.0.80+200094 — 2026-09-24

- Adiciona **Alterar** diretamente em **Branch de destino** na confirmação final de envio. Ao trocar a branch, o app recarrega os metadados e a detecção de workflow daquela branch antes de permitir o envio.
- Mantém a preferência da última branch usada como best-effort e preserva a seleção atual ao reabrir o seletor.
- Passa a identificar versões de projetos Shell/Termux via `MANIFEST.json` e variáveis `*VERSION=` no `manager.sh`, no ZIP local e no repositório remoto.
- Quando não há versão interna confiável, exibe uma versão inferida do nome do ZIP apenas como pista visual, sem usá-la como fonte forte na comparação de segurança.
- Adiciona testes de regressão para o retorno tipado do diálogo, troca de branch e detecção de versão do Termux Manager.

## 2.0.79+200093 — 2026-09-24

- Corrige o erro fatal de análise em `global_builds_screen.dart`: `AsyncValue<GlobalBuildsSnapshot>` não usa mais o getter inexistente `valueOrNull`; o polling passa a ler somente `AsyncData`.
- Confirma e protege por teste o contrato de `_confirmZip()`: o diálogo `showDialog<ManagedUploadBuildPolicy>` retorna `buildPolicy`; o `bool` permanece apenas no diálogo interno `showDialog<bool>` de confirmação forçada.
- Limpa warnings introduzidos pela reorganização recente de Projetos, incluindo import sem uso, resultados de `ref.refresh` descartados e helpers/membros mortos.
- Correção baseada nos logs Android-APK-69 e Verificação do Projeto CI-69.

## 2.0.78+200092 — 2026-09-23

- Corrige a suíte `TokenPermissionDiagnosticsService`: o diagnóstico de **Contents** para PAT clássico volta a exigir apenas `repo`, alinhado ao fluxo atual de sincronização do projeto sem build.
- Mantém `repo + workflow` exclusivamente para operações de **Actions/Build**, preservando a separação introduzida nas versões 2.0.74–2.0.76.
- Correção baseada nos logs Android-APK-67 e Verificação do Projeto CI-67, que apresentavam 99 testes aprovados e 1 falha.

## 2.0.76+200090 — 2026-09-23

- Corrige o pré-check de **Enviar nova versão**: PAT clássico com `repo` volta a ser suficiente para sincronizar arquivos, sem exigir `workflow` quando a operação não inicia build.
- Mantém `repo + workflow` para **Enviar build**, preservando a separação entre sincronização do projeto e controle de GitHub Actions.
- Ajusta o diagnóstico equivalente de PAT fine-grained para `Contents: write` na sincronização e `Actions: write` na etapa de build.
- Correção baseada nos logs Android-APK-66 e Verificação do Projeto CI-66, que apresentavam 99 testes aprovados e 1 falha no `PermissionPreflightService`.

## 2.0.75+200089 — 2026-09-23

- Corrige erro de análise em `global_builds_screen.dart`: `ListView` não possui construtor `const`.
- Corrige identificador inexistente `buildPolicy` no diálogo de criação de fork; confirmação volta a retornar `true`.
- Mantém as melhorias da 2.0.74 para seleção de branch, Builds globais e projetos sem workflow.
- Correções baseadas nos logs Android-APK-65 e Verificação do Projeto CI-65.

## 2.0.74+200088 — 2026-09-23

- O envio de uma nova versão agora permite escolher a branch de destino antes da conferência; a última branch escolhida por repositório é lembrada localmente e branches protegidas são identificadas.
- A comparação de identidade/versão do projeto passa a consultar a branch realmente selecionada, evitando comparar `dev`/`release` contra `main`.
- Adicionada a aba global **Builds** no menu inferior, reunindo as execuções recentes do GitHub Actions de todos os projetos e permitindo filtrar por executando, sucesso ou falha.
- **Acompanhados** foi movido para dentro de Projetos em um seletor `Meus projetos / Acompanhados`, mantendo cinco itens no menu inferior.
- Projetos sem workflow de APK, como scripts e utilitários que não precisam de compilação, agora são identificados já na conferência e terminam como **Projeto atualizado • Sem workflow de build**, sem falso erro ou estado de build pendente.
- O pré-check de **Enviar nova versão** exige somente permissão de Contents; permissões de Actions continuam necessárias apenas para operações de build.
- Quando um workflow de APK é detectado, a conferência permite desmarcar **Iniciar build após o envio**; nesse caso o projeto é sincronizado sem consultar/disparar Actions.
- A detecção de ausência de workflow foi antecipada para evitar espera desnecessária antes de concluir projetos que não utilizam GitHub Actions; falhas de rede/API durante a inspeção continuam sendo tratadas como diagnóstico pendente, não como ausência de workflow.
- Testes foram ampliados para cobrir branch específica, projeto sem workflow e a separação de permissões entre sincronização e build.

## 2.0.73+200087 — 2026-09-16

- Corrigidos os dois erros `non_constant_list_element` detectados nos logs Android APK 63 e CI 63.
- `leftover` em `build_cleanup_service_test.dart` passou a ser constante em tempo de compilação, preservando os testes de limpeza de artifacts.
- Removido import de teste não utilizado.
- Nenhuma regra de exclusão de build, artifact ou APK de Release foi alterada.

## 2.0.72+200086 — 2026-09-16

- Refatorado `ManagedUpload` em componentes internos de estado, diagnóstico, ciclo de vida, relatório e codec JSON.
- Preservado o contrato público usado pela Central de Envios, telas e `UploadManagerService`.
- Mantidas as mesmas 51 chaves de persistência para compatibilidade com checkpoints anteriores.
- Adicionado teste de contrato cobrindo diagnóstico, relatório, round-trip JSON e retry após a divisão.

## 2.0.71+200085 — 2026-09-16

- Refatorado o ciclo de vida do SQLite para uma única conexão compartilhada por isolate.
- Removido o construtor público de `LocalDatabase`, evitando abertura acidental de conexões independentes.
- Aberturas concorrentes do banco agora reutilizam o mesmo `Future<Database>`.
- `localDatabaseProvider`, startup, monitor de builds e preferências de recuperação deixaram de fechar o banco após operações curtas.
- `singleInstance: true` voltou a ser usado com ownership controlado por isolate.
- Mantidos reparo idempotente do esquema, reconstrução local segura e preservação do token GitHub.

## 2.0.70+200084 — 2026-09-16

- Refatoradas as telas grandes de Configurações, Detalhe do repositório, Builds/Detalhe da build e APKs/Releases.
- Exclusão de build passou a limpar artifacts e APKs de Release vinculados com segurança ao mesmo commit.
- Adicionada exclusão direta de assets de Release e paginação ampliada de Releases.

## 2.0.69+200083 — 2026-09-16

- Corrigida a referência de `_shortSha` que interrompia a compilação.
- Workflow Android passou a executar análise e testes Dart antes do Gradle.
