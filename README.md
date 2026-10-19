# GitHub Manager 2.0.135
## STATUS.json + correções do Android APK #124 (2.0.135)

- Ao **conferir um envio de ZIP**, reconhece `STATUS.json` na raiz (ou raiz efetiva) e usa sua versão interna como evidência real, não apenas a pista do nome do arquivo.
- Na busca de metadados do repositório, preserva **maiúsculas/minúsculas** do caminho real do GitHub, permitindo localizar `STATUS.json` e `MANIFEST.json`.
- Suporta `project`, `app_name` e `application_id` de `STATUS.json`; mantém **separadas** a versão da integração, a do manager incorporado e a do APK esperado.
- Corrige os testes do Android APK #124: raios retangulares do card seguem 4 dp; raios realmente em pill preservam 99 dp. A consulta Android não declara um pacote ausente quando o sistema pode ocultá-lo.
- Acrescenta regressões para a versão do ZIP e do repositório, inclusive arquivos de subprojetos que não devem sobrepor a raiz.

## Correção do versionamento da CI Android APK #123 (2.0.134)

- Corrige a documentação canônica `docs/VERSIONING.md` para corresponder ao formato exigido pelo workflow.
- Preserva os recursos de identificação do SDK e a análise de app instalado, introduzidos na versão 2.0.133.
- Adiciona teste de regressão para evitar novas divergências entre o versionamento do projeto e a documentação.

## APK instalado com detecção melhor e SDK visível (2.0.133)

- **Status do APK redesenhado:** cartão mais claro, com estados visuais distintos para instalar, atualizar, atualizado e inconclusivo.
- **App não instalado em vermelho:** quando o pacote não for encontrado no aparelho, o aviso fica destacado em vermelho.
- **Versão no topo do card do projeto:** a versão foi movida para um chip acima do nome do app.
- **SDK Android exibido:** o cabeçalho e a janela de informações do projeto podem mostrar `targetSdk`, `minSdk` e `compileSdk`.
- **Detecção melhorada:** a checagem nativa do pacote foi ajustada para reduzir respostas inconclusivas.

## Limpeza automática por projeto (2.0.131)

**Configurações → Transferências → Limpeza automática dos downloads** oferece:

- **Após concluir (padrão):** publica e valida o arquivo novo antes de retirar os demais arquivos finais gerenciados na pasta do projeto.
- **Antes de iniciar:** remove os arquivos finais antigos antes de começar. Se o novo download falhar, o anterior poderá já ter sido excluído. Depois da publicação, faz uma conferência para respeitar downloads simultâneos.
- **Desativada:** conserva os arquivos até o usuário decidir removê-los.

A limpeza se limita aos arquivos finais de propriedade do GitHub Manager em `Downloads/GitHub/<projeto>` (Android 10+). Downloads `.part` privados, pausados e em andamento não são excluídos. Em Android 9 ou inferior a limpeza só alcança caminhos gerenciados previamente registrados no histórico; arquivos de terceiros e pastas pessoais são preservados. Se o Android não confirmar a limpeza, o app informa o problema, sem considerar silenciosamente o diretório limpo. A proteção se aplica a APKs, ZIPs de projetos, logs, artifacts e demais arquivos publicados pelo gerenciador. A publicação é serializada por pasta, evitando que duas conclusões concorrentes causem limpeza incorreta.


## Downloads pausáveis e diagnóstico de lentidão (2.0.130)

- Na **Central de Downloads**, tocar em **Pausar** cancela a requisição de rede e mantém a parte já gravada no armazenamento temporário do aplicativo. A transferência aparece na seção **Pausados**, com **Retomar** e **Cancelar**.
- **Retomar** aguarda o fechamento do arquivo da conexão anterior, lê os bytes efetivamente salvos e solicita o restante do arquivo via HTTP Range quando o servidor aceita. Links de Releases/Artifacts do GitHub obtêm novamente um URL autorizado. Se o servidor não suportar Range e responder com conteúdo completo, o download recomeça do zero para evitar corrupção.
- Pausas são persistidas no histórico. **Limpar histórico não apaga downloads pausados** nem os arquivos parciais. Downloads pausados não retomam automaticamente ao abrir o app.
- O tempo estimado permanece dependente da velocidade medida, e não pode prever congestionamento da internet/CDN. Depois de 15 segundos sem novos bytes, o app zera a velocidade/ETA desatualizados e mostra aviso. A Central sinaliza quando múltiplos downloads dividem o acesso à rede.
- **Proteção de integridade:** downloads por link público conferem `Content-Range` e comprimento informado antes de aceitar uma retomada; uma resposta incompatível causa erro em vez de anexar bytes errados.
- Não há aceleração artificial ou mudança na banda disponível. Reiniciar a conexão **pode** ajudar em algumas condições, sem garantia de aumentar a taxa. Ao perder a URL assinada de um link público com parâmetros efêmeros após reinício do app, a retomada pode exigir um novo link.


## Copiar relatório da auditoria Google Play (2.0.129)

Na janela **Play → Preparação para Google Play**, há o botão **Copiar relatório** ao lado de **Fechar**. Ele fica habilitado somente quando a consulta da branch terminar com sucesso. A cópia usa a área de transferência do Android (sem gravar o relatório no repositório) e inclui repositório, branch, resultado geral, cobertura da árvore, observações e ressalvas, verificações técnicas com status/detalhes/evidências e pendências para a Play Console.

O próprio botão confirma **Copiado** quando o Android recebe o texto e mostra mensagem de erro se a cópia falhar. **Reavaliar** invalida o estado anterior e exige uma nova análise antes de copiar. A auditoria continua sendo uma avaliação parcial, não uma certificação de publicação.

## Auditoria de publicação na Google Play (2.0.128)

Dentro de cada repositório, o quinto atalho **Play** abre uma janela de avaliação parcial do código. Os quatro atalhos anteriores (Enviar, GitHub/Fork, Copiar, APK) foram compactados sem serem removidos.

A avaliação analisa a árvore da branch selecionada no GitHub e os arquivos de origem permitidos, verificando configuração literal de **targetSdk >= 36** para apps Android comuns em 2026, `compileSdk` (separado do target), versionCode, applicationId, pistas de AAB/assinatura Release, política de privacidade, permissões sensíveis e requisitos de compatibilidade.

Os itens externos, como Segurança dos dados, conteúdo, teste da conta, ficha da loja e publicação, aparecem como **pendentes de confirmação manual**. A leitura de um valor no Gradle não equivale a validar o AAB gerado nem a aprovação da Google Play. O app **não acessa keystores, Secrets ou dados da Play Console**. Há links para a política oficial e para o Play Console e opção de reanalisar.

Limitações: Flutter/Gradle com `targetSdk` calculado dinamicamente é **desconhecido** até conferir o manifesto mesclado; análises de 64 bits/páginas de 16 KB precisam do artefato final. Workflow e diretórios podem estar incompletos; árvores truncadas são sinalizadas. O Google Play define exceções de API para TV/Wear/Automotive/XR, que devem ser conferidas no Play Console.


## Correção do histórico em Configurações (Android APK #116) — 2.0.127

- No workflow Android APK #116, `flutter analyze` não teve erros bloqueantes e `flutter test` encerrou com **227 testes aprovados e 1 falha**.
- O teste `test/system_ui_settings_contract_test.dart` esperava o histórico das últimas três versões em ordem decrescente, mas a tela listava `2.0.126, 2.0.124, 2.0.125`.
- A seção **Configurações → Sobre e novidades → Últimas 3 mudanças** agora lista `2.0.127, 2.0.126, 2.0.125`, com textos correspondentes às suas versões.
- O contrato de ordenação foi preservado para impedir regressões nas próximas atualizações. A lógica de downloads, Builds e APKs não foi alterada.
- Compilação Android e execução da suíte Flutter da 2.0.127 precisam ser validadas no GitHub Actions.

## Correção do teste de seleção de APK (Android APK #115) — 2.0.126

- O workflow Android APK #115 passou em `flutter analyze`, mas parou em `flutter test` após **227 testes aprovados e 1 reprovado**.
- O teste `test/build_apk_selection_contract_test.dart` ainda esperava as consultas `listReleaseAssets`, `listArtifacts` e a resolução da última versão diretamente em `repository_detail_screen_actions.dart`. Na 2.0.125, essa lógica foi centralizada em `repository_apk_status_provider.dart` para compartilhar os dados com a identificação do aplicativo instalado.
- O teste agora valida o caminho efetivo: atalho chama provider, provider busca Releases + Artifacts independentemente, agrupa a última versão e calcula estado instalado; ações seguem com seleção de ABI e download direto.
- **Código de produção preservado.** Trata-se da correção de um contrato de teste desatualizado, não de alteração na lógica de seleção. `flutter test` e build Android da nova versão ainda precisam ser executados na CI.

## APK: instalação e atualização no Android — 2.0.125

- Mostra no detalhe do repositório os estados **Instalar**, **Atualizar**, **Atualizado**, **Mais recente no aparelho**, **Sem APK** e **Não foi possível verificar**. Apresenta a versão instalada e a última versão de APK identificada no GitHub.
- Usa `applicationId` obtido dos metadados do projeto. Não infere o nome do pacote a partir do nome do repositório.
- Consulta apenas o pacote solicitado pelo `PackageManager` Android por canal nativo, com `longVersionCode` e `versionName`. O manifesto declara visibilidade de apps com tela inicial, **sem QUERY_ALL_PACKAGES**.
- Android 11+ pode ocultar pacotes. Quando uma consulta não encontra o pacote em um sistema sujeito a essa restrição, o app informa **Não foi possível verificar** em vez de afirmar que está desinstalado.
- Compara as versões publicadas em Releases/Artifacts com a versão instalada. Quando só existe versionName inferido do nome do arquivo/tag e não há versionCode remoto, apresenta ressalva explícita de que a comparação é pela versão visível.
- Mantém seleção de arquitetura e download direto; se uma versão igual ou anterior já estiver instalada, pergunta antes de baixá-la novamente.
- A instalação da atualização continua exigindo confirmação do Android e assinatura compatível. As otimizações de transferência anteriores foram mantidas.

**Limites:** a identidade e a versão real de um APK de Release não podem ser garantidas apenas pelo nome do arquivo; sem metadados suficientes a comparação é indicativa. Validação final exige `flutter analyze`, testes na CI e aparelho real.

## Atalho APK funcional no repositório — 2.0.124

- O botão APK na tela do repositório não fica mais desabilitado por depender exclusivamente de Artifacts. A busca é iniciada ao tocar, consultando **Releases e Artifacts** independentemente.
- Havendo um APK oficial da versão mais recente, inicia o download direto pela Central de Downloads; quando há **múltiplas variantes** (ARM64, ARM32, x86, x86_64, Universal), abre o seletor existente antes de baixar.
- A versão é ordenada pelo nome dos arquivos/tag quando reconhecível; um Artifact pode prevalecer se sua versão identificada for maior que a Release. Sem versões comparáveis, prefere a Release publicada.
- Artifacts expirados são ignorados e não são misturados entre execuções. Se uma das duas fontes do GitHub falhar, a outra continua disponível; se não houver APK, o app exibe uma explicação e oferece o catálogo completo.
- Mantém confirmação para ABI possivelmente incompatível, inspeção do APK após o download, recuperação de interrupções e os demais recursos existentes.

**Limite:** nome e ABI de arquivo são pistas; a compatibilidade efetiva só pode ser confirmada após inspecionar o APK. Builds que não produziram APK não oferecem download.


## Correção da análise Dart (Android APK #112) — 2.0.123

- O workflow do APK #112 falhou na etapa `flutter analyze`, antes de executar testes ou compilar o APK, por cinco erros `argument_type_not_assignable` em `test/static_web_project_detection_test.dart`.
- O construtor `ArchiveFile` exige bytes (`List<int>`), não `String`: o teste agora cria cada arquivo usando `utf8.encode()`, informa o tamanho dos bytes reais e usa `ZipEncoder().encode()` sem `!` desnecessário.
- Adicionado teste de regressão para um projeto web mínimo com apenas `index.html` na raiz.
- Foram preservadas a detecção de projetos web da 2.0.122, os quatro cartões compactos no resumo de Builds e as otimizações de downloads da 2.0.121.
- Validação Flutter/Android continua pendente de execução na CI.

## Resumo de Builds mais denso e projetos web reconhecidos — 2.0.122

- **Projetos web estáticos/portfólio:** o app agora identifica melhor ZIPs e repositórios com estrutura como `index.html`, `styles.css`, `app.js`, `README.md` e `vercel.json`, classificando-os como **Site estático**.
- **Nome do projeto web:** quando não houver metadado mais forte, o nome pode ser inferido pelo primeiro título do `README.md` ou pelo `<title>` do `index.html`.
- **Tecnologias detectadas:** repositórios desse tipo passam a mostrar melhor pistas como **Web**, **HTML**, **CSS**, **JavaScript** e **Vercel**.
- **Resumo das execuções:** no detalhe da Build, os quatro blocos **Evento, Branch, Tempo e Etapas** passam a ocupar a mesma linha quando a largura permitir, reduzindo altura e rolagem.
- **Downloads de APK:** permanecem as otimizações da 2.0.121 para velocidade mais estável, menos atualizações visuais e retomada automática em falhas transitórias.

**Limites:** a identificação web continua heurística e não substitui metadados explícitos. A validação final de layout/compilação depende da CI e de testes em aparelho.

## Correção da CI duplicada (Android APK #109 / CI #108) — 2.0.120

Os dois workflows da versão 2.0.119 interromperam o build após **201 testes aprovados e 2 falhas**: o `test/workflow_log_naming_contract_test.dart` detectou que `.github/workflows/ci.yml` permanecia ativo no checkout GitHub, apesar de não existir no ZIP. O sincronizador incremental protege arquivos de `.github/workflows/` de exclusão implícita.

**Correção aplicável com o GitHub Manager atual:** este ZIP inclui `.github/workflows/ci.yml` como *substituto inativo*, com somente `workflow_dispatch` e job `if: ${{ false }}`. Ao enviar pela opção de atualizar projeto, o arquivo sobrescreve o CI antigo sem pedir exclusão remota. Não há triggers `push` ou `pull_request`, logo não executa CI duplicada. Os testes reprovam qualquer ci.yml ainda ativo, mas aceitam a ausência do arquivo ou o stub desativado. Os workflows `android-apk.yml` e `android-release.yml` continuam realizando análise/testes/compilação.

**Limite:** a desativação só acontece após o ZIP ser enviado com êxito para a branch correta. Excluir definitivamente o ci.yml remoto continua sendo a solução mais limpa; instruções em `docs/CI_LEGACY_REMOVAL.md`. A tentativa de exclusão por integração GitHub recebeu HTTP 403, sem modificar o arquivo remoto.

## Correção de testes de Builds e CI — 2.0.119

Os workflows Android APK #108 e CI #107 identificaram três falhas de testes, não erros da compilação. O teste da tela de Builds procurava um rótulo antigo (`Android APK • #78`), embora a versão atual use `Android APK • execução #78`. Os testes foram alinhados ao texto existente na interface.

**Atenção à remoção da CI antiga:** a versão 2.0.118 já não incluía `.github/workflows/ci.yml` no ZIP, mas o arquivo permaneceu no repositório GitHub porque o envio incremental não apaga necessariamente arquivos ausentes no pacote. Exclua explicitamente `.github/workflows/ci.yml` na branch `main` antes de validar a versão. Instruções em `docs/CI_LEGACY_REMOVAL.md`. Os workflows `android-apk.yml` e `android-release.yml` continuam com análise e testes.


## Workflow CI independente removido — 2.0.118

O workflow independente `.github/workflows/ci.yml` foi removido para evitar duas execuções de verificação a cada push na branch `main`. O **GitHub Manager Android APK** mantém as etapas `flutter analyze`, `flutter test`, verificação de versão, assinatura e validação do APK antes de publicar o artefato. O **GitHub Manager Android Release** preserva suas próprias verificações e a validação do certificado oficial. Os testes de Dart/Flutter permanecem no projeto: somente o job duplicado de CI foi retirado. Os checks de branches protegidas que exigiam `Analisar e testar` devem ser atualizados no GitHub para não bloquear merges. Consulte `docs/RELEASE_2.0.118.md` e `docs/VALIDATION_2.0.118.md`.


## Correção da CI #106 — 2.0.117

A CI #106 parava em `flutter analyze`: os componentes `_RunStatusIcon` e `_JobIcon` eram chamados no detalhe das execuções sem estarem definidos. Ambos foram restaurados como widgets privados compartilhados pela biblioteca de Builds, com status visíveis e tooltips. A correção não altera downloads, associação de Releases ou rotas. Consulte `docs/RELEASE_2.0.117.md` e `docs/VALIDATION_2.0.117.md`.

### Recursos da versão anterior

A escolha de APKs nas Builds, detalhes de execução e Releases usa uma interface comum com sugestão conservadora, alternativas, avisos de compatibilidade e detalhes técnicos. A versão real não é o número da execução. O workflow Android APK pode publicar `build-info.json` como artifact separado para informar a versão e o SHA da execução. Veja `docs/RELEASE_2.0.116.md` e `docs/BUILD_INFO_PROTOCOL.md`.

- Corrige a falha dos workflows CI #104 e Android APK #105: 191 testes aprovados e um contrato Android incompatível com a alteração introduzida em 2.0.114.
- Notificações de serviços em foreground voltam a abrir a MainActivity por `ACTION_MAIN`/`CATEGORY_LAUNCHER`, reutilizando a task existente com `CLEAR_TOP`/`SINGLE_TOP`.
- Preserva a rota específica em `notificationRoute`, que aponta para o upload ou download selecionado, sem voltar à Home.
- Amplia o teste de regressão para verificar tanto a reutilização da Activity quanto a navegação das transferências.
- Versão canônica `2.0.117+200131`; a compilação e a navegação em aparelho físico exigem verificação na CI/Android.

## Notificações que abrem o evento 2.0.114

- Notificações de GitHub Actions agora abrem o repositório e a execução pelo ID e branch; quando não está na primeira página, o app consulta a execução diretamente.
- Toques em downloads e envios abrem a Central correspondente com o registro destacado e acesso aos detalhes. Serviços foreground nativos enviam o identificador correto, mesmo na abertura da Activity.
- Tap no app aberto, minimizado e iniciado por notificação é tratado em Flutter e Android. Eventos legados são compatíveis, e destinos desconhecidos são ignorados sem abrir URLs externas.
- Falhas de build e download recebem prioridade maior que notificações de conclusão normal. A tela de Novidades não desvia o usuário que abriu uma notificação.
- Nova versão `2.0.114+200128`, com testes de contrato, documentação e histórico. A compilação precisa ser confirmada pela CI.

## Correção da CI após a busca compacta 2.0.113

- Corrige `global_builds_enhancements_test.dart` para abrir a lupa antes de buscar uma branch no histórico.
- O teste agora confere que a pesquisa está oculta inicialmente e disponível após o toque, evitando `Bad state: No element` no Flutter Test.
- Mantém o comportamento da v2.0.112 nas telas de Builds, Downloads, APKs, prévia do ZIP e diagnóstico; nenhuma regra de negócio foi alterada.
- Versão canônica `2.0.113+200127`; documentação e histórico sincronizados. A CI deve executar `flutter test` e o Android APK para confirmar o resultado.

## Busca, APKs, Downloads, prévia de ZIP e diagnóstico 2.0.112

- Busca global de Builds sob demanda pela lupa, com filtros avançados recolhíveis e indicadores de filtros ativos.
- Botões APK com feedback imediato, proteção contra toques repetidos e consultas independentes a Artifacts e Releases; uma fonte indisponível não oculta a outra.
- Downloads exibem títulos compactos sem renomear arquivos. Ações Compartilhar/Excluir usam ícones com tooltips; nome original e caminho ficam nos detalhes. Não há rótulo de Release **provável** tomado como fato.
- Prévia de sincronização ampliada, agrupada por diretórios, com remoções primeiro e cópia do caminho integral.
- Diagnóstico usa localização proveniente de annotations do GitHub ou linhas reconhecidas do log; diferencia confirmação de hipótese e oferece acesso ao arquivo no commit da execução quando o caminho é seguro.
- Versão canônica `2.0.112+200126` e documentação/testes atualizados. A validação Flutter/Android deve ocorrer no CI.

## Correções de CI, testes e consistência visual 2.0.111

- Corrige os raios de dois contêineres da confirmação de envio para 4 px, conforme o contrato de estilo.
- Remove um banner de versão não utilizado, sinalizado pelo analisador.
- Atualiza o teste do relatório de identificação para o mesmo rótulo apresentado na interface: **Versão no GitHub**.
- Valida as **três últimas versões** do histórico automaticamente a partir da versão canônica, em vez de fixar versões antigas no teste de tela inteira.
- Testa a presença de itens de Novidades sem exigir títulos editoriais de uma atualização específica.
- A fonte canônica segue sendo `pubspec.yaml` (`2.0.111+200125`); para homologação, executar os comandos indicados em `docs/VALIDATION_2.0.111.md`.

## Conferência compacta e diagnóstico de projetos 2.0.110

- Confirmação de ZIP apresenta destino, branch, versão remota → ZIP, contagem de alterações e alertas de identidade ou remoção de arquivos.
- Metadados da API, detalhes técnicos, rótulos de identidade e instruções de workflows ficam recolhidos; **Ver arquivos** continua disponível.
- **Diagnosticar / Como corrigir** fornece instruções específicas para versões ausentes, identidade divergente ou nome desconhecido e permite **Copiar diagnóstico** sem token.
- Na Home e nos detalhes, quando não houver nome explícito, projetos Android podem obter o nome exibido de `android:label` no `AndroidManifest.xml` e `strings.xml`.
- `nameSource` e `metadataIssue` distinguem nome inferido por alternativa e falha de consulta; a branch, o pré-check de permissão e a confirmação extra de identidade divergente permanecem.
- Consulte `docs/IDENTIFICACAO_E_ENVIO.md` para um guia técnico.

## Builds inteligentes 2.0.109

- Visão por último commit e histórico recente com busca, filtros e comparação de execuções.
- Atualização otimizada (15 s para builds ativas, 60 s para busca global) e horário real da consulta ao GitHub.
- Diagnóstico/etapas sob demanda e duração aproximada de cada build.
- Artifacts específicos da execução são priorizados; APKs de Release relacionados somente por commit pedem confirmação e **nunca são apagados automaticamente** ao excluir uma build.



## Tela inteira configurável 2.0.108

- em **Configurações > Aparência**, a opção **Tela inteira** liga ou desliga o modo imersivo;
- ligada, usa `SystemUiMode.immersiveSticky`, mantendo o comportamento padrão das versões anteriores;
- desligada, usa `SystemUiMode.edgeToEdge`, com as barras do Android visíveis e layout adaptado às áreas seguras;
- a escolha é persistida em `settings.fullscreen_enabled` no banco SQLite local e é recuperada após o primeiro frame;
- a preferência é reaplicada quando o app volta ao primeiro plano, inclusive com FlutterEngine preservado; após fechar o teclado, uma reaplicação tardia evita que o modo imersivo se perca;
- **limitação do sistema:** Android/Flutter podem ignorar solicitações de modo imersivo ao usar targetSdk 35 sem migração, e não permitem optar por outros modos ao usar targetSdk 36 ou maior; o app não altera nem reduz o targetSdk para contornar isso.



## Descrições completas na Home 2.0.107

- em **Configurações > Página inicial**, a opção **Mostrar descrição dos repositórios** controla se os cartões da Home incluem a descrição cadastrada no GitHub;
- quando ativada, a descrição é exibida abaixo do nome do repositório, com quebra de linha e sem truncamento de texto ou limite artificial de linhas;
- ao desativar, a Home mantém os cartões compactos como antes, sem remover a descrição do repositório no GitHub;
- o ajuste é salvo no banco local e aplicado automaticamente às listas que usam `RepositoryCard`;
- a opção começa **desativada** até o usuário habilitá-la.


## Builds explicados e APK certo para o aparelho 2.0.106

- falhas de build deixam de crescer dentro dos detalhes da execução e passam a usar o resumo compacto **erro(s) encontrado(s) — Ver erros**;
- **Ver erros** abre uma janela dedicada com navegação entre falhas e blocos em linguagem simples: O que aconteceu, Onde aconteceu, Causa identificada/Possível causa e Como corrigir;
- **Causa identificada** só é usada quando a leitura automática do log encontrou uma assinatura técnica forte; nos demais casos o aplicativo apresenta **Possível causa**;
- mensagem original e contexto do GitHub ficam recolhidos em **Detalhes técnicos**, com ações para copiar erro, copiar diagnóstico e baixar logs completos;
- o botão **APK** de uma execução consulta apenas artifacts e Releases realmente vinculados àquela build antes de oferecer download;
- a tela global **Builds** usa a mesma seleção segura e o atalho APK do repositório abre a lista explícita, eliminando caminhos que escolhiam o primeiro arquivo silenciosamente;
- quando existem várias variantes, o seletor mostra versão, execução, arquitetura, tamanho e origem e recomenda a ABI específica compatível com `Build.SUPPORTED_ABIS`;
- APK incompatível com as ABIs do aparelho gera um aviso antes do download; Universal continua disponível como opção para compartilhamento;
- Configurações passa a mostrar modelo, Android, arquitetura principal, ABIs suportadas e suporte a 64 bits, sem permissão especial;
- ao extrair APKs de um Artifact, a preferência de ABI também é preservada na Central de Downloads e em tentativas de retomada.



## Detalhes de builds mais claros 2.0.105

- o painel de uma execução deixa de exibir uma lista longa de pares `rótulo: valor` e passa a começar por um **Resumo** em blocos para Evento, Branch, Duração e Etapas;
- falhas passam a aparecer antes dos metadados técnicos, com título direto, etapa que falhou e mensagem principal do GitHub;
- o diagnóstico completo continua disponível, mas fica recolhido em **Detalhes do diagnóstico** até o usuário precisar dele;
- commit, horários, número da execução e caminho do workflow continuam disponíveis em **Detalhes técnicos**, também expansível;
- a mensagem do commit saiu do cabeçalho e fica em um bloco próprio, evitando repetição e competição visual com status/versão;
- o estado do APK passa a usar um aviso curto **APK não gerado**, seguido apenas da causa relevante;
- nenhuma ação foi removida: Logs, Repetir, APK, Excluir, atualização, etapas e cópia do diagnóstico permanecem disponíveis.


## Novidades desacopladas do startup 2.0.104

- a abertura automática de **Novidades da atualização** não participa mais do `MaterialApp.builder` e não sobrepõe a árvore principal da Home;
- o novo `StartupUpdateCoordinator` aguarda o app estar em `resumed`, dois frames completos, uma pequena janela de estabilização e a confirmação nativa de `onFlutterUiDisplayed()`;
- a `MainActivity` expõe o estado da Activity ao Flutter para diferenciar cold start de `cached_engine_reattach`;
- em reattach de um engine preservado por upload/download, a tela automática é ignorada naquele ciclo, evitando disputar a superfície do Android durante a reconexão;
- quando necessária, Novidades abre como `MaterialPageRoute` opaca e só grava a versão como vista depois de **Continuar**;
- a tela manual em **Configurações > Novidades desta versão** continua disponível normalmente;
- a telemetria local registra os marcos da verificação e da primeira renderização da rota para facilitar confirmação em aparelho real.


## Reabertura estável com engine em cache 2.0.103

- a `MainActivity` passa a informar `getCachedEngineId()` somente quando o engine preservado existe e já está executando Dart, permitindo que o embedding reconheça corretamente o reattach;
- em reaberturas com engine ativo, o Android troca imediatamente do `LaunchTheme` para o `NormalTheme`, evitando manter a tela nativa de abertura sobre a interface já renderizada;
- uploads e downloads continuam preservando o mesmo `FlutterEngine`, pois `shouldDestroyEngineWithHost()` permanece `false`;
- o splash noturno usa fundo `#050B14`, alinhado ao fundo escuro principal, com status/navigation bar em modo escuro;
- a telemetria local registra `android.engine_reattach`, contador cumulativo e contexto do Android para validar o ciclo de reabertura;
- a tela **Novidades da atualização** descreve somente as mudanças desta versão.


## APKs unificados 2.0.102

- Releases e Artifacts usam o mesmo desenho de card: versão no topo, tamanho/data, origem e formato em indicadores compactos e ações alinhadas na mesma posição;
- o nome bruto do Artifact e a mensagem de classificação inferida deixam a listagem principal, reduzindo ruído visual;
- variantes reconhecíveis, como Universal, ARM64, ARMv7, x86 e Performance, aparecem em indicador compacto;
- quando a mesma versão já existe em uma Release, o Artifact é marcado como **Publicado** e deixa de oferecer **Publicar** novamente;
- downloads redirecionados para uma Release tentam preservar também a variante correspondente;
- a extração de versão ignora `versionCode` e sufixos de arquivo para exibir, por exemplo, `2.0.100` em vez de `2.0.100-200114-universal-release.apk`;
- a tela **Novidades da atualização** foi atualizada para esta versão e continua sendo exibida uma única vez após a atualização.


## Consistência visual, telemetria e novidades confiáveis 2.0.101

- padroniza os cantos de cards, botões, campos, diálogos, snackbars, indicadores de navegação e outros retângulos para o mesmo raio discreto de 4 px usado na Home;
- preserva somente elementos intencionalmente circulares/pill, como alguns indicadores de status;
- adiciona **Configurações > Erros e telemetria**, com captura local de falhas Flutter/Dart, importação do último crash nativo do Android, histórico limitado, cópia, exportação e limpeza;
- instala um `UncaughtExceptionHandler` nativo desde o `Application` para registrar crashes que encerram o processo e importá-los no próximo acesso;
- tokens, senhas, API keys e secrets conhecidos são ocultados nos relatórios, que permanecem locais e nunca são enviados automaticamente;
- o startup registra falhas auxiliares de tema, banco, UI do sistema e monitor de builds sem permitir que a própria telemetria derrube o aplicativo;
- a tela **Novidades da atualização** continua automática, mas a versão só é marcada como vista depois de tocar em **Continuar**; se o app for fechado antes, ela reaparece no próximo acesso;
- Configurações ganha **Novidades desta versão** para rever manualmente o resumo atual sem alterar o controle automático por versão.


## Correção de janelas duplicadas nos Recentes 2.0.100

- `MainActivity` passa de `singleTop` para `singleTask`, com afinidade padrão do aplicativo e `documentLaunchMode="never"`, fazendo as reaberturas convergirem para a mesma tarefa do Android;
- no startup e em novos Intents, tarefas duplicadas antigas do próprio GitHub Manager são removidas de `ActivityManager.appTasks`, inclusive resíduos criados antes desta correção;
- remove `FLAG_ACTIVITY_NEW_TASK` dos fluxos de abrir URI e instalar APK quando iniciados pela própria Activity, evitando criar uma nova tarefa desnecessária;
- notificações de upload/download agora usam `Intent` explícito para `MainActivity`, com `ACTION_MAIN`, categoria `LAUNCHER`, `CLEAR_TOP` e `SINGLE_TOP`;
- o objetivo é impedir dois cartões do GitHub Manager em **Aplicativos recentes** depois de atualizar, instalar APK ou tocar em uma notificação;
- inclui teste de contrato para proteger essa configuração nas próximas versões.


## Home mais reta e novidades da atualização 2.0.99

- os cards de **Meus repositórios** passam de cantos muito arredondados para raio de 4 px, deixando a listagem mais reta e compacta sem alterar os demais cards do aplicativo;
- uma nova tela **Novidades da atualização** abre automaticamente depois do primeiro frame ao detectar uma versão ainda não vista;
- a versão exibida é lida do manifesto `github-manager.json` e a última versão já mostrada é guardada localmente em `app.whats_new.last_seen_version`;
- a versão é marcada como apresentada assim que a tela aparece; **Continuar** apenas fecha o resumo, garantindo que ele não se repita no próximo acesso da mesma versão;
- falhas no armazenamento local ou leitura de versão são tratadas como recurso auxiliar e nunca bloqueiam a inicialização.

## Navegação compacta e ações mais claras 2.0.98

- atalhos de APKs, Commits, Diagnóstico do token e Issues/Bugs foram movidos para ícones compactos no cabeçalho do projeto;
- lista do projeto agora fica em ordem alfabética e sem atalhos duplicados;
- cards de Releases destacam a versão em badge, removem a tag redundante e usam botões explícitos Excluir/Baixar;
- seletor de branch agora exige a ação clara **Continuar** após a escolha.


A exclusão em lote de Builds agora mostra etapa, item atual e porcentagem real em vez de um indicador infinito. **Excluir APKs anteriores** usa exatamente os APKs/artifacts carregados na tela, evitando o falso “não havia APKs anteriores” quando a lista visível contém versões antigas. Na Central de Downloads, **Excluir do aparelho** só remove o registro após o Android confirmar a exclusão física do arquivo. A Home ficou mais compacta: descrições saíram dos cards e a pesquisa virou uma lupa no topo que abre o campo somente quando necessário. O leitor de README ganhou cache em memória, decodificação de arquivos grandes fora da thread principal e renderização Markdown lazy para reduzir travamentos.

## APKs mais limpos e ordenação por versão 2.0.96

A tela **APKs** agora agrupa os arquivos de uma mesma versão, inclusive quando um projeto publica muitas versões dentro de uma única GitHub Release de tag fixa. A ordenação prioriza a versão detectada no nome do APK, corrigindo casos como o Explorador XP em que `alpha.74` aparecia abaixo de versões antigas. Variantes Universal, ARM64 e ARMv7 ficam reunidas em um único card e são escolhidas ao tocar em **Escolher**. Os cards removem badges redundantes e ações destrutivas deixam de ocupar a linha principal. Avisos de ações passam a usar feedback flutuante compacto no rodapé, enquanto os indicadores globais de download/envio viram botões pequenos de progresso. A limpeza de APKs antigos também passa a manter apenas a versão mais recente (com todas as suas variantes), mesmo dentro de uma Release de tag fixa.

## Estabilidade de CI e seletor de branch 2.0.95

Corrige as duas falhas restantes observadas nos jobs CI #84 e Android APK #85. O teste de repositório vazio deixa de depender da quebra de linha produzida pelo formatter, e o teste do seletor passa a aguardar o estado real da interface por uma chave estável em vez de presumir que a lista remota apareça em 400 ms. A CI também deixa de reformatar os fontes no runner antes dos testes: passa a verificar a formatação em modo somente leitura, garantindo que o código testado seja exatamente o código enviado.

## Correção de análise/compilação 2.0.94

Corrige a regressão da 2.0.93 em que o novo overlay de preparação usava `ValueListenable<String>` sem importar `package:flutter/foundation.dart`, fazendo `flutter analyze` interromper tanto o CI quanto o job Android APK. O comportamento de carregamento progressivo e do seletor compacto de branch é mantido.

## Carregamento responsivo de projeto e branches 2.0.93

A abertura de um repositório agora reaproveita imediatamente os dados que já foram carregados na lista de projetos e atualiza o conteúdo em segundo plano. Quando não existe cache, a tela deixa de ficar vazia: mostra o projeto e as seções em carregamento progressivo, com timeout e **Tentar novamente** em falhas lentas. O seletor de branch passou de folha inferior grande para diálogo compacto centralizado; ele abre antes da resposta da API, mostra a branch atual e carrega **Outras branches** em segundo plano. Após escolher a branch no envio, um indicador explícito informa a etapa de preparação enquanto permissões, versão, prévia de arquivos, workflow e cota da API são consultados em paralelo.


## Correção final do teste do seletor de branch 2.0.92

Os jobs CI #81 e Android APK #82 confirmaram que o travamento terminou e que 126 dos 127 testes passam. A única falha restante era uma expectativa frágil do próprio teste: após selecionar `develop`, ele exigia que todo texto `develop` desaparecesse da árvore de widgets, embora a seleção já tivesse sido retornada corretamente. A 2.0.92 passa a validar o contrato importante — a branch devolvida é `develop` — sem depender da presença textual transitória da animação/rota.

## Correção do seletor de branch nos testes 2.0.91

Os jobs CI #80 e Android APK #81 confirmaram que o travamento anterior foi eliminado: a suíte termina normalmente, com 126 testes aprovados e apenas um teste falhando. A falha ocorria porque `develop` estava presente no seletor, porém fora do viewport de 600 px usado pelo `testWidgets`; o teste agora rola até a branch antes do toque e os itens do seletor possuem chaves estáveis para automação.

## Estabilidade dos testes de interface 2.0.90

Os jobs CI #79 e Android APK #80 mostraram que 33 dos 34 arquivos de teste terminavam normalmente e somente `repository_send_flow_widget_test.dart` permanecia ativo até o timeout. A 2.0.90 substitui esse teste monolítico por testes de widget focados e determinísticos para seleção de branch e minimização do diálogo de progresso. As regras do fluxo completo continuam cobertas pelos testes de contrato e pelos testes unitários dos serviços.


GitHub Manager é um aplicativo Flutter/Dart para Android que administra repositórios e GitHub Actions diretamente pela API do GitHub, sem backend intermediário.


## Correção do `pumpAndSettle` infinito 2.0.89

Os jobs CI #78 e Android APK #79 mostraram que 33 dos 34 arquivos de teste concluíam normalmente e apenas `repository_send_flow_widget_test.dart` nunca finalizava. A causa era `pumpAndSettle()` ser chamado depois da abertura do diálogo de progresso, que contém animação contínua e portanto nunca fica totalmente estável. A 2.0.89 substitui essas esperas por pumps limitados até o estado esperado aparecer ou desaparecer, mantendo o teste de interface sem fila real de I/O e preservando o timeout de 3 minutos dos workflows como proteção.

## Isolamento de I/O do teste 2.0.88

A 2.0.88 separou o `testWidgets` da fila real de upload com `runBackgroundQueue: false` e adicionou timeout de 3 minutos aos workflows. Os logs seguintes mostraram que ainda restava uma espera infinita de UI por `pumpAndSettle()`, corrigida na 2.0.89.

## Correção de persistência e testes 2.0.86

A 2.0.86 corrige as falhas dos jobs GitHub Manager CI #75 e Android APK #76. O serviço de uploads não deixa mais o timer de persistência pendente em testes, `waitUntilIdle()` aguarda a gravação do histórico e o descarte do serviço passa a aguardar a persistência antes de encerrar. Isso elimina a corrida que podia tentar apagar uma pasta temporária enquanto `history.json` ainda estava sendo escrito.

## Correção CI/APK e nomes de logs 2.0.85

A 2.0.85 corrige as três falhas de testes observadas nos jobs CI #74 / Android APK #75 e padroniza a saída dos logs. No GitHub, os workflows passam a usar os nomes `GitHub Manager CI`, `GitHub Manager Android APK` e `GitHub Manager Android Release`. Pelo botão **Log** do app, o arquivo também inclui repositório, workflow e número da execução sem duplicar o nome do projeto.

## Correção CI/APK 2.0.84

A 2.0.84 corrige a regressão de teste que interrompia os jobs #73 com `Undefined name 'push'` e remove warnings diretamente ligados às alterações recentes, sem alterar a nomenclatura dos downloads de logs.

## Builds por projeto e downloads rápidos 2.0.84

- a aba global **Builds** passa a listar cada repositório apenas uma vez, usando somente o conjunto de workflows do commit/versão mais recente;
- ao tocar em um projeto, uma folha inferior mostra as builds atuais daquele commit, como **Android APK** e **Verificação do Projeto (CI)** quando as duas existem;
- cada build do pop-up ganha ações rápidas **Log** e **APK**; o APK é localizado somente quando solicitado para evitar chamadas extras em toda a lista;
- a tela pede atualização a cada 6 segundos; enquanto há builds ativas, apenas os repositórios em execução são consultados nesse ciclo curto, e a varredura global ocorre a cada 1 minuto ou manualmente;
- corrigidos os erros de análise dos jobs #72: helper ausente `_isLikelyRootFile` e nulabilidade da branch selecionada no fluxo **Enviar versão**;
- limpos warnings relacionados a `temporaryFile`, `knownWorkflows`, `syncPreview` e preparação de APK.

## Branches, prévia de sincronização e detecção de projetos 2.0.82

- Arquivos, Commits, Builds e Enviar versão passam a usar o mesmo seletor de branch, com opção de criar uma nova branch a partir da atual quando o repositório já possui um commit de origem.
- A confirmação de envio mostra uma prévia somente-leitura da sincronização, separando arquivos novos, alterados e removidos antes de qualquer mutação no GitHub.
- A detecção de identidade/versão do ZIP prioriza a raiz efetiva do projeto, evitando que `example/`, ferramentas ou subprojetos assumam a versão principal.
- A inferência pelo nome do ZIP preserva versões completas como `0.1.0-alpha.58`, `beta`, `rc` e metadados SemVer; continua explícita como inferência, não como fonte forte.
- A identificação foi ampliada para Godot (`project.godot`), Python (`pyproject.toml`) e Rust (`Cargo.toml`), e a confirmação informa a origem da versão quando conhecida.
- A confirmação também exibe o limite REST restante da conta GitHub quando a API disponibiliza essa informação.


## Fluxo de envio e Builds mais seguros 2.0.81

- a branch de destino passa a ser escolhida **antes** do pré-check de sincronização; se a branch for alterada na confirmação final, o pré-check é executado novamente antes de continuar;
- repositórios realmente vazios, quando a API responde com zero branches, podem receber o primeiro envio e inicializar a branch padrão; falhas da API continuam sendo tratadas como erro e nunca são confundidas com repositório vazio;
- a comparação de versões passa a respeitar precedência **SemVer**, incluindo `alpha`, `beta` e `rc`: uma versão estável é posterior ao pré-lançamento equivalente e identificadores numéricos como `alpha.10` são comparados numericamente;
- a aba global **Builds** reutiliza a lista de repositórios por até 10 minutos, atualiza a cada 10 segundos somente os projetos com build ativa e faz varredura completa em intervalo de 3 minutos ou quando o usuário atualiza manualmente;
- adicionados testes SemVer, testes de cache/polling da Builds e um `testWidgets` do fluxo real de envio pela interface, cobrindo escolha de `develop`, build desmarcada e ordem branch → pré-check.


## Branch alterável e versão de projetos Shell/Termux 2.0.80

- a confirmação final de **Enviar versão** ganha **Alterar** ao lado da branch de destino; trocar a branch reabre a seleção e recalcula versão do repositório, proteção e presença de workflow para a nova branch antes do envio;
- a última branch escolhida continua sendo lembrada, mas a confirmação final deixa de ser somente informativa;
- projetos Shell/Termux passam a ter versão identificada por `MANIFEST.json` e por variáveis `*VERSION=` no `manager.sh`, tanto no ZIP local quanto no repositório GitHub;
- quando nenhum metadado interno confiável possui versão, o nome do ZIP pode fornecer apenas uma **pista visual**, exibida explicitamente como “pelo nome do ZIP” e sem ser usada como versão confiável na validação de segurança;
- adiciona testes de regressão para troca de branch no diálogo e detecção de versão do Termux Manager.

## Correção de build e regressões 2.0.79

- corrige a incompatibilidade com Riverpod 3 na tela global **Builds**, removendo o uso de `AsyncValue.valueOrNull` que bloqueava `flutter analyze` e o APK;
- preserva o retorno tipado `ManagedUploadBuildPolicy` no diálogo **Enviar versão** e adiciona teste de regressão para impedir retorno `bool` nesse fluxo;
- mantém polling adaptativo da tela Builds usando apenas estado `AsyncData`, sem depender de extensões removidas;
- limpa warnings introduzidos pela reorganização recente de Projetos: import sem uso, resultados de `refresh` descartados e helpers/membros mortos.

### Funcionalidades consolidadas da 2.0.78

- corrige o diagnóstico de permissões para PAT clássico: **Contents** passa a exibir corretamente apenas `repo` como requisito para sincronização do projeto sem build;
- **Enviar nova versão** permite escolher a branch de destino (`main`, `dev`, `release` ou outra existente) e lembra a última opção usada em cada repositório;
- a conferência de identidade e versão usa a branch escolhida, não mais obrigatoriamente a branch padrão;
- o menu inferior passa a ter **Projetos, Builds, Downloads, Perfil e Opções**; **Acompanhados** fica dentro de Projetos;
- a nova tela **Builds** reúne execuções recentes de todos os projetos, ordenadas da mais nova para a mais antiga, com filtros para executando, sucesso e falha;
- projetos sem workflow de APK são tratados como projetos válidos que apenas sincronizam arquivos: quando a ausência puder ser confirmada, isso já é explicado na conferência; o envio termina em **Projeto atualizado • Sem workflow de build** e não cria falso alerta de build;
- quando há workflow de APK, a conferência permite manter marcada ou desmarcar **Iniciar build após o envio**; a permissão de Contents é suficiente para enviar uma nova versão e Actions só é necessária quando uma build for realmente solicitada;
- a verificação de workflow é feita antes da janela de espera do Actions quando possível, reduzindo atraso em projetos que não usam CI.



## Refatoração de telas e limpeza vinculada de builds 2.0.70

- refatora **Configurações**, **Detalhe do repositório**, **Builds/Detalhe da build** e **APKs/Releases**, separando UI, estado/ações e widgets auxiliares sem reescrever os fluxos existentes;
- exclusão de uma build passa a ser coordenada: primeiro remove o workflow run, depois confirma a limpeza dos artifacts e remove explicitamente qualquer artifact remanescente ligado ao mesmo `run_id`;
- APKs publicados como **Release assets** passam a ser ligados ao commit da build; quando o vínculo com o mesmo SHA é seguro, excluir a build também exclui o APK correspondente sem apagar a Release nem a tag;
- Releases publicadas pelo próprio GitHub Manager passam a usar o `head_sha` do artifact como `target_commitish`, tornando o vínculo futuro entre build e APK determinístico;
- tela **APKs** ganha exclusão direta para arquivos de Release e a ação **Excluir APKs anteriores** agora limpa tanto artifacts APK antigos quanto APKs antigos de Releases, mantendo o mais recente de cada origem;
- listagem de Releases deixa de consultar somente as 30 primeiras e passa a paginar até 500 Releases, permitindo localizar e administrar APKs mais antigos;
- caches/providers de artifacts e Releases são invalidados depois das exclusões para evitar itens já removidos continuarem aparecendo na interface;
- adiciona testes de regressão para vínculo `workflow_run/head_sha`, limpeza coordenada da build e limpeza de APKs anteriores nas duas origens.

## Correção do build e prevenção 2.0.69

- corrige a falha de compilação em `upload_progress_dialog.dart` causada por `_shortSha(...)` estar declarado dentro de `_FailureDiagnostic`, enquanto também era chamado por `UploadProgressDialog`;
- o formatador de SHA curto agora é um helper privado de arquivo, compartilhado com segurança pelas duas classes;
- remove importação não utilizada introduzida no mesmo diálogo;
- mantém o fluxo de **Projeto enviado • Build pendente** da 2.0.68, sem alterar a lógica de upload ou reenvio;
- além da CI, o workflow **Android APK** agora executa `flutter analyze` e `flutter test` antes da etapa Gradle, evitando gastar a compilação inteira em erros Dart detectáveis previamente.

## Builds protegidas e diagnóstico acionável 2.0.68

- workflows existentes em `.github/workflows/**` passam a ser tratados como infraestrutura protegida: um ZIP pode substituir um workflow pelo mesmo caminho, mas não pode apagá-lo apenas por omissão durante a sincronização;
- o diálogo **Conferir build** informa essa proteção antes do envio, reduzindo o risco de desativar GitHub Actions sem perceber;
- depois que o commit já foi publicado, a ausência de uma execução do Actions não aparece mais como **Envio com falha**: o estado correto é **Projeto enviado • Build pendente**;
- **Verificar build** repete somente a descoberta/inicialização da build usando o commit já enviado, sem reenviar o ZIP;
- a inspeção dos YAMLs diferencia workflow de APK ausente, workflow sem gatilho e workflow com `push` que ainda não gerou run;
- workflows com `push` recebem uma janela adicional de espera para reduzir falsos negativos causados pela indexação do GitHub Actions;
- o diagnóstico principal ficou compacto e rolável, com **Como corrigir** visível e detalhes técnicos recolhidos; há atalhos para **Abrir Builds**, copiar diagnóstico e copiar um exemplo de `push` + `workflow_dispatch` quando aplicável.


## Recuperação de dados locais 2.0.67

- corrige a migração do SQLite para instalações atualizadas, elevando o esquema para a versão 2;
- cria/repara tabelas e índices ausentes de forma idempotente ao criar, atualizar e abrir o banco;
- evita o compartilhamento acidental da mesma conexão SQLite entre serviços independentes que abrem/fecham o banco;
- falhas no estado local de projetos fixados deixam de derrubar a listagem principal obtida do GitHub;
- entradas JSON locais corrompidas são descartadas individualmente, sem exigir limpeza de todos os dados do aplicativo;
- Configurações ganha **Diagnóstico de dados locais**, com reparo de estrutura e opção de reconstruir somente o banco local, preservando o token GitHub.

## Conferência de build e ajuda 2.0.66

- corrige a falha de compilação causada pela chamada do menu de repositório sem o parâmetro obrigatório de projeto fixado;
- ZIPs Node/JavaScript passam a ler `name`, `displayName` e `version` do `package.json` da raiz, inclusive quando o ZIP possui uma única pasta-raiz;
- o diálogo **Conferir build** deixa de mostrar em vermelho a versão instalada do GitHub Manager e passa a destacar a **versão do projeto a enviar**;
- avisos de identidade/versão ganham botão `?` com explicação do motivo e instruções específicas para corrigir;
- Configurações ganha uma área **Ajuda do aplicativo** com guia de identidade, envios, builds, APKs, token, Secrets e solução de problemas;
- **Chave / token GitHub atual** fica acessível diretamente em Configurações, com exibição protegida e botão de copiar;
- o antigo banner vermelho de versão do GitHub Manager foi neutralizado para não ser confundido com a versão do projeto.

## Projetos fixados e lista otimizada 2.0.65

- **Fixar no topo / Desafixar do topo** usa a tabela local de favoritos que já existia no SQLite, sem criar armazenamento paralelo.
- projetos fixados aparecem antes dos demais e recebem um indicador discreto no card;
- novo filtro **Fixados** e ordenação por **Mais recentes, Mais antigos, Nome A–Z, Maiores e Menores**;
- a preferência de fixação permanece local e acompanha renomeações pelo `repository_id`; referências órfãs são limpas após uma listagem válida do GitHub;
- cards passam a usar uma leitura resumida de nome/versão, evitando consultar linguagens e todos os metadados completos só para montar a lista;
- a análise completa de tecnologias, package/applicationId e versionCode continua disponível nas telas internas;
- documentação e identificação de versão foram sincronizadas com a versão atual.

## Tamanho dos projetos 2.0.64

- mostra o tamanho informado pela API do GitHub ao lado da versão no card;
- mostra quantidade de projetos e tamanho total abaixo de **Meus repositórios**;
- não adiciona chamadas extras por projeto para obter o tamanho.


## Tela de APKs e Releases 2.0.63

- Releases deixam de ficar escondidas dentro de uma lista expansível e passam a aparecer diretamente na tela;
- cada arquivo de Release recebe identificação visual clara de **Release**, formato, versão/tag e download direto;
- Artifacts continuam separados e agora recebem o selo explícito **Artifact**, reduzindo a confusão entre as duas origens;
- busca por nome/versão e filtro **Todos / Releases / Artifacts** foram adicionados;
- a barra superior foi simplificada, mantendo busca, filtro, upload e um menu para ações administrativas;
- a tela continua usando os dados reais do repositório, sem inventar nomes, ícones ou versões.

## Recuperação inteligente de envios 2.0.62

- cada tentativa registra o **método de sincronização** usado: incremental, reconstrução completa da árvore ou arquivos individuais;
- falhas temporárias de rede, `408`, `429` e `5xx` recebem repetição automática controlada, com espera e histórico visível;
- quando o GitHub rejeita a árvore incremental com `422`, a recuperação automática revalida o SHA da branch e tenta **reconstruir a árvore final completa**, em vez de repetir os mesmos dados;
- antes de publicar um commit, trocar de método ou alterar um arquivo individual, o app confirma novamente o SHA da branch e interrompe se houver mudança concorrente;
- como último recurso manual, alterações pequenas e seguras podem usar a **API de arquivos individuais**, com limite de operações/tamanho e bloqueio para executáveis ou objetos Git não compatíveis;
- o diálogo de erro diferencia **Repetir método atual** de **Tentar método alternativo** e mostra qual opção é recomendada;
- o histórico do envio registra cada recuperação, código HTTP/endpoint relevante e o método que efetivamente concluiu a sincronização;
- Configurações ganhou **Recuperação automática de envios**, ativada por padrão e limitada a alternativas consideradas seguras.


## Diagnóstico detalhado de falhas no envio 2.0.61

- o diálogo de falha informa exatamente **onde o envio parou**, preservando a última operação real em vez de mostrar apenas “Falha no envio”;
- exibe **até onde o processo chegou**, incluindo arquivos já analisados e se a falha ocorreu depois da leitura do ZIP;
- preserva e mostra **HTTP, endpoint, código interno e resposta detalhada da API do GitHub**;
- respostas `422` passam a explicar separadamente falhas ao criar árvore Git, commit, atualizar branch, enviar blob ou usar a API de conteúdo;
- quando for possível determinar com segurança, informa o **impacto no repositório** — por exemplo, se a branch permaneceu no commit anterior;
- o GitHub Manager mostra blocos separados de **Resposta do GitHub**, **O que isso significa** e **O que fazer agora**;
- o parser da API inclui detalhes do array `errors` retornado pelo GitHub, não apenas a mensagem genérica `Validation Failed`;
- **Copiar diagnóstico** reúne etapa, progresso, HTTP, endpoint, resposta do GitHub, interpretação e ação sugerida;
- as etapas recentes deixam de cortar a mensagem em uma única linha no diálogo de envio.


## Builds em tempo quase real e diagnóstico 2.0.60

- a tela de Builds continua consultando o GitHub mesmo quando nenhuma execução estava ativa ao abrir a tela;
- atualização automática adaptativa: 6 s com build em andamento e 15 s quando tudo está parado, usando uma consulta leve das execuções recentes;
- a listagem mostra horário de cada execução e o momento da última atualização;
- segurar uma build, quando existem falhas visíveis, seleciona automaticamente todas as falhas, preservando as execuções de sucesso;
- exclusão em lote continua mesmo se uma execução falhar ao apagar e mantém apenas as falhas restantes selecionadas;
- detalhes da build mostram evento, tentativa, horários, duração de jobs/etapas e resumo do estado do APK quando isso pode ser determinado com segurança;
- falhas consultam annotations e analisam automaticamente o ZIP de logs para destacar a linha e o contexto mais relevantes;
- botão **Copiar diagnóstico** reúne os dados necessários para compartilhar o erro sem baixar e procurar manualmente no log inteiro.

## Dados do GitHub sem cache local 2.0.59

- Repositórios, descrições e perfil agora são consultados diretamente na API do GitHub, sem fallback para snapshots persistidos.
- Acompanhados persiste apenas a lista `owner/repo` escolhida pelo usuário; os dados exibidos são buscados novamente no GitHub.
- Diagnóstico de permissões não reutiliza relatório remoto em TTL local.
- Snapshots legados `github.repositories`, `github.profile` e `followed.repositories.cache` são apagados automaticamente.
- Providers de perfil, repositórios e metadados de projeto usam `autoDispose` para não manter dados remotos fora da tela.

A lista agora usa o cache somente para abrir imediatamente e passa a tratar a resposta mais recente da API como fonte autoritativa. Criar, editar, renomear, excluir e criar fork atualizam os cards no mesmo instante. Ao voltar da tela interna, a listagem reconcilia silenciosamente com o GitHub, corrigindo descrições e demais metadados antigos sem spinner de tela inteira.

`GitHubRepository` também possui igualdade por valor, estabilizando o cache de versão/tecnologias dos cards: o mesmo repositório não cria providers duplicados a cada reconstrução e, quando os dados realmente mudam, os metadados são renovados.

## Rename de repositório reforçado 2.0.57

- valida o novo nome antes de chamar o GitHub;
- mostra a prévia do novo endereço `owner/nome`;
- bloqueia nome vazio, igual ao atual, acima de 100 caracteres, com espaços, barras ou caracteres incompatíveis;
- detecta previamente quando já existe um repositório com o nome escolhido;
- atualiza cache principal, Acompanhados, informações do projeto e permissões após renomear.

## Listagem estável 2.0.56

A lista preserva os cards durante atualizações e deixa o spinner central restrito à primeira carga sem dados disponíveis.

## Android/Kotlin nativo 2.0.55

A detecção reconhece `app/build.gradle.kts` e `app/build.gradle`, extraindo `versionName`, `versionCode`, `applicationId`/`namespace` para cards, ZIPs e builds.

## Identidade oficial

- versão: `2.0.108+200122`;
- package Dart: `github_manager`;
- applicationId/namespace: `br.com.githubmanager.app`;
- assinatura oficial própria e permanente;
- APK Release universal com `armeabi-v7a` e `arm64-v8a`.


## Inicialização sem travar na splash 2.0.54

A 2.0.54 remove inicializações bloqueantes antes de `runApp()`. O Flutter agora desenha o primeiro frame imediatamente; leitura do tema, WorkManager e notificações são inicializados depois do primeiro frame, com timeout e isolamento de falhas. Assim, indisponibilidade ou lentidão de plugins nativos não mantém o aplicativo preso no logo.

## Splash screen Android 2.0.53

A 2.0.53 corrige o corte do ícone na tela de abertura do Android 12+, usando um recurso de splash com área segura maior e fundo branco em qualquer tema. O launcher/adaptive icon permanece igual.


## Ícone Android e correção de build 2.0.52

A 2.0.52 corrige os foreground services de upload e download para usar um ícone monocromático próprio de notificação (`ic_stat_github_manager`), evitando a falha Kotlin causada pela antiga referência `R.drawable.ic_launcher` depois da migração do launcher para `mipmap`.


O aplicativo passa a usar o novo ícone roxo de repositório/sincronização como launcher oficial. Foram adicionados recursos `mipmap` para todas as densidades Android e Adaptive Icon para Android 8 ou superior.

A versão também corrige o `pubspec.lock` da 2.0.50: quatro dependências fornecidas pelo Flutter SDK estavam com o campo `description` incorreto, fazendo `flutter pub get --enforce-lockfile` abortar com exit code 65 tanto na CI quanto no workflow de APK. O monitor local de notificações de build também deixa de bloquear o envio quando falha, corrigindo a causa dos testes antigos do `UploadManagerService`.

## Correção da conexão GitHub 2.0.50

O assistente de configuração agora diferencia corretamente ausência de autenticação de um token rejeitado pelo GitHub. Respostas `401` do endpoint `/user` deixam de exibir a mensagem enganosa “Conecte sua conta GitHub para continuar” e passam a explicar que o Personal Access Token pode estar expirado, revogado ou copiado incorretamente.

A entrada do PAT também é normalizada antes do teste e antes de ser gravada: espaços/quebras de linha acidentais, caracteres invisíveis, aspas/backticks e prefixos copiados como `Bearer` ou `Authorization: Bearer` são removidos. O botão Colar usa a mesma normalização, e o teclado pode concluir diretamente com “Testar e conectar”.

## Consolidação de segurança e sincronização 2.0.49

A listagem de repositórios continua abrindo pelo cache local para manter a inicialização rápida, mas agora reconcilia os dados com a API ao entrar na tela e ao retornar ao aplicativo. Repositórios removidos diretamente no site do GitHub deixam de permanecer como itens fantasmas no cache.

Downloads redirecionados deixaram de propagar URLs temporárias assinadas para endpoints diagnósticos e mensagens persistidas. Os serviços Android de upload/download tratam o timeout de `dataSync` do Android 15+, preservando os checkpoints existentes para retomada posterior.

As dependências usadas pela aplicação foram fixadas na resolução utilizada pelo Flutter 3.47.1 e o `pubspec.lock` passou a fazer parte do projeto. No envio de ZIP, arquivos maiores passam por arquivo temporário e base64 em fluxo, evitando manter simultaneamente o binário descompactado e sua representação base64 completa na memória.


## APKs compactos e envio flexível 2.0.31

A tela de APKs e Artifacts foi compactada: ações `Baixar`, `Publicar` e `Excluir` ficam lado a lado, com botões menores, enquanto o card mostra formato, versão detectada, data, tamanho, workflow run e classificação provável de build (`Debug`, `Profile`, `Release`, `AAB / Play`, `Estável provável`, `Prévia`). A estabilidade é tratada como inferência quando o GitHub não fornece o buildType diretamente.

A proteção de envio deixou de usar nome e versão como bloqueios rígidos. Regressão de versão é permitida com aviso; renomear projeto/repositório gera apenas alerta. Divergência isolada de `applicationId` ou pacote também pode ser confirmada. Somente a divergência simultânea de dois identificadores fortes entra em modo de risco alto, ainda com uma segunda confirmação explícita para `Forçar envio`.

## Interface e proteção de identidade 2.0.30

A versão 2.0.30 aproxima a interface do novo padrão visual do GitHub Manager: fundo azul-preto, superfícies em camadas, bordas discretas, cartões de repositório maiores e mais informativos, chips compactos, ações primária/secundária e navegação inferior flutuante. O tema compartilhado propaga a mesma linguagem para telas de builds, downloads, Secrets, configurações e diálogos sem criar uma segunda arquitetura visual.

A proteção de envio também corrige falso bloqueio quando o nome visível usa acentos ou separadores diferentes do nome do repositório, como `Tática Manager` e `TaticaManager`. A comparação agora dobra diacríticos antes da normalização e, em projetos Android/Flutter, tenta ler `applicationId` diretamente de `android/app/build.gradle(.kts)` quando os metadados de raiz não o informam. `applicationId` incompatível continua bloqueando o envio.

## Hotfix de compilação e CI 2.0.29

A versão 2.0.29 corrige a incompatibilidade introduzida no importador de Secrets com `file_picker 12`: `PlatformFile.size` não existe mais nessa API e foi substituído por `await PlatformFile.length()`. O limite preventivo de tamanho do arquivo continua sendo validado antes da leitura completa.

A CI também deixou de bloquear todo o pipeline por dívida de formatação preexistente. O runner normaliza `lib` e `test`, emite um warning quando houver diferenças e então executa `flutter analyze` e `flutter test`. Erros reais de análise ou testes continuam reprovando a CI.

## Proteção preventiva de permissões 2.0.28

Ações críticas agora consultam um diagnóstico antes de chamar a API. **Enviar nova versão** exige permissão de Contents para sincronizar arquivos; operações explicitamente ligadas ao GitHub Actions continuam validando Actions, operações de Secrets verificam `Secrets: write` e a exclusão permanente verifica a capacidade de exclusão. Quando uma negação já foi confirmada, a ação é interrompida antes de selecionar/enviar dados e o app mostra exatamente a permissão necessária, com acesso direto ao diagnóstico do token.

O cache dura poucos minutos e usa uma impressão SHA-256 do token apenas em memória como parte da chave. Se o token for trocado, o diagnóstico antigo não é reutilizado. Resultados inconclusivos de PAT fine-grained não bloqueiam a operação: como o GitHub não oferece introspecção segura de todas as permissões de escrita, a chamada real continua sendo a autoridade final. Rate limit ou indisponibilidade temporária do diagnóstico também não são tratados como permissão ausente.

## Diagnóstico de permissões 2.0.27

Cada repositório próprio possui `Diagnóstico do token`. A verificação é não destrutiva: usa somente consultas de leitura para testar acesso a Contents, Actions, Secrets e Administration, lê `X-Accepted-GitHub-Permissions` quando o GitHub o retorna e identifica os escopos expostos por PAT clássico.

O relatório separa `Confirmada`, `Disponível` por inferência, `Sem acesso` e `Verifique no token`. Em PAT fine-grained, permissões de escrita não são testadas por mutações, para que o diagnóstico nunca altere arquivos, Secrets, workflows ou configurações. O app mostra a permissão necessária para cada função, incluindo `Contents: write + Workflows: write` para sincronização completa por ZIP, `Actions: write`, `Secrets: write` e `Administration: write` para administração/exclusão. Para PAT clássico, o diagnóstico considera `repo`, `workflow` e `delete_repo` junto com o papel da conta no repositório.

O diagnóstico pode ser copiado sem incluir o token.

## GitHub Secrets 2.0.26

O módulo de Secrets aceita PAT fine-grained (`github_pat_...`) e token clássico (`ghp_...`). Para Secrets, o fine-grained deve ter `Secrets: Read and write`; no token clássico, use o escopo `repo`. Antes de gravar, o aplicativo valida nomes, duplicidades, limite de 48 KB por valor e o limite final de 100 Secrets por repositório.

Importações TXT/ENV aceitam `NOME=valor`, `NOME: valor` e `export NOME=valor`; JSON e XML continuam suportados. O lote é pré-visualizado como `Criar` ou `Substituir` e o resultado é individual por Secret, permitindo sucesso parcial. O diagnóstico copiável registra nome, HTTP, endpoint, código e mensagem da API quando disponíveis, mas nunca inclui o valor do Secret.

A criptografia continua local com sealed box/Libsodium antes do `PUT` na API do GitHub. Arquivos de importação recebem limite preventivo de tamanho para evitar consumo excessivo de memória.

## Repositório oficial

O desenvolvimento oficial usa `adriedsonlemoz/GitHub-Manager`. Validações de Actions e builds devem sempre ser feitas neste repositório; o repositório anterior não é fonte de validação da versão atual.

## Repositórios acompanhados

A lista usa cache local e atualização paralela para abrir rapidamente. Cada acompanhado possui ação `Fork`, que cria uma cópia na conta conectada, e o diálogo de inclusão possui botão para colar a URL.

A área Projetos possui um seletor interno entre `Meus projetos` e `Acompanhados`. Repositórios públicos de outros desenvolvedores podem ser adicionados por URL ou `owner/repo`, sem criar outra sessão. Ao colar somente uma URL de perfil, como `github.com/usuario`, o app consulta os repositórios públicos daquela conta e permite escolher qual acompanhar. Eles são mantidos localmente como referências e abertos em modo somente leitura, com download do projeto e acesso a Releases/APKs quando disponíveis.

## Notificações de Builds

O GitHub Manager pode acompanhar execuções em segundo plano e avisar quando uma build termina com sucesso, falha, é cancelada ou excede o tempo. O monitor é ativado por padrão após a permissão do Android e pode ser desligado em Configurações.

Para economizar bateria e respeitar as regras do Android, a verificação periódica é feita em intervalos aproximados de 15 minutos e o próprio sistema pode atrasar uma execução em situações de economia de energia.

## GitHub Actions e Builds

A tela Builds usa `GET /repos/{owner}/{repo}/actions/runs` como fonte principal das execuções recentes. Cada run preserva `workflow_id` e `path`; ao abrir um workflow específico, o filtro é feito localmente. Se o resultado filtrado for vazio, o app consulta também o endpoint específico por workflow ID/arquivo e exibe diagnóstico em vez de transformar automaticamente a resposta em “nenhuma execução”.

A tela agrupa execuções pelo mesmo commit/envio. Cada grupo mostra data e hora com segundos, SHA curto e origem (`push`, manual ou ambos); dentro dele ficam os workflows relacionados, com número, tentativa, branch, status e duração. Runs em andamento são atualizados automaticamente. Jobs e steps exibem explicações simples e, em falhas, o app tenta recuperar a annotation principal do check run para destacar job, etapa e mensagem.

O fluxo **Enviar nova versão** da tela do projeto primeiro permite escolher a branch, compara os metadados contra essa mesma branch, sincroniza o ZIP e, quando existe um workflow de APK compatível, verifica as execuções pelo SHA do novo commit. Se o `push` já iniciou o workflow Android APK, nenhuma execução duplicada é criada. Se não iniciou, o app aguarda a indexação e usa `workflow_dispatch`; em repositório recém-criado, também inspeciona estruturalmente os YAMLs em `.github/workflows` quando a listagem de workflows ainda estiver vazia. Se um workflow de APK por `push` existe mas o Actions demora a indexar a execução, o app espera uma janela adicional antes de marcar a build como pendente. Se não existir workflow de APK na branch escolhida, o envio termina normalmente como **Projeto atualizado • Sem workflow de build**. Falha real em um workflow existente não desfaz o commit nem transforma o envio já concluído em falha.


## Central de Envios

O fluxo **Enviar nova versão** não depende de um diálogo bloqueando a tela. Cada sincronização entra em uma fila global do aplicativo, pode ser minimizada e continua visível em qualquer tela por um indicador flutuante. A Central de Envios mantém histórico, progresso, etapa atual, arquivo processado, commit, workflow, falhas e logs copiáveis.

Para reduzir chamadas desnecessárias, o envio calcula o SHA Git dos arquivos do ZIP e reutiliza blobs já idênticos na árvore atual. Envios concorrentes são serializados e uma tentativa duplicada do mesmo ZIP/repositório é ignorada enquanto a anterior estiver ativa.

Durante a sincronização, o Android mantém um serviço em primeiro plano com notificação de progresso. Se a interface for removida dos recentes, o envio continua enquanto o processo estiver vivo. Se o processo for realmente encerrado, a fila é restaurada automaticamente ao abrir o app: o GitHub Manager usa a cópia privada do ZIP e reaproveita blobs/commit já salvos no checkpoint. Se o ZIP não tiver alterações, a Central mantém a opção `Executar build` usando o commit atual, sem reenviar o projeto.

A versão 2.0.25 remove o banner vermelho global. O destaque vermelho com texto branco aparece somente na confirmação de envio do ZIP, identificando claramente a versão do GitHub Manager instalada antes da sincronização. A Home permite editar o perfil GitHub tocando no avatar, e o menu de gerenciamento do repositório usa uma engrenagem com diálogo centralizado.


## Central de Downloads

Todos os downloads GitHub usam o mesmo gerenciador interno:

- APKs e artifacts;
- ZIP do projeto;
- logs do GitHub Actions;
- arquivos GitHub integrados futuramente pelo mesmo serviço.

A Central separa `Baixando`, `Concluídos` e `Falharam`, mostrando progresso, bytes, tamanho total, velocidade, estimativa restante e status. Durante downloads ativos, um serviço Android em primeiro plano mantém o processo com notificação de progresso ao minimizar ou remover a interface dos recentes. Downloads interrompidos preservam o arquivo parcial e, quando o servidor aceita `Range`, retomam a partir dos bytes já recebidos em vez de reiniciar do zero.

Arquivos concluídos são publicados diretamente na pasta pública `Downloads` do Android, sem pedir uma pasta a cada operação. O histórico pode ser removido sem apagar o arquivo; a exclusão do arquivo é uma ação separada. Arquivos concluídos podem ser abertos ou compartilhados. APKs oferecem `Instalar`, que apenas abre o instalador oficial do Android.

Falhas mantêm log sanitizado com data/hora, endpoint da API, HTTP, etapa, bytes, tamanho esperado, mensagem do GitHub e código interno. Token, Secrets, API Keys, senhas, `Authorization` e URLs temporárias assinadas não são registrados.

## Artifacts

Artifacts expirados continuam visíveis no histórico e são marcados como expirados, em vez de simplesmente desaparecer. Artifacts ativos com APK são extraídos e publicados como APK; outros artifacts são baixados como ZIP.

## Sincronização por ZIP

O envio de ZIP sincroniza completamente os arquivos do projeto. A implementação compara a árvore atual do repositório com os caminhos presentes no ZIP e cria remoções Git (`sha: null`) para arquivos antigos que não existem mais no pacote antes de criar o novo commit. A exceção de segurança é `.github/workflows/**`: workflows já existentes são preservados quando o ZIP apenas os omite, evitando que uma atualização do código desative a própria build. Se o ZIP trouxer o mesmo caminho de workflow, ele pode ser atualizado normalmente.

Se a árvore resultante for idêntica à árvore atual, o app não cria commit nem dispara build automaticamente. A tela informa que o projeto já está atualizado e oferece `Executar build mesmo assim` para uma recompilação manual do mesmo commit.

## Assinatura

Os workflows `Android APK` e `Android Release` usam os mesmos Secrets oficiais:

- `KEYSTORE_BASE64`
- `KEYSTORE_PASSWORD`
- `KEY_ALIAS`
- `KEY_PASSWORD`

A chave oficial desta geração usa o alias `github_manager_release`. O certificado público esperado fica em `android/release-signing.properties`. Keystore, arquivo de Secrets, `.env` e `key.properties` não fazem parte do ZIP do projeto.


## Sobre e suporte

A área Sobre mantém as três mudanças mais recentes recolhidas em um painel expansível, identifica o desenvolvedor como `@AdriedsonLemos`, oferece chave Pix e canal de feedback copiáveis e informa que o GitHub Manager é um projeto independente, sem parceria, afiliação, endosso ou patrocínio do GitHub. A integração Groq permanece opcional e reservada para futuros recursos de IA, como resumo de logs e explicação de erros; ela não é necessária para as funções GitHub atuais.


## Persistência SQLite 2.0.71

O banco local agora possui um único proprietário por isolate (`LocalDatabase.shared`). A UI inteira reutiliza a mesma conexão, e operações auxiliares como monitoramento de builds, preferências de recuperação e limpeza inicial deixaram de abrir e fechar conexões temporárias. A abertura concorrente é deduplicada e o WorkManager mantém sua própria conexão somente porque executa em outro isolate. Isso substitui o workaround de múltiplas conexões independentes da 2.0.67 sem alterar o esquema ou apagar dados.

## Arquitetura de ManagedUpload 2.0.72

`ManagedUpload` continua sendo o contrato consumido pela Central de Envios e pelo `UploadManagerService`, mas suas responsabilidades internas foram separadas. O arquivo principal mantém os dados persistidos e a API pública; estado derivado, diagnóstico de falhas, mutações de ciclo de vida, relatório técnico e codec JSON ficam em partes internas específicas. A estrutura JSON permanece compatível com checkpoints das versões anteriores.

Ao alterar o fluxo de upload, evitar recolocar regras extensas diretamente em `managed_upload.dart`: mudanças de diagnóstico pertencem a `managed_upload_failure.dart`, mudanças de retry/progresso a `managed_upload_lifecycle.dart`, textos/estado derivado a `managed_upload_state.dart`, relatório a `managed_upload_report.dart` e persistência a `managed_upload_codec.dart`.


## Correção 2.0.73

Os workflows 63 revelaram dois erros de análise no teste de limpeza de build: uma variável local `final` era usada dentro de listas `const`. A variável agora é `const`, permitindo que CI/testes avancem sem alterar a lógica de limpeza de builds/APKs/artifacts.
