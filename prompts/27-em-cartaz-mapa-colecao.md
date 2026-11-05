# Prompt 27 · Em cartaz, Mapa com card e busca, Colecionáveis, Amigos, Filmes, Trocar viagem e fontes dos botões (05/11/2026)

> **Nota do orquestrador (05/11):** o `prompts/26-capa-inteligente.md` (do Vinicius) já cria o `EventsService` (Bandsintown + Ticketmaster Discovery + feeds públicos, chaves opcionais). O "Em cartaz" daqui usa o `EventsService` do 26 quando ele existir, além do board/colar link/cartaz; a seção de API pendente fica resolvida por lá.

Pedidos do Vinicius em 05/11/2026. Faça depois da RODADA-22 e do prompt 25 (precisa da identidade v8, do `Quero…` e do `DayEngine`). Pode rodar em **4 agentes em paralelo**: ver `prompts/RODADA-23.md`. As telas estão em `design/v8/screens/`; os dados nelas são **exemplos** (BH e Japão dos seeds; Park Hyatt, Billboard Live e os amigos não estão nos seeds).
Regras que valem pra tudo aqui (CLAUDE.md): cache primeiro e stale-while-revalidate; offline é estado normal; Modo de Pouco Dados (`allowsConstrainedNetworkAccess`) = sem pré-download; só campos usados nas chamadas; nada de scraping; nada em japonês na interface; UI em pt-BR; uma fonte com chave é opcional.

| Item | Telas |
|---|---|
| 1 Em cartaz | `EmCartaz`, `LugarEmCartaz`, `CapaEmCartaz`, `DiaEmCartaz` |
| 2 Mapa | `MapaPino`, `MapaFiltro` |
| 3 Fontes dos botões | `BotoesFontes` |
| 4 Colecionáveis | `Colecao`, `Colecionavel`, `ColecionavelNovo` |
| 5 Amigos que foram | `LugarAmigos` |
| 6 Filmes | `LugarAmigos` (bloco), `Filmes`, `FilmesVazio` |
| 7 Trocar viagem | `TrocarViagem` (e `CapaEmCartaz`, `NovaViagem9`: botão no canto) |

## 1. Em cartaz (museu, casa de show, estádio)
**O que entregar.** Quando o lugar é museu, casa de show ou estádio, o app mostra **o que está em cartaz** (exposição, show, jogo) e usa isso como entrada de navegação: chip na capa, tela própria, item na Linha do dia e bloco no Lugar.

**Fontes na v1 (só o que o app já tem; nenhuma API nova):**
1. O que já está no board: `Place.extra.art` (`runsFrom`, `runsUntil`, `sessions`, `ticketURL`), `extra.sport.sessions` (jogos), `extra.experience`, e `Ticket` ligado a `Session`/`Reservation` (já é âncora do solver).
2. **Colar link ou texto** da programação: o extrator no aparelho que já existe, `Must/Services/Ingest/EventExtractor.swift` (`EventExtractor.parse` devolve `ArtEvent`; `looksLikeEvent`, `isTicketSite`). Entra pelo fluxo de Adicionar/Colar (`Must/Features/Add/`, `Must/Features/ColarTexto/`); quando o texto casa com um lugar do board, atualiza a programação desse lugar; quando não casa, pergunta a qual lugar pertence (ou cria um Must do tipo certo).
3. **Foto ou print do cartaz**: Vision (OCR) com o mesmo leitor do fluxo de ingresso (`Must/Services/Tickets/TicketReader.swift`, `TicketText.swift`), depois `EventExtractor`; conferir antes de salvar (confiança por campo, como no ingresso).
4. Nada de scraping de site de museu/casa de show.

**Decisão pendente do Vinicius, não implementar:** uma API de eventos pra preencher sozinha. Candidatas a avaliar (todas a confirmar antes de qualquer código): **Ticketmaster Discovery API** (chave grátis, cobertura boa nos EUA/Europa e limitada no Japão e no Brasil), **Sympla** (não tem API pública de busca), **Eventbrite** (a busca pública de eventos foi descontinuada; só dá pra ler eventos de uma organização), **Bandsintown/Songkick** (por artista, acesso restrito), agenda oficial de cada museu (sem padrão). Se a decisão for "sim", entra atrás de um protocolo `EventSource` (como `ExperienceSource`), opcional e desligável; a v1 não depende disso.

**Modelo.** Sem mudar o schema SwiftData. Valor `ShowEvent` (não persistido): `id`, `placeId?`, `kind` (`exhibition | show | match`), `title`, `startsAt?`, `runsUntil?`, `sessions: [EventSession]`, `priceText?`, `source` (`board | link | poster`), `checkedAt?`. Montado a partir de `PlaceExtra`. Pra show e jogo colados (sem lugar com `extra.art`), acrescentar a `PlaceExtra` a chave aditiva **`program: [EventSession]`** (Codable com `decodeIfPresent`; é JSON dentro de `extraData`, não muda o schema do SwiftData). Espelhar no `data/board.schema.json` (campo opcional) e nos testes de `BoardCodecTests`.

**Onde aparece:**
- **Capa** (`Must/Features/Home/HomeView.swift`, `CapaModel.swift`): chip "Em cartaz · N hoje" acima do card Agora, só quando N > 0; abre `EmCartaz`. Ver `CapaEmCartaz.png`.
- **Tela Em cartaz** (`Must/Features/EmCartaz/EmCartazView.swift`, nova): título + numeral, pílulas (Na viagem · Hoje · Museus · Shows · Jogos), linhas com índice, nome, meta, origem (`do board`, `ingresso · QR salvo`, `link colado`, `foto do cartaz`) e à direita o dia/hora; "Hoje" primeiro, depois "Dias seguintes". Rodapé com Colar link / Foto do cartaz. Entradas: chip da capa e botão na aba Viagem (`Must/Features/Trip/ProximosView.swift`). Ver `EmCartaz.png`.
- **Linha do dia** (`Must/Services/Day/MicroStops.swift`, `DayEngineV8.swift`): faixa preta "Em cartaz hoje" sob o título e, quando há janela livre, **micro-parada tracejada em laranja** "Moriyama · retrospectiva · cabe 55 min · fecha 18:00". Regras: só entra se o lugar está aberto na janela, a exposição está em temporada (`runsFrom…runsUntil`) e cabe entre duas âncoras sem mexer nelas; nunca substitui uma parada aceita. Ver `DiaEmCartaz.png`.
- **Lugar de museu/show/estádio** (`Must/Features/Place/PlaceView.swift`, `KindPanels.swift`): bloco "Em cartaz" com tag AGORA/EM BREVE, título, período, origem, "Colar programação" e "Fotografar cartaz", e a data da última checagem (colado há N dias). Ver `LugarEmCartaz.png`.

**Dados e custo.** Tudo local; zero chamada de rede (v1). Programação vencida (`runsUntil` < hoje) some da lista mas fica no lugar. Offline: igual online.

**Testes.** `ShowEventTests` (montagem a partir de `ArtEvent`/`Ticket`; vencida some; "hoje" respeita fuso da cidade), `EmCartazDayTests` (micro-parada só cabe se aberto e em temporada; não mexe em âncora), `BoardCodecTests` (`program` round-trip e arquivo antigo sem a chave).

## 2. Mapa: card do pino, filtro por Must e busca "o melhor lámen agora"
Arquivos: `Must/Features/Map/MapView.swift` (`selectedId`, `layers`, sheet "Perto de você"), `MapPins.swift` (`MapLayer`, `MapPin`), `PinsMemo.swift`, `MapLibreView.swift`; busca em `Must/Features/Quero/QueroView.swift` e `Must/Services/Intelligence/IntentParser.swift`.

**a) Card maior ao tocar no pino** (`MapaPino.png`). Hoje o pino só seleciona. Passa a abrir um **card** de baixo (detent médio, ~44% da tela, arrasta pra cima = abre o Lugar inteiro): foto (a de sempre do `PlacePhotoStore`, com crédito; placeholder de cor enquanto não carrega; **nunca baixa foto nova só por causa do card em dado móvel**: usa a que estiver no disco), nome 34/700, tag "aberto até", meta (Must, tipo, nota), ficha de 3 campos (fila, preço, distância e tempo), uma linha "amigos que foram" (item 5, só se houver), e três ações: **Ir agora · N min** (laranja), **Feito**, expandir. A câmera não pula: o pino selecionado sobe um pouco e o mapa mantém o contexto. Fechar = tocar fora ou arrastar pra baixo. Reaproveitar `PlaceFicha`/`PlacePanel` em vez de duplicar a ficha.

**b) Filtro por Must (listas)** (`MapaFiltro.png`). Linha de pílulas rolável no topo: **Todos N**, **Eat N**, **Drink N**, Art, Photo, See, Listen, Shop, Sport, Do — com contagem do board da região (calculada em memória, sem rede). Uma ou várias; filtra pinos `unplanned`/`today`/`tomorrow`/`done`, **não** o metrô nem "você está aqui". Estado em `@AppStorage` por região (`map.mustFilter.<regionId>`). Convive com as camadas atuais (`MapLayer`: hoje, amanhã, sem plano, feitos, metrô): camadas dizem **quando**, Must diz **o quê**. Pílula ativa = tinta; sobre mapa claro use fundo papel.

**c) Busca "quero procurar um lámen perto de mim agora, o melhor possível"** (liga com o `Quero…` do prompt 25).
- Campo no topo do mapa (texto ou voz). Interpreta com o `IntentParser` que já existe (sem rede): `{verbo: comer, objeto: lámen, quando: hoje, qualidade: melhor, raio}`. Acrescentar `qualidade: melhor | barato | qualquer` ("o melhor", "mais bem avaliado", "barato") e `raio` (padrão 1,5 km a pé, 3 km se nada).
- Chips do que entendeu (lámen · aberto agora · melhor nota · até 1,5 km), editáveis.
- **Ordem de busca (cache primeiro):** 1) o seu board (`Place` + `OpenNowIndex`), 2) o último `NearbyCache` (Wi-Fi), 3) só se não bastar e houver rede, **uma** chamada do `WantSearch` do prompt 25 (Places Text Search, `locationBias` no ponto, `includedType`, `openNow: true`, `strictTypeFiltering`, `pageSize` 10). Não dispara a cada tecla: só no "buscar"/enter.
- **Ranking "o melhor" no aparelho:** `nota × log(1 + nº de avaliações)`, só aberto agora, até o raio; empate pelo mais perto. Item do board ganha um selo "no seu board". Mostra 3 no card inferior ("Melhor agora · 3 de 11 · por nota") com ações **Encaixar hoje (HH:MM)** (mesma rota do Quero: `DayEngine` tenta a janela) e **Ver no Quero…** (abre `QueroView` já preenchida).
- **Custo (atenção):** `rating` e `userRatingCount` ficam no nível **Enterprise** da Places API (New), acima do Pro que o prompt 25 usa. **Decisão pendente do Vinicius:** (i) aceitar o SKU Enterprise nessa busca (cota grátis própria; registrar em `ApiBudget` — hoje `ApiBudget.Sku` só tem Essentials/Pro, então criar `placesEnterprise` com cota 1.000/mês) ou (ii) ficar no Pro sem nota e ranquear por aberto + perto + popularidade do `NearbyRanker`/Foursquare. Enquanto não decidir, implemente (ii) e deixe (i) atrás de um flag.
- Offline: só board e cache, com chip "offline · só o seu board". Resultado sem coordenada nunca vira pino.

**Testes.** `MapFilterTests` (contagem por lista; filtro não esconde metrô nem posição; persistência por região), `MapSearchTests` ("o melhor lámen perto de mim agora" → intent; ranking por nota×log; só aberto; board antes de rede; nunca item sem coordenada), `MapCardTests` (card não pede foto nova em dado móvel).

## 3. Fontes apertadas nos botões
Prancha: `BotoesFontes.png` (antes/depois e a tabela). Causa: `V8Button` tem altura mínima 56 mas o rótulo usa `minimumScaleFactor(0.8)` (vira 12,8 pt) ou quebra em 2 linhas dentro de altura quase fixa; `V8Pill` de 30 pt com fonte 12 (2,5×); botões redondos com glifo grande demais.
**Regra numérica (implementar em `Must/DesignSystem/V8/V8Components.swift`):**
- Botão: **altura ≥ 3,1 × fonte**; padrão 56/16·700, compacto 44/14·700; **padding H = máx(14, 0,36 × altura)** (20 e 16); ícone = fonte + 2; gap 8–10.
- Rótulo em **uma linha** com degraus **16 → 15 → 14** (`ViewThatFits`, não `minimumScaleFactor` abaixo de 0,875). Se não couber em 14, quebra em 2 linhas a 15 e a **altura cresce** (`minHeight 56`, padding vertical 12). Nunca cortar texto.
- Pílula: **altura ≥ 2,6 × fonte**: 34/13·600 e **pequena 32/12·600** (era 30/12); padding H 14; linhas de pílulas rolam na horizontal, nunca quebram.
- Botão redondo: 44 (glifo 18), 36 (glifo 16), 52 (glifo 20); traço 1,8–2.
- Dynamic Type: fonte com `@ScaledMetric(relativeTo: .body)` até `xxxLarge`; altura = `max(base, 3,1 × fonte)`; em `accessibility*` o botão ocupa a largura toda.
- **Textos:** encurtar o que força quebra ("Só guardar em Shop" → "Só guardar"; "Mandar cartaz pelo WhatsApp" → "Mandar cartaz"). Procure por `.frame(height: 30` e `V8Font.text(1[0-2]` em `Must/Features/**` (`QueroView`, `MandarView`, `Dia`, `Montar`) e troque pelos componentes, sem tamanho fixo.
**Testes.** `ButtonMetricsTests` (função pura `ButtonMetrics.size(forWidth:text:dynamicType:)`: nunca < 14 pt em linha única; altura ≥ 3,1 × fonte; pílula ≥ 2,6×). Verificar visualmente Quero, Compartilhar, Lugar e MapaPino em xxxLarge.

## 4. Colecionáveis (cada "feito" gera um)
Telas: `ColecionavelNovo.png` (o momento), `Colecionavel.png` (os cards 1080×1920 e 1080×1080 e as variantes), `Colecao.png` (a página). Arquivos: `Must/Features/Collection/` (nova), `Must/Features/Share/` (renderer e share sheet), `Must/Features/Place/PlaceView.swift` (o "Feito" já existe).

**Derivar do que já existe, sem mudar o SwiftData.** Um colecionável é um valor calculado de um `Place` com `done` (`DoneMark.at`): nome, data, bairro/área (`stampCode`, sigla latina), cidade, lista (`ListKind`), região, **ordem** = posição entre os feitos da região por `done.at` (nº 14), **total** = lugares do board (14/105). "Raro" = tem `Ticket`/`Reservation` (âncora). Desfazer o "feito" remove o colecionável e a ordem se recalcula (a ordem é derivada, não guardada). A vitrine (até 3 fixados) e a visão escolhida ficam em `UserDefaults` por região (`collection.pinned.<regionId>`, `collection.group.<regionId>`).

**O card (identidade v8, brutalista).** Cor sólida do lugar (a da capa da viagem), arcos de 1 pt (3 px a 1080), **numeral gigante** = ordem, micro-rótulos nos cantos ("Feito · sáb 15 nov 2026", "Tóquio · Shinjuku sul"), nome grande, uma linha ("tsukemen · Must eat"), **selo** redondo com a sigla do bairro (SJK) e "FEITO", faixa preta no pé ("must · guia de bolso", "014 / 105"). Variantes (proposta de design, o Vinicius pode trocar): **cor da viagem** (padrão), **tinta** com numeral laranja (âncora: ingresso/reserva), **papel com contorno** (ar livre: photo, see, sport). Sem foto (leve, offline, sem licença). **Nunca** coordenada exata, gasto, nome de hotel nem nada em japonês. Dois formatos: **Stories 1080×1920** (padrão) e **Feed 1080×1080** (Instagram e Facebook).

**Renderizar e compartilhar.** `CollectibleCardView` em SwiftUI; `CollectibleRenderer` usa `ImageRenderer` (escala 1,0, tamanho fixo em pontos = pixels; fontes do bundle já registradas) e grava um PNG em `NSTemporaryDirectory()` (`must-014-fuunji.png`), apagado depois do envio. **Share sheet** (`ShareLink` com a imagem ou `UIActivityViewController`): lista Instagram, Facebook, WhatsApp, Mensagens, Salvar nas Fotos. **Sem SDK do Facebook/Instagram e sem App ID.** Atalho direto pros Stories do Instagram (`instagram-stories://`) exigiria App ID da Meta e `LSApplicationQueriesSchemes`: fica fora; decisão do Vinicius se quiser depois. Padrão Stories, toggle pro Feed.

**O momento (`ColecionavelNovo`).** Ao marcar **Feito** (depois da folha opcional de gasto), uma tela cheia em tinta: "Novo na coleção · Mais um feito.", o card girado −4° sobe com mola (1,8 s) e um haptic `.success`; botões **Mandar** (laranja), **Ver coleção**, **Depois**. Reduzir movimento: sem mola nem giro, só fade. Não aparece de novo pro mesmo lugar (`UserDefaults` guarda os ids já celebrados). Marcar vários feitos seguidos: só o último celebra; os outros entram quietos.

**A página (`Colecao`).** Título "Coleção" + numeral (38 feitos), segmentos **Cidade · Lista · Data**, botão **Organizar** (fixar até 3 na **Vitrine**, esconder), seções com contagem ("Tóquio 14 de 52"), grade de 3 colunas de cards pequenos e **espaços tracejados "a fazer"** (só os primeiros por seção, pra mostrar o que falta). Toque abre o card grande com Mandar. Entradas: aba Viagem (`ProximosView.swift`), ícone na linha de estatísticas e o link do `ColecionavelNovo`. Performance: miniaturas renderizadas uma vez e em cache em memória; a grade usa `LazyVGrid`.

**Testes.** `CollectibleTests` (ordem por `done.at`, total, variante âncora/ar livre, desfazer recalcula), `CollectibleRendererTests` (PNG 1080×1920 e 1080×1080; sem coordenada nem texto japonês no que é desenhado), `CollectionGroupingTests` (cidade/lista/data).

## 5. Amigos que foram (lista mockada por enquanto)
Tela: `LugarAmigos.png` (bloco "Amigos que foram"). Ao abrir um lugar, lista os amigos que já foram: avatar com iniciais, nome, quando, uma frase, nota. **Por enquanto é mock**: `FriendsProviding` (protocolo) com `MockFriendsSource`, que devolve de um pool fixo de 5 pessoas (Ana Beatriz, Pedro, Carol, Rafa, Lu) de 0 a 3 visitas por lugar, de forma **determinística** (hash do `placeId`) pra o design e os testes ficarem estáveis. O bloco mostra a etiqueta **"exemplo · lista fixa"** enquanto a fonte for mock. Sem visitas = o bloco some. Mesma linha resumida ("Ana e Pedro foram · “…”") no card do mapa (item 2) e no `Dicas`. Arquivos: `Must/Services/Friends/FriendsProviding.swift`, `MockFriendsSource.swift`; UI em `Must/Features/Place/FriendsSection.swift` (ao lado de `TipsSection.swift`, depois de "Dicas de quem foi"). **Decisão pendente do Vinicius:** a fonte real (provavelmente o "Viajar junto" por CloudKit do prompt 25, que já dá "feito por pessoa") e o que cada amigo compartilha. Não criar conta nem backend. Testes: `FriendsTests` (determinismo, no máximo 3, vazio some).

## 6. Filmes gravados no lugar e no bairro
Telas: bloco em `LugarAmigos.png`; lista em `Filmes.png`; sem resultado em `FilmesVazio.png`. Uma lista de filmes **filmados** (e, opcionalmente, **ambientados**) perto do lugar: o Japão é ótimo nisso (Park Hyatt e *Lost in Translation*) e BH também tem, em menor número.

**Fonte nova (decisão do Vinicius em 05/11/2026): Wikidata.** É da mesma família do Wikimedia Commons que o app já usa; sem chave. Consulta **SPARQL** em `https://query.wikidata.org/sparql` (GET, `format=json`), `wikibase:around` num raio pequeno do lugar sobre a propriedade **P625** (coordenadas) do local, ligando ao filme pela **P915** ("local de filmagem") e, como extra "Ambientados", pela **P840** ("local da narrativa"). Esboço:
```
SELECT ?film ?filmLabel ?year ?directorLabel ?loc ?locLabel ?rel WHERE {
  SERVICE wikibase:around { ?loc wdt:P625 ?coord .
    bd:serviceParam wikibase:center "Point(<lng> <lat>)"^^geo:wktLiteral .   # lng primeiro
    bd:serviceParam wikibase:radius "1.5" . }                                 # km
  { ?film wdt:P915 ?loc . BIND("filmado" AS ?rel) } UNION { ?film wdt:P840 ?loc . BIND("ambientado" AS ?rel) }
  ?film wdt:P31 wd:Q11424 .                                                  # filme (conferir subclasses/séries)
  OPTIONAL { ?film wdt:P577 ?d . BIND(YEAR(?d) AS ?year) } OPTIONAL { ?film wdt:P57 ?director }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "pt,en". }
} LIMIT 40
```
Ajustar a consulta no código (a de cima é o ponto de partida; o caminho `P31/P279*` pode estourar o tempo). **Rótulos só em pt ou en**: descartar resultado cujo título só exista em japonês (nada em japonês na interface). Sem pôster (licença): capa tipográfica (ano em numeral laranja) como no design.

**Premissas.**
- **Cache 30 dias**, em disco (`Caches/Films/<geohash 1 km>-<raio>.json`, só o que a tela usa: título, ano, direção, nome do local, relação, distância). Stale-while-revalidate: abre com o cache e atualiza em segundo plano. Offline depois da primeira consulta.
- Dispara **só com o Lugar aberto** (ou a tela Filmes), uma vez por lugar por sessão, deduplicado em voo; **nunca pré-baixa** nem roda em segundo plano. No Modo de Pouco Dados só se o Lugar estiver aberto (a resposta tem poucos KB). Timeout curto (8 s) e `NetResilience`/circuit breaker como os outros serviços. Contar os bytes em `DataUsage`; **não** entra no `ApiBudget` (não é Google).
- `User-Agent` no formato da política da Wikimedia (nome do app + contato). **O contato é decisão do Vinicius**; não usar o e-mail dele sem perguntar.
- Atribuição visível: "Wikidata · CC0".
- **Sem resultado** (BH vai ter pouco): o bloco **some** do Lugar (nada de caixa vazia); a tela Filmes, se aberta, mostra "Nada filmado aqui, ainda" com **Tentar 5 km** e **Ver BH inteira**. Resultado vazio também fica em cache (30 dias) pra não repetir a consulta.
- Filmes do bairro: centro da `Area` (`Must/Services/Areas/`) e raio 1,5 km; dá pra guardar o filme como nota no lugar (sem criar Must).
Arquivos: `Must/Services/Films/WikidataFilms.swift`, `FilmsProviding.swift`, `FilmCache.swift`; UI `Must/Features/Films/FilmsView.swift` e `Must/Features/Place/FilmsSection.swift`. **Testes:** `WikidataFilmsTests` (parser de uma resposta gravada em `MustTests/Fixtures/`, lat/lng na ordem certa, descarta título só japonês, vazio), `FilmCacheTests` (30 dias, vazio também é cacheado).

## 7. Trocar de viagem (botão no canto superior esquerdo)
Tela: `TrocarViagem.png` (e `CapaEmCartaz.png`, `NovaViagem9.png` com o botão). Na **capa** (`HomeView.swift`), círculo 44 com o ícone de troca no canto superior esquerdo; a ficha de data passa pra ao lado dele (`left: 72`). Toque abre a folha **"Minhas viagens"** (sobre a capa escurecida): uma linha por viagem com quadrado na cor do lugar, nome, datas/estado e etiqueta (**agora**, GPS, plano), mais a linha tracejada **Nova viagem**. Trocar = `RegionStore` troca o container e a capa faz o fade de 0,4 s; **não apaga nada**. O modo automático (GPS) continua em Ajustes › Região.
Neste prompt a lista são as três regiões fixas (`bh`, `jp`, `it`); **Nova viagem** abre o fluxo do `prompts/28-nova-viagem.md` quando existir (até lá, a linha fica escondida atrás de um flag). Arquivos: `Must/Features/Home/TripSwitcherSheet.swift` (nova), `Must/Features/Settings/RegionSheet.swift` (reaproveitar a lógica). Testes: `TripSwitcherTests` (ordem, a ativa marcada, trocar mantém os dados das outras).

## Verificar
- `design/v8/screens/EmCartaz.png`, `LugarEmCartaz.png`, `CapaEmCartaz.png`, `DiaEmCartaz.png`, `MapaPino.png`, `MapaFiltro.png`, `Colecao.png`, `Colecionavel.png`, `ColecionavelNovo.png`, `LugarAmigos.png`, `Filmes.png`, `FilmesVazio.png`, `TrocarViagem.png`, `BotoesFontes.png` comparados com os prints do simulador. Atalhos de QA (`-debugScreen`): `emcartaz`, `lugar-emcartaz`, `mapa-pino`, `mapa-filtro`, `colecao`, `colecionavel-novo`, `lugar-amigos`, `filmes`, `trocar-viagem`, em JP e BH; Dynamic Type xxxLarge em Quero, Compartilhar, MapaPino e Lugar.
- Em cartaz: colar o texto de uma exposição vira linha na tela e micro-parada no dia, sem rede.
- Mapa: tocar no pino abre o card; "o melhor lámen perto de mim agora" em Shinjuku devolve Fuunji (board) antes de qualquer indicado; modo avião mostra só o board com o chip offline.
- Colecionável: marcar "Feito" mostra o momento; "Mandar" gera PNG 1080×1920 e 1080×1080; a página agrupa por cidade/lista/data; desfazer o feito remove o card.
- Filmes: Park Hyatt/Shinjuku lista *Lost in Translation*; Mercado Central (BH) não mostra bloco; segundo acesso gasta 0 KB (cache).
- Suíte de testes verde; `ApiBudgetTests` continua verde; abrir o app com cache quente gasta 0 KB.
