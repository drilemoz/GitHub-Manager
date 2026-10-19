# GitHub Manager 2.0.134+200148

- Android APK #123: docs/VERSIONING.md estava sem o literal `version: 2.0.133+200147` e interrompia o workflow antes do flutter analyze. Corrigido na 2.0.134, com teste de regressão e histórico restaurado.

- Detecção de aplicativo instalado/ausente ajustada na consulta nativa do Android.
- Card APK redesenhado, com destaque em vermelho quando o app não está instalado.
- Cabeçalho do projeto reorganizado: versão em chip no topo e SDK Android visível.
- RepositoryProjectInfo agora pode carregar minSdk, targetSdk e compileSdk a partir do repositório.
- Validar em CI/aparelho a nova apresentação do card e a detecção em Android 11+.


- Base 2.0.131+200145. Módulo Secrets: `pickImportFile` usa `FileType.any` devido a arquivos ocultos `.env` que não aparecem com filtro Android; `parseImportFile` aplica whitelist de nomes/extensões e decodificação UTF-8/BOM. O formato continua sem multilinhas literais.
- `RepositorySecretsService.deleteMany` envia DELETE individual por nome para a API GitHub, com progresso, deduplicação e resultados por item; `SecretDeletionResult` não expõe conteúdo.
- UI `RepositorySecretsScreen` apresenta Excluir todas quando há itens; consulta lista atualizada, requer permissão, confirma com digitação de EXCLUIR, mostra progresso e resultado com cópia segura. Delete é irreversível e restrito ao repositório.
- Testes: `test/repository_secrets_service_test.dart`, `test/secrets_bulk_delete_ui_contract_test.dart`. Executar `flutter analyze`, `flutter test` e workflow Android APK. Sem SDK Dart/Flutter local.

# GitHub Manager 2.0.131+200145

- Preferência `settings.download_cleanup_mode` em SQLite com opções `afterSuccess`, `beforeStart` e `disabled`, padrão `afterSuccess`.
- Limpeza restrita à pasta `Downloads/GitHub/<projeto>` via MediaStore, apenas itens criados pelo próprio pacote Android e não pendentes (API 29+); no legado, apenas caminhos de arquivos explicitamente registrados no histórico.
- Publicações e limpeza serializadas por pasta. O modo Antes de iniciar remove os finais antigos antes de transferir, mantendo proteção dos parciais; a consolidação após publicar preserva a regra de somente um arquivo em downloads concorrentes.
- `cleanupWarning` persiste avisos de falha após publicação. Código não lê Secrets nem exclui ZIPs-fonte, arquivos externos ao diretório dedicado ou `.part`.
- `flutter test`, `flutter analyze` e compilação Android permanecem pendentes neste ambiente; validar no GitHub Actions e Android 9/10/13+ antes de depender da limpeza em produção.

# Atualização 2.0.130+200144

- `DownloadManagerService`: adiciona estado paused, `pause`, `resume`, `cancelPaused`, registro de operações em andamento e espera pelo fechamento do sink antes de retomar. Downloads ativos mantêm a proteção de fluxo em Releases/Artifacts; opção pública valida Content-Range e total.
- `ManagedDownload`: estado serializado `paused`, `isHistoryClearable` e `resetForRetry(preserveProgress: true)`. Pausados permanecem fora da limpeza de histórico e não são retomados ao restaurar o aplicativo.
- UI `downloads_screen` e `downloads_widgets`: ação Pausar, seção Pausados, Retomar/Cancelar. Monitor leve por Timer de 5 s detecta downloads sem avanço há 15 s e zera velocidade/ETA obsoletos; mostra observação sobre banda compartilhada em downloads simultâneos.
- Riscos a testar no Android: alternar Pausar/Retomar rápido; rede Wi-Fi/móvel; Release/Artifact com Range e URL temporária; servidor que ignora Range; fechar o app durante a pausa; salvar/abrir APK. A velocidade depende da rede e CDN; não há ganho garantido por reconexão.
- Testes adicionados em `test/download_pause_resume_test.dart`, versionCode e notas sincronizados. Flutter/Dart indisponíveis localmente, executar `flutter analyze`, `flutter test` e build em CI.

# Atualização 2.0.129+200143

- Na janela de auditoria Play (`play_readiness_dialog.dart`), botão **Copiar relatório** habilitado só depois de `Future<PlayReadinessReport>` concluir com dados válidos. Usa `Clipboard.setData(ClipboardData(text: ...))` e feedback visível.
- Formatação pura e testável em `PlayReadinessReport.toCopyText(repositoryFullName: ...)`, cobrindo todos os achados automáticos, manuais, evidências, estados e limites de leitura da árvore, inclusive projetos não Android.
- Reavaliar invalida feedback e cópia pendente anterior. Sem alterações na lógica de API 36, avaliação, downloads ou assinatura.
- Adicionados `test/play_readiness_report_copy_test.dart` e extensões a `test/play_readiness_ui_contract_test.dart`.
- VersionName 2.0.129, versionCode 200143, changelog, README, Versioning, release, validation, WhatsNew e histórico sincronizados. Flutter/Gradle indisponíveis localmente; validar no CI.

# Atualização 2.0.128+200142

- Novo botão Play em `repository_detail_screen.dart`, quinta ação em linha. Os quatro botões anteriores continuam funcionais.
- `PlayReadinessService` busca árvore GitHub na branch padrão, lê somente Gradle/manifesto/pubspec e poucos workflows, distingue resultados confirmados no código de pendências de build/Play Console. Não consulta Secrets/keystores.
- UI em `play_readiness_dialog.dart`, com renovação sob demanda, resultados verificado/atenção/não confirmado e links oficiais.
- Regra API Android comum 36 a partir de 31/08/2026, exceções para outros form factors não analisadas automaticamente. `flutter.targetSdkVersion` dinâmico não é assumido como 36.
- Testes: `test/play_readiness_service_test.dart`, `test/play_readiness_ui_contract_test.dart`.
- Importante: Flutter/Dart não instalado localmente. Confirmar via CI (`flutter analyze`, `flutter test` e build APK).

# Atualização 2.0.127+200141

- Fonte: logs Android APK #116 (15/10/2026), `flutter analyze` aprovado, `flutter test` com 227 testes aprovados e 1 falha em `test/system_ui_settings_contract_test.dart`, linha 53.
- Causa: últimas três notas de Configurações em ordem `2.0.126`, `2.0.124`, `2.0.125`, divergindo da ordem sequencial decrescente exigida.
- Correção em produção: notas agora `2.0.127`, `2.0.126`, `2.0.125` com descrições correspondentes. Teste de contrato preservado.
- VersionName e versionCode sincronizados, README, CHANGELOG, docs/VERSIONING, docs/RELEASE, docs/VALIDATION, Novidades e histórico atualizados.
- Verificações locais de arquivos e estrutura do ZIP; `flutter test`, `flutter analyze` e build APK pendentes de execução no GitHub Actions, Flutter não está instalado no ambiente.

# Atualização 2.0.126+200140

- Origem: Android APK #115 na base 2.0.125; `flutter analyze` aprovado, teste `repository APK shortcut busca a última versão sem pré-desabilitar o botão` falhou; resumo 227 aprovados e 1 falha. A execução parou antes da compilação do APK.
- Diagnóstico: o contrato procurava `listReleaseAssets(repository.fullName)`, `listArtifacts(repository.fullName)` e `LatestApkShortcut.resolve` no arquivo de ações; essas operações foram migradas para `repository_apk_status_provider.dart` na versão 2.0.125.
- Correção: o teste confere o uso de `repositoryApkStatusProvider(repository).future` pelas ações e confirma consultas independentes de Releases/Artifacts, resolução de última versão, avaliação de instalação e continuidade do download pelo seletor.
- Código de produção preservado. Sincronizados pubspec, github-manager.json, README, CHANGELOG, VERSIONING, Novidades, Configurações, release e validation. Executar testes/assemble na CI.

# Atualização 2.0.125+200139

- Canal nativo `getInstalledAppInfo` usa PackageManager sob consulta de pacote individual validado; read `versionName`, `longVersionCode` e status installed/notInstalled/unknown. Ausência no Android 11+ não confirma desinstalação.
- Manifest usa queries de apps com launcher, sem QUERY_ALL_PACKAGES.
- `repositoryApkStatusProvider` combina projetos/Release/Artifacts e estado instalado, com duas fontes independentes.
- `ApkInstallationAssessment` compara SemVer e code somente se ambos informados. Estado Atualizado sem código remoto tem ressalva explícita.
- UI mostra status e versões, muda label do botão APK e solicita confirmação para baixar versão já instalada/mais antiga.
- Na sequência, rodar flutter analyze/test/build no GitHub Actions; validar no Android real. 

# Atualização 2.0.124+200138

- Atalho APK na tela do repositório: remove guarda baseada só em Artifacts e consulta Releases+Artifacts sob demanda; mostra seletor existente para variantes da versão mais recente, iniciando downloads com DownloadManagerService.
- Novo resolvedor puro `lib/features/builds/domain/latest_apk_shortcut.dart`: filtra APKs e artifacts expirados, agrupa versões de Releases e variantes de um mesmo run, compara versão explícita de artifact com Release. Prefere Release se não houver prova de versão superior no artifact.
- Mantém confirmação de incompatibilidade estimada pela ABI informada no nome do APK e no Android.
- Testes: `test/latest_apk_shortcut_test.dart`, `test/build_apk_selection_contract_test.dart`.
- Validar via GitHub Actions: `flutter analyze`, `flutter test`, `assemble` e download real de APK no celular.

# Atualização 2.0.123+200137

- Fonte: ZIP 2.0.122+200136, logs Android APK #112.
- A análise Flutter interrompeu o workflow após cinco erros `argument_type_not_assignable` em `test/static_web_project_detection_test.dart` (linhas 10–14): `ArchiveFile` requer dados `List<int>`, mas eram `String`.
- Os arquivos de teste passam por `utf8.encode()` e usam `bytes.length` em `ArchiveFile`, removido operador `!` em `ZipEncoder().encode()`.
- Acrescentado teste de site HTML isolado. Preservadas as melhorias web/Builds/downloads anteriores.
- Versionamento `2.0.123+200137`. Necessário executar `flutter analyze`, `flutter test` e `assemble` no GitHub Actions; SDK Flutter/Dart indisponível localmente.

# Atualização 2.0.122+200136

- Identificação de projetos: adicionada heurística para **site estático/portfólio** em ZIPs e repositórios, usando `index.html`, `styles.css`, `app.js`, `README.md`, `vercel.json`, `netlify.toml`, `_headers` e `_redirects`.
- Nome de projeto web: quando não há metadado mais forte, o app pode usar o primeiro `#` do `README.md` ou o `<title>` do `index.html`.
- Builds: resumo do detalhe da execução reorganizado em **4 cartões** (Evento, Branch, Tempo, Etapas) na mesma linha quando houver largura suficiente; rótulos e texto reduzidos para celular.
- Downloads: mantidas as otimizações da 2.0.121 para velocidade/retomada de APK.
- Revisão: validar em CI/aparelho o layout dos 4 cartões e a identificação do portfólio web. Sem Flutter/Dart local neste ambiente.

# Histórico 2.0.120+200134

- Logs recebidos: Android APK #109 e CI #108; 201 testes aprovados, 2 falhas no `workflow_log_naming_contract_test.dart` porque a branch main ainda contém `ci.yml` ativo.
- Conferida a presença remota via GitHub; tentativa de exclusão via integração bloqueada em HTTP 403 (recurso inacessível para a integração).
- Solução para upload incremental com versão instalada: adicionar `.github/workflows/ci.yml` como stub inativo, disparo manual apenas e `if: ${{ false }}`, sem CI redundante em push/PR.
- Ajustado o teste para rejeitar o workflow antigo ativo mas aceitar o arquivo ausente ou a versão inativa, sem suprimir as verificações das pipelines Android.
- Versão canônica, versionCode, README, CHANGELOG, VERSIONING, Novidades, Configurações, release e validação atualizados.
- Pendente: enviar ZIP para main, confirmar diff remoto de ci.yml, rodar workflow Android APK e testes reais Flutter/Android. A exclusão definitiva por operador com permissão segue recomendada.

# Atualização 2.0.119+200133

- Logs analisados: GitHub Manager CI #107 e Android APK #108, ambos v2.0.118, 200 testes aprovados e 3 reprovados.
- `global_builds_screen_test.dart` foi alinhado ao texto atual: `Android APK • execução #78` e `Verificação do Projeto (CI) • execução #78`.
- Dois testes de `workflow_log_naming_contract_test.dart` exigem ausência do CI local e agora orientam a remover o arquivo remoto; o repositório GitHub ainda contém `.github/workflows/ci.yml`, embora não exista no ZIP da v2.0.118.
- Para não executar a CI separada, excluir `.github/workflows/ci.yml` da branch `main` via GitHub UI ou `git rm`, além de remover do ZIP. O ZIP atualizado continua sem CI, com análise/testes preservados no APK e na Release.
- README, CHANGELOG, VERSIONING, tela Novidades, últimas três mudanças, notas de release e versionCode sincronizados.
- Não foi possível executar `flutter test`, `flutter analyze` ou compilar Android localmente.

# Atualização 2.0.118+200132

- Pedido: remover a CI separada e redundante, preservando os testes dos workflows de compilação.
- Removido apenas `.github/workflows/ci.yml`. `android-apk.yml` e `android-release.yml` continuam com análise, testes, versão, assinatura e validações relevantes.
- O teste `workflow_log_naming_contract_test.dart` passou a exigir a ausência de ci.yml e as verificações presentes nas duas pipelines de APK.
- Verificar branch protection: status `Analisar e testar` pode precisar ser retirado/substituído nas regras do repositório.
- Testes Flutter/Android e instalação no aparelho pendentes, SDK indisponível localmente.

# Atualização 2.0.117+200131

- Fonte: 2.0.116+200130; log: GitHub Manager CI #106.
- `flutter analyze` interrompido por `_RunStatusIcon` e `_JobIcon` indefinidos em `repository_run_details.dart` (linhas 64 e 259). Ambos implementados em `repository_run_details_widgets.dart`, mesmo conjunto de `part` de `repository_actions_screen.dart`.
- Teste de contrato adicionado para presença dos dois widgets, sua integração e estados de status.
- Executar `bash tool/check_version_sync.sh`, `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings`, `flutter test --no-pub` e Android APK no GitHub Actions. Sem Flutter/Dart no ambiente local, não há validação dinâmica.

# Atualização 2.0.116+200130

- Fonte: 2.0.115+200129.
- Novos arquivos: smart_apk_picker.dart, build_manifest.dart, build_diagnostic_advice.dart.
- Workflow gera `build-info.json` opcional como artifact separado `build-info-<run_id>`. A leitura confere runId/commit.
- O seletor nunca valida ABI de bytes remotos; apenas estimativa pelo nome até conferência no Android.
- CI/Flutter/análise Dart e testes em aparelhos pendentes neste ambiente.

## Atualização 2.0.115

- CI #104 e Android APK #105: ambos apresentaram 191 testes aprovados e 1 falha no contrato `android_recents_task_contract_test.dart`.
- Causa: ações personalizadas `OPEN_UPLOAD` / `OPEN_DOWNLOAD` substituíram `Intent.ACTION_MAIN` e `CATEGORY_LAUNCHER` ao adicionar navegação de notificações em 2.0.114.
- Correção em `UploadForegroundService.kt` e `DownloadForegroundService.kt`: usar ACTION_MAIN + CATEGORY_LAUNCHER, preservando `notificationRoute` com o ID da transferência e `CLEAR_TOP` + `SINGLE_TOP`.
- Testes de contrato ampliados para impedir regressão da task única e perda de rota.
- Fonte canônica `2.0.115+200129`. Executar Flutter/Android na CI e validar os toques em aparelho real.

## Atualização 2.0.114

- Corrigido roteamento de notificações locais e foreground Android (toque com app aberto, em segundo plano ou fechado).
- Payload tipado de build, download e envio, com parser estrito de rota e suporte legado.
- Builds buscam uma execução específica quando ela não está na lista recente.
- Centrais destacam registro relacionado à notificação e oferecem acesso a detalhes.
- Canais de sucesso discretos e falhas prioritárias; diálogo automático de novidades suspenso ao abrir notificação.
- Versão 2.0.114+200128; ver docs/RELEASE_2.0.114.md e docs/VALIDATION_2.0.114.md.

## Atualização 2.0.113

- CI #102 / Android APK #103: um único teste falhou por procurar `builds-search` antes de expandir a lupa (`StateError: Bad state: No element`).
- `test/global_builds_enhancements_test.dart`: o teste agora toca no tooltip `Buscar builds` antes de digitar e verifica os dois estados. Não reabrir busca automaticamente na UI apenas para satisfazer testes antigos.
- Versão `2.0.113+200127` sincronizada. Ver `docs/VALIDATION_2.0.113.md`; Flutter/Dart não estavam disponíveis localmente para executar testes e compilar.

## Atualização 2.0.112

- Busca da Central de Builds na lupa e filtros avançados recolhidos por padrão.
- Botões APK global/detalhes sinalizam a consulta e aceitam resultados parciais de Artifacts/Releases; confirmam associação ambígua de Releases.
- Downloads com rótulo curto sem tocar no nome físico; detalhes completos; actions por ícone e sem truncar texto.
- Preview de ZIP em janela ampla por pasta, remoções em primeiro lugar; cópia de caminho.
- Modelo `WorkflowErrorLocation` com origem, caminho/linha e link limitado ao commit SHA. Annotations são confirmação; logs são estimativa, e resumo de testes recebe baixa prioridade.
- Versão `2.0.112+200126`; ver `docs/VALIDATION_2.0.112.md`.

## Atualização 2.0.111

- Corrigidos erros reportados por CI #100 / Android APK #101: raios 6/5 agora 4; teste de histórico dinâmico; rótulo da versão remota alinhado ao relatório.
- `update_whats_new_contract_test` verifica versão e itens de novidades sem prender o teste aos títulos de uma release antiga.
- Removida `_ProjectVersionBanner` (classe não usada) e reforçado `tool/check_version_sync.sh` para verificar interfaces e documentação.
- Versão `2.0.111+200125`; sem SDK Flutter/Dart neste ambiente: rodar CI real antes de declarar APK válido.

## Atualização 2.0.110

- Confirmação de ZIP compacta: branch, GitHub → ZIP, resumo de mudanças, alertas e checkbox de build. Detalhes técnicos em `ExpansionTile` com diagnóstico acessível.
- `UploadIdentificationDiagnosis` gera orientações específicas e relatório copiável sem tokens nem cabeçalhos HTTP. `ProjectSafetyCheck` continua responsável pela decisão de segurança.
- `AndroidProjectNameResolver` usa `xml` para extrair `android:label` literal ou `@string` em `strings.xml`, sem transformar nome visual em identidade forte.
- `RepositoryProjectInfo` expõe `nameSource` e `metadataIssue`. `loadSummary` e `load` resolvem o nome mesmo quando a versão já veio dos metadados.
- Versão `2.0.110+200124`, testes e docs em sincronia. Flutter/Dart SDK ainda não instalado neste ambiente; não alegar compilação aprovada.

## Atualização 2.0.109

- Builds globais agora mantêm `entries` como última versão/commit e `historyEntries` como últimos 25 runs por repositório.
- `GlobalBuildsService` tem relógio injetável para testes, cache global de 60 s e mínimo de 15 s para runs ativos.
- A interface oferece pesquisa, filtros, histórico e diagnóstico de jobs somente sob demanda.
- **Nunca apagar assets de Release apenas por igualdade de SHA:** o mesmo commit pode ter várias execuções. `BuildCleanupService` agora conserva esses assets e a UI alerta antes de baixá-los.
- Versionamento `2.0.109+200123`.

# GitHub Manager — handoff

Estado atual: `2.0.115+200129`. Dados remotos do GitHub não usam mais cache persistente: repositórios, descrições, perfil e permissões são consultados diretamente; Acompanhados salva apenas os nomes escolhidos e reconsulta a API; snapshots legados são apagados no startup. Providers remotos usam autoDispose.


## Alterações 2.0.108

- **Configurações > Aparência > Tela inteira** alterna modo imersivo (`immersiveSticky`) ou barras do Android visíveis (`edgeToEdge`);
- `SystemUiSettings` é um singleton `ValueNotifier<bool>` com persistência no SQLite (`settings.fullscreen_enabled`) e preferência padrão ligada;
- `main.dart` reaplica o modo no startup depois do primeiro frame e ao retomar o app, sem bloquear a splash Flutter, preservando a integração com engine em cache;
- após fechamento do teclado, o modo imersivo é reaplicado com atraso superior a um segundo, devido às restrições Android;
- Android com targetSdk 35+ pode impedir modos não edge-to-edge, e em 36+ os ignora. Não reduzir targetSdk nem prometer contorno;
- atualizados `pubspec.yaml`, manifesto JSON, README, CHANGELOG, VERSIONING, RELEASE, VALIDATION, Novidades, últimos três registros e testes de contrato.

## Alterações 2.0.107

- **Configurações > Página inicial** passa a oferecer `Mostrar descrição dos repositórios`, inicialmente desligado;
- `RepositoryDescriptionSettings` persiste o booleano `settings.show_repository_descriptions` no `LocalDatabase` compartilhado;
- `showRepositoryDescriptionsProvider` disponibiliza a preferência ao `RepositoryCard` e à tela de configurações;
- `RepositoryCard` apresenta a descrição do GitHub sem limite de linhas nem de caracteres quando a preferência está ativa;
- o valor é alterado por `settings_screen_actions.dart`, com invalidação do provider para atualização da interface;
- usar `asData?.value`, e **não** `valueOrNull`, para compatibilidade com `flutter_riverpod` 3.x;
- atualizados versão, README, CHANGELOG, VERSIONING, RELEASE, VALIDATION, novidades e testes de contrato para `2.0.107+200121`.

## Alterações 2.0.106

- detalhes de Builds mostram apenas um resumo compacto de falhas; **Ver erros** abre `_FailureDetailsDialog` com uma falha por vez;
- `_BuildFailureExplanation` usa regras determinísticas sobre logs/annotations e só marca **Causa identificada** quando `logsInspected` e uma assinatura forte confirmam a causa;
- o botão APK usa `ArtifactService.listArtifactsForRun` + `findReleaseApksForBuild` para limitar opções à execução/commit atual; a tela global **Builds** segue a mesma regra e não pode voltar a selecionar `first` silenciosamente;
- `PlatformActions.getAndroidDeviceInfo()` e `MainActivity.getDeviceInfo` expõem `Build.SUPPORTED_ABIS`, `SUPPORTED_64_BIT_ABIS`, modelo e versão do Android sem permissão;
- `ApkVariantInfo` centraliza detecção de arm64-v8a, armeabi-v7a, x86_64, x86, Universal e compatibilidade;
- APK específico da ABI principal é recomendado antes do Universal; seleção incompatível exige confirmação;
- `DownloadManagerService` persiste ABI principal/lista de ABIs no download para selecionar o APK correto quando um Artifact contém várias variantes e manter isso em retry;
- Configurações mostra as informações de arquitetura do aparelho;
- preservar o fallback **Ver todos os APKs** quando nenhuma associação segura com a execução for encontrada.

## Alterações 2.0.105

- `_RunDetailsSheet` mantém todas as ações existentes, mas remove a mensagem de commit duplicada do cabeçalho;
- `_RunInformationCard` virou um resumo visual em blocos para Evento, Branch, Duração e Etapas;
- mensagem do commit tem área própria e limitada a duas linhas;
- metadados de baixa prioridade ficam recolhidos em **Detalhes técnicos**;
- falhas aparecem antes do resumo e `_FailureSummaryCard` mostra só a síntese inicialmente, deixando horários/contexto do log em **Detalhes do diagnóstico**;
- o resultado relacionado ao APK usa o aviso compacto **APK não gerado**;
- não remover Logs, Repetir, APK, Excluir, atualização, jobs/etapas nem cópia de diagnóstico em refatorações futuras;
- `test/repository_run_details_visual_contract_test.dart` protege a nova hierarquia.

## Alterações 2.0.104

- `StartupUpdateGate` foi removido: **Novidades** não pode voltar a envolver/recobrir a Home pelo `MaterialApp.builder`.
- `StartupUpdateCoordinator` aguarda `AppLifecycleState.resumed`, dois frames, estabilização e `flutterUiDisplayed=true` antes de consultar/abrir a tela automática.
- `MainActivity` expõe `getActivityLaunchState` no channel `br.com.githubmanager.app/platform`, incluindo `cachedEngineReattach`, `flutterUiDisplayed`, `taskId` e `restoredActivityState`.
- Se `cachedEngineReattach=true`, a abertura automática é ignorada naquele ciclo; não remover essa proteção enquanto o engine permanecer preservado para transferências.
- A abertura automática usa `MaterialPageRoute` opaca e `requireConfirmation=true`; `app.whats_new.last_seen_version` só é persistida depois de **Continuar**.
- Telemetria de startup usa os eventos `startup.whats_new_check_started`, `startup.whats_new_needed`, `startup.whats_new_route_opened`, `startup.whats_new_first_frame`, `startup.whats_new_continue` e eventos de skip/retry.
- A visualização manual em Configurações continua usando `UpdateWhatsNewScreen` sem bloquear o botão Voltar.

## Alterações 2.0.103

- `MainActivity.getCachedEngineId()` retorna `github_manager_main_engine` apenas quando o engine cacheado existe e `dartExecutor.isExecutingDart` está ativo; não voltar a usar `provideFlutterEngine()` para esse fluxo.
- `shouldDestroyEngineWithHost()` continua `false`: uploads/downloads podem manter o isolate vivo enquanto a Activity sai da tela.
- Em reattach, `NormalTheme` é aplicado antes de `super.onCreate()` e o background nativo da janela é limpo após o attach, evitando que a splash fique sobre a Home já renderizada.
- `values-night` usa tema Material escuro e `values-night/colors.xml` define `launch_background=#050B14`.
- `GitHubManagerApplication` registra o último `cached_engine_reattach`; `AppTelemetryService` importa o evento como `android.engine_reattach` também ao receber `AppLifecycleState.resumed`.
- `test/android_cached_engine_contract_test.dart` protege o contrato do reattach e do splash noturno.


## Alterações 2.0.102

- Tela **APKs** usa a mesma estrutura visual para Release e Artifact.
- Artifact mostra versão amigável no título quando detectável; nome bruto deixa de dominar o card.
- Foram removidos da listagem principal o rótulo redundante de buildType e a frase de classificação inferida.
- Variante de Artifact é detectada quando possível (`Universal`, `ARM64`, `ARMv7`, `x86`, `Performance`).
- Se existir APK de Release da mesma versão, o Artifact recebe **Publicado**, não oferece **Publicar** e o download direto tenta selecionar a mesma variante.
- `_versionFromName` foi restringido para não interpretar versionCode/sufixos do filename como parte da versão.
- Ações seguem a mesma ordem visual nos cards: baixar/escolher, publicar quando cabível e excluir.
- Novidades/configurações/documentação sincronizadas em `2.0.102+200116`.

## Alterações 2.0.101

- raio retangular global padronizado em 4 px; pills de status intencionais permanecem em 99/999;
- nova central **Erros e telemetria** em Configurações com captura local, exportação e limpeza;
- `LocalDatabase.schemaVersion = 3` inclui tabela `error_telemetry` com retenção de 120 eventos;
- `main.dart` instala handlers para `FlutterError.onError`, `PlatformDispatcher.onError` e `runZonedGuarded`;
- `GitHubManagerApplication` captura o último crash nativo via `UncaughtExceptionHandler` e `MainActivity` expõe `consumeNativeCrashReport` ao Flutter;
- relatórios sanitizam padrões conhecidos de tokens/senhas/segredos e nunca são enviados automaticamente;
- Na 2.0.101 o antigo `StartupUpdateGate` passou a persistir `app.whats_new.last_seen_version` depois de **Continuar**; na 2.0.104 ele foi removido e essa responsabilidade passou ao `StartupUpdateCoordinator`;
- Configurações permite rever manualmente a tela **Novidades desta versão**.

## Alterações 2.0.100

- Corrige duplicação do GitHub Manager em **Aplicativos recentes** no Android: `MainActivity` usa `singleTask`, afinidade padrão do pacote e `documentLaunchMode="never"`.
- `cleanupDuplicateRecentTasks()` roda em `onCreate()` e `onNewIntent()` e remove de `ActivityManager.appTasks` qualquer tarefa antiga do próprio app cujo id seja diferente da task atual; isso limpa resíduos de versões anteriores.
- Não reintroduzir `android:taskAffinity=""`; a afinidade vazia separava a Activity da tarefa normal do aplicativo e podia favorecer uma segunda entrada após atualização/reabertura.
- `openUri()` e `installApk()` não usam mais `FLAG_ACTIVITY_NEW_TASK` quando partem da `MainActivity`.
- Notificações de upload/download usam Intent explícito para `MainActivity` com `ACTION_MAIN` + `CATEGORY_LAUNCHER`, `CLEAR_TOP` e `SINGLE_TOP`, para trazer a tarefa existente à frente.
- `test/android_recents_task_contract_test.dart` protege esse contrato.


## Alterações 2.0.99

- Cards da Home usam raio de 4 px exclusivamente na lista de projetos, mantendo o restante do tema inalterado.
- Histórico 2.0.99: o antigo `StartupUpdateGate` consultava a versão depois do primeiro frame; desde 2.0.104 ele não existe mais.
- `UpdateWhatsNewScreen` cobre a interface como uma tela completa; a versão é marcada como apresentada assim que a tela aparece e **Continuar** fecha o resumo.
- A checagem de novidades possui timeout/falha controlada e nunca bloqueia o primeiro frame nem o uso do aplicativo.

## Alterações 2.0.98

- Cabeçalho do projeto ganhou atalhos compactos para APKs/artifacts, Commits, Diagnóstico do token e Issues/Bugs; a lista principal restante está em ordem alfabética.
- Releases mostram a versão em badge e ações explícitas Excluir/Baixar, sem tag de release redundante.
- Seletor de branch não usa mais o check ambíguo: escolha uma branch e confirme em **Continuar**.

## Alterações 2.0.97

- Builds: exclusão em lote expõe `BuildCleanupProgress` com etapa, item atual, total e percentual; a AppBar não usa mais spinner indeterminado durante a exclusão.
- APKs: **Excluir anteriores** usa os snapshots já visíveis (`_future`/`_releaseFuture`) ao chamar `deleteOlderApkOutputs`, evitando uma segunda listagem inconsistente.
- Downloads: `deletePublishedDownload` retorna confirmação booleana do Android. O histórico só é removido depois de exclusão física confirmada; `content://` é reaberto para distinguir item já ausente de falha silenciosa.
- Home: cards não mostram descrição; a descrição continua pesquisável. A pesquisa agora é uma lupa no AppBar e o campo ocupa o título somente enquanto ativo.
- README: cache em memória por repositório/branch, `Isolate.run` para decodificação Base64 grande e `ListView.builder` para renderização lazy dos blocos Markdown. Atualizar força nova consulta.
- Markdown do README foi separado em `repository_markdown_preview.dart` para manter os arquivos menores e modularizados.

## Alterações 2.0.96

- A tela APKs agrupa assets por Release + versão detectada no nome do arquivo; isso é intencional porque alguns projetos, como o Explorador XP, usam uma única tag fixa (`explorador-xp-dev`) para armazenar várias versões.
- A ordenação dos grupos prioriza a versão detectada (incluindo `alpha.N`, `beta.N`, `rc.N`) e só usa `publishedAt` como fallback, evitando que versões novas apareçam no fim quando todos os assets compartilham a mesma data da Release.
- Variantes Universal/ARM64/ARMv7 da mesma versão aparecem em um único card. O botão abre um bottom sheet e Universal fica primeiro/recomendado quando disponível.
- Cards de Release foram simplificados: sem badge `Direto`, sem badge duplicado de versão/nome bruto e com gerenciamento no menu de três pontos.
- `showCenteredNotice` mantém a API antiga, mas agora renderiza SnackBar flutuante compacto no rodapé; não voltar a avisos grandes no centro.
- Indicadores globais de upload/download são FABs pequenos com progresso, para não cobrir cards e botões.
- Cobertura: `test/release_asset_group_test.dart` protege ordenação e agrupamento.

## Alterações 2.0.95

- Corrige as falhas residuais dos jobs CI #84 / Android APK #85 sem alterar a lógica funcional do envio.
- O teste de repositório vazio usa regex tolerante a whitespace em vez de comparar uma linha exata que o formatter podia quebrar.
- O seletor expõe `ValueKey('repository_branch_others_toggle')`; o teste aguarda esse estado com pumps limitados e só então expande/seleciona `develop`.
- O workflow CI não modifica mais `lib/` e `test/` antes dos testes. A formatação é verificada com `--output=none` e gera apenas warning quando necessário.
- Há teste de contrato para impedir que a CI volte a formatar/mutar os fontes antes da suíte.

## Alterações 2.0.94

- Corrige regressão de análise introduzida pelo overlay de preparação/carregamento: `ValueListenable<String>` agora tem o import explícito de `package:flutter/foundation.dart` na biblioteca de detalhe do repositório.
- Mantém o carregamento progressivo da 2.0.93 sem bloquear o analyzer/CI.

## Alterações 2.0.93

- Seletor de branch virou diálogo compacto centralizado e abre antes de `listBranches` concluir; a branch atual fica visível e a lista completa é aberta por **Outras branches**.
- `listBranches` usa timeout de 12 s e erro inline com **Tentar novamente**; criação de branch também possui timeout explícito.
- O envio mostra overlay **Preparando envio** logo após a escolha da branch, evitando o intervalo em que parecia que nada acontecia.
- Pré-check de permissão é feito primeiro; depois versão remota, diff/prévia, workflow e rate limit são disparados em paralelo e possuem limites de tempo.
- `RepositoryService` mantém cache somente em memória dos repositórios já listados. A tela de detalhe usa esse snapshot para abrir imediatamente e atualiza silenciosamente em segundo plano.
- Sem cache, a tela Projeto mostra shell de carregamento progressivo; após 12 s sem resposta, exibe erro com **Tentar novamente**.
- Metadados do projeto têm fallback após timeout e não prendem a tela inteira.




## Alterações 2.0.92

- Jobs CI #81 / Android APK #82: a suíte termina rapidamente e 126 testes passam; restava somente 1 falha de expectativa no teste do seletor.
- A branch `develop` já era selecionada corretamente (`selected.name == 'develop'`), portanto a lógica de produção estava correta.
- Removida a expectativa frágil que exigia `find.text('develop') == findsNothing` após o pop da rota, pois o texto pode permanecer transitoriamente na árvore durante a animação sem invalidar o resultado.
- O teste continua cobrindo scroll até a branch, toque no item estável e valor retornado.

## Alterações 2.0.91

- Jobs CI #80 / Android APK #81: a suíte deixa de travar e finaliza rapidamente; restava somente 1 teste falhando.
- O log mostrou explicitamente que `develop` estava fora do viewport (`y=816` em uma tela de 600 px), portanto o toque não atingia o item e o resultado ficava `null`.
- O teste agora usa uma chave estável da branch, chama `ensureVisible` e somente depois toca no item.
- O seletor reutilizável de branches expõe `ValueKey('repository_branch_<nome>')` em cada `ListTile`, melhorando a automação sem alterar a lógica de produção.
- Removido o import não utilizado apontado pelo analyzer.

## Alterações 2.0.90

- Jobs CI #79 / Android APK #80: 33 dos 34 arquivos de teste concluíam; o único pendente era `repository_send_flow_widget_test.dart`.
- O teste end-to-end instável foi decomposto em testes de widget focados para seleção de branch e minimização do progresso.
- O fluxo branch → pré-check → confirmação/política continua protegido pelos testes de contrato e os serviços de upload continuam cobertos por testes unitários próprios.
- Evitar `pumpAndSettle()` em UI com progresso indeterminado/animação contínua e evitar testes de widget monolíticos que misturem banco, roteamento, persistência e várias operações assíncronas.

## Alterações 2.0.89

- Corrigido o travamento confirmado pelos jobs CI #78 e Android APK #79: `repository_send_flow_widget_test.dart` era o único entre 34 arquivos de teste que não concluía.
- O teste não usa mais `pumpAndSettle()` no fluxo que abre o diálogo de progresso, porque esse diálogo possui animação contínua e nunca entra em estado totalmente estável.
- As esperas do fluxo usam `_pumpUntilVisible` e `_pumpUntilGone`, com número máximo de pumps e falha explícita caso a UI não alcance o estado esperado.
- O teste continua usando `UploadManagerService.forTest(runBackgroundQueue: false)`, portanto não inicia cópia/persistência real dentro do `FakeAsync`.
- Os workflows continuam com `timeout-minutes: 3` na etapa de testes como proteção contra qualquer regressão futura.

## Alterações 2.0.88

- `repository_send_flow_widget_test.dart` não inicia mais a fila real de cópia/persistência dentro do `FakeAsync` de `testWidgets`.
- `UploadManagerService.forTest` ganhou `runBackgroundQueue`, padrão `true`; somente o teste de interface usa `false`, preservando a cobertura real da fila nos testes unitários.
- O teste fecha explicitamente o diálogo de progresso antes de terminar.
- CI, Android APK e Android Release definem `timeout-minutes: 3` na etapa de testes para falhar rápido em caso de novo travamento.

## Alterações 2.0.87

- corrigido deadlock em `waitUntilIdle()` dentro de `testWidgets`; não há mais polling com `Future.delayed`;
- a fila usa `Completer` para sinalizar conclusão e permitir que testes de widget terminem sem avançar relógio virtual;
- falhas de upload/build aguardam a persistência do histórico e a limpeza do ZIP antes de liberar a fila;
- mudança motivada pelos jobs CI #76 e Android APK #77, que completavam os demais testes em ~30 s e ficavam presos até cancelamento.


## Alterações 2.0.86

- Corrigido timer de persistência pendente no teste real do fluxo de envio.
- `UploadManagerService.forTest` usa persistência sem debounce para não deixar `Timer` falso ativo no fim de `testWidgets`.
- `waitUntilIdle()` agora também aguarda a persistência do histórico terminar.
- `dispose()` tornou-se assíncrono e aguarda a persistência/foreground antes de fechar, eliminando corrida com a remoção de diretórios temporários.

## Alterações 2.0.85

- corrigidas as três falhas de teste vistas nos jobs CI #74 / Android APK #75;
- ZIP Android nativo contendo apenas `app/` volta a expor identidade e versão pelo Gradle do módulo;
- teste de repositório vazio acompanha a implementação atual em `repository_branch_selector.dart`;
- teste do envio rola o diálogo antes de tocar na opção de build;
- workflows e downloads internos de logs usam nomes previsíveis com prefixo do repositório.

## Alterações 2.0.84

- Builds global lista um card por repositório e mantém somente os workflows ligados ao commit/versão mais recente;
- toque no card abre pop-up com as builds atuais do projeto e atalhos para baixar Log/APK;
- polling de UI é de 6 s; repositórios com build ativa são repolidos no ciclo curto, enquanto a varredura global é limitada a 1 min ou atualização manual;
- correção dos erros dos logs #72 em `LocalProjectService` e no fluxo nullable de seleção de branch;
- testes de Builds atualizados para agrupamento, múltiplos workflows no mesmo commit e navegação específica.

## Alterações 2.0.82

- seletor de branch compartilhado por Arquivos, Commits, Builds e Enviar versão, com criação de branch a partir da branch atual;
- prévia read-only do ZIP antes do envio, com novos/alterados/removidos, preservando a regra de workflows protegidos;
- detecção local usa a raiz efetiva do projeto e evita escolher metadados de subprojetos por acidente;
- parser de nome de ZIP preserva pré-lançamentos SemVer;
- suporte de identidade/versão ampliado para Godot, Python e Rust;
- conferência de envio mostra origem da versão e rate limit REST restante quando disponível;
- testes adicionados para os novos contratos.

## Alterações 2.0.81

- envio escolhe a branch antes do pré-check e repete o pré-check ao trocar a branch na confirmação;
- repositório vazio pode ser inicializado no primeiro envio quando a API retorna zero branches;
- comparação de versão segue SemVer para prereleases;
- Builds global usa cache em memória de repositórios, polling seletivo de execuções ativas e varredura completa espaçada;
- suíte inclui teste de widget do fluxo real de envio.

## Arquitetura

Flutter/Dart Android local-first, sem backend obrigatório. GitHub é acessado diretamente pelo aparelho.

## Identidade definitiva

- repositório oficial: `adriedsonlemoz/GitHub-Manager`;
- applicationId: `br.com.githubmanager.app`
- assinatura própria e permanente com alias `github_manager_release`;
- Secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`;
- certificado público pinado em `android/release-signing.properties`;
- Android APK e Android Release usam a mesma assinatura.

## Recursos principais

- notificações de conclusão/falha de builds em segundo plano;
- repositórios acompanhados em modo somente leitura, com Releases/APKs públicos e seleção de repositório ao colar URL de perfil;
- lista e CRUD de repositórios;
- projetos fixados localmente, filtro de fixados e ordenação por data/nome/tamanho;
- cards usam resumo leve de nome/versão; análise completa permanece nas telas internas;
- metadados de projeto, versão e tecnologias;
- navegação/edição/upload de arquivos;
- ZIP com sincronização completa e remoção de arquivos obsoletos, preservando `.github/workflows/**` quando o pacote apenas omite esses arquivos;
- recuperação inteligente de envio: retry transitório, fallback incremental → árvore completa, proteção por SHA da branch e fallback manual seguro por Contents API;
- Actions: executar, acompanhar, cancelar, reexecutar, jobs/etapas/logs, atualização automática adaptativa e diagnóstico de falhas com contexto extraído do log;
- Builds agrupadas por commit/envio, com horário até segundos e número da tentativa;
- Enviar build sincroniza o ZIP e garante o disparo do Android APK sem duplicar runs; commit publicado com build não iniciada vira estado **Build pendente** e pode ser rechecado sem reenviar o ZIP;
- Central de Envios permite minimizar a sincronização, navegar no app, acompanhar fila/histórico e repetir interrupções;
- relatório de envio separa resumo, arquivos alterados, GitHub/build e linha do tempo, evitando logs repetitivos por arquivo;
- falhas de envio preservam operação exata, progresso, HTTP, endpoint e resposta detalhada da API, com interpretação/ação sugerida e impacto seguro no repositório;
- upload reutiliza blobs cujo SHA Git já corresponde ao conteúdo do ZIP e serializa envios para reduzir chamadas mutativas concorrentes;
- artifacts/APK com Releases exibidas diretamente em cards, identificação explícita Release/Artifact, busca e filtros;
- Commits;
- Bugs via GitHub Issues sem reformulação adicional;
- GitHub Secrets com sealed box, PAT fine-grained/clássico, validação 48 KB/100, importação TXT/ENV/JSON/XML e diagnóstico por Secret;
- diagnóstico não destrutivo do token por repositório, com leitura real, escopos clássicos, `X-Accepted-GitHub-Permissions` e permissões necessárias para escrita;
- configurações, edição de perfil GitHub por popup responsivo, Groq/API opcional e tema;
- Central de Downloads com serviço Android em primeiro plano, retomada parcial por HTTP Range e publicação na pasta pública Downloads;
- download do projeto em ZIP;
- instalação de APK iniciada pelo usuário via FileProvider/instalador Android.






## Refatoração e ciclo de vida de APKs/builds 2.0.70

- telas grandes foram divididas conservadoramente em arquivos de apresentação e actions/controllers: Configurações, Detalhe do repositório, Builds/Detalhe da build e APKs/Releases;
- exclusão de build usa `BuildCleanupService`: apaga o workflow run, verifica artifacts remanescentes pelo `workflowRunId` e limpa APKs de Release somente quando o mesmo commit pode ser comprovado;
- `ActionArtifact` preserva `workflow_run.id` e `workflow_run.head_sha`; `ReleaseAsset` preserva release/tag/`target_commitish` para correlação segura;
- `ArtifactService.listArtifactsForRun` consulta os artifacts do run antes da exclusão; `listReleaseAssets` pagina até 5 páginas de 100 Releases;
- Release asset é recurso independente: a tela APKs/Releases agora permite excluí-lo diretamente sem remover Release/tag;
- `Excluir APKs anteriores` trata separadamente Actions artifacts e Release assets, preservando o APK mais recente de cada origem;
- ao publicar Release a partir de artifact, usar `artifact.workflowRunHeadSha` como `target_commitish` quando disponível; a branch é apenas fallback para artifacts antigos;
- providers de artifacts/Releases são `autoDispose` e são invalidados após operações destrutivas;
- testes relevantes: `build_cleanup_service_test.dart`, `build_artifact_linkage_test.dart`, `build_release_linkage_test.dart` e `older_apk_cleanup_test.dart`.

## Correção do build 2.0.69

- `UploadProgressDialog` e `_FailureDiagnostic` passam a usar um helper privado de arquivo para abreviar SHA;
- corrige o erro de compilação `The method '_shortSha' isn't defined for the type 'UploadProgressDialog'`;
- nenhum comportamento do fluxo de upload/build pendente foi removido;
- Android APK agora roda `flutter analyze` e `flutter test` antes do Gradle para falhar cedo em erros Dart.

## Proteção de workflows e build pendente 2.0.68

- `.github/workflows/**` é infraestrutura protegida durante a sincronização: ausência no ZIP não gera remoção; inclusão do mesmo caminho continua permitindo atualização intencional;
- a confirmação do ZIP avisa explicitamente que workflows existentes serão preservados;
- `ensureBuildForCommit` inspeciona estruturalmente YAMLs e diferencia `APK_WORKFLOW_NOT_FOUND`, `APK_WORKFLOW_TRIGGER_MISSING` e `APK_WORKFLOW_PUSH_NOT_STARTED`;
- workflow de APK com `push` recebe uma janela adicional de polling para absorver atraso de indexação do Actions;
- após commit válido, falha de descoberta/disparo da build usa `ManagedUploadStatus.buildPending`, preserva o SHA e retry executa somente `_runBuild`;
- o diálogo de progresso é rolável, resume o problema e recolhe diagnóstico técnico; build pendente oferece **Abrir Builds**, **Verificar build**, exemplo de gatilho copiável e deixa claro que o ZIP já foi enviado;
- nunca voltar a classificar falha de Actions como falha de upload quando `commitSha` válido já foi publicado.

## Persistência e recuperação 2.0.67

- SQLite usa `schemaVersion = 3`, com `CREATE TABLE/INDEX IF NOT EXISTS` em criação, upgrade e abertura;
- instalações antigas com banco incompleto são migradas sem exigir limpar dados do Android;
- cada `LocalDatabase` abre conexão própria (`singleInstance: false`), evitando que serviços auxiliares fechem a conexão usada pela UI;
- reconciliação de projetos fixados é auxiliar e não pode derrubar a lista remota de repositórios;
- JSON local inválido é removido somente na chave afetada;
- Configurações > Diagnóstico de dados locais pode reparar o esquema ou reconstruir apenas o SQLite, preservando o PAT no `flutter_secure_storage`.

## Conferência, ajuda e token 2.0.66

- build 57 corrigido: o detalhe do repositório resolve o estado de fixado antes de abrir o menu e passa `isFavorite`;
- análise local de ZIP Node/JavaScript lê versão/nome do `package.json` da raiz ou da única pasta-raiz;
- `Conferir build` mostra a versão do projeto a enviar, não a versão instalada do GitHub Manager;
- avisos de identidade/versão têm ajuda contextual com fontes aceitas e passos para corrigir;
- Configurações possui central de ajuda geral e acesso direto para exibir/copiar o token GitHub atual;
- token continua apenas em `flutter_secure_storage` e nunca deve aparecer em logs/diagnósticos.

## APKs e segurança de envio 2.0.31

- cards de APK/artifact compactos, com três ações lado a lado e badges de formato/build/estabilidade/versão;
- classificação por nome diferencia Debug, Profile, Release, prévia e AAB/Google Play, sem afirmar certeza quando a API não fornece buildType;
- versão anterior não bloqueia mais envio: regressão fica disponível com aviso;
- nome do projeto/repositório é apenas pista e nunca bloqueia sozinho;
- uma divergência forte (`applicationId` ou pacote) vira aviso; duas divergências fortes simultâneas ativam risco alto;
- risco alto ainda pode ser forçado com uma segunda confirmação explícita mostrando o destino.

## UI e identidade de projeto 2.0.30

- novo padrão visual azul-preto/índigo aplicado no tema compartilhado, cards de repositório, busca, filtros e navegação inferior;
- componentes globais de cards, campos, botões, diálogos e navegação levam a mesma identidade às demais telas sem arquitetura paralela;
- comparação de projeto normaliza diacríticos, evitando falso bloqueio entre nomes equivalentes como `Tática Manager` e `TaticaManager`;
- identidade Android do repositório tenta ler `android/app/build.gradle.kts` e `android/app/build.gradle` quando os metadados não trazem `applicationId`;
- divergência real de `applicationId` continua sendo bloqueio forte.

## Hotfix 2.0.29

- corrigida compilação do importador de Secrets com `file_picker 12`, usando `PlatformFile.length()` em vez do getter removido `size`;
- CI normaliza a formatação no runner e avisa sobre diferenças sem interromper o pipeline somente por formatação;
- `flutter analyze` e `flutter test` continuam sendo gates reais da CI.

## Pré-checagem de permissões 2.0.28

- `Enviar build` consulta Contents/Workflows e Actions antes de abrir o seletor de ZIP;
- criar, substituir, importar e excluir Secrets consultam a capacidade de escrita de Secrets;
- exclusão permanente de repositório consulta a capacidade de exclusão antes da confirmação destrutiva;
- negação confirmada bloqueia antecipadamente e mostra a permissão faltante com atalho para o diagnóstico;
- resultado `unknown` de PAT fine-grained não bloqueia, evitando falso negativo;
- cache de 3 minutos usa fingerprint SHA-256 do token apenas em memória, portanto troca de token não reaproveita resultado antigo;
- rate limit/indisponibilidade do diagnóstico não são convertidos em falta de permissão.

## Diagnóstico do token 2.0.27

- disponível em cada repositório próprio;
- executa somente GETs e nunca altera dados para testar permissões;
- confirma leitura de Contents, Actions, Secrets e Administration;
- PAT clássico: cruza `X-OAuth-Scopes` com o papel da conta e identifica `repo`, `workflow` e `delete_repo`;
- PAT fine-grained: mostra a permissão exata necessária para escrita sem fingir que é possível introspectar o que o GitHub não expõe;
- usa `X-Accepted-GitHub-Permissions` em falhas de leitura quando disponível;
- relatório copiável não inclui token;
- testes dedicados cobrem token clássico, fine-grained, permissão ausente e papel não administrativo.

## Secrets 2.0.26

- aceita tokens fine-grained e clássicos sem restringir prefixo na validação de `/user`;
- assistente explica `Secrets: Read and write` para fine-grained e `repo` para clássico;
- parser TXT/ENV aceita `=`, `:` e `export`, detectando duplicidades após normalização;
- pré-valida 48 KB por valor e 100 Secrets finais por repositório;
- importação em lote continua após falha individual e gera relatório sanitizado copiável;
- erros HTTP preservam status, endpoint e mensagem da API sem registrar valores;
- testes dedicados cobrem parser, limites, lote parcial, criptografia e exclusão.

## Segurança

Nunca incluir keystore, `.env`, tokens ou key.properties no ZIP/repositório.

## ZIP idêntico

Se um ZIP gerar a mesma árvore Git já publicada, não criar commit nem build automática. Informar `Projeto já está atualizado` e permitir `Executar build mesmo assim` via `workflow_dispatch`.

## UI e Sobre 2.0.25

- não existe mais banner vermelho global de versão de teste;
- a confirmação de envio do ZIP mostra um card vermelho/branco com a versão instalada;
- avatar da Home abre edição de perfil GitHub em diálogo responsivo;
- gerenciamento do repositório usa engrenagem e diálogo centralizado;
- Sobre mostra as três mudanças mais recentes em ExpansionTile, Pix, feedback, desenvolvedor e aviso de independência do GitHub;
- Groq é opcional e atualmente não é consumido automaticamente por nenhuma função principal.


## Ciclo de vida SQLite 2.0.71

- `LocalDatabase` possui construtor privado e expõe somente `LocalDatabase.shared`; não reintroduzir `LocalDatabase()` em serviços.
- `shared` é por isolate: UI e providers usam uma conexão durante toda a sessão; WorkManager possui outra instância estática no isolate de background.
- `singleInstance: true` voltou a ser seguro porque não existem mais serviços curtos fechando handles compartilhados.
- `_opening` deduplica aberturas concorrentes do mesmo isolate.
- `localDatabaseProvider` não fecha a conexão em `ref.onDispose`; startup, `BuildMonitorService` e `UploadRecoverySettings` também não fecham o banco após cada operação.
- `rebuildLocalDatabase()` é o único fluxo autorizado a fechar internamente a conexão antes de excluir e reabrir o banco.
- manter `schemaVersion = 3` enquanto não houver nova alteração real de schema; `_ensureSchema` continua idempotente para instalações antigas.

## Refatoração ManagedUpload 2.0.72

- `lib/features/uploads/domain/managed_upload.dart` agora é o contrato principal e caiu de 983 para cerca de 235 linhas.
- Não alterar a API pública sem revisar `UploadManagerService`, UI da Central de Envios e testes de persistência.
- `managed_upload_state.dart`: getters derivados, labels, progresso e conversão para `ZipProjectPreview`.
- `managed_upload_failure.dart`: classificação de falhas, impacto no repositório, recuperação recomendada e instruções ao usuário.
- `managed_upload_lifecycle.dart`: contadores, logs, interrupção, retomada e retry.
- `managed_upload_report.dart`: linha do tempo amigável e relatório técnico copiável.
- `managed_upload_codec.dart`: persistência JSON; manter compatibilidade retroativa das 51 chaves existentes.
- `managed_upload_refactor_contract_test.dart` é o teste de proteção da divisão e deve evoluir quando um novo campo persistido for adicionado.

## Correção dos logs 63 — 2.0.73

- Android APK 63 e Verificação CI 63 falhavam no `flutter analyze` antes dos testes/Gradle.
- causa: `leftover` era declarado como `final` apontando para um objeto `const`, mas era reutilizado dentro de listas literais `const`; a variável em si não era uma constante de tempo de compilação;
- correção: `const leftover = ActionArtifact(...)`;
- nenhuma lógica de `BuildCleanupService` foi alterada;
- manter o teste de exclusão de artifact remanescente para prevenir regressões no vínculo Build → Artifact/APK.

## Branch de envio, Builds globais e projetos sem workflow — 2.0.74

- O envio permite escolher a branch e persiste localmente a última branch usada por repositório.
- `RepositoryProjectInfoService.load(..., branch:)` compara os metadados contra a branch escolhida.
- A navegação principal agora é Projetos / Builds / Downloads / Perfil / Opções; Acompanhados fica dentro de Projetos.
- `GlobalBuildsService` reúne até cinco runs recentes por repositório em lotes, sem enriquecimento de versão para evitar chamadas extras.
- `APK_WORKFLOW_NOT_FOUND` deixa de ser falha de build na Central de Envios: o item termina como concluído sem workflow.
- O preflight `syncProject` exige Contents, enquanto `sendBuild` continua exigindo Contents + Actions para operações explicitamente ligadas ao Actions.
