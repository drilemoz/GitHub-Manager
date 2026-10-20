### 2.0.136

A versão canônica é `version: 2.0.136+200150` (versionName 2.0.136; Android versionCode 200150). Corrige alertas repetidos de builds com ledger SQLite e adiciona Configurações → Notificações com chave geral e categorias de builds/downloads. Consulte `docs/RELEASE_2.0.136.md`.

### 2.0.135

A versão canônica é `version: 2.0.135+200149` (versionName 2.0.135; Android versionCode 200149). Adiciona suporte a `STATUS.json` e corrige as duas falhas de testes do workflow Android APK #124, com regressões. Consulte `docs/RELEASE_2.0.135.md`.

### 2.0.134

A versão canônica é `version: 2.0.134+200148` (versionName 2.0.134; versionCode 200148). Corrige a documentação que bloqueou a validação de versão do workflow **Android APK #123**, restaura o histórico de versões e introduz teste de regressão. Consulte `docs/RELEASE_2.0.134.md`.

### 2.0.133

A versão `version: 2.0.133+200147` melhorou a detecção do APK instalado, redesenhou seu cartão e passou a identificar SDK Android no detalhe do projeto. Consulte `docs/RELEASE_2.0.133.md`.

### 2.0.132

A versão `version: 2.0.132+200146` melhora a seleção/importação de `.env` e variantes na tela Secrets, oferece exclusão em lote apenas após confirmação digitada, processamento individual, progresso e resultado copiável sem valores. Consulte `docs/RELEASE_2.0.132.md`.

### 2.0.131

A versão `version: 2.0.131+200145` adiciona a configuração persistente de limpeza automática de downloads por projeto (após conclusão, antes de iniciar, desligada), excluindo apenas arquivos finais gerenciados na pasta exata e preservando parciais, pausados e outros documentos. Veja `docs/RELEASE_2.0.131.md`.

### 2.0.130

A versão `2.0.130+200144` introduz pausas reais, retomada segura por HTTP Range, persistência de estado pausado, proteção do histórico e alertas de conexão sem progresso. Preserva os mecanismos de integridade e download de APK. Configuração canônica: `version: 2.0.130+200144`. Veja `docs/RELEASE_2.0.130.md`.

### 2.0.129

A versão `2.0.129+200143` permite copiar o relatório completo da auditoria da Google Play pela janela Play, preservando resultados, evidências, limitações e pendências manuais. O botão só é ativado após a análise bem-sucedida e confirma a cópia. Consulte `docs/RELEASE_2.0.129.md`.

### 2.0.128

A versão 2.0.128+200142 adiciona auditoria parcial de publicação Google Play no detalhe de repositórios e quinta ação compacta Play. API 36, versão, bundle e verificações manuais são apresentados sem atestar aprovação da Play Console. Veja `docs/RELEASE_2.0.128.md`.

### 2.0.127

A versão `2.0.127+200141` corrige o histórico de Configurações fora de ordem que reprovou o único teste do Android APK #116. A tela lista `2.0.127`, `2.0.126` e `2.0.125`, do mais recente ao mais antigo. Não altera o fluxo de APKs. Veja `docs/RELEASE_2.0.127.md`.

### 2.0.126

A versão 2.0.126+200140 corrige o contrato de teste de seleção de APK que bloqueou o workflow Android APK #115 após a centralização das consultas no provider da 2.0.125. Mantém a checagem de app instalado e seleção de ABI sem alterações na lógica de produção. Veja `docs/RELEASE_2.0.126.md`.

### 2.0.125

A versão 2.0.125+200139 integra o estado de instalação do Android ao botão APK e compara a versão instalada com a última publicação disponível, com ressalvas de visibilidade de pacotes e confiança dos metadados. Veja `docs/RELEASE_2.0.125.md`.

### 2.0.124

A versão 2.0.124+200138 corrige o atalho APK da tela do repositório, consultando Releases e Artifacts sob demanda, oferecendo download direto da versão mais recente e seleção de arquitetura quando há variantes. Veja `docs/RELEASE_2.0.124.md`.

### 2.0.123

A versão `2.0.123+200137` corrige cinco incompatibilidades `String` → `List<int>` no teste de projeto web estático que bloquearam o Android APK #112. Remove `!` desnecessário e preserva as melhorias da 2.0.122. Veja `docs/RELEASE_2.0.123.md`.

### 2.0.122

A versão 2.0.122+200136 amplia a identificação de projetos web/portfólio, infere nome por `README.md` ou `index.html` quando apropriado e compacta o resumo de Builds para exibir Evento, Branch, Tempo e Etapas em uma única linha quando houver espaço. Veja `docs/RELEASE_2.0.122.md`.

### 2.0.120

A versão 2.0.120+200134 disponibiliza um arquivo de compatibilidade `.github/workflows/ci.yml` **inativo**. O arquivo substitui a antiga CI ainda preservada pela sincronização incremental: não tem `push` nem `pull_request` e usa job `if: ${{ false }}`. Os testes agora exigem ausência do CI ou sua configuração inerte, nunca uma CI duplicada ativa. APK e Release preservam análise e testes. Consulte `docs/RELEASE_2.0.120.md`.

### 2.0.119

A versão 2.0.119+200133 corrige o teste visual desatualizado da Central de Builds e documenta por que a CI #107 ainda encontrou o workflow `ci.yml`: o arquivo havia sido retirado do ZIP, mas não do GitHub. É necessário excluí-lo explicitamente do repositório. A análise, os testes e o build do APK seguem preservados nos dois workflows Android. Veja `docs/RELEASE_2.0.119.md` e `docs/CI_LEGACY_REMOVAL.md`.

### 2.0.118

A versão 2.0.118+200132 remove o workflow CI separado, mantendo análise Dart, testes Flutter, assinatura e build nos workflows de APK e Release. Os checks exigidos por regras de branch devem ser ajustados no GitHub se ainda apontarem para o job removido. Veja `docs/RELEASE_2.0.118.md`.

### 2.0.117

A versão 2.0.117+200131 corrige as duas referências a widgets ausentes no detalhe das execuções de Builds, responsáveis pela interrupção de `flutter analyze` na CI #106. Os ícones de execução e jobs voltam a distinguir status e permanecem na mesma biblioteca Dart. Inclui teste de contrato e documentação; execução real da CI continua pendente. Veja `docs/RELEASE_2.0.117.md`.

### 2.0.116

A versão 2.0.116+200130 distingue execução GitHub Actions da versão real do app, adiciona seleção guiada de APK, diagnósticos úteis de arquivo/linha e metadados build-info.json opcionais gerados pelo workflow Android APK. A ABI lida pelo nome é hipótese; manifests do workflow não substituem inspeção do arquivo baixado. Veja `docs/RELEASE_2.0.116.md`.

### 2.0.114

A 2.0.114+200128 corrige a navegação dos toques em notificações de Builds, Downloads e Envios. Cada aviso leva ao registro/execução relevante. Builds antigas são consultadas diretamente pelo ID; eventos legados permanecem compatíveis e canais distinguem falhas de conclusões normais. A tela de Novidades não deve competir com a abertura causada por notificação.

### 2.0.113

A 2.0.113+200127 corrige o único teste que interrompia os workflows CI #102 e Android APK #103: depois de mover a busca global das Builds para a lupa na 2.0.112, o teste ainda tentava inserir texto antes de abrir o campo. O novo teste abre a busca primeiro e valida seu estado inicial e expandido, sem alterar o comportamento de produção.

### 2.0.112

A 2.0.112+200126 compacta a pesquisa e filtros das Builds, adiciona feedback e recuperação de erro nas consultas de APKs, melhora nomes e ações nos Downloads, agrupa a prévia de ZIP por pasta e preserva arquivo/linha das annotations e dos logs nos diagnósticos. Mantém as salvaguardas de Releases, identidade e exclusão.

### 2.0.111

A 2.0.111+200125 corrige três falhas de contrato nos jobs CI #100 e Android APK #101: raios fora do padrão, histórico com versões fixas obsoletas e divergência de terminologia no relatório de identificação. Remove banner sem uso, torna os testes de conteúdo rotativo menos frágeis e amplia a checagem de sincronização das versões em documentação e interface.

### 2.0.110

A 2.0.110+200124 simplifica a confirmação de envio de ZIP, permite expandir informações técnicas e copiar um diagnóstico contextual de nome/versão/identidade sem credenciais. Projetos Android podem usar o `android:label` do Manifest/strings como nome visual quando não houver metadados melhores. Mantém avisos de remoção, troca de branch e confirmação extra para identidades incompatíveis.

### 2.0.109

A 2.0.109+200123 amplia Builds com histórico recente, busca por projeto/branch/workflow/versão/SHA, filtros de status e período, comparação de execuções, duração e consulta de jobs/diagnóstico sob demanda. O polling global usa cache de 60 s e acompanha builds ativas a cada 15 s, mantendo horário efetivo da última consulta e preservando resultados quando possível. APKs de Release associados somente por commit são rotulados como ambíguos; a exclusão de builds preserva sempre os Releases. Testes e docs sincronizados.

# Versionamento

A fonte canônica é `pubspec.yaml`.

Versão atual:

`version: 2.0.129+200143`

- antes do `+`: versionName exibido ao usuário;
- depois do `+`: versionCode Android;
- cada APK futuro precisa usar versionCode maior;
- versões oficiais não usam o sufixo `alpha`.

A versão `2.0.115+200129` restaura o lançamento da MainActivity por ACTION_MAIN/CATEGORY_LAUNCHER nas notificações nativas, preservando as rotas específicas das transferências e o contrato de task única.

A versão `2.0.108+200122` permite ligar ou desligar a tela inteira nas Configurações, preservando o modo imersivo como padrão e salvando a preferência local; Android recente pode restringir a alteração.

A versão `2.0.107+200121` torna opcional a exibição da descrição completa dos repositórios na Home, com preferência local e atualização reativa dos cartões.

A versão `2.0.106+200120` separa erros de build em uma janela própria, relaciona APKs à execução correta e recomenda a variante compatível com as ABIs informadas pelo Android.

A versão `2.0.105+200119` reorganiza os detalhes dos Builds em uma hierarquia mais limpa: resumo primeiro, falha priorizada e metadados técnicos recolhidos.

A versão `2.0.104+200118` desacopla a tela automática de novidades do `MaterialApp.builder`, só a abre após a UI nativa/Flutter estar estável e bloqueia essa abertura durante reattach de engine preservado.

A versão `2.0.103+200117` estabiliza a reabertura da Activity com FlutterEngine preservado, alinha a splash ao tema escuro e registra reanexos do engine na telemetria local.

A versão `2.0.99+200113` reduz o arredondamento dos cards da Home e adiciona uma tela de novidades exibida uma única vez no primeiro acesso de cada atualização.

A versão `2.0.98+200112` compacta a navegação interna do projeto, torna exclusão de Releases e confirmação de branch mais explícitas e reduz informação redundante nos cards de APKs.

A versão `2.0.96+200110` reorganiza a tela de APKs: grupos passam a ser ordenados pela versão detectada mesmo quando várias builds estão anexadas à mesma Release de tag fixa, variantes de ABI ficam agrupadas e o feedback global de ações deixa de cobrir o centro da tela.

A versão `2.0.95+200109` corrige as duas falhas residuais de testes dos jobs CI #84 / Android APK #85 e elimina uma fonte de divergência do pipeline: a CI não reformata mais os fontes antes de executar análise e testes. Os contratos do seletor de branch agora são independentes de whitespace e de atrasos fixos de rede/UI.

A versão `2.0.92+200106` corrige a única falha restante dos jobs CI #81 e Android APK #82: o seletor já retornava `develop`, mas o teste ainda exigia que o texto desaparecesse completamente após o fechamento da rota; essa expectativa frágil foi removida.

A versão `2.0.89+200103` corrige o travamento confirmado pelos jobs CI #78 e Android APK #79: o teste de envio pela interface não usa mais `pumpAndSettle()` enquanto o diálogo de progresso possui animação contínua; as esperas agora são limitadas e falham explicitamente se o estado visual esperado não aparecer.

A versão `2.0.88+200102` separa o teste de interface da fila real de I/O usando `runBackgroundQueue: false` e adiciona timeout de 3 minutos às etapas de teste dos workflows.

A versão `2.0.86+200100` corrige o ciclo de persistência do `UploadManagerService`: testes não deixam mais debounce pendente, `waitUntilIdle()` aguarda gravações e `dispose()` aguarda o encerramento seguro antes de liberar arquivos temporários.

A versão `2.0.85+200099` corrige as três falhas de testes dos jobs CI #74 / Android APK #75 e padroniza os nomes dos workflows/downloads de logs para identificar projeto, tipo de workflow e execução.

A versão `2.0.84+200098` reorganiza Builds para um card por repositório, abre os workflows mais recentes em pop-up com downloads rápidos de Log/APK e corrige os erros fatais encontrados nos jobs #72.

A versão `2.0.82+200096` unifica a escolha/criação de branches, adiciona prévia read-only da sincronização e melhora a identificação de versões em projetos com subpastas, nomes com pré-release, Godot, Python e Rust.

A versão `2.0.81+200095` corrige a ordem branch → pré-check, libera o primeiro envio para repositórios realmente vazios, adota comparação SemVer correta e reduz o consumo da API na aba global Builds com cache em memória e polling seletivo.

A versão `2.0.80+200094` adiciona troca de branch diretamente na confirmação final de envio e amplia a identificação de versão para projetos Shell/Termux por `MANIFEST.json` e `manager.sh`, mantendo o nome do ZIP apenas como pista visual quando não houver metadado interno.

A versão `2.0.79+200093` corrige a incompatibilidade de `AsyncValue.valueOrNull` com Riverpod 3 na tela global de Builds, protege o retorno tipado do diálogo de envio com teste de regressão e limpa warnings introduzidos na reorganização recente.

A versão `2.0.78+200092` corrigiu a suíte `TokenPermissionDiagnosticsService`, alinhando o diagnóstico de Contents para PAT clássico ao fluxo atual de sincronização sem build. A versão `2.0.76+200090` havia corrigido o pré-check de permissões do envio.

A versão `2.0.72+200086` refatora o modelo `ManagedUpload` sem alterar seu contrato público, separando estado derivado, diagnóstico de falhas, mutações de ciclo de vida, relatório técnico e codec JSON em componentes internos menores.

A versão `2.0.71+200085` refatora o ciclo de vida do SQLite para uma única conexão compartilhada por isolate, deduplica aberturas concorrentes e remove fechamentos de banco por serviços auxiliares de curta duração.

A versão `2.0.70+200084` refatora as telas grandes de Configurações, Detalhe do repositório, Builds/Detalhe da build e APKs/Releases e torna a exclusão de builds responsável também pela limpeza de artifacts e APKs de Release vinculados com segurança ao mesmo commit.

A versão `2.0.69+200083` corrige a referência de `_shortSha` fora do escopo em `UploadProgressDialog`, compartilhando o helper no nível do arquivo e restaurando a compilação/CI da tela de progresso de envio.

A versão `2.0.68+200082` protege workflows do GitHub Actions contra remoção implícita durante a sincronização por ZIP, separa envio concluído de build pendente, melhora a descoberta de gatilhos e compacta o diagnóstico com ações de correção sem reenviar o projeto.

A versão `2.0.67+200081` corrige a migração e o ciclo de vida do SQLite, repara tabelas ausentes automaticamente, isola conexões locais entre serviços e adiciona diagnóstico/reconstrução do banco local sem apagar o token GitHub.

A versão `2.0.66+200080` corrige o build 57, adiciona leitura de versão de `package.json` em ZIPs Node/JavaScript, troca o banner de conferência pela versão real do projeto a enviar, acrescenta ajuda contextual para identidade/versão e expõe a chave/token GitHub atual com exibição/cópia em Configurações.

A versão `2.0.65+200079` ativa projetos fixados usando a persistência SQLite já existente, adiciona filtro/ordenação da lista e separa o carregamento resumido dos cards da análise completa de metadados para reduzir chamadas desnecessárias à API.

A versão `2.0.64+200078` adiciona o tamanho informado pelo GitHub aos cards de projetos e um resumo no topo com quantidade de projetos e tamanho total, sem chamadas extras por repositório.

A versão `2.0.63+200077` redesenha a tela de APKs/Releases: remove a lista recolhível de Releases, exibe cada arquivo diretamente em cards identificados, adiciona busca e filtros, simplifica a barra superior e mantém Artifacts claramente separados das Releases.

A versão `2.0.62+200076` adiciona recuperação inteligente de envios: repetição controlada para falhas temporárias, fallback automático de árvore incremental para reconstrução completa, proteção por SHA da branch, método manual por arquivos individuais para alterações pequenas/seguras e histórico de tentativas no diagnóstico.

A versão `2.0.61+200075` torna as falhas de envio explicáveis: preserva a operação exata que falhou, HTTP/endpoint/resposta completa do GitHub, progresso alcançado, impacto seguro no repositório e orientação específica por tipo de erro.

A versão `2.0.60+200074` melhora Builds: polling leve a cada 6/15 segundos, seleção automática de falhas por toque longo, exclusão em lote tolerante a falhas individuais e diagnóstico que combina annotations com contexto extraído dos logs do GitHub Actions.


A versão `2.0.59+200073` remove o uso de cache local para dados remotos do GitHub. Repositórios, descrições, perfil, permissões e metadados são consultados diretamente; Acompanhados guarda somente referências owner/repo; snapshots legados são removidos no startup.

A versão `2.0.53+200067` corrige a splash screen do Android 12+: fundo branco em qualquer tema e recurso de splash separado, com área segura maior para impedir o corte do ícone. O launcher/adaptive icon continua inalterado.

A versão `2.0.50+200064` corrige o assistente de configuração: `401` no `/user` passa a ser identificado como PAT rejeitado, e tokens colados são normalizados para remover formatação/whitespace invisível antes do teste e armazenamento.

A versão `2.0.49+200063` adiciona reconciliação de repositórios excluídos externamente, sanitização de URLs temporárias de download, timeout `dataSync` no Android 15+, lock de dependências e menor uso de memória para arquivos grandes em ZIP.

A versão `2.0.28+200042` integra o diagnóstico às ações críticas: Enviar build, mutações de Secrets e exclusão de repositório usam pré-checagem em cache e bloqueiam somente permissões já negadas com segurança.

A versão `2.0.26+200040` reforça GitHub Secrets com suporte documentado a PAT fine-grained/clássico, validação de 48 KB/100 Secrets, importação com diagnóstico por item e testes dedicados.

A versão `2.0.25+200039` remove o banner global de teste, melhora Acompanhados para aceitar URLs de perfil, adiciona edição de perfil pela Home, reorganiza Sobre/suporte e mantém downloads em foreground com retomada parcial por HTTP Range.

A versão `2.0.24+200038` reorganiza o log de envio em relatório visual e textual com métricas de arquivos, resultado da build, workflow, arquivos alterados e linha do tempo limpa.

A versão `2.0.23+200037` mantém envios em primeiro plano com notificação de progresso e adiciona checkpoints persistentes para retomada automática após encerramento do processo.

A versão `2.0.22+200036` adicionou a Central de Envios minimizável, fila global persistida, deduplicação de envios, reutilização de blobs Git idênticos e identificação visual de APK de teste.

A versão `2.0.21+200035` corrigiu a trava de identidade/versão, seleção de workflows, Releases privadas e persistência de downloads interrompidos.

A versão `2.0.20+200034` corrigiu os erros de nulabilidade encontrados nos logs #17 e moveu as ações do detalhe da build para o topo.


A 2.0.58 preserva stale-while-revalidate, mas deixa de depender de invalidações para atualizar a Home: a lista fresca retornada pela API é aplicada diretamente, enquanto falhas de rede mantêm o último snapshot válido.

### 2.0.90

A 2.0.90 corrige o travamento confirmado pelos jobs CI #79 e Android APK #80 ao decompor `repository_send_flow_widget_test.dart` em testes de widget focados. A seleção de branch e o diálogo de progresso continuam cobertos pela interface; a ordem branch → pré-check → confirmação/política permanece coberta pelos testes de contrato; e o upload real permanece nos testes unitários do serviço.



### 2.0.92

A 2.0.92 remove a última expectativa frágil do teste de seleção de branch. Os logs CI #81 e Android APK #82 já mostravam 126 testes aprovados; a branch `develop` era retornada corretamente e somente a asserção de ausência total do texto falhava durante a transição do bottom sheet.

### 2.0.91

A 2.0.91 corrige a falha de viewport do teste de seleção de branch observada nos jobs CI #80 e Android APK #81. A branch `develop` já existia na UI, mas estava fora da área visível do `testWidgets`; o teste agora a traz para a viewport com `ensureVisible` antes de tocar.







### 2.0.108

A 2.0.108 permite alternar o modo imersivo (`SystemUiMode.immersiveSticky`) e a visualização com barras de sistema (`SystemUiMode.edgeToEdge`). A escolha começa ativada, é persistida em `settings.fullscreen_enabled` e reaplicada ao iniciar/retomar a Activity sem atrasar o primeiro frame. Por limitações do Android e Flutter, a plataforma pode ignorar a solicitação de modo imersivo em targets recentes. `versionCode` sobe de `200121` para `200122`.

### 2.0.107

A 2.0.107 reintroduz as descrições dos repositórios na Home como opção do usuário. O texto recebido da API GitHub aparece por inteiro quando habilitado, sem corte de linhas; por padrão a Home permanece compacta. A preferência fica no banco SQLite local e é observada via Riverpod. O `versionCode` Android sobe de `200120` para `200121` para permitir atualização sobre a versão anterior.

### 2.0.106

A 2.0.106 torna o fluxo de Builds mais seguro e compreensível: falhas saem do bloco expansível da execução e ganham uma janela dedicada com explicação leiga e detalhes técnicos sob demanda; o botão APK passa a buscar arquivos vinculados à execução/commit; e a escolha de variante usa as ABIs reais reportadas pelo Android, com recomendação do APK específico compatível e aviso para arquitetura incompatível.


### 2.0.105

A 2.0.105 reduz o excesso de informação no bottom sheet de Builds sem remover dados. Evento, branch, duração e etapas ficam no resumo; mensagem do commit ganha área própria; execução, SHA, horários e workflow ficam em detalhes técnicos expansíveis. Em falhas, o motivo principal aparece primeiro e o diagnóstico extenso fica recolhido.

### 2.0.104

A 2.0.104 remove `StartupUpdateGate` da árvore do `MaterialApp.builder`. A verificação automática passa para `StartupUpdateCoordinator`, que só abre uma rota Flutter opaca depois de `resumed`, frames estáveis e confirmação nativa de `onFlutterUiDisplayed()`. `MainActivity.getActivityLaunchState` informa quando a Activity está reanexando o engine em cache; nesse caso a abertura automática é pulada para não interferir com splash/superfície nativa. A versão só é marcada como vista após **Continuar**.

### 2.0.103

A 2.0.103 mantém o FlutterEngine vivo durante transferências, mas passa a reutilizá-lo pelo contrato explícito de `getCachedEngineId()` quando o isolate já está executando. Reaberturas trocam para `NormalTheme` antes do attach, o splash noturno usa o mesmo fundo base da interface escura e a telemetria local registra `android.engine_reattach` em cada reanexo importado no resume.

### 2.0.102

A 2.0.102 padroniza os cards de Release e Artifact na mesma tela. Artifacts passam a exibir versão amigável e variante compacta, sem a frase de classificação inferida. Quando uma Release da mesma versão já existe, o card recebe **Publicado**, a ação **Publicar** desaparece e o download prioriza uma variante equivalente. O parser visual de versão deixa de incorporar versionCode e sufixos de nome de arquivo.

### 2.0.101

A 2.0.101 padroniza superfícies retangulares em raio de 4 px e adiciona telemetria local de estabilidade. O SQLite passa ao schema 3 com `error_telemetry`; o Flutter captura erros de framework, dispatcher e zone; o Android registra o último crash nativo desde o `Application`; e Configurações permite revisar/exportar os eventos sem envio automático. A tela de novidades passa a marcar a versão como vista somente após confirmação explícita em **Continuar**.

### 2.0.100

A 2.0.100 corrige o ciclo de task/Recentes no Android. `MainActivity` usa `singleTask`, afinidade padrão e `documentLaunchMode="never"`; no startup e em novos Intents, tarefas antigas duplicadas do próprio pacote são removidas; intents externos iniciados pela Activity deixam de forçar `NEW_TASK`; notificações de transferência voltam para a Activity principal existente. O objetivo é manter uma única entrada do GitHub Manager nos Recentes.

### 2.0.99

A 2.0.99 deixa os cards de projetos quase retos com raio de 4 px e introduz `StartupUpdateGate`/`UpdateWhatsNewScreen`. A versão instalada é lida do manifesto canônico e comparada com a última versão apresentada no banco local; a versão é marcada como apresentada quando a tela aparece, portanto o aviso não se repete até uma nova atualização.

### 2.0.98

A 2.0.98 move atalhos secundários para o cabeçalho do projeto, deixa a lista principal em ordem alfabética, simplifica os cards de Releases e substitui o check da escolha de branch por um botão Continuar explícito.

### 2.0.97

A 2.0.97 torna exclusões destrutivas verificáveis e visíveis, corrige a divergência da limpeza de APKs usando os itens já carregados na tela, compacta a Home e reduz o custo de abrir READMEs grandes com cache, decodificação fora da UI e lista lazy de blocos Markdown.

### 2.0.96

A 2.0.96 corrige a apresentação de APKs em repositórios que mantêm várias versões na mesma Release, agrupa Universal/ARM64/ARMv7 em um seletor único e reduz a interferência visual dos avisos e indicadores globais de transferência.

### 2.0.95

A 2.0.95 estabiliza a suíte após o redesenho do seletor de branches: o teste de repositório vazio tolera formatação automática, o `testWidgets` aguarda o botão/lista por estado real com timeout finito e a CI verifica formatação sem alterar o código que será testado.

### 2.0.94

A 2.0.94 corrige a regressão de análise da 2.0.93 causada pelo uso de `ValueListenable<String>` no overlay de operação sem importar `flutter/foundation.dart`. Não altera o comportamento funcional do fluxo; restaura a compilação/análise do projeto.

### 2.0.93

A 2.0.93 elimina os intervalos de interface vazia observados após selecionar a branch e ao abrir alguns repositórios. O seletor abre antes da API, a tela de projeto usa o snapshot já obtido na listagem e as consultas remotas têm timeout/retry. A confirmação de envio exibe progresso explícito e paraleliza as consultas auxiliares da branch.
