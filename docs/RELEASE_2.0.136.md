# GitHub Manager 2.0.136+200150

## Notificações configuráveis e anti-repetição

- Configurações → Notificações: nova chave geral **Permitir avisos opcionais**, desligada por padrão, e quatro seletores independentes para sucesso/falha de builds e downloads.
- Persistência local SQLite dos ajustes e do histórico de eventos notificados, com reserva transacional de cada ID. Monitores do WorkManager e da UI deixam de competir para emitir a mesma notificação.
- Migração dos IDs já notificados pelas versões anteriores (até 250); histórico novo não perde IDs antigos por rotação.
- Apenas eventos de builds concluídos nas últimas 2 horas, criados após ativação do monitor, entram em novas notificações.
- Toque no alerta de build marca evento como aberto e cancela a notificação local correspondente. Desligar chave geral cancela alertas opcionais existentes por canal nativo, preservando notificações de serviços foreground ativos.
- Downloads não pedem permissão de notificação apenas por iniciar. Serviços Android foreground que sustentam uploads/downloads continuam funcionando com suas notificações de progresso até concluir/parar.

## Limitações e testes pendentes

- A limpeza manual pelo painel do Android não expõe um callback de leitura ao Dart nesta implementação, mas o ledger por ID evita redisparo do mesmo evento.
- Os testes Flutter completos, análise estática e compilação Android deverão ser executados no workflow Android APK. Teste em aparelho para permissões Android 13+, pause/retoma de transferências e monitorização em segundo plano.
