# QA do Must — Belo Horizonte, antes de usar de verdade

Legenda: **[x] auto** = coberto por teste automático (`MustTests`, 144 testes) · **[x] sim** = visto no simulador
(prints em `scripts/qa-screens.sh`) · **[ ] iPhone** = precisa do aparelho/GPS real · **[!]** = bloqueado (motivo ao lado).

Rodar tudo que é automático:

```sh
xcodebuild -project Must.xcodeproj -scheme Must -destination 'platform=iOS Simulator,name=iPhone 17' test
./scripts/qa-screens.sh          # prints de BH (sáb 31 out, Savassi) e Japão (15 nov, Naka-Meguro) em qa-screens/
```

## 1. Primeira abertura
- [x] auto — seed BH carregado: 23 lugares, 5 listas, meta R$ 200 (`QAScenarioTests.firstOpenLoadsBHSeed`, `RegionStoreTests`).
- [x] sim — tela Importar aparece na 1ª abertura da região, com contagens, viagem/cidades e "Permitir" localização.
- [ ] iPhone — o pedido de localização do iOS aparece ao tocar "Permitir" e a Início mostra "Perto de você" com GPS real.

## 2. Sincronizar Places (Ajustes → Sincronizar horários e preço)
- [x] auto — resolve os approx em lote de 50, preço do board não é sobrescrito, nome exato tem prioridade (`PlacesSyncTests`).
- [!] — **a chave atual volta HTTP 403 PERMISSION_DENIED** em todas as chamadas. No Google Cloud: ativar **Places API (New)**,
  liberar a chave pra essa API (Restrições de API) e, se a restrição de app for "iOS", o bundle `dev.viniso.must`.
  Depois: os 23 lugares ganham horário e a Lista passa a mostrar "aberto até…". Conferir o contador "N usados" (≈ 46 na 1ª vez).

## 3. Sábado de manhã — o fluxo completo
- [x] auto — Montar "livre", R$ 200, Savassi 09:30 → 1 see + 1 eat + 1 drink, sem Inhotim, sem exceção (`DaySolverBHTests`).
- [x] auto — aceitar grava o dia (e substitui, não duplica); registrar gasto marca 済 no lugar e na parada (`DayFlowTests`).
- [x] sim — Proposta → Trocar o almoço (alternativas na janela) → Aceitar → Hoje → Mapa com rota e pinos.
- [x] sim — Live Activity inicia ao aceitar o dia (log `Live Activity iniciada: …`).
- [ ] iPhone — "Ir agora" abre o Apple Maps; Registrar gasto marca 済 e a Live Activity avança pra próxima parada;
  no fim do dia (tudo 済) ela some.

## 4. Domingo de compras
- [x] auto — Montar "compras" no domingo → Feira Hippie entra de manhã, sem Must listen (`QAScenarioTests.sundayShoppingPullsFeiraHippieInTheMorning`).

## 5. Orçamento R$ 100
- [x] auto — Glouton/Trindade não entram; com "vale a exceção" (já marcado no seed) + "jantar bom" no texto, entra um deles fora da meta (`QAScenarioTests.budget100WithSplurge`, `DaySolverBHTests.tightBudgetKeepsFineDiningOutUnlessAsked`).

## 6. Nova lista "kissaten"
- [x] sim — prévia ao vivo, ícone/cor, fotos CC do **Wikimedia Commons** (o Flickr não dá mais chave pra conta grátis).
- [!] — "2 lugares pelo Places" depende do item 2. Sem a chave funcionando: adicionar pelo board, à mão ou por link.
- [ ] iPhone — a lista aparece no hub com a cor e a foto.

## 7. Adicionar por link
- [x] auto — IG/TT/YT/Maps detectados; URL do Maps vira nome + coordenada; legenda com 📍/@/"no X" vira lugares; nada inventado (`LinkResolverTests`, `PlaceExtractorTests`, `PlaceExtractionAITests`).
- [x] sim — link do Google Maps: lugar novo com sub sugerida ("Must eat · Ramen"); lugar existente: "já está no board".
- [ ] iPhone — um Reel real (a legenda pública costuma falhar → o fluxo de colar o texto tem que funcionar).

## 8. Assistente
- [x] auto — "tô cansado, troca o bar de hoje por algo perto do jantar e me diz quanto já fui": gasto certo + até 2 trocas do board (`FallbackAssistantTests`).
- [x] sim — com Apple Intelligence (o simulador tem): sugestões, troca e gasto; pergunta aberta vai pro modelo com ferramentas.
- [x] auto — sem Apple Intelligence tudo responde por palavra-chave, sem crash.
- [ ] iPhone — 3 perguntas das sugestões; tocar "Trocar" muda a parada no Hoje.

## 9. Menu escondido e Japão
- [x] auto — trocar pra Japão e voltar não perde gastos de BH (`RegionStoreTests.switchingRegionKeepsEachBoard`).
- [x] auto — 15 nov 10:00 em Naka-Meguro → a Início mostra o Udatsu como "Próxima" (`QAScenarioTests.japanHomeShowsUdatsuAsNext`).
- [ ] iPhone — fazer pelo menu: Ajustes → 5 toques na versão → Japão → simular data e GPS.

## 10. Exportar → apagar → reinstalar → importar
- [x] auto — export/import com 済, gasto, dias e eventos volta idêntico, sem duplicar (`QAScenarioTests.exportWipeImportRestoresEverything`, `BoardCodecTests`, `TripEventCodecTests`).
- [ ] iPhone — fazer de verdade: Ajustes → Exportar board → apagar o app → instalar → Importar (Escolher .json).

## 11. Sem rede
- [x] auto — serviços respeitam "Dados ao vivo" desligado e devolvem cache (tempo, fotos) sem erro fatal.
- [ ] iPhone — modo avião: app abre, listas e Hoje funcionam, a Início mostra o chip "sem dados ao vivo".

## 12. Consumo
- [x] revisado no código — GPS só em primeiro plano, a cada 50 m; rota a pé pedida uma vez por par de paradas;
  ETA em cache de 10 min; widgets/Live Activity só atualizam quando algo muda.
- [ ] iPhone — uma tarde com o mapa aberto: ≤ ~10% de bateria (Xcode → Debug Navigator → Energy).

## 13. Mapa papel em relevo (prompt 12)
- [x] sim — Centro de BH: relevo nas quadras, fitas e pontilhado, nomes em Archivo caps, parque com pontinhos, sem POIs.
- [x] sim — pinos: carimbo de sem plano, aberto cheio com anel (forçado com `-debugPinsOpen YES`, faltam horários do Places),
  fechando com arco, hoje numerado com pílula no próximo, contas na rota futura, amanhã tracejado.
- [x] sim — zoom out (~14 km): prédios somem, quadras lisas, cidades; sem plano vira cluster.
- [x] sim — Japão: tiles offline (Tóquio/Kansai), rótulos em japonês com Zen Kaku, metrô em vermelho.
- [ ] iPhone — 60 fps no iPhone Air com as 3 camadas de pino; pulso do aberto só com o mapa parado.

## 14. Abertura e zoom do mapa (prompt 11 · A)
- [x] auto — perto → bairro; nada a 500 m → mais perto; próxima parada ganha se < 3×; gesto segura 20 s; ⌖ volta;
  < 100 m não reavalia; enquadramento respeita as folgas (`MapCameraPlannerTests`, `MapCameraControllerTests`).
- [x] sim — Savassi: escala de bairro, sheet "Perto de você" com os 2 mais perto e a próxima parada.
- [x] sim — Santo Agostinho: zoom até o Mercado Central, linha tracejada com "1,2 km · 10 min de metrô", aviso em serif,
  card com Apple Maps / Google Maps / Ver o dia.
- [ ] iPhone — arrastar o mapa não briga com a câmera; ligar/desligar camada reavalia.

## 15. Dicas de quem foi (prompt 11 · B)
- [x] auto — parse do Google (original + tradução), Foursquare (match + tips), Reddit (só comentários que citam o nome),
  legenda de origem primeiro, cache 24 h / apaga com 30 dias, fallback do resumo em texto (`TipsParsingTests`, `TipsSummaryParseTests`).
- [x] sim — Udatsu com amostras (`-debugScreen dicas:j01 -debugTips fake`): header comprimido, resumo e temas gerados no
  aparelho, card verde "de onde veio este must", dica em japonês com a tradução embaixo, filtros, rodapé.
- [!] — fontes reais: Google depende do item 2 (403 e sem `placeId`); Foursquare e Reddit precisam de `FOURSQUARE_KEY` e
  `REDDIT_CLIENT_ID`. Sem elas a seção mostra só a legenda de origem.
- [!] — o modelo do simulador recusou (guardrail) resumir as amostras de BH; as do Japão passaram. Conferir no iPhone com
  dicas reais; quando recusa, a tela diz "O modelo do aparelho não resumiu essas dicas".

## 16. Tipos photo, art e sport (prompt 13)
- [x] auto — sol (NOAA, sem rede): Tóquio 15/11 nasce 06:16 · põe 16:34 · golden 15:57–16:34 · azul até 17:01; BH 15/11
  05:08 / 18:12 (bate com timeanddate). O prompt citava 16:38 e 18:16; os valores astronômicos são esses (`SunServiceTests`).
- [x] auto — previsão hora a hora + AQI (`HourlyWeatherTests`); seeds com `kind`/`extra`; board antigo ganha as listas
  novas uma vez sem sobrescrever nada (`ExtrasDataTests`).
- [x] auto — Montar "fotografia" em Tóquio 15/11: golden da manhã (Senso-ji) → museu no sol alto → almoço → Yanaka no
  golden → Nippori na hora azul; nuvens 80% no golden tiram o Yanaka ("nublado no golden") (`PhotoDayTests`).
- [x] auto — art: "termina em 4 dias" prioriza e entra na explicação; temporada acabada fica de fora; última entrada;
  ingresso comprado vira âncora (`ArtRulesTests`).
- [x] auto — sport: domingo 07:00 a corrida entra; começando 12:00 (31°) não entra; janela "até as 10h" (`SportRulesTests`).
- [x] auto — extrator de evento: página japonesa (2026.10.3〜2026.11.30, ¥1,400 / 学生 ¥1,120), link da Sympla
  ("até 16/11", R$ 20 / meia R$ 10) (`EventExtractorTests`).
- [x] sim — Lugar photo (Yanaka, GPS simulado, 15/11 15:20): arco do sol, golden/azul, sol a 242° "bate no eixo da rua",
  Céu com Open-Meteo real, bússola "Contraluz no golden", chips, "Luz de hoje" + "Sair 15:45". Menu escondido →
  Simular nuvens 20%/80% troca a frase ("céu limpo no pôr do sol — vale ir hoje" ↔ "nublado… melhor outro dia").
- [x] sim — Luz de hoje: faixas azul/golden/dura/golden/azul, agora, chips, spots por hora (passados a 50%, próximo em
  dourado), museu no sol alto, frase de amanhã.
- [x] sim — Lugar art (Moriyama, 26/11): "termina em 4 dias" em terracota, aberto até 20:00 (qui), Entrada · temporada,
  Estilo, Também aqui (Comprar / esgotado; toque longo marca ingresso comprado), "Ir agora · 10 min" + "Pôr no dia 13h".
- [x] sim — Lugar sport (Pampulha, 01/11): Condições com métricas e AQI, Melhor janela por hora, percurso. Com a previsão
  real de hoje (chuva 40% de manhã, sensação 30° ao meio-dia) não há janela verde — a tela diz isso.
- [x] sim — hub com 8 tiles de 118 pt (photo "golden hoje 15:50", art "1 termina esta semana", sport "corrida 1",
  see teal de templos/mirantes).
- [x] auto — "quero correr cedo" liga sport, "sem corrida" desliga, "pegar o golden" liga photo (`KindIntentTests`).
  O assistente filtra por photo/sport e vê golden de hoje, "termina em N dias"/preço/sessão e "evitar agora (quente · 31°)".
- [ ] iPhone — "Começar" abre o Strava (`strava://record`) se estiver instalado; senão a rota a pé.
- Nota — as exposições dos seeds (Moriyama no TOP Museum, mostras de BH) são exemplos do design: conferir as agendas.

## 17. Região pelo GPS e boards maiores (01/11)
- [x] sim — GPS simulado em Savassi abre BH; em Naka-Meguro abre Japão; 6 trocas seguidas sem crash. Ajustes › Região
  mostra Automático / BH / Japão ("pelo GPS · agora em Belo Horizonte").
- [x] corrigido — trocar de região com a sincronização rodando derrubava o app (container antigo solto no meio do
  `await`). Agora cada tarefa segura o container dela e para se a região mudou.
- [x] auto — seeds: BH 50 lugares, Japão 103 (lista do Milanote inteira) + 3 voos; board antigo recebe os novos uma vez
  e o "see" violeta com museus vira templos/mirantes + art (`OldSeedRealignTests`, `ExtrasDataTests`).
- [x] auto — Tóquio 13–17 e 20–24 são a mesma cidade pro solver; "fica pro fim" ganha prioridade nos últimos dias.
- [!] — Places resolve 50 lugares por sincronização: o Japão (103 aproximados) precisa de 3 sincronizações quando o
  Google voltar a funcionar.

## Notas
- O simulador "iPhone 17 Pro" ficou travando o test runner ("hung before establishing connection") depois de muitas
  execuções; o "iPhone 17" roda limpo. Se acontecer: `xcrun simctl erase <udid>`.
- Marcar 済 direto na Lista (sem passar pelo Lugar) ficou de fora: o toque longo da Lista é Editar. Hoje o 済 é pelo
  Lugar → Feito ou pelo "+ gasto" do Hoje.

## 18. Mapas offline por cidade (02/11)
- [ ] Ajustes › Mapas offline lista Minas Gerais (BH, Inhotim) e Japão (7 cidades) com tamanho; "você está aqui" na cidade do GPS.
- [ ] Baixar BH: progresso em %, depois ✓ e "baixado"; "No iPhone" soma o tamanho. Cancelar no meio não deixa arquivo.
- [ ] Modo avião com BH baixado: o Mapa mostra ruas e prédios. Sem baixar e com internet, o mapa também aparece (lido do R2).
- [ ] Apagar (lixeira → confirmar) libera o espaço; o mapa troca pro R2 sem reabrir.
- [ ] No Mapa, cidade do GPS sem baixar mostra o aviso "Baixar"; o × some com ele só pra essa cidade.

## 19. Board completo (fatia 1 · prompt 14 A, 02/11)
- [x] sim — `-debugScreen board`: cabeçalho, busca, chips, grupos com "+ N em <lista>" e swipe; `board:editar`: bolinhas,
  "2 selecionados" e barra de lote. Testes: 178 passando (BoardEditsTests).
- [ ] sim (aberto) — `editar-lista:eat` e `nova-lista` saem deslocados ~22 pt pra esquerda (o formulário NewListView já
  existia assim; não é da edição). Causa provável: a linha "busca “…”" do cabeçalho da foto, que não quebra. Não corrigido.
- [ ] iPhone — arrastar entre listas (drop no cabeçalho) e arrastar pra reordenar: só dá pra confirmar tocando.
- [ ] sim — o store do BH no simulador tem os 103 lugares do Japão (dado antigo do aparelho de teste); os prints de BH
  mostram o Japão até apagar/reimportar o board.

## Fatia 3 (prompt 15 · A): importar ingresso
- Share Extension `MustShare` (dev.viniso.must.share) embutida no app e no esquema; grava em `Inbox/<uuid>` no App Group e abre `must://import?id=`. Verificado: build e embed. Não verificado: compartilhar de verdade pelo Mail/Arquivos (precisa de aparelho; no simulador não dá pra disparar a folha de compartilhar).
- Leitura no aparelho: PDF com texto e QR, foto, `.pkpass` stored e deflate, link (só com "Ler a página"). 17 testes novos (`TicketReaderTests`, `TicketMatcherTests`), suíte inteira verde.
- No simulador, Vision de código de barras não funciona ("Could not create inference context"); o QR cai no `CIDetector`. Verificar o Vision no aparelho.
- Telas: `ingresso-entrada` e `ingresso-revisar` (PDF de exemplo na caixa) no `qa-screens.sh`, região JP. Conferir o print contra `design/screens/TicketRevisar.png`.
- Pendente: Escanear com câmera real (DataScanner), Voo e Trem (fatias 5 e 6, TODO explícito na tela), "Avisar saia às + Live Activity" (sem campo no modelo ainda).

## Rodada 14–16 (fatia 7) · o que só dá pra testar no iPhone

Os prints do `scripts/qa-screens.sh` cobrem a aparência. Esta lista cobre o que o simulador não cobre (câmera, Share, Mail, Arquivos, `shoebox://`, proteção de arquivo, lembretes, arrastar no Board, AeroDataBox real). Nenhum item usa API paga além da cota já combinada (AeroDataBox: 400 unidades/mês).

### Prompt 14 · Board, Por perto, experiências, ingresso
- **Board:** selecionar 3 em Must eat, mover pra Must drink, marcar "fica pro fim", apagar 1 com confirmação. Arrastar reordena e persiste (fechar o app e reabrir). Busca por "Reel" acha os que vieram de link.
- **Por perto** (GPS real em Naka-Meguro, 18:42): destaque fora do board com nota e frase; "+ Must drink" cria o lugar com placeId; a Home mostra a linha "Por perto:" ao reabrir.
- **Experiências:** nesta rodada não há API de experiências (decisão de 02/11): só o card de colar link. Colar um link do Klook preenche título, preço e duração.
- **Ingresso:** criar um ingresso manual com código → QR gerado, aparece em Reservas como âncora e no Hoje do dia; conflito com Udatsu 19:00 aparece no card de experiências.

### Prompt 15 · importar ingresso, Carteira, voos
- **Share (Mail → Must):** compartilhar um PDF de reserva do Mail pro Must → o fluxo lê QR e campos, sugere o lugar certo, salva, aparece em Reservas e no Hoje do dia (Live Activity fica pra depois; hoje é só lembrete).
- **Scanner (VisionKit):** escanear a tela de outro app com QR → "Encontrei" com código e data. Testar com a câmera de verdade (o simulador não tem).
- **`.pkpass`:** abrir um `.pkpass` de teste (Arquivos → Compartilhar → Must) → campos de `pass.json` preenchidos, QR gerado igual ao do passe.
- **Carteira:** Suica com saldo anotado e aviso abaixo de ¥1.000; "Abrir no Wallet" abre o Wallet (`shoebox://`).
- **Proteção:** os arquivos de ingresso e Carteira são gravados com `FileProtectionType.complete` (`TicketFiles`). Bloquear o iPhone e abrir o item pela Carteira: o arquivo só abre com o aparelho desbloqueado.
- **Voo GRU→HND de PDF LATAM:** PNR, 2 pernas, checklist com 12 itens. Marcar "Visit Japan Web" na Carteira marca o item sozinho.
- **Status de voo (AeroDataBox real, cota):** com `AERODATABOX_KEY`, status e portão atualizam ao abrir Voos. Conferir que uma atualização gasta 1 unidade e que, sem a chave, o card mostra só o horário programado.
- **Lembretes:** ligar "Lembrar no horário" em Voos (pede permissão) e conferir que o item com `dueAt` chega no horário. Ligar "Avisar saia às" na conferência do ingresso (pede permissão) e conferir o aviso no horário de sair (visita − 40 min, estimativa).
- **Arrastar no Board:** arrastar um lugar pra outra lista (soltar sobre o cartão da lista de destino) e conferir que a troca persiste ao reabrir o app.

### Prompt 16 · Adicionar por link com mapa
- Não há bloco "Verificar" no prompt 16. Conferir, no aparelho: colar um link do Maps com nome, colar uma legenda com 3 lugares (Places real, com cota), e o mapa com os pinos numerados.

### Diferenças do design que ficaram (por tela, curto)
- **Editar lista / Nova lista:** conferido no print. Sem deslocamento. Cores em linha com rolagem horizontal, cortada na borda direita como no design. A busca de foto trunca ("busca “… belo horiz…”") em vez de quebrar.
- **Conferir (TicketRevisar):** conferido no print. Linha compacta "rótulo · ● valor · origem" como no design. "Pessoas" e "Pago" ficam em linhas separadas (o design junta em "Pessoas · pago"). As opções ("Vale a exceção", "Avisar saia às") ficam abaixo da dobra e não foram vistas no print.
- **Conferir, "Avisar saia às":** lembrete local só, sem Live Activity. A hora de sair é visita − 40 min (estimativa fixa), não a rota real.
- **Voos:** conferido no print. O cartão mostra CNF→HND com "saia às 15:25 pro aeroporto", que é o cálculo de voo doméstico (2 h + 1 h antes de 18:25). Os status são de mentira (`-debugFlight fake`).
- **Hoje · voo:** a hora do voo e a de sair pro aeroporto saem no fuso do aeroporto de origem. Coberto por teste unitário (FlightTests), não por print.
- **Não comparados por completo nesta rodada:** Board, Ingresso, TicketEntrada, Experiências, Descobrir, Carteira, Viagem, AdicionarMapa e Lugar › 3D. Os prints foram gerados (`scripts/qa-screens.sh`) mas a comparação visual não terminou; conferir na próxima passada.
