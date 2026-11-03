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
- [x] iPhone — o pedido de localização do iOS aparece ao tocar "Permitir" e a Início mostra "Perto de você" com GPS real (Vinicius, 01/11/2026).

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
  Em 03/11 o "iPhone 17" também degradou (3 de 5 rodadas com "hung", igual no commit anterior ao A.5); depois do `erase`, 4 de 4 limpas.
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

## Fatia 8B · Compras da viagem (prompt 17 · B)
- Decisão: compras ficam **fora do export do board** (como a Carteira); o JSON do board não muda. As compras compradas já saem como `expenses` (categoria shop).
- Taxa US$ → R$ em `Settings.brlPerUSD` = 5,50 (padrão de referência, editável em Compras › Regras › "mudar"). Cota do Brasil = previsto convertido em US$.
- Tax-free: 10% (8% comida) de taxa embutida, reembolso = preço × taxa / (1 + taxa), só loja/dia ≥ ¥ 5.000 com recibo.
- Sem foto nos itens (sem rede nesta fatia): o card usa bloco de cor da categoria.
- Checagem de comida sem modelo no aparelho: regex/palavras (função pura). Foundation Models não entrou.
- Verificado: 15 testes (`ShoppingTests`), build e prints `compras` e `compras-regras` (DEBUG, região jp). Não verificado: Viagem › tag Compras e Carteira › atalho em tela; toque no card e no editor; sheet de taxa.

## Performance (prompt 18 · A)

**Método.** Tentado no simulador (iPhone 17, iOS 26.5, Debug): `xctrace record --template 'Time Profiler'` com `--launch` (app instalado) e com `--attach Must`, por ~15 s, nas telas Lista (`-debugScreen lista:eat`) e Início. Nas duas tentativas a gravação não fechou (ficou parada e saiu com trace de 52 KB, sem tabelas de dados), então não há números de Time Profiler nem de Hangs deste ambiente. Como o briefing manda, passei pro fallback: teste de medição em `MustTests/OpenNowIndexTests.swift` (`PerformanceMeasureTests`), que roda o "abertos agora" pros 103 lugares do seed JP (metade Tóquio, metade Quioto; jantar e bar que vira a noite) 50 vezes e imprime os tempos. Não tem asserção de tempo (depende da máquina).

**Antes/depois (simulador, prints do teste, 50 passadas × 103 lugares):**

| Caminho | Tempo | Decodificações de JSON |
|---|---|---|
| Antes: getter decodifica o `Data` a cada leitura (emulado: decode + `isOpen`) | 64–66 ms | 5 150 |
| Depois: `Place.openState` com cache por objeto | 17–18 ms | 1 por lugar (no primeiro acesso) |
| Depois: `OpenNowIndex` (usado pela Lista) | 13–14 ms no total, 1 recálculo | 0 |

Observação: o "antes" é uma emulação do getter antigo, não o código antigo rodando. A Lista antes chamava `openState` dentro do comparador do `sort` (n log n chamadas com decodificação cada); agora são n chamadas por recálculo.

**A.1 · JSON decodificado a cada leitura.** `Place.hours`, `Place.extra`, `Place.tickets`, `TripInfo.cities`, `Flight.legs` e `Flight.checklist` passam por `JSONMemo` (`Must/Models/JSONMemo.swift`): um cache por objeto (`@Transient`, fora do schema) que guarda o valor e o `Data` de origem e compara os bytes a cada leitura. Se o SwiftData trocar o `Data` (sync, merge, import) sem passar pelo setter, o cache se invalida. Schema e export não mudaram. `Place.tickets` saiu da extensão (de `Ticket.swift`) pro corpo da classe, porque extensão não guarda propriedade. Testes: `MustTests/JSONMemoTests.swift` (5).

**A.2 · Bússola e GPS.** Heading saiu do `LocationService` pro `Compass` (`@Observable` próprio, `let compass` no serviço). Só `CompassBridge` (view de 1 pt, `Must/Features/Map/CompassBridge.swift`) lê o heading e empurra o valor pro coordenador do MapLibre (`YouHeadingSink`). `MapView.body` não lê mais heading; `MapScene.heading` foi removido. `headingFilter` 8 → 10. O filtro de 50 m já rodava antes de publicar `device`; agora a regra é a função pura `LocationService.publishable(_:after:)`, testada. Testes: `MustTests/LocationGateTests.swift` (6), incluindo "girar a bússola não invalida quem lê posição".

**A.3 · Trabalho fora do body.** `OpenNowIndex` (`Must/Models/OpenNowIndex.swift`) guarda, por tela, o snapshot de abertos e distâncias e só recalcula quando muda o minuto, a posição (≥ 50 m), o fuso ou o conjunto de lugares (`PlacesRevision`: id, 済, reserva, horário, área, lista, coordenada). Lista usa o índice: filtro e ordenação leem o snapshot, com uma chave por lugar em vez de `openState` por comparação. Testes: `MustTests/OpenNowIndexTests.swift` (3 + a medição).

**Ficou de fora (e por quê)**
- **Home:** `HomeModel` continua montado a cada `body`. Os abertos saem do cache de JSON agora (custo baixo). Não mexi porque `HomeModel` é usado por `OutsideBridge` e `QAScenarioTests`; fica pra quando a Home for refeita (B).
- **Mapa:** `pins` ainda é recalculado a cada `body` (`openState` por lugar sem roteiro). Heading não entra mais, mas não há memo dos pinos.
- **Lista/Board:** sem `LazyVStack` (o VStack externo da Lista não é lazy, então não ajuda) e sem `@Query` com `predicate`/`fetchLimit` (o board inteiro tem ~100 lugares).
- **Calendário:** `PlaceHours.weekMinute` cria um `Calendar` por chamada. É o que sobra no custo de `openState` (~3 µs); fica pra próxima medição.
- **A.4 em diante** (rede, offline, arranque, Foundation Models): outra fatia.

**Testes.** 346 → 361 (todos passando). Build de simulador e de aparelho (`generic/platform=iOS`, sem assinatura) OK.

**A.4 · Rede (prompt 18 · A.4).** Feito no simulador (iPhone 17, iOS 26.5). Instruments no aparelho continua pendente (abaixo).

- `Connectivity` (`Must/Services/Connectivity.swift`): `NWPathMonitor` → `online / constrained / offline` + `isExpensive`. Publica no main (`@Observable`) e espelha num `Mutex` que o `HTTP` lê de qualquer thread.
- `AppNetwork.session` (uma sessão): timeout 8 s por request, 20 s por recurso, `waitsForConnectivity = false`, 4 conexões por host. Download de mapa segue na sessão própria (`PackDownload`), intacto.
- `HTTP` (`Must/Services/Network.swift`): offline falha na hora com `ServiceError.offline` (nada sai); GET transitório (timeout, conexão perdida, 5xx, 429 com Retry-After ≤ 5 s) repete até 2 vezes com backoff 0,5/1 s e jitter; POST nunca repete; `HTTP(kind: .prefetch)` manda `allowsConstrainedNetworkAccess = false`; AeroDataBox com `retries: 0, breaker: nil`.
- Disjuntor por serviço (`CircuitBreaker`, `Must/Services/NetResilience.swift`): 3 falhas seguidas abrem por 2 min, depois 1 tentativa de meia-abertura; `ServiceError.circuitOpen`.
- Dedupe (`InFlight`): dois GETs iguais em voo viram uma requisição. POST não entra.
- Fila de saída (`OutboxItem`, `Must/Services/Outbox.swift`), no schema da região: `flightStatus` (passa pelo `FlightStatusUpdater.run`, então respeita `FlightPolicy` e a cota; sem rede não marca o trecho) e `readLink` (sem rede, o link entra na fila; ao reenviar, a legenda fica guardada e o Adicionar a usa). `resolvePlace` não entrou: `Place.resolveQueued` já é a fila do Places. Reenvio: na abertura e quando o chip volta a "online". Offline não conta tentativa; 6 tentativas que falham desistem (backoff até 30 min).
- Adicionar: "N esperando internet" quando há itens na fila.
- Home: o chip agora diz "sem internet · offline ok" quando `Connectivity` está offline (antes era "sem dados ao vivo" só pra erro/menu).
- Foto de fundo (`TintedPhoto` → `PhotoLoader`): cache primeiro (memória → disco em `Caches/must-cache`, qualquer idade → rede só sem cópia ou com cópia de mais de 30 dias). Sem imagem e sem rede: gradiente da cor, sem spinner. Substituiu `AsyncImage`.
- Lugar › 3D: botão "3D" fica esmaecido e desabilitado sem rede (acessibilidade: "precisa de internet"). No 3D, sem rede ou com a Look Around sem resposta em 6 s: aviso discreto "sem conexão · o 3D precisa de internet" com Fechar.
- Chamadas que dependem de rede saíram do main: as providers já eram `struct` sem isolamento (execução fora do main); o que ficou no main é a orquestração (`SyncCoordinator`, `FlightStatusUpdater`, `ETACache`, `TipsModel`) e as escritas SwiftData.
- `.task(id:)`: dicas do Lugar (`PlaceView`) viraram `.task(id:)` cancelável. Os outros `Task {}` de ações do usuário ficaram (sem efeito de tela presa medido).

**Debug.** `-debugNetwork offline` (força offline; `Connectivity` não liga o monitor) e `-debugNetwork slow` (3 s de latência e 30% de falha por tentativa). Desligados sob XCTest.

**Simulador (prints em `build/qa/`, não commitados).**
- `offline`: Início com chip "sem internet · offline ok"; Lista, Adicionar e Lugar abrem sem tela presa; Lugar com "3D" esmaecido; 3D com o aviso.
- `slow`: Lugar abre normal, 3D habilitado.
- Não medi tempo de hang nem Time Profiler (Instruments não roda aqui sem o aparelho). Foto offline: o Lugar j18 mostrou a foto, mas não confirmei se veio do disco ou de uma sessão anterior.

**Testes.** 361 → 377 (16 novos em `MustTests/NetResilienceTests.swift`: 11 de `HTTP` com `NetStub` por host, 5 de fila/FlightPolicy). Todos passando.

**Ficou de fora.** Medição no iPhone com Instruments e Network Link Conditioner (pendente do Vinicius). Limite de 300 MB LRU do cache de foto (não implementado). Pré-download no Wi-Fi e "dia salvo offline" (A.5). Arranque (A.6). Foundation Models (A.7). Cancelamento de requisição quando todos os interessados saem do dedupe (a Task segue até o fim).

**A.5 · Dia offline (prompt 18 · A.5).** `DayPrefetch` (`Must/Services/DayPrefetch.swift`) roda ao aceitar o dia (Montar), às 07:00 com o app aberto e quando o Wi-Fi volta (hoje e amanhã). Só no Wi-Fi, fora do Modo de Pouco Dados e sem medido (`PrefetchPolicy`). Baixa a foto principal de cada parada (Commons com cache, ou a da lista; **sem Google**) e a previsão da cidade. **Não** chama Routes nem Street View (custam cota) e **não** baixa o mapa (~100 MB): a Hoje só mostra "mapa de … não baixado · baixar". Estado no `PlannedDay` (`offlineSavedAt`, `offlineDone`, `offlineTotal`). Hoje: "dia salvo offline ✓", "salvando… 3/7", "salvo 5/7 · completa no Wi-Fi", "salva no Wi-Fi". Testes: `MustTests/DayPrefetchTests.swift` (10). Simulador: `-debugNetwork wifi -debugScreen aceitar` → "dia salvo offline ✓" (`build/qa/a5-wifi-salvo.png`); `-debugNetwork celular -debugScreen aceitar` → "salva no Wi-Fi" (`build/qa/a5-celular-aceitar.png`); `-debugNetwork offline -debugScreen hoje` depois de salvar → Hoje completo com "dia salvo offline ✓" (`build/qa/a5-offline-hoje.png`).

**A.6 · Arranque.** Medido no simulador (iPhone 17, iOS 26.5, Debug), 3 aberturas a frio por fase, `LaunchTiming` (só DEBUG, categoria `launch`):

| Medida | Antes | Depois |
|---|---|---|
| Primeiro frame, desde o processo | 726–849 ms | 602–660 ms |
| Primeiro frame, desde o `init` do App | 292–356 ms | 163–182 ms |
| Início da primeira sincronização | ~330 ms (com o primeiro frame) | ~2,3 s (espera 2 s) |
| `init` do App, desde o processo (pré-`main`, fora do nosso código) | 433–492 ms | 439–477 ms |

- `StartupSync`: a primeira sincronização espera 2 s; abertura, `.active` e "voltou a rede" viram um pedido só. Antes, a sincronização disparava duas vezes no arranque.
- Abas montadas na primeira visita e vivas depois (`RootView`). Antes as quatro subiam no arranque, e o Mapa pedia rotas (`MKDirections`) e criava o `MLNMapView` antes do primeiro frame. Agora o MapLibre é criado uma vez, na primeira vez que o Mapa abre; trocar de aba não recria.
- Volta do background: `syncIfNeeded` já tinha o limite de 6 h. Mantido.
- Não medi com `-debugNetwork slow`/`offline` antes da mudança (a linha de base foi só de primeiro frame). Com as duas: primeiro frame ~630–655 ms e sincronização encerrada em ~2,3–2,4 s (com cache de previsão).
- Ficou de fora: o pré-`main` (~450 ms, dyld e inicializadores estáticos) não é nosso código; não investiguei.

**A.7 · Foundation Models.** Nenhuma sessão é criada na abertura do app (o `ChatModel` não cria nada em `init`; `Services` só cria o `DayPrefetch`, sem modelo). A sessão do Assistente é criada no ponto único `ChatModel.makeSession` (contador `sessionsMade`). Quando o Assistente abre, `warm()` cria uma sessão e chama `prewarm()` numa `Task.detached` (fora do main); ela vale pra primeira pergunta por 60 s. Quando a tela fecha, a pergunta em curso é cancelada (`asking?.cancel()`) e a resposta parcial não vira mensagem. Outras sessões (Montar, Adicionar por link, Dicas, Ticket, Experiências) já eram criadas só na ação do usuário; não mexi. Testes: `MustTests/AssistantWarmTests.swift` (3). Não dá pra medir no simulador (sem Apple Intelligence).

**A.8 · Testes e o que só o iPhone mede.**
- Testes novos: `StartupSyncTests` (4), `DayPrefetchTests` (10), `AssistantWarmTests` (3). Suíte completa: **395** testes passando (base 378).
- Simulador: nenhuma tela presa com `-debugNetwork slow` e `offline` (Hoje e Início abrem em ~640 ms). Não rodei Network Link Conditioner nem 100% Loss no aparelho.
- **Só o iPhone mede:** Instruments (Hangs > 250 ms, SwiftUI, Time Profiler) e o pré-download real em Wi-Fi.
- Vinicius testou em 03/11 com Wi-Fi sem internet: só o 3D e as fotos falharam; o resto fluiu. Isso confirma o caminho offline; o pré-download de fotos sem internet fica pendente de teste no aparelho.

iPhone: [ ] medir com Instruments (Hangs + Time Profiler) — Vinicius

## Início novo (prompt 18 · B)

**Feito.** Card do dia com foto do bairro escurecida, "Hoje em <bairro>", selo (`StationStamp`), bloco Agora (fila, saia às, a pé), progresso em selos e "Ir agora" → Como chegar. Sem dia: "Hoje, pra onde?" com 3 bairros e "Montar por bairro". "Amanhã, pra onde?" com 3 cartões (foto, selo, contagem, chip de contexto, faixa da categoria). "Por perto" (uma linha), "gasto hoje" (orçamento fica em Ajustes › Dia, que já existia), "+" abre Adicionar. `HomeState` recalcula só no minuto, na posição (≥ 50 m), ao salvar (300 ms de silêncio) e ao voltar pra frente; `HomeModel` ficou intacto pro `OutsideBridge` e os testes.

**Prints** (`scripts/qa-screens.sh`, seção "Início novo"): `jp-inicio-sem-dia`, `jp-inicio-aceito`, `bh-inicio-sem-dia`, `bh-inicio-aceito`. Conferidos contra Home6.png / Home6BH.png. `-debugScreen inicio` agora apaga o dia de hoje antes de mostrar a Início (sem isso, um print "sem dia" herdava o dia aceito da rodada anterior).

**Testes.** `MustTests/AreaTests.swift` (15): tabelas decodificam e cobrem os bairros pedidos, vizinhos apontam pra área existente e são simétricos, lugar → bairro (nome, alias, centroide, cidade), índice (contagem, dominante, abertos, "hoje pra onde", "amanhã", bairro do dia), card do dia e data/cidade.

**Pendências**
- Horário no aparelho: o seed JP tem horário em 1 de 103 lugares e o BH em nenhum. No simulador, "Hoje, pra onde?" cai no fallback (3 bairros com mais musts, subtítulo "nada aberto agora · os 3 com mais musts"). No iPhone os horários vêm do sync do Places; confirmar lá.
- Layout: compactado (card do dia 320 pt, cartões de amanhã 116 pt, espaços menores) pra que o gasto e o "Perto de você" fiquem acima da tab bar sem rolar em iPhone 17. Conferir no aparelho.
- Distância acima de 2 km mostra só a distância ("5,2 km"), sem "a pé". O trecho de trem é do Como chegar.
- Cores aproximadas: Inokashira, JR Nara, JR Sagano e o ônibus de BH e Kyoto. Metrô de BH não está na tabela de bairros.
- "Melhor avaliado" pra foto do bairro = verificado no Places › ordem do board (o board não guarda nota). Foto é Commons via `PlaceHero`, não Google (prompt 19).
- Não feito: reverse geocoding (`CLGeocoder`, fatia C); pré-download da foto dos bairros no Wi-Fi (hoje é cache sob demanda); "ver todos", "Montar por bairro" e o toque no cartão são TODO até a tela Bairros (fatia C); o "+" abre só Link/Nome (Texto é a fatia E).
- Tema da viagem (prompt 20): o selo usa `StampPalette` (ponto único), sem cor de país.
- Medição com Instruments e Network Link Conditioner no aparelho (hangs da Início): pendente, como na parte A.
- Suíte: a primeira rodada completa caiu com "Test crashed with signal kill before establishing connection" (runner do simulador, não código). Simulador apagado (`erase`) e rodada refeita.


## Avisos do guia (prompt 18 · C.17)

**O que é.** O app avisa sem ser aberto: "Saia em 5 min pro <parada>", "Golden em 20 min · você está a N min do <foto>", "<lugar> abre agora · está a N min". Só do dia aceito de hoje, só de agora em diante, no máximo um aviso a cada 45 min (prioridade: saída > golden > abre agora). Tudo local, sem push e sem rede. Ajustes › Dia › "Avisos do guia" (ligado por padrão); desligar tira os avisos pendentes.

**Como se calcula.** Saída = hora da parada − deslocamento estimado pelo solver (a pé até o andar do dia, senão metrô) − 5 min; o aviso chega 5 min antes dessa saída. Golden = início da janela (manhã ou tarde) menos 20 min, pra lista photo cuja parada cai perto da janela. Abre agora = primeiro horário de abertura do lugar depois do início do dia, se ele estava fechado e a parada é depois dessa abertura. A origem é a posição de agora se estiver a até 40 km da cidade, senão o centro. Não usa GPS em segundo plano nem a Routes. Os avisos usam trigger de calendário no fuso da região.

**Permissão.** Só é pedida no aceite do dia (Montar › Aceitar). Recálculos (gravações, volta do app, 済, desfazer, o toggle) não pedem. Sem permissão, nada é agendado.

**Identificadores.** `guide.<AAAA-MM-DD>.<n>`. O agendador só remove e recria os `guide.*`; os lembretes de ingresso (`ticket.leave.*`) e de voo (`flight.*`) não são tocados. Se o plano não muda, nada é reagendado.

**Testes.** `MustTests/GuideNudgesTests.swift` (12 de função pura: saída, golden com e sem janela, abre agora, prioridade, espaçamento de 45 min com o limite exato, só futuro, horas já tocadas, ids) e `GuideSchedulerTests` (6 com fake de central: troca só `guide.*`, reagendar sem mudança não toca nada, dia sem aceite, desligado, permissão negada, desligar). Suíte completa: **413** passando (base 395).

**Debug.** `-debugScreen avisos` lista no log (categoria `guide`) os avisos do dia aceito, sem agendar. Ex.: `log show --predicate 'subsystem == "dev.viniso.must" AND category == "guide"'`.

**Simulador (Japão, 15/11 09:00 JST, dia aceito).** Saídas previstas: 09:25 Santuário Meiji ("chega às 09:50", ~20 min); 11:15 Ramen Hōsenka (~11 min, chega 11:31); 14:11 Koffee Mameya (~14 min, chega 14:30); 18:40 Udatsu Sushi (~15 min, chega 19:00). Espaçamento ok. Print do toggle em Ajustes › Dia em `build/qa/c17-ajustes.png`.

**Ficou de fora / não verificado no aparelho.**
- O agendamento real na Central de Notificações não foi visto no simulador: a permissão não pôde ser concedida por `simctl privacy` (sandbox), então o app não agendou nada de fato. Falta: aceitar o dia com permissão no iPhone e conferir que os avisos chegam no horário.
- Golden e "abre agora" aparecem só nos testes; o dia de QA não tinha parada de foto na janela de golden nem lugar fechado ao começar o dia.
- Os tempos de deslocamento são a estimativa do solver, não a matriz do Routes: o aviso pode sair alguns minutos fora do tempo real de trajeto.
- Pendente do Vinicius: testar no iPhone se o aviso chega com o app fechado.
