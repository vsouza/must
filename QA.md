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

## Colar texto (prompt 18 · E)

**Entregue.** E.21: o Adicionar ganha o seletor Link · Texto · Nome ("Nome" abre a busca por nome existente). Em Texto, o pipeline roda no aparelho: URLs (NSDataDetector) viram links; o texto vai em blocos de até 3.000 caracteres pro Foundation Models (`@Generable ParsedTravelText`, com nomes `SuggestedDay`, `TextPlace`, `TextTipDraft` pra não colidir com `ExtractedPlace` e `Tip`); sem modelo, o parser por regex (listas, títulos, frases com "no/na/em" e nomes em Title Case, dicas por verbo de instrução ou por ingresso/passe). Categoria pela palavra do nome e do trecho, e depois pelo `primaryType` do Places. Conferência no Places e junção de duplicados pelo `PlaceResolver` do prompt 16. E.22: tela conforme `ColarTexto.png` (texto marcado por cor, contadores, grupos por dia com "virar dia N", dicas que vão pras notas ou pra Carteira, "Só salvar" e "Adicionar N e criar dia K"). `PlannedDay.focusAreaName` guarda a área do dia (a fatia C troca por `focus`). E.23: sem rede, a conferência entra na fila de saída como `OutboxKind.conferText` (o `Outbox.drain` recebe o provedor de Places), o botão mostra "N esperando internet" e, ao reabrir o texto, a conferência feita é aplicada.

**Código.** `Must/Services/Ingest/TravelText.swift` (parser e tipos), `Must/Services/Intelligence/TravelTextExtractor.swift` (Foundation Models, blocos, merge), `Must/Services/Ingest/TextConference.swift` (fila), `Must/Features/Add/PlaceImport.swift` (gravação dos lugares, tirada do `AddLinkView.save` e usada pelos dois fluxos), `Must/Features/ColarTexto/` (modelo, view, destaque e amostra em DEBUG). `PlaceExtractor.isPlausible` ficou internal; `ExtractedPlace.dayIndex` novo (o `PlaceResolver.combine` preserva).

**Testes.** 406 passando (base 395 + 11 em `MustTests/ColarTextoTests.swift`): amostra igual à fixture `MustTests/Fixtures/colar-texto-amostra.txt`; 2 dias, 8 lugares, 2 links, 3 dicas; categorias sem Places; blocos ≤ 3.000 caracteres; merge; Carteira ("Tokyo Subway Ticket 72h", passe de trem); análise com Places fake (8 conferidos, 6 marcados, grupos); sem Places; fila offline e drain; gravação (6 lugares, 2 dias de 3 paradas, 1 item na Carteira, dicas nas notas).

**Prints (simulador "Must-Texto", iPhone 17, Debug, `build/qa/`, não commitados).**
- `xcrun simctl launch 9826BD97-6F13-4C68-90E6-4B044D56602F dev.viniso.must -skipOnboarding YES -region jp -debugPlaces fake -debugScreen colar-texto:amostra` e `xcrun simctl io 9826BD97-6F13-4C68-90E6-4B044D56602F screenshot build/qa/colar-amostra-1.png`. Mostra o seletor com "Texto" ativo e o texto marcado (comer, ver, beber, área tracejada, dica âmbar, links em preto).
- Revisão (coordenador): `build/qa/colar-recolhido-2.png`, mesmo comando. Card recolhido (~200 pt a partir do dia em foco, fade, última linha cinza, "ver tudo"), contadores, cartão do dia com o selo do bairro (渋谷), "virar dia 1" e os botões fixos embaixo. A lista do dia rola por trás do fade; dicas e links ficam abaixo, sem print.
- Offline (`-debugNetwork offline`) e Foundation Models: não rodados. O simulador não tem Apple Intelligence, então o aparelho cai no parser por regex.

**Ficou de fora.** Fallback na nuvem (Haiku) pro Texto: o fluxo do link já tem o seu; o Texto não chama a nuvem. Nomes em japonês (`nameLocal`) no parser de regex. `StationStamp` não existe neste worktree, então a Texto não mostra selo de estação. Leitura de links no `-debugPlaces fake` usa legenda de mentira (sem rede).

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

## Fotos do Google (prompt 19)

**Chamadas reais (simulador "Must-Fotos", 03/11, o máximo acordado: 4 lugares, uma vez cada).** Text Search (IDs/Essentials, pra achar o placeId, como no teste de 03/11), Details com `photos` (sincronização só desses lugares, `-debugSyncOnly`) e uma `/media` por lugar ao abrir o Lugar. Total: **4 Text Search + 4 Details + 4 `/media` = 12 chamadas**. Contadores no fim: `placesEssentials` 4, `placesPro` 4, `placePhotos` 4. Nenhuma chamada a AeroDataBox ou Anthropic. Não fiz lote real (Ajustes › Dados › Baixar) pra não gastar cota.

| Lugar | Região | Resultado |
|---|---|---|
| Fuunji | JP | foto da fachada (placa FUUNJI), crédito "FOTO · GOOGLE · @N. HAJIME" |
| Udatsu Sushi | JP | foto do balcão, crédito "@UDATSU SUSHI" |
| Mercado Central | BH | foto do balcão de queijos, crédito "@THALES" |
| Museu Inimá de Paula | BH | foto da pintura (campo de arroz), crédito "@MUSEU INIMÁ DE PAULA" |

**Verificado no simulador:**
- Contador sobe 1 por lugar novo (`placePhotos` 0 → 4), e não sobe ao reabrir (Lugar e Lista: 4 → 4).
- Lista (`lista:eat`): miniatura do Mercado Central com cantos 14 pt; os outros lugares seguem com o gradiente da cor.
- Modo avião (`-debugNetwork offline`, Mercado Central): hero aparece do disco, 3D esmaecido, nenhuma chamada.

**Prints (em `build/qa/`, não commitados):**
- `build/qa/fuunji-try1.png`, `build/qa/udatsu.png`, `build/qa/mercado-central.png`, `build/qa/museu-inima.png`: hero com foto e crédito.
- `build/qa/lista-eat-thumbs.png`: Lista com miniatura.
- `build/qa/offline-mercado.png`: hero offline.

**Comandos (simulador BD4F5784…, container `…/Library/Preferences/dev.viniso.must`):**
- Sincronizar só alguns lugares: `defaults write <P> region jp|bh`, `defaults write <P> debugSyncOnly -string "j01,j05"` (BH: `p01,p11`), relança. Depois apaga `debugSyncOnly`.
- Abrir o Lugar: `defaults write <P> debugScreen -string "lugar:j05"` e relança.
- Lista: `debugScreen -string "lista:eat"`. Offline: `debugNetwork -string offline`.
- Fake (sem cota, pros prints de UI): `debugPhotos -string fake`.

**Não capturado (pendente):**
- Ajustes › Dados (MB do mês, cache, lote). A tela está pronta e compila, mas o print exige rolar até a seção Dados, e o simulador não rola sozinho. Fica pro Vinicius no iPhone.
- Lote real "84 de 130": não rodado, pela cota.

**Ficou de fora:**
- Galeria (deslizar): código pronto (até 5 páginas, uma `/media` por deslize), não testado deslizando (gastaria cota).
- Card "Agora" da Home e cards de bairro: fatia B, não toquei.
- Mapas offline não entram em "MB do mês" (baixam por sessão própria).
- Lugar novo (Adicionar antes de salvar): mostra gradiente até sincronizar (candidato sem Details não tem foto).

**iPhone (Vinicius):** [ ] conferir o hero e a galeria com fotos reais · [ ] Ajustes › Dados: MB, cache e lote no Wi-Fi · [ ] Modo de Pouco Dados: sem foto nova fora do Lugar aberto

## Tema da viagem (prompt 20)

**Feito.** `TripTheme` (tokens por país, tabela aberta por ISO 3166 em `TripTheme.byCountry`), injetado em `MustApp` com `Region.country`. Lavado do topo (`.tripWash()`, 300 pt, ou cor sólida `tripSoft2` em 120 pt com "Reduzir transparência") em Início, Hoje, Musts e Viagem. Selos (`StationStamp`) com tinta do país sobre papel e fundo `stampInk` a 55% no card do dia (50% nos cartões de bairro). Rótulo da cidade/dia em `tripInk`, ponto da aba ativa e ponto de "Amanhã, pra onde?" em `trip`, anel do dia de hoje na Viagem em `trip`. Bandeira vetorial de 22 pt (`TripFlag`) ao lado da data na Início e no card de cada trecho na Viagem. Identidade (verde, azul, tinta, links, listas, trem, mapa) não muda.

**Prints** (`scripts/qa-screens.sh`, seção "Tema da viagem"): `tema-jp-inicio`, `tema-jp-hoje`, `tema-jp-musts`, `tema-jp-viagem`, `tema-bh-inicio`, `tema-bh-hoje`, `tema-bh-musts`, `tema-bh-viagem` (em `build/qa/`, não commitados). Conferidos contra Home6.png (Japão) e Home6BH.png (Brasil): lavado, bandeira, rótulo, pontos e selos batem.

**Testes.** `MustTests/TripThemeTests.swift` (12): tokens exatos de JP e BR, mapa região → país, tabela aberta (chaves ISO, país desconhecido cai no neutro), tons do país não usam cor de identidade, cores de identidade fixas, forma do lavado (300 pt / 120 pt sólido / sem lavado), fundo do selo a 55%, bandeira só pra JP e BR. Suíte completa: **422** passando (base 410).

**Diferenças em relação aos Home6**
- A troca de região usa `withAnimation` de 0,4 s em `RegionStore.switchTo`, mas o `.id` da raiz recria a árvore (troca de container). Por isso a transição de cor pode aparecer como troca direta; medir no aparelho.
- Hoje ganhou o rótulo "Tóquio · dia 1/5" (ou "Belo Horizonte") em tom do país, que não existia na tela antes.
- Viagem: não há coleção de selos ainda; a borda `trip` ficou no anel do dia de hoje.
- Cartões de bairro com 50% de fundo (o Home6 mostra 50%; o card do dia 55%).

**Pendente**
- Guia (prompt 18 C): usar `.tripWash()` antes do `.background` da tela e `StationStamp(surface: .photo / .paper)`.
- Coleção de selos na Viagem (quando existir) deve usar `theme.tripColor` na borda.
- `StationStamp` perdeu os parâmetros `ring:` e `fill:` (agora `surface:`, `filled:`, `fillOpacity:`). Quem já tiver código com a API antiga precisa migrar.

## Bairros e Guia (prompt 18 · C.14–16)

**Automático.** Suíte completa no simulador (iPhone 17): **482 testes em 89 suítes, todos passando**. Novos: `AreaFocusSolverTests` (Shinjuku+ monta Nakano → Fuunji → Gyoen no golden → Golden Gai; offline com matriz vazia dá a mesma ordem; Ginza nunca entra com foco; frase "Comece por…"; determinismo), `AreaFocusPlanTests` (vizinhos até 15 min, simetria da tabela, bairro desconhecido), `BairrosGuiaTests` (raio ∝ √musts com teto, projeção da câmera no centro e a 1 km, norte para cima, deslocamento pela tabela e pela estimativa, pino do mini-mapa).

**C.15 · solver por área.** `DayRequest.focus = .area(id:, includeNeighbors:, maxHopMinutes:)`. `AreaFocusPlan` monta o conjunto (bairro + vizinhos da tabela, sem rede). Candidato fora do foco sai em silêncio. Pontuação: trocar de bairro custa o trecho da tabela (25 min se não há ligação direta), voltar a um bairro já deixado custa +40, o que fecha dentro da janela sai antes. A explicação abre com a frase da ordem. Regras do CLAUDE.md (uma refeição por janela, reservas âncora, cidade, orçamento) continuam as mesmas.

**C.14 · Bairros** (`Must/Features/Bairros/`). Mapa papel (MapLibre existente) com uma bolha por bairro (raio ∝ √musts, cor = o que mais tem, kanji no maior, contagem em mono), tempos entre vizinhos tracejados, você (azul). Sheet do bairro: selo (`surface: .paper`), nome 30/600, musts/abertos/tempo, barra de mistura, "Junto, a poucos minutos" (`LineChip` com a cor da linha), frase do solver, "Ajustar" e "Montar <bairro>+" (grava o dia com foco e abre o Guia). Início: "ver todos", "Montar por bairro", os 3 cartões de bairro e os 3 bairros do "Hoje, pra onde?" abrem a tela. O card do dia abre o Guia; "Ir agora" continua indo pro Como chegar.

**C.16 · Guia do dia** (`Must/Features/Guia/`). Mini-mapa com o percurso (trecho de trem na cor oficial, a pé pontilhado, paradas numeradas). "Guia de hoje · Shinjuku+" com o selo. Cada parada: hora, kanji do bairro, cartão com a foto principal (`PlaceThumb`) e a cor do tipo a 50%; atual em verde com "Como chegar · N min"; golden em dourado; noite em cinza; feito com 済. Entre as paradas: chip da linha + minutos, ou "a pé N min", ou "metrô · N min". Deslocamento pela tabela de vizinhos (offline); sem ligação, a estimativa de sempre. Fim com o último trem (`LastTrains`, o que já existia). Base: "Trocar" (Montar) e "Ir pro <próximo> · saia HH:MM".

**Prints** (`build/qa/`, não commitados; `scripts/qa-screens.sh` ganhou a seção "Bairros e Guia"): `bairros-mapa`, `bairros-shinjuku`, `guia-shinjuku`. Conferidos contra `Bairros.png` e `GuiaBairro.png`: a sheet e o Guia agora sobem acima da tab bar (ajuste de 96 pt, como no Início).

**Diferenças dos PNGs e por quê.**
- O seed JP não tem Gyoen nem Golden Gai: o "Shinjuku+" do simulador usa o que o seed tem (Menya Kaijin, Koffee Mameya, Udatsu), não o exemplo do mock. O exemplo está nos testes do solver (fixtures). Não mexi no seed (ele cresce no board do Vinicius).
- Bolhas: o centro inicial da câmera não enquadra todos os bairros (abre no centro da região); o Shinjuku do mock fica fora da tela no primeiro quadro.
- Trecho de trem: só o que está nos trilhos aproximados (JY, JC aproximada, H, G…). Linhas sem ligação na tabela de vizinhos caem na estimativa.
- Último trem: vem do `LastTrains` existente (com "Último … · HH:MM"), chip neutro em vez do chip com a cor da linha.
- Fotos das paradas: `PlaceThumb` (caminho do prompt 19), não Commons.
- Filtro (ícone do canto do mock) e "Ajustar" com ação própria ficaram de fora; "Ajustar" abre o Montar de hoje.
- Plataforma/saída ("saída sul") não existe nos dados: só "a pé N min".

**Pendências (só no iPhone).**
- Instruments e Network Link Conditioner nas telas Bairros e Guia (hangs > 250 ms).
- Bolhas com GPS real: distância da sheet e ordem da frase com horários do Places (o seed JP tem horário em pouquíssimos lugares).
- Toque na bolha e a sheet com o mapa em movimento.

iPhone: [ ] medir Bairros e Guia com Instruments — Vinicius

## Rodada 21 · fatia 5 (prontidão da viagem, 03/11)

**Suíte completa** (simulador BD4F5784, iPhone): **514 testes em 95 suítes, todos passando**. Novos: `TripReadinessTests` (8 testes: TripInfo 11–24/11 e fuso Asia/Tokyo; rota Tóquio → Kyoto → Tóquio contígua; datas das cidades dentro da viagem; seed JP válido (cidade na viagem, lista existente, ids únicos, coordenadas no Japão, reservas dentro da viagem); catálogo de mapas decodifica com Tóquio e Kyoto; Suica e JR Pass entram uma vez, não voltam se apagados, e não entram em BH).

| # | Item | Status | Onde está / o que foi feito |
|---|---|---|---|
| 1 | `TripInfo` JP | **OK** (teste novo) | 11/11 → 24/11, casa Naka-Meguro, tz Asia/Tokyo. Cidades: tokyo1 **13→17**, kyoto 17→20, tokyo2 20→24. tokyo1 começa 13 (não 11) de propósito: o voo NY→Tóquio sai 12/11 e pousa 13/11 (`seed-jp.json`, evento "chega no dia seguinte"). 11/11 é a saída de BH. |
| 2 | Seed JP válido | **OK** (teste novo) | 105 lugares, 8 listas, 3 cidades; zero ids repetidos, zero cidade/lista órfã, todas as coordenadas dentro do Japão. Validação de schema feita por decodificação (`BoardCodec.decode`) + teste de regras; sem `jsonschema` no ambiente. |
| 3 | Mapas offline Tóquio e Kyoto | **Catálogo OK; download NÃO testado** | `data/map-packs.json`: `jp-tokyo` (Tóquio) e `jp-kansai` (Kyoto · Nara). Ajustes › Mapas offline lista `MapPack.catalog` filtrado pela região (`OfflineMapsView`). Nada foi baixado nem subido. Pendência: baixar no Wi-Fi no iPhone (checklist). |
| 4 | Voos importáveis | **Caminho OK; teste real pendente** | "Trazer ingresso" em Voos (`FlightsView`), Reservas e Agenda → `TicketImportModel` → `TicketRevisarView` → `FlightFromTicket` (template escolhido por `FlightRules.templateKey`). JSON: `board.flights` no import. Não testado: leitura real de PDF/.pkpass/foto no aparelho, e AeroDataBox (não chamado, como pedido). |
| 5 | Checklist intl-japan | **OK** (testes existentes) | `Must/Data/checklists/intl-japan.json` carrega; voo que toca o Japão ganha o modelo (`ChecklistTests`, `FlightTests` ~245: 12 itens, prazo do check-in, Visit Japan Web marcado pela Carteira). Sem teste novo. |
| 6 | Carteira: Suica e JR Pass | **Feito agora** (teste novo) | Antes só existiam no `WalletDemo` (DEBUG). Agora `WalletStarter` põe **Suica** (sem saldo; anotado à mão, aviso de recarga) e **JR Pass** (sem datas: você preenche do voucher) na Carteira do Japão, uma vez. Ids em `Settings.seenSeedIds` (prefixo `wallet-starter-`): apagar não faz voltar. BH não recebe. |
| 7 | Export do board | **OK** (testes existentes) | `BoardCodecTests`: `exportMatchesSeed` e `roundTripIntoFreshContainer` (export → decode → import em container novo → export igual), nas duas regiões. Ajustes › Board completo › Exportar board (.json). Sem teste novo. |
| 8 | `docs/checklist-viagem.md` | **Feito** | Commitado. Só texto; nenhuma chave aparece. |

**Chaves.** Não li nem imprimi `Secrets.plist`; só copiei o arquivo pro worktree (gitignored). Nenhuma chamada paga: AeroDataBox, Google, Anthropic e Open-Meteo não foram chamados nesta fatia.

**Não testado (só no iPhone).**
- Baixar Tóquio e Kyoto em Ajustes › Mapas offline, e abrir o mapa em modo avião.
- Leitura real de PDF/.pkpass/foto em "Trazer ingresso" (câmera e Fotos).
- Lote de fotos no Wi-Fi (Ajustes › Dados) com o board JP.
- Permissão de notificação do "Avisos do guia".
- Modo avião de ponta a ponta (Hoje, dia aceito, mapa, Carteira).
- Prints `scripts/qa-screens.sh` de JP não foram refeitos nesta fatia (fica pra fatia 6).

## Rodada 21 · fatia 1 (performance)

**Método.** Medição por prints em `MustTests/PerformanceRodada21Tests.swift` (sem asserção de tempo). "Antes" foi rodado no commit `08e22c8` (código antigo, só o teste novo); "depois" na suíte completa depois dos commits de A.2–A.5. Simulador B3980C62 (erased), Debug. Os números são de uma execução por lado: ordem de grandeza, não benchmark.

| Medida | Antes | Depois |
|---|---|---|
| Início · 50 bodies × 103 lugares (antes: `HomeModel` montado e recalculado a cada body; depois: `HomeState.refresh` no gatilho + leitura por body) | 34–36 ms (≈0,7 ms por body) | refresh 2–4 ms, 1× por gatilho; leitura por body ≈ 0,02 ms (50 leituras = 20 µs), 1 recálculo |
| Mapa · pinos · 50 bodies × 2 montagens (antes: lista refeita em `scene` e em `nearby`) | 50–52 ms | 1,6 ms, 1 montagem (`PinsMemo`, chave igual) |
| `PlaceHours.weekMinute` · 20 000 chamadas | 8,5 ms | 7,9 ms (ganho pequeno: `Calendar` já era barato no simulador; a troca evita a alocação e o custo sobe em aparelho mais antigo) |

**Feito**
- **A.1 Início (memo).** A Início já não monta `HomeModel` no `body`: `HomeState` (prompt 18 · B) calcula dia, bairros, abertos e linhas no gatilho (minuto, posição ≥ 50 m, salvar, voltar). `HomeModel` ficou só pro `OutsideBridge` (widgets/Live Activity) e pro `QAScenarioTests`. Nada novo a fazer além da medição.
- **A.2 Pinos do mapa.** `PinsMemo` (`Must/Features/Map/PinsMemo.swift`) guarda os pinos por chave: revisão do conjunto de lugares (`PlacesRevision`), minuto, fuso, paradas de hoje/amanhã com 済, foco, seleção, cidade, posição e raio a pé. Camadas ligadas não entram (pinos são todos; a camada filtra depois). O `body` do mapa lê `pins` várias vezes e só a primeira monta.
- **A.3 LazyVStack.** Lista (`ListView`) e hub de Musts (`MustsHubView`) passaram a `LazyVStack`. Board já é `List` (lazy) e cada grupo é uma `Section`: não mexi.
- **A.4 Calendar.** `PlaceHours.weekMinute` usa um `Calendar` por fuso, guardado num `Mutex<[TimeZone: Calendar]>` (thread-safe, Swift 6).
- **A.5 Dedupe (`InFlight`).** Cada entrada guarda os interessados. Quando sai o último (cancelou ou terminou), a `Task` compartilhada é cancelada e a entrada some. Testes: `MustTests/InFlightCancelTests.swift` (cancelar o único interessado cancela a requisição e zera o `count`; cancelar um de dois não afeta o outro).

**Ficou de fora (anotado)**
- `TransitLoader.load(region)` é chamado a cada `body` do mapa (`transit` em `MapView`). Não medido; candidato a memo na próxima rodada.
- Instruments no aparelho continua pendente (não há aparelho nesta rodada).

**Testes.** Suíte completa no simulador B3980C62: `✔ Test run with 512 tests in 96 suites passed`.

## Rodada 21 · fatia 0 (layout igual aos PNGs, 03/11)
Conferido no simulador (9826BD97) com `-region jp -region.auto NO` contra `design/screens/*.png`: Início (`inicio`, `inicio-aceito`), Hoje (`hoje-aceito`), Guia, Bairros, Musts, Lista (`lista:eat`), Viagem › Voos, Ajustes, Nova lista, Editar lista, Mapa.
- **Corrigido:** `NewListView` (Nova lista e Editar lista) tinha o botão "Criar / Salvar" sobreposto ao fim do scroll (fotos de fundo e o crédito da foto ficavam atrás do botão). Agora o botão fica fora do scroll, num VStack. A "~22 pt pra esquerda" não apareceu nos prints: as margens saem simétricas (22/22 pt); se o deslocamento aparecer no iPhone, é outro problema.
- **Corrigido:** fade branco por trás da tab bar em `RootView` (116 pt, sem toque), pra todas as telas que rolam. Antes a última linha cortava seco embaixo da pílula.
- **Conferido sem mudança:** Início e Hoje com cabeçalho, cards e blocos em stack; metadados de linha única com `lineLimit(1)`; chips em faixa horizontal; Musts com grade de 2 colunas e placeholder de cor.
- **Dynamic Type XXXL:** `xcrun simctl ui <udid> content_size extra-extra-extra-large` aplicado antes de abrir Início, Hoje, Musts, Lugar, Viagem e Mapa. Nos prints não deu pra confirmar que o texto cresceu (o `-UIPreferredContentSizeCategoryName` não foi testado); a checagem de sobreposição ficou incompleta e precisa de nova rodada com o tamanho confirmado. Resetado para `large` depois.
- **Ainda difere dos PNGs:**
  - Início: o chip "offline ok" some quando há rede (no PNG aparece sempre); o card do dia usa foto de fundo em vez do gradiente escuro do PNG (regra do app: foto em todo lugar que mostra um lugar).
  - Hoje: o botão flutuante (sparkles) fica sobre a hora da linha 4 quando a lista está no topo; o PNG tem o mesmo botão com mais folga entre as linhas.
  - Musts: o app usa a foto do Commons com o gradiente a 82%, então o contraste varia com a foto; o PNG usa tons mais claros.
  - Mapa: "Pra onde hoje?" fica sob a hora da barra de status (mapa em tela cheia; não mexi).
- **Não verificado:** placeholder de cor em cada foto durante o carregamento (só com `-debugNetwork slow`); fica pra fatia 6.

## Rodada 21 · fatias 3–4

- **Reforço na nuvem (Colar texto):** só com menos de 2 lugares no aparelho, ajuste ligado e chave. Haiku (`claude-haiku-5-5`, effort low, sem thinking), uma tentativa, sem repetir. Sem rede entra na fila (`OutboxKind.cloudText`). Testes com `NetStub` em `MustTests/ColarTextoCloudTests.swift`. Nada de chamada real.
- **nameLocal:** "Fuunji (風雲児)" e "風雲児 Fuunji" viram `nameLocal`. Testes no mesmo arquivo.
- **Selo de grupo:** o kanji do bairro já era `StationStamp`; a linha pequena agora mostra "dia N" quando o bairro não tem sub.
- **Tinta do país (fatia 4):** os selos já leem `TripTheme.stampInk` pelo ambiente (`MustApp` injeta o tema da região). A coleção de bairros da Viagem ganhou `border: theme.tripColor` no `StationStamp`.
- **Pendente de QA no aparelho:** print de `colar-texto:amostra` fica em "Lendo o texto…" no simulador, sem resultado em 14 s. O `-debugScreen bairros` abriu o Mapa, não a lista de bairros. Conferir os dois antes de dar a fatia por fechada.

## Rodada 21 · fatia 2 (bairro pelo GPS, 03/11/2026)

- Feito: `CurrentAreaService` (actor, fora do main): tabela curada primeiro (polígono se houver, senão centroide a até 1,2 km); depois célula de ~300 m (`AreaGrid`), cache em `Caches/must-cache` (`DiskAreaCellStore`), `CLGeocoder` uma vez por célula, uma requisição por vez, offline usa o último valor.
- Feito: nome do geocoder vira bairro (`AreaNameMatch`, sem acento/caixa, "-ku"/"City"/"Ward" tirados se o nome inteiro não bater).
- Feito: Home sem dia aceito mostra "Hoje em <bairro>" com a foto do bairro; "Por perto · <bairro>" no cabeçalho da tela Por perto.
- Feito: `AreaCoverPrefetch` baixa uma capa por bairro do board só com `PrefetchPolicy` (Wi-Fi, fora do Pouco Dados), gera miniatura de 240 px no aparelho. Disparado junto do pré-download do dia (`runPrefetchPending`). Desvio: a capa é a de 1024 px que o Commons devolve (já era o que `PhotoLoader` guardava), não uma de 800 px.
- Pendente: a miniatura de 240 px ainda não é lida por nenhuma lista (a Bairros usa a foto grande); fica no disco pra quando a lista usar.
- Testes: `CurrentAreaTests` (12) e suíte completa verde (518 testes).
- Print: `qa/inicio-gps.png` (simulador, GPS simulado em Shinjuku, JP): "Hoje em Shinjuku".

iPhone: [ ] andar entre Shinjuku, Ginza e Shibuya e ver o bairro trocar (fora da tabela, a troca espera o geocoder) — Vinicius
[ ] sem sinal, abrir o app no bairro já visto: mostra o último bairro — Vinicius
[ ] Wi-Fi com Modo de Pouco Dados ligado: nada de capa nova — Vinicius

## Rodada 21 · fatia 6 (QA da rodada, 03/11)

**Automático.** Suíte completa no simulador: **547 testes em 99 suítes, todos passando**. Build de aparelho (`generic/platform=iOS`, sem assinatura) OK.

**Prints** (JP às 12:50 em Naka-Meguro e BH na Savassi, fakes de Places/Nearby/voo): Início, Hoje (dia aceito), Guia, Bairros, Lugar (Udatsu com reserva; Mercado Central), Musts, Viagem, Carteira, Voos, Compras, Colar texto (amostra). Conferidos contra `design/screens/`.

**Corrigido nesta fatia.**
- **Crash na troca de região no arranque** (SIGTRAP no SwiftData em `AppRoot.syncThenRefresh`): a sincronização da abertura espera 2 s e lia o `modelContext` da árvore que já tinha saído. Acontecia ao abrir com a região errada pro GPS — no iPhone, a primeira abertura no Japão. Agora o pedido leva contexto/container/geração da árvore e a árvore que sai cancela o pendente (`StartupSyncTests.cancelarDuranteOAtrasoNaoRoda`). Widgets e avisos do guia capturam o contexto antes do `Task`.
- Card "Hoje em <bairro>" da Início tinha altura fixa de 296 pt e cortava o "HOJE EM" no topo: agora cresce com o conteúdo.
- Fade global atrás da tab bar (fatia 0) removido: cobria o mapa e os botões do Lugar; cada tela já tem o seu.

**Ainda diferente / pendente.**
- Carteira em DEBUG (`-debugScreen carteira`) mostra Suica e JR Pass duas vezes (itens de partida + itens de exemplo). No uso normal só entram os de partida, e não duplicam um cartão do mesmo tipo.
- Colar texto (amostra, simulador): Meiji Jingu e Fuunji aparecem como "novo" mesmo existindo no board (Santuário Meiji, Fuunji) — o casamento de nomes não junta "Meiji Jingu" × "Santuário Meiji".
- Hoje: o botão flutuante do assistente fica sobre a hora da 4ª linha com a lista no topo.
- Dynamic Type XXXL não verificado nos prints (o `content_size` do simulador não refletiu).

**Pendências corrigidas depois da fatia 6 (03/11).** Suíte: 551 testes passam; build do aparelho ok.
- Colar texto: "Meiji Jingu" casa com "Santuário Meiji" (`PlaceMatcher.core` tira palavras de tipo: santuário/jingu/templo/parque/mercado…; nome próprio igual com ≥ 4 letras). Lugar do board com coordenada chute (`approx`) aceita o mesmo nome a até 2 km (Fuunji estava a ~1 km do chute do seed) e usa a posição do Places: aparece marcado, não riscado. Print da amostra: Meiji Jingu, Fuunji e Koffee Mameya "no board", marcados.
- Hoje: a timeline termina num fade branco sólido da altura do FAB pra baixo (cobre também a área embaixo da tab bar); a hora da linha de baixo não fica mais sob o botão.
- Dynamic Type: todas as fontes eram `fixedSize` (por isso o XXXL não mudava nada nos prints). Agora `MustFonts` usa `relativeTo:` pelo tamanho até 30 pt, com teto em `.xxxLarge` na raiz (`DynamicTypeSize.mustCap`); kanji e números de vitrine (> 30 pt) seguem fixos. Prints em XXXL de Início, Hoje, Guia, Musts, Lugar, Viagem, Carteira, Voos, Compras, Bairros, Nova lista: nada sobreposto; textos longos truncam com "…". Colunas de hora (Guia, proposta, Como chegar, Luz, sessões) não quebram mais ("09:4 / 8").
- Carteira em DEBUG: os itens de exemplo preenchem a Suica e o JR Pass de partida em vez de duplicar (conferido com instalação limpa).
- Continua: o toque em "Ajustar" na Bairros não foi exercitado no simulador (sem ferramenta de toque; a lógica tem teste). `-region.auto NO` trocar a região uma vez segue sem explicação (não se repetiu). Colar texto no simulador leva ~15 s na primeira abertura depois de instalar (modelo no aparelho carregando).

**Grupo 3 (05/11).** Suíte: 556 testes passam; build do aparelho ok.
- **Mapa do Guia em branco com uma parada só** (corrigido): `MapLibreView` ignorava o `.fit` de um ponto e o mapa ficava no 0,0 (mar cinza). Acontecia à noite, com só a última parada do dia. Agora centra no ponto (zoom 15).
- **Bairros:** sem bairro escolhido e sem você por perto, a câmera enquadra a cidade inteira (até 18 km do maior bairro, sem puxar Kyoto), como o `Bairros.png`; perto de você ou com bairro escolhido, a vizinhança (5,5 km). Laterais com mais folga (o nome "ROPPONGI" cortava). `BairrosCameraTests`. Na cidade inteira as bolhas de Shibuya/Harajuku/Shinjuku se encostam (são bairros a ~1 km um do outro).
- **Barra de status sobre mapa:** véu branco (`StatusBarScrim`) em Mapa, Bairros e Guia; a hora não fica em cima dos nomes do mapa.
- **Ajustar:** `-debugScreen ajustar:<bairro>` abre o que o botão abre (Bairros + Montar com foco). O Montar agora diz o foco no título ("Montar Shinjuku+").
- **`-region.auto NO`** (explicado e corrigido): o argumento chega como String "NO"; `as? Bool` lia nil e o automático seguia ligado. `RegionStore.readAuto` usa `bool(forKey:)`. `RegionAutoTests`.
- **Fotos do Commons:** a API arredonda a largura pra cima até um tamanho padrão do Wikimedia; 1024 virava 1280 px. Agora pede 960 e guarda em 800 px, JPEG 0,7 (`PhotoLoader.compact`), como a premissa. Fotos já no disco ficam como estão.
- **`TransitLoader`:** já tinha cache por região (o `body` do mapa só faz uma busca no dicionário). Nada a fazer.
- **Placeholder de foto** conferido com `-debugNetwork slow` e instalação limpa: Início (card e bairros), Musts e Lugar mostram a cor/gradiente até a foto chegar.
- **Miniatura 240 px:** não usei nas listas de bairro de propósito. O menor cartão de bairro tem 116 pt (~350 px na tela); a de 240 px ficaria borrada, e não economiza rede (a foto grande já está no disco). Continua gerada.

**Crash no iPhone (05/11, corrigido).** EXC_BREAKPOINT em `AppRoot.refreshOutsideSoon` (`context.container`). Na troca de região (GPS, Ajustes, menu escondido) ou ao zerar, o `RegionStore` soltava o container antigo; a árvore velha ainda vivia por um instante (animação de 0,4 s) e recebia o `didSave` do board novo, lia o `context` do container solto e o SwiftData parava o app. A fatia 6 tinha coberto só a sincronização. Agora: (1) `RegionStore` guarda os containers que saíram (`retired`), então nenhum `context` velho aponta pra container solto, em nenhuma tela; (2) `AppRoot` sabe a própria geração e a árvore velha ignora `didSave`, sincronização, pré-download e avisos. `RegionSwitchLifetimeTests`: sem a correção o teste reproduz o crash; com ela passa. 557 testes. O aviso "Modifying state during view update" do console é outro (não derruba) e fica pra investigar.

**Fotos vivas (05/11).** Pedido do Vinicius ("muito sutil e sem vida"). O v5 deixava ~18% da foto aparecer (saturação .7 + cor a 82%). Agora: foto em cor cheia, cor do Must só atrás do texto (Musts, lista, Nova/Editar lista), Lugar com foto do Commons tratado como o do Google (faixa de cor embaixo), heroes da Início escurecem só no topo e embaixo, zoom lento (22 s) no hero da Início e do Lugar (Reduzir movimento desliga). Capa da lista e foto do bairro preferem a foto do Google já no disco (lote de fotos, Lugar aberto, dia baixado); foto escolhida à mão na lista vale sempre (`ListCover`, marcada em `listPhoto.manual` no UserDefaults, sem mexer no esquema). `ListCoverTests`. 560 testes. Comparação v5 × vivo: `-photoStyle classic`.
- No simulador não há foto do Google no disco (lugares fake): as capas seguem do Commons lá. **iPhone:** rodar o lote de fotos no Wi-Fi e conferir que Musts/listas/bairros trocam pra foto dos seus lugares.

**iPhone (Vinicius).** Ver `docs/checklist-viagem.md`. Além dele: abrir o app pela primeira vez no Japão (troca BH → Japão pelo GPS) e confirmar que não fecha; andar entre bairros e ver "Hoje em <bairro>" trocar; Colar texto com resposta real do ChatGPT; avisos do guia com o app fechado; Instruments (Hangs).

## v8 (rodada 22, 05/11/2026)

**Como rodar.**

```sh
xcodegen generate
xcodebuild -project Must.xcodeproj -scheme Must -destination 'platform=iOS Simulator,name=Must-V8F' -derivedDataPath build/dd test
DEVICE=Must-V8F DD=build/qa-dd ONLY=v8 scripts/qa-screens.sh build/qa-f   # ~100 prints em build/qa-f (não vão pro git)
```

O script usa fakes pras APIs pagas (Places, Nearby, AeroDataBox, tips) e, por região, monta e aceita o dia do motor às
08:30 (`-debugScreen aceitar-dia:<bairro>` com `-dev.simDate` só naquela abertura) antes das telas: JP sáb/dom 15/11
14:20 Shinjuku, BH sáb 07/11 14:35 Savassi, IT qui 15/04/2027 11:40 Trastevere e qua 14/04 14:00 Monti (DiaIT). Por região:
as 20 telas do `ONLY=v8`, capa e Agora em xxxLarge, mais Linha, Lugar, Bolso e Dicas em xxxLarge e as 6 em modo avião
(`-debugNetwork offline`). **Não edite o `qa-screens.sh` com ele rodando** (o zsh lê o arquivo aos poucos e quebra).

**Conferido (print × `design/v8/screens/`).**

| Tela | JP | BH | IT | Diferença que ficou |
|---|---|---|---|---|
| Capa (`CapaJP/BR/IT`) | ok | ok | ok | Dados do dia (paradas, gasto, "e … à noite") são os do motor sobre o seed, não os do mock; temperatura some em datas fora da previsão (Roma 2027). |
| Capa com foto | ok | ok | ok | — |
| Bom dia (`Manha`) | ok | ok | ok | Às 14:20 (o print não é às 07:20); "sem previsão no aparelho" quando a data simulada passa dos 16 dias do Open-Meteo. |
| Agora | ok | ok | ok | O numeral com tracking −0,06em (igual ao CSS) encosta o "1" no "5" em "15:46" — decisão de design, não mexi. |
| Linha do dia (`Dia`, `DiaIT`) | ok | ok | ok | Paradas e bairros saem do motor (Monti vira "Centro Storico + Monti", dia 5 em vez de 4 pelas datas placeholder). |
| Montar / proposta | ok | ok | ok | Nenhum chip de grana fica marcado quando a meta da região (¥ 15.000) não é um dos três. Toggle é o do iOS 26. |
| Guia | ok | ok | ok | Rótulos da faixa: paradas a poucos metros perdem o rótulo em vez de sobrepor (corrigido nesta rodada). |
| Dicas | ok | ok | ok | — |
| Bolso (`Utilidades`, `BolsoIT`) | ok | ok | ok | Valores em display ocupam mais altura que no design (entrelinha do SwiftUI > `.92` do CSS); a última fileira fica atrás da barra e rola. |
| Lugar / sem foto / museu | ok | ok | ok | Museu IT sem a âncora da reserva: a Borghese é seg 12/04 e o print é qui 15/04. A foto do Commons às vezes não é do lugar (Da Enzo saiu uma garagem) — só o lote de fotos do Google resolve. |
| Musts / Lista | ok | ok | ok | "0 abertos": os fakes do Places não têm horário. |
| Próximos | ok | ok | ok | — |
| Ir (`Transporte`) | ok | ok | ok | Sem rede do Routes os modos vêm da estimativa ("Metrô · 1 min" quando o lugar é perto). |
| Boa noite (`Noite`) | ok | ok | ok | A barra de abas aparece (no PNG não): a tela não tem botão de voltar próprio, esconder a barra deixaria só o gesto. Numeral do gasto sem espaço ("€0", "¥11,3k"), como no PNG e no teste. |
| Ajustes › Região | ok | ok | ok | — |

- **Troca de região:** entre JP, BH e IT só mudam a capa (vermelho, verde, azzurro), a Boa noite e o anel do selo. Barra, botões laranja, cards tinta, Linha, Lista e Bolso são iguais nas três.
- **€:** "€ 12,50" em todas as telas de Roma (`MoneyFormatStyle`), incluindo Linha, Lugar ("€ 30 / pessoa", "€ 1–3"), Bolso e capa. Única exceção de propósito: o numeral gigante da Boa noite.
- **Dynamic Type xxxLarge** (capa, Agora, Linha, Lugar, Bolso, Dicas): numeral fixo e `accessibilityHidden`, nada sobreposto. Corrigido: a hora da Linha e do Bom dia virava "14:…" (agora encolhe) e o crédito da foto do Lugar quebrava em 5 linhas por cima da ficha (agora uma linha).
- **Modo avião** (`-debugNetwork offline`): capa, Linha, Lugar, Bolso e Dicas completos com o que está no disco; Agora usa a estimativa de caminhada.

**Corrigido nesta rodada (agente F).**
- Texto: `V8Font.text` tinha `.monospacedDigit()`; no Schibsted o `tnum` também alarga vírgula, ponto e dois-pontos ("dia , numa tela só ."). Tirado; números alinhados ficam no mono. Schibsted virou a fonte padrão na raiz (`Text` sem fonte não sai mais em SF).
- Títulos: Bricolage com `opsz` = tamanho (54) saía ~8 % mais largo que o design; agora `opsz` 96 (títulos) / 40 (seção), como o `v8.css`.
- Capa e Agora antes da primeira parada diziam "Dia feito" / "O dia acabou": agora "Primeira · 1 de N · saia às" e "O dia começa às…". Agora não diz mais "até 16:30" com "saia às 17:05".
- Widgets/Live Activity: Schibsted e Martian Mono (wdth 100) no lugar de Archivo/Geist; 済 virou ✓.
- Texto invisível: letra dos pinos do mapa e contagem das bolhas de Bairros em papel sobre tinta.
- Nada em japonês na interface: sem 済 (Home, Guia, mapa, Viagem, Luz, Importar, Gasto, lote), sem kanji nas listas/pinos/bolhas, `nameLocal` só na ficha do Lugar (saiu das linhas da Lista, Board, Proposta e lista do Mapa); campo de kanji da Nova lista removido.
- Compras em Roma: a conta usa a moeda das regras (€) com o câmbio do euro de Ajustes; tax-free de € 70 por loja. `ShoppingEuroTests`.
- Metrô de Roma no mapa: A, B/B1 e C traçados à mão pelas estações em `scripts/gen-transit.py` (sem rede, `approx: true`), `roma-lines.geojson`.
- Lugar: o conteúdo some num fade antes dos botões. Guia: rótulos da faixa não sobrepõem nem ficam sob "Abrir o mapa".
- `V8StubScreen` apagado; `TODO(v8:*)` resolvidos, menos os dois abaixo.

**Ficou pendente.**
- **Barra de status escura** sobre capa, Agora, Montar, Ir, Próximos, Bom dia e Boa noite: o app força `.preferredColorScheme(.light)` e o SwiftUI não tem estilo de barra por tela com a navigation bar escondida. Os caminhos possíveis (trocar o esquema de cor da janela por tela via `PreferenceKey`, ou um `UIHostingController` próprio na raiz com `preferredStatusBarStyle`) mexem na raiz de tudo; não fiz sem o aparelho pra conferir.
- Tracking dos títulos: o `.disp` do CSS tem −0,03em; `Font` não carrega tracking, então só sai onde a tela pôs `.tracking`.
- `TODO(v8:A)` no `GuiaTabView`: faixa do Guia com o mapa de verdade em tema escuro (hoje é o esquema desenhado).
- `TODO(v8:E)` no `RegionStore`: `Settings.init` usar `region.defaultFXRate` — mexe no modelo SwiftData, fica.
- Tram 8 de Roma não está no traçado.

**Suíte.** `✔ Test run with 706 tests in 125 suites passed` (eram 701; +4 `ShoppingEuroTests`, +1 metrô de Roma). Build de aparelho (`generic/platform=iOS`, com assinatura do Personal Team, sem `CODE_SIGNING_ALLOWED=NO`): `** BUILD SUCCEEDED **`.

**Só dá pra testar no iPhone.**
- [ ] Live Activity "saia às" na tela bloqueada e na Dynamic Island: começa ao aceitar, avança com Feito, some no fim do dia.
- [ ] Os 4 avisos locais (bom dia 07:20, saia em 5 min, golden em 20 min, último trem em 50 min) com o app fechado, no máximo um a cada 45 min; tocar abre Bom dia / Agora.
- [ ] GPS real trocando a região (Brasil → BH, Japão, Itália) e o bairro da capa; Roma no aeroporto.
- [ ] Fontes variáveis no aparelho (Bricolage wdth/opsz, Martian wdth 100) no app e nos widgets.
- [ ] Barra de status sobre as telas tinta/laranja/cor do lugar (ver pendente).
- [ ] Modo de Pouco Dados: nada de pré-download nem foto nova fora do Lugar aberto.
- [ ] Rede real do Routes (trem/metrô entre paradas, "saia às" com o tempo de verdade) e o modo avião de verdade (`NWPathMonitor`).
- [ ] Dynamic Type pelo Ajustes do iPhone (o simulador usou o argumento de launch).
- [ ] Traçado do metrô de Roma por cima do mapa (é aproximado).
- [ ] Lote de fotos do Google no Wi-Fi trocando as capas do Commons (Da Enzo e outros com foto errada).

## Prompt 29 · Vídeo do Instagram (05/11/2026)

Link do Instagram/TikTok sem legenda → cartão "Ler o vídeo" (3 passos + `PhotosPicker` de vídeos). Share Extension aceita `public.movie` e abre o Adicionar com o vídeo. `VideoReader` lê tela (Vision, 1 quadro/s, no máx. 90) e fala (`SpeechAnalyzer`; `SFSpeechRecognizer` no aparelho de reserva), junta com a legenda em `[legenda]`/`[tela mm:ss]`/`[fala mm:ss]` e o extrator de sempre acha os lugares; a conferência mostra "visto na tela 00:04" / "falado 00:07". O vídeo é apagado depois da leitura.

- Testes: `VideoReaderTests` (vídeo de fixture desenhado com `AVAssetWriter`, OCR, junção, cancelar, progresso, fala sintetizada tolerante a falta de modelo) e `VideoIngestTests` (texto → extrator falso → origem).

**Só dá pra testar no iPhone.**
- [ ] Gravação de tela real de um reel de comida em BH (Mercado Central · fígado com jiló): lugares com "visto na tela".
- [ ] Modelo de fala pt-BR: baixa só no Wi-Fi; no celular/Pouco Dados fica "sem modelo de fala" e a leitura segue só com a tela.
- [ ] Reel de 30 s lido em menos de 15 s; Cancelar a qualquer momento; a tela não trava.
- [ ] Compartilhar um vídeo de Fotos → Must abre o Adicionar já lendo.

## Robustez e profiling (rodada 23 · G, 05/11/2026)

Pedido do Vinicius: "quero tudo testado e funcionando. Faça profiling e testes de digitação pra pegar crashing, inclusive
com internet ruim" — e antes: "ao digitar na tela de adicionar na lista o app quebra".

**Como rodar.**

```sh
scripts/ui-tests.sh                                   # tudo (digitação + navegação + profiling), matriz padrão, ~3 h
DEVICE=Must-R23g scripts/ui-tests.sh AddToListTypingTests          # uma classe
MATRIX="bh:normal,jp:flaky,it:dropping" scripts/ui-tests.sh FieldsTypingTests/testQuero
scripts/ui-tests.sh PerformanceTests                  # só os números (ver abaixo)
```

- Target **`MustUITests`** (XCUITest) com scheme próprio: o scheme `Must` continua só com os unitários (rápido).
- O app abre como no `qa-screens.sh`: região, data (`-dev.simSetAt 0`) e GPS simulados, **todos os fakes** (Places,
  Nearby, AeroDataBox, dicas, Routes, Autocomplete, Em cartaz, fotos do Google) — nenhuma chamada paga, nada de cota — e
  **`-debugFreshStore YES`**: board novo do seed numa pasta temporária a cada abertura, sem tocar no board do simulador.
- `MATRIX` = `região:rede` (`bh|jp|it` : `normal|wifi|slow|flaky|dropping|offline`). Sem ela, cada cenário de digitação
  roda em BH, JP e IT (rede normal) e em BH com `slow` e `offline`; a navegação roda BH `flaky`, JP `dropping`, IT `flaky`.
- No fim o script procura **`Fatal error`** do processo Must no log do simulador: um trap do Swift aparece pro XCTest só
  como "o app saiu", e o simulador não deixa `.ips` em `~/Library/Logs/DiagnosticReports`.

**Ganchos DEBUG novos** (todos desligados no host de testes e em Release).
- `-debugNetwork flaky`: latência 0,5–8 s e 40 % de falha por tentativa — timeout, 500, 429 (Retry-After 1), resposta
  cortada no meio e JSON inválido com 200 (`NetworkChaos`, passa pelo `HTTP` e pelo `CaptionFetcher`).
- `-debugNetwork dropping` (+ `-debugNetworkPeriod 4`): a rede cai e volta a cada N s; o `Connectivity` acompanha (chip,
  fila de saída, sync ao voltar) e o que estava em voo quando caiu volta `networkConnectionLost`. `slow` ficou igual.
- `-debugGPSHop "7:35.69,139.70;16:-19.93,-43.93"`: o GPS simulado pula de região no meio do uso (automático ligado).
- `-debugSyncEvery 3`: sync + Places + fila de saída a cada 3 s, gravando no board durante a digitação.
- `-debugFreshStore YES`: ver acima.

**Cenários de digitação** (`AddToListTypingTests`, `FieldsTypingTests`): rajadas de `typeText` com acentos, emoji,
japonês, italiano e pontuação; apagar tudo; colar (5.000 caracteres pelo menu Colar); 23 dígitos, "nan" e letras nos campos
de número; girar (o app é só retrato: tem que ignorar); mandar pro fundo e voltar; fechar a sheet pela metade e reabrir;
trocar de região pelo GPS com a sheet aberta e o sync gravando.

| Tela / campo | Teste |
|---|---|
| Lista › Adicionar à mão (`EditPlaceView(newInListId:)`): nome, nome local, preço, bairro, notas, salvar | `testTypeEverythingAndSave`, `testPasteLongTextRotateBackground`, `testCloseHalfTypedAndReopen`, `testRegionSwitchByGPSWhileTyping` |
| Lista art (campos do tipo: inteira, estudante, duração, link do ingresso) | `testArtListExtraFields` |
| Editar lugar existente (com o GPS trocando a região aos 9 s) | `testEditExistingPlace` |
| Nova lista › Adicionar lugares (busca no board, Places, manual) | `testNewListAddItems` |
| Quero… (texto, buscar) e as abas Texto / Link / Nome por cima | `testQuero` |
| Adicionar › Link (lixo, Reel, Maps) e a legenda colada | `testAddLink` |
| Adicionar › Texto (5.000 caracteres, Ler texto, fundo) | `testColarTexto` |
| Buscar por nome (Autocomplete fake, escolher) | `testBuscarNome` |
| Mapa › busca "o melhor X agora" (texto e voz) | `testMapaBusca` |
| Montar › "ou diga…" | `testMontarOuDiga` |
| Assistente (4 perguntas sem esperar a resposta) | `testAssistente` |
| Gasto (teclado próprio, rápido) | `testGasto` |
| SOS › Seu seguro / Seu plano (todos os campos, Guardar) | `testSOSSeguro` |
| Carteira › item novo (todos os campos) | `testCarteira` |
| Ingresso › Revisar (PDF de exemplo) | `testIngressoRevisar` |

**Navegação com internet ruim** (`NavigationStressTests`): os 77 `-debugScreen` do `MustApp.swift` (cobrem todas as rotas
do `Router.swift`; `.day` e `.diaRecebido` vão pelos links) e 15 links `must://` (inclusive quebrados: `must://d/lixo`,
`must://lugar/nao-existe`, `montar?date=lixo`). Em cada tela: não cai, não fica vazia depois de 3 s, rola, e nenhum
spinner passa de 20 s.

**Resultado** (simulador `Must-R23g`, iPhone 17 · iOS 26.5, build Debug, 05/11 21h–00h).

| Suíte | BH | JP | IT | BH lenta | BH offline | flaky / dropping |
|---|---|---|---|---|---|---|
| Digitação (17 cenários, `AddToListTypingTests` + `FieldsTypingTests`) | ok | ok | ok | ok | ok | JP flaky no colar, BH dropping na troca de região: ok |
| Navegação (77 telas + 15 links) | flaky ok | dropping ok | flaky ok | — | — | nenhuma tela caiu, vazia ou com spinner > 20 s |
| Profiling (8 medições) | ok | ok | — | — | offline | — |

Nenhum `Fatal error` do Must no log do simulador nas rodadas finais. Na primeira rodada falharam 7 cenários por causa do
próprio teste (campo sem foco depois do "buscar", elemento que sumiu na troca de região, rótulo em caixa alta) — corrigido
no `MustUITestCase` (`enter`, `safeTap`, `BEGINSWITH[c]`) — e **um de verdade** (Colar texto, abaixo).

**Crashes e travas achados (e corrigidos).**
1. **Crash ao digitar número grande** (`KindExtraFields`, listas art/photo/sport/do): o campo relia o valor com `Int(_:)` a
   cada tecla; 19+ dígitos (ou "nan"/"inf" colados) davam `Fatal error: Double value cannot be converted to Int because the
   result would be greater than Int.max`. **Reproduzido no simulador** (Lista art › Adicionar à mão › "inteira": 23 dígitos →
   o app sai). O mesmo `Int(_:)` estava no Revisar ingresso (preço), na Carteira (saldo) e no Gasto (preço do lugar).
   Correção: `NumberInput` (só número finito até 1e12, inteiros ASCII limitados); `TicketMoney.parse` e os parsers dos
   campos passam por ele. Regressão: `RobustnessTests` (5 testes) e `testArtListExtraFields` (digita os 23 dígitos primeiro —
   com texto antes o campo já virava nil e o crash passava batido).
2. **"Lendo o texto…" sem fim** no Adicionar › Texto com 5.000 caracteres (BH, JP, IT, lenta e offline): o Foundation
   Models dizia "disponível" mas não respondia (no simulador o catálogo do modelo está vazio; no iPhone pode acontecer com o
   modelo baixando). Sem teto, a tela ficava esperando. Correção: 12 s por bloco e 20 s no texto todo; passou disso, o bloco
   cai nas palavras-chave. Regressão: `deadlineCutsSlowWork`, `stuckModelFallsBackToKeywords`; o UI test passou de 234 s
   (5 falhas) pra 80 s.
3. **Foto cortada gravada pra sempre** (`-debugNetwork flaky`, resposta pela metade): a foto do Google e a do Commons iam
   pro disco como vieram e ficavam meio cinza por 30 dias (a foto é baixada uma vez só). O `ImageIO` diz que JPEG cortado
   está completo; agora só grava JPEG com EOI (FF D9) e PNG com IEND. Regressão: `truncatedPhotoIsNotComplete`.
4. **Viagem com a volta antes da ida** (board importado com `to` < `from`): `a...b` com a > b é trap. Agora a faixa da
   cidade nunca inverte.

**O "digitar na tela de adicionar na lista quebra" (relato do Vinicius).** Tentado, sem reproduzir fora do item 1:
- Lista › Adicionar à mão em BH, JP e IT, rede normal/lenta/offline: todos os campos em rajadas, apagar, colar 5.000
  caracteres, 23 dígitos/"nan"/letras no preço, girar, fundo e volta, fechar pela metade e reabrir 3×, salvar.
- O suspeito da troca de região: GPS pulando BH → Tóquio → BH (e JP → BH, IT → JP) com o Novo lugar aberto, digitando, e o
  sync gravando no board a cada 3 s (`-debugGPSHop`, `-debugSyncEvery`), também com a rede caindo e voltando. A árvore troca,
  a sheet some, nenhum trap: os containers antigos ficam vivos (`RegionStore.retired`) e o `requestSync` leva o contexto dele.
- Editar lugar existente com o GPS trocando a região aos 9 s; Nova lista › Adicionar lugares (busca a cada tecla, Places, manual).
- O mais provável é o item 1, se a lista era art/photo/sport/do (o preço/duração é campo numérico do tipo); o item 2 parece
  "travou" (não é crash) e não deixa log.
- Mais resistente nos pontos suspeitos: o `EditPlaceView` não tem mais `@Query` de todos os lugares (relia o board inteiro a
  cada tecla) — lê o lugar pelo id no contexto da própria árvore só ao abrir/salvar/apagar; a Lista lê a relação uma vez por
  `body` e o `@Query` dela agora tem predicado; `DayPlanPrefs` (lido no `body` da Lista, capa e Linha) não decodifica mais o
  dia a cada redesenho.

**Profiling** (`PerformanceTests`, 3–5 iterações, desvio padrão < 8 % salvo memória delta). CPU inclui o trabalho de
acessibilidade que o XCUITest pede ao app a cada gesto (cresce com o número de linhas): compare rodadas, não telas.

| Medição | Número |
|---|---|
| Abertura fria até responder (`XCTApplicationLaunchMetric`, BH offline) | **1,39 s** (±2,4 %) |
| Volta do fundo (JP offline): relógio · CPU · memória | 2,12 s (inclui as esperas do teste) · 0,11 s · 79 MB |
| Lista Eat JP (48), 12 rolagens: relógio · CPU · pico de memória | 27,8 s · 3,9 s · 94 MB |
| Musts, 8 rolagens | 7,8 s · 0,82 s · 71 MB |
| Linha do dia (dia aceito), 8 rolagens | 7,3 s · 0,59 s · 75 MB |
| Coleção, 8 rolagens | 7,5 s · 0,76 s · 81 MB |
| Mapa (MapLibre), 4 arrastos + 2 pinças | CPU 0,80 s · pico 88 MB |
| Digitar 104 teclas no Novo lugar (JP) | 6,3 s · CPU 3,1 s (~30 ms/tecla, com o teclado e a acessibilidade) · 105 MB |

- `XCTHitchMetric` (iOS 26) compila e roda, mas o simulador não devolve hitches: medir no iPhone (abaixo).
- Memória estável em todas (pico 70–105 MB; nada cresce entre iterações).
- Corrigido barato: JSON do dia no `body` (memo), `@Query` sem predicado no Editar lugar e na Lista, foto decodificada no
  main (`PhotoLoader` agora lê e decodifica fora do main com `preparingForDisplay`). O `ImageRenderer` (cartaz, colecionável)
  só roda em ação, nunca no `body`. Fotos: memória → disco → rede, uma por lugar (ok).

**Só dá no iPhone.**
- [ ] Repetir o relato: Lista (de cada tipo, principalmente art/photo/sport/do) › Adicionar à mão, digitando de verdade
  (autocorreção, previsões, ditado, teclado japonês no nome local). Se cair, Ajustes › Privacidade › Análise › Dados de
  Análise › `Must-…ips` (ou `JetsamEvent` se foi memória) e mandar.
- [ ] Hitches ao rolar Lista/Musts/Linha/Mapa: Xcode › Instruments › Animation Hitches no iPhone Air (o simulador não mede).
- [ ] Internet ruim real: metrô (sinal caindo), Modo de Pouco Dados, Wi-Fi do hotel com portal — o `flaky`/`dropping` só
  simulam o que passa pelo `HTTP`; MapLibre (tiles) e MapKit têm rede própria.
- [ ] Colar texto com o Apple Intelligence de verdade: 5.000 caracteres responde antes dos 20 s ou cai nas palavras-chave.

## Rodada 32 · v9 navegação simples (09/11/2026)
Fase 1 tem que estar no iPhone até a noite de 10/11 (a viagem começa em 11/11).

### r32/0 · contrato (orquestrador)
- `Must/DesignSystem/V9/V9.swift`: `V9.accent` (#D9572B claro / #F07A4E escuro, é o `.tint` do app), `V9.alert` (`.red`), fundos do sistema, `.v9Screen()`, `.v9Card()`, `.v9Primary()`, `V9AskField` ("Pedir algo…", toque), `V9SectionHeader`, `V9Row` (miniatura 56 pt + motivo), `V9Notice` (faixa com ação e ✕).
- Modo escuro: o app segue o aparelho (`UIUserInterfaceStyle` saiu; sem `.preferredColorScheme(.light)` global). Telas ainda V8 ficam no claro por `.v8Legacy()` (raízes das abas em `RootView`, `Route.legacyLight`, `AppRouter.Sheet.legacyLight`, covers). Cada tela convertida tira o wrapper.
- `Must/Services/Context/TodayContext.swift`: `ContextRule` (à mão › parada do dia › confirmado › hotel/cidade), `ArrivalProposer` (stub; agente C), `TodayContextModel` no environment (criado na `RootView`).
- `AppRouter.showOnMap(MapShowcase)` / `mapShowcase`: "Ver no mapa" do Quero abre o Explorar só com esses pinos.

### Gestos que sobraram (item 1)
(preencher na rodada: cada `DragGesture`/`LongPress` em `Must/Features` com o controle visível equivalente)
