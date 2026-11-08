# Must — memória do projeto para o Claude Code

App iOS pessoal (um usuário: Vinicius) que transforma um board de "Musts" (Must eat, drink, see, listen, shop…) num guia de dia: monta o roteiro a partir de intenção, GPS, horário de funcionamento, tempo e orçamento. Primeira versão roda em **Belo Horizonte** (pra testar com GPS real); a viagem ao **Japão** (11–24 nov 2026, Tóquio → Kyoto → Tóquio) é a segunda região. Um menu escondido troca a região.

## Decisões que não mudam sem conversar
- **iOS only, SwiftUI, SwiftData, iOS 26+, Xcode 26.** Sem backend. Sem conta. Tudo no iPhone.
- **Uma `Region` por vez** (`bh` | `jp`). Cada região tem o próprio `ModelContainer` (arquivo `must-bh.store`, `must-jp.store`), moeda, fuso, cidades, board e gastos. Trocar região = trocar container, não apaga nada.
- **Viagens dinâmicas (prompt 28, aprovado em 06/11/2026):** `Region` fixa vira `Trip` (registro `trips.json` no App Group, `TripStore`), um container por viagem; `bh`/`jp`/`it` viram as viagens de fábrica com os mesmos arquivos `.store` (migração de dados = nenhuma). Conteúdo por país em `data/countries/<cc>.json` (`CountryProfile`, genérico quando falta). Cidade nova: bairros gerados dos Musts; mapa offline só se houver pack no catálogo (senão o app mostra o comando do `tiles.sh`); destino pelo `MKLocalSearchCompleter`; automático = viagem com hoje nas datas › país do GPS › casa.
- **Região:** abre sozinha onde o GPS está (Brasil → BH, Japão → Japão). Ajustes › Região tem Automático / BH / Japão (pedido do Vinicius em 01/11/2026); escolher uma região à mão desliga o automático.
- **Menu escondido:** em Ajustes, 5 toques no rótulo de versão abrem a sheet de testes (região + simular data/GPS/nuvens + dados ao vivo on/off + zerar board). Isso não aparece na UI normal.
- **Seeds crescem sem apagar nada:** board existente recebe uma vez o que o seed ganhou (`RegionStore.mergeSeed`, ids em `Settings.seenSeedIds`); o que ainda bate com o seed antigo é realinhado (`realign`). Tóquio 1 e 2 contam como a mesma cidade no solver.
- **Solver determinístico** monta o dia (regras abaixo). O modelo de linguagem só interpreta pedido em texto/voz → parâmetros, e conversa no Assistente. Nunca inventa lugares: só escolhe entre os do board.
- **IA no aparelho primeiro:** Apple Foundation Models (`FoundationModels` framework, iOS 26) com *tool calling* sobre o catálogo. Fallback opcional na nuvem: Claude Haiku (structured outputs) só pra links difíceis — **só Haiku com `effort: low`, sem thinking, nunca modelo mais caro (regra crítica do Vinicius; `CloudBoostTests` garante)** — chave em `Secrets.plist` (gitignored), e desligável em Ajustes.
- **Dados vivos:** Google Places API (New) só pra horários/preço/placeId (snapshot em cache, 1.000 chamadas grátis/mês — pedir `id`-only quando não precisar de detalhes); Open-Meteo pro tempo (JMA no Japão); rotas por deep link (Apple Maps / Google Maps) + MapKit ETA; **mapa em MapLibre Native** (SwiftPM, único pacote externo) com style "papel em relevo" (`Must/DesignSystem/MapStyle/`) e Protomaps PMTiles por cidade, **baixados no app** (Ajustes › Mapas offline, pedido do Vinicius em 02/11/2026) de um bucket R2 público (`MAP_TILES_URL`); sem baixar, o mapa lê o mesmo arquivo do R2 pela rede. Catálogo em `data/map-packs.json`, gerar com `scripts/tiles.sh` e subir com `scripts/tiles-upload.sh` (ver `data/map-packs.md`); nada de tiles no bundle; **Wikimedia Commons** (API sem chave; só CC BY/BY-SA, CC0, domínio público) pra foto de fundo das listas e heroes, sempre com crédito visível. (Era Flickr, mas o Flickr parou de dar chave de API pra conta grátis — decidido em 01/11/2026.)
- **Regras do dia** (ver `prompts/05-dia.md`): uma refeição por janela (almoço, jantar) salvo exceção explícita; reservas são âncoras fixas; "fica pro fim" só entra nos últimos dias da cidade; orçamento diário com exceções marcadas por lugar; lugar de outra cidade nunca entra; respeita tipo de dia (livre, compras, noite, fotografia, templos, descanso) e quanto andar.
- **Tipos de Must** (prompt 13): `MustList.kind` = place | photo | art | sport; dados em `Place.extra` (`photo`/`art`/`sport`). Sol calculado no aparelho (`SunService`, NOAA); golden = sol de 6° até o pôr, azul = do pôr a −6° (como no design). Must see virou templos/mirantes (teal); museus ficam em art.
- **Central da viagem** (prompts 14–15): o Must guarda tudo que tem data, código ou cartão. Tipo novo `ListKind.experience` ("Must do", cor night) com `Place.extra.experience`; `Ticket` ligado a `Session`/`Reservation` é **âncora** no solver e aparece em Reservas, Hoje e Live Activity. Ingresso entra por um fluxo só (Share Extension `MustShare`, câmera/VisionKit, Fotos, colar, arquivo, à mão), lido **no aparelho** (PDFKit, Vision, `.pkpass` = zip com `pass.json`, extrator com confiança por campo) e conferido antes de salvar. `WalletItem` (Suica, JR Pass, cartão, eSIM, Visit Japan Web, seguro, passaporte) só lista e abre — sem integração com o Wallet além de `shoebox://`; saldo da Suica é anotado à mão. `Flight` com checklist por fase (72 h, malas, aeroporto, pouso) a partir de modelos em `Must/Data/checklists/`.
- **Status de voo:** só **AeroDataBox** (RapidAPI, `AERODATABOX_KEY`, header `X-RapidAPI-Key` + `X-RapidAPI-Host: aerodatabox.p.rapidapi.com`) — decidido pelo Vinicius em 02/11/2026; aviationstack fora por ora. Plano grátis = **400 unidades/mês** (uma consulta por número de voo custa 2): cache por voo, só consultar de 24 h antes até o pouso, no máximo a cada 30 min, nunca em loop/background; sem chave ou sem cota, mostra o horário programado.
- **Experiências:** por enquanto **só colando link** (Viator, Klook, Airbnb, GetYourGuide, ingressos) — decisão de 02/11/2026. A Viator (afiliado Basic, header `exp-api-key`) fica pra depois, atrás do protocolo `ExperienceSource`. Nada de scraping.
- **Voos:** status ao vivo só pela **AeroDataBox** (RapidAPI, Basic grátis 400 unidades/mês); sem chave, mostra o horário programado.
- **Por perto, agora:** board + Google Nearby (popularidade) + Wikipedia geosearch + Foursquare, ranqueado no aparelho. Nunca push; só na Home e na tela própria.
- **Guia, não banco de dados** (prompt 18, 02/11): a Home mostra só o dia (bairro, agora, saia às) — orçamento vai pra Ajustes. Planejamento por **bairro + vizinhos** (`Area`, tabela curada com tempos de trem) e guia com deslocamentos entre paradas. **Resiliência é requisito**: nada de JSON decodificado em `body`, serviços fora do main, `NWPathMonitor`, timeouts curtos, circuit breaker, fila de saída offline, dia baixado pro offline. Visual: selo de estação por bairro, kanji grande, cor oficial das linhas.
- **Importação/exportação** pelo JSON em `data/board.schema.json`. Seeds em `data/seed-bh.json` e `data/seed-jp.json` (coordenadas `approx: true` são chute — resolver no Places na primeira sincronização).

## Premissa: visual e econômico em dados (03/11/2026, pedido do Vinicius)
O app tem que ser **bem visual** (foto em todo lugar que mostra um lugar ou bairro) e ao mesmo tempo **gastar o mínimo de internet**. Valem pra toda tela e todo serviço, novo ou existente:
- **Cache primeiro, sempre.** Toda leitura mostra o que está no aparelho na hora e atualiza em segundo plano (stale-while-revalidate). Nenhuma tela espera a rede pra aparecer.
- **Imagem: uma por lugar, baixada uma vez.** Foto principal em 800 px JPEG/HEIC (qualidade 0,7), miniatura gerada no aparelho (240 px) — nunca uma segunda chamada. Cache em disco com teto (300 MB, LRU) e validade de 30 dias; `URLCache` pra respostas GET.
- **Pré-baixar só no Wi-Fi** (e com o dia aceito, o bairro escolhido ou o board novo); no celular, só o que está na tela. Respeitar **Modo de Pouco Dados** (`allowsConstrainedNetworkAccess`): nele, nada de pré-download nem foto nova fora do Lugar aberto.
- **Pedir só os campos usados** (field masks do Google), agrupar o que dá numa chamada, deduplicar requisições em voo, nunca repetir a mesma chamada na mesma sessão.
- **Offline é estado normal, não erro:** chip "sem internet · offline ok", fila de saída pro que precisa de rede, e o dia aceito 100% utilizável sem conexão.
- **Medir:** Ajustes › Dados mostra MB usados no mês (celular × Wi-Fi), cache em disco e cota do Google; QA confere que abrir o app com cache quente gasta 0 KB.

## Design (v5, tema claro) — fonte da verdade em `design/`
- Telas: `design/screens/*.png` (render) e `*.html` (HTML de referência, abrir no navegador; os links entre telas funcionam). `must-light.css` tem os tokens.
- Fundo branco `#FFFFFF`, tinta `#121316`, secundário `#7A7F87`, superfícies `#F1F2F4` / `#F6F7F9`, borda `#EEF0F3`.
- Acentos: verde `#22DD7E` (texto sobre ele `#0B2A18`) e azul `#2B7BFF` (texto `#0F3B8C`). Formas 3D (elipses com gradiente) atrás, cards de vidro empilhados e girados 1–2°.
- Cor por Must (claro → forte, texto escuro): eat `#B9F5CF→#22DD7E/#0B2A18`, drink `#9FD6FF→#2B7BFF/#0F3B8C`, coffee `#FFD2BF→#FF7A45/#5A2200`, see `#DCCFFF→#8B5CF6/#2E1065`, temple `#B8F2EA→#14B8A6/#063F3A`, listen `#FFC6DA→#FF4D8D/#5A0F2E`, shop `#FFE3A3→#FFB020/#4A2E00`, night `#C9D2FF→#5B6CFF/#161C66`. **Fotos vivas (05/11/2026, pedido do Vinicius — substitui o "gradiente a 82%" do v5):** foto em cor cheia; a cor do Must só numa rampa atrás do texto (`TintedPhoto`, `PhotoStyle.vivid`); heroes escurecem só onde tem texto e têm zoom lento (desliga com Reduzir movimento). Capa de lista: foto escolhida à mão › foto do Google de um lugar da lista já no disco › Commons (`ListCover`, nunca baixa nada). `-photoStyle classic` (DEBUG) mostra o v5.
- Fontes (bundle, OFL): **Archivo** (UI), **Instrument Serif Italic** (voz do usuário, legendas), **Geist Mono** (horas, ¥/R$, códigos de estação), **Zen Kaku Gothic New** (kanji). Escala: título 30/600, nome de lista 20, lugar 17/600, corpo 15, meta 13, serif 18–20, mono 13, micro 11 mono caixa alta com tracking .1em.
- Ícones: set próprio em `design/icons/*.svg` (traço 1.6, viewBox 24). Importar como *custom SF Symbols*; `design/icons/README.md` dá o SF Symbol de fallback de cada um.
- 済 (feito) é o selo do app: círculo verde com o kanji.

## Convenções de código
- Pastas: `App/`, `DesignSystem/`, `Models/`, `Data/` (import/export, seeds, Region), `Services/` (Places, Weather, Photos, Routes, Location, Intelligence), `Solver/`, `Features/<Tela>/`, `Widgets/` (extension). Todas ficam dentro de `Must/` (o APFS não diferencia `Data/` de `data/`); testes em `MustTests/`.
- Projeto gerado por **xcodegen**: edite `project.yml` e rode `xcodegen generate` (nunca edite o `.pbxproj` à mão). Arquivo novo dentro de `Must/` entra sozinho no target do app; `Must/Widgets/` é só da extensão. Team `BS5ZUHVH99` (Personal Team).
- Views pequenas; estado em `@Observable` por feature; nada de singletons globais além de `RegionStore` e `Services`.
- Tudo em pt-BR na UI. Datas e moeda via `FormatStyle` com o locale/currency da região.
- Sem dependências externas de UI além do MapLibre (mapa). Se precisar de Markdown no chat, usar o nativo.
- Chaves: `Secrets.plist` (não commitado) com `GOOGLE_PLACES_KEY` e, opcionais, `ANTHROPIC_KEY`, `MAP_TILES_URL`, `PROTOMAPS_KEY`, `FOURSQUARE_KEY`, `REDDIT_CLIENT_ID`, `AERODATABOX_KEY` (Viator/GYG/aviationstack: não usar por enquanto). Toda fonte com chave é opcional: sem chave, a fonte some sem erro. `Secrets.example.plist` commitado.
- Testes: unitários do Solver e do parser de JSON obrigatórios; UI tests não.
- Commits pequenos, mensagem em português, um prompt = um ou mais commits.

## Como o trabalho está dividido
Os prompts em `prompts/` são executados em ordem (01 → 25; a rodada atual é a `prompts/RODADA-22.md` (23 + 24 com agentes em paralelo); depois dela, o `25-produto-dia-a-dia.md` e o `26-capa-inteligente.md` em paralelo; o 22 foi substituído). Cada um diz o que entregar e como verificar. Antes de cada prompt, olhar os PNGs das telas citadas.

## Tema da viagem (03/11/2026, pedido do Vinicius) — prompt 20
- Ao entrar numa viagem/região, o app ganha a **bandeira do país** (círculo 22 pt ao lado da data, vetor, offline) e um **tom leve** do país: lavado no topo das telas principais, tinta dos selos, ponto dos títulos de seção e da aba ativa, rótulo da cidade.
- Tokens por país em `TripTheme` (JP vermelho #BC002D / selo #C8102E; BR verde #009C3B / amarelo claro), derivados de `City.country`.
- **Identidade não muda:** botões verde #22DD7E, links azul #2B7BFF, tinta #121316, cores das listas, linhas de trem e pinos do mapa ficam iguais.
- Referência: `design/screens/Home6.png` (Japão) e `Home6BH.png` (Brasil).

## Layout das telas (03/11/2026)
- Os PNGs de `design/screens/` foram realinhados: nada de texto sobreposto, cortado no meio ou embaixo da tab bar.
- No app, montar as telas com stacks (`VStack`/`ScrollView`), nunca posições fixas: texto que quebra empurra o bloco seguinte. Metadados de linha única usam `lineLimit(1)` + truncamento; títulos no máximo 2 linhas.
- Listas que continuam rolam por trás de um fade branco antes da tab bar ou dos botões; linhas de chips rolam na horizontal.
- Fotos têm sempre placeholder de cor enquanto carregam (premissa offline).

## Selos sem japonês (05/11/2026, pedido do Vinicius: "não falo japonês")
- O selo do bairro (`StationStamp`) mostra **sigla latina + nome**, nunca kanji: código de estação JR quando existe (Shinjuku SJK, Shibuya SBY, Ueno UEN, Harajuku HJK, Akihabara AKB, Ikebukuro IKB), senão 3 letras do nome (Ginza GNZ, Asakusa ASK). Selo pequeno: só a sigla. Mesmo padrão do Brasil (SAV / BH · 1897).
- Rótulos de lugar/bairro na interface sempre em letras latinas (Nakano, Gyoen, Kabukichō). Kanji só onde tem uso prático: nome local do lugar pra mostrar a um taxista ou atendente (`nameLocal` no Lugar), nunca como enfeite.
- `Area` ganha `stampCode` (sigla) e usa o nome latino como segunda linha; o `stampText` em kanji deixa de ser exibido.

## Identidade v8 — "guia de bolso, o dia inteiro" (05/11/2026, pedido do Vinicius) — prompt 23
- **Substitui** o visual v5–v7. Conceito e diagnóstico em `docs/conceito-v8.md`; telas em `design/v8/screens/`.
- **Três cores**: tinta #121212, papel #F2F0EA, laranja #FF4A1C (a única cor: ação e "agora"). Cinzas só pra texto secundário (#6B6B66 sobre papel, #A3A39C sobre tinta). Sem lima, azul, cor por lista ou cor oficial de linha de trem.
- **Cor do lugar** (`TripTheme`): só a capa do dia, a Boa noite e o anel do selo. Japão #D7000F + branco; Brasil #007A33 + branco; sem viagem: papel + tinta.
- **Fontes**: Bricolage Grotesque (display e numeral gigante), Schibsted Grotesk (texto), Martian Mono (ficha técnica). Substituem Archivo, Geist Mono, Instrument Serif e Zen Kaku.
- **Texturas**: arcos de 1 pt, um numeral gigante por tela (sempre com significado), micro-rótulos nos cantos. Sem degradê, sem foto lavada atrás de texto.
- **O dia**: 9 paradas por padrão (ritmo 6/9/12), com micro-paradas tracejadas e deslocamentos como itens. Cinco momentos: Bom dia → Agora/Ir → Lugar/Dicas/Bolso → Guia/Linha/Listas → Boa noite. O app fala sozinho (Live Activity + 4 avisos locais).
- **Ícone**: arcos + ponto laranja sobre tinta ("você está aqui"); nunca muda com a viagem. Nada em japonês na interface.

## Itália · Roma (05/11/2026, pedido do Vinicius) — prompt 24
- Terceira região `it` (Roma), moeda EUR, cor do lugar **azzurro #1F5FB4** + branco (não repete o verde do Brasil nem o vermelho do Japão). Seed em `data/seed-it.json` (63 Musts, 7 reservas); datas da viagem ainda **[A CONFIRMAR]** (placeholder abr/2027).
- Regras locais no Bolso e no solver: bilhete BIT validado, coperto sem gorjeta, nasoni, igrejas com ombro e joelho cobertos, jantar nunca antes das 19:30, riposo 13–16, Borghese com turno de 2 h.
- Telas em `design/v8/screens/*IT.png`. Fotos de referência (Wikimedia Commons, CC) em `design/v8/screens/photos/` — só pro design; no app as fotos vêm do Google/Commons com crédito.

## Produto no dia a dia (05/11/2026, pedido do Vinicius) — prompt 25
- Diagnóstico em `docs/produto-dia-a-dia.md`. Quatro capacidades novas: **Quero…** (vontade em linguagem natural → só lojas/lugares físicos na cidade de hoje → "Encaixar hoje"; lojas online nunca entram), **Mandar o dia** (cartaz 1080×1920 pro WhatsApp, link que abre no app sem servidor, PDF, "viajar junto" via CloudKit compartilhado), **SOS** (números do país, seguro cadastrado, hospital com inglês, endereço no idioma local, consulado; offline; nunca liga sozinho) e **Atalhos** (deslize da capa pra direita: Suica, ingressos, mapa offline, SOS, linhas perto, indicados fora do board).
- O `+` da barra abre o Quero… primeiro; Link/Texto/Nome viram abas secundárias.

## Capa inteligente (05/11/2026, pedido do Vinicius) — prompt 26
- A capa sabe o bairro (GPS por célula), o que você deveria estar fazendo (dia aceito) e mostra até 4 cartões "Agora vale" escolhidos por um ranker local: plano, Musts perto e abertos, fecha logo, eventos de hoje, luz/tempo, indicados fora do board. Cada cartão diz o motivo.
- Eventos sem API paga: Bandsintown + Ticketmaster Discovery + feeds públicos por cidade (validar URLs), cache de 6 h no Wi-Fi; Haiku low só pra estruturar feed sem estrutura, 1×/dia. Nunca inventa evento.

## O corte (07/11/2026, pedido do Vinicius) — prompt 30
- **Linguagem de todas as telas principais**: foto em cima (P&B contrastada × cor do lugar, trama de pontos, arcos de 1 pt), **régua preta grossa**, papel embaixo com índice separado por réguas de 2 pt. Brutalista: sem degradê, sem sombra, sem carrossel; cor só em bloco inteiro (**laranja = seu**, **tinta = de fora do board**). Referências: `design/v8/screens/CorteFundo.png` (opção C), `CorteFluxo.png`, `CorteGesto.png`.
- **Puxar a régua = "quero…"**: só puxa a régua com pegador laranja e texto ("↓ puxe · quero…"); as outras são estáticas. Resultado em duas faixas: seus Musts do pedido **mesmo longe** (cidade de hoje) e o que tem **perto agora** fora do board. Sem API nova (é o Quero do prompt 25).
- **Passo a passo** na primeira vez e na primeira entrada de cada viagem; depois a régua fala e cutuca (para após 3 usos). Mapa, Ajustes, sheets, SOS e Nova viagem ficam fora do corte.

## Navegação v9 (08/11/2026) — prompt 31 · mapa em `design/v9/Fluxos.png`
- **Barra**: Hoje · Explorar · Musts · Viagem · `+`. Faixa de tinta de largura total (sem cápsula nem sombra); aba ativa = bloco de papel com filete laranja de 3 pt; `+` = célula laranja de 74 pt. Some com o quero aberto e nas telas que já escondiam; acima de XL só ícones. `MustTab.explorar` é a aba Explorar (substituiu Mapa e Guia).
- **Cantos fixos** nos blocos de foto: esquerda = ⇄ (capa), ← (empurrada) ou ✕ (sheet/tela cheia); direita = ✦ (`AssistantCorner`, abre o Assistente). Botões quadrados de 44 pt, borda 2 pt, sem raio (`V8CornerButton`). Nada de FAB redondo de IA (Mapa/Dia saíram).
- **Assistente** (`AssistantView`, sheet sem raio): abre por ✦, deslizar ← na capa, "Continuar no Assistente" do Quero, `must://assistente`. **Página 1 = Dicas** (`DicasPage`, "O que eu sei de hoje": filtros Agora · bairro · país · Salvas); a conversa fica embaixo e a primeira pergunta vira a conversa ("↑ dicas" volta). `Route.dicas` não empilha tela: `AppRouter.push(.dicas)` abre o Assistente.
- **Quero × pergunta** (`QueroQuestion`): texto com "?" ou que começa com "dá tempo", "quanto", "como", "posso", "vale", "e se", "o que"… vira a faixa tinta "✦ isso é uma pergunta" (resposta curta do mesmo `ChatModel`: Foundation Models quando há, senão palavra-chave) + "Continuar no Assistente"; os chips de lugar continuam embaixo; nenhuma busca de lugar roda.
- **Bolso = Atalhos + Bolso**: deslizar → (ou a alça da borda) abre o Bolso empilhado, com Suica, ingressos de hoje, mapa offline, SOS e linhas perto no topo (`AtalhosPanel`) e a grade do Bolso embaixo. "Indicados fora do board" saíram (vão pro Explorar e pro quero).
- **`+` = Quero · Guardar**: campo do quero em cima; embaixo Link · Vídeo · Texto · Ingresso · Presente e "Buscar por nome"; segurar o `+` = Montar o dia. Presente abre a folha `Sheet.presenteNovo(source:)`.
- **Viagem**: linha fixa "Minhas viagens" (bandeira + moeda da atual) no topo da aba, além do ⇄ da capa.

## Explorar, Presentes e o resto da rodada final (08/11/2026) — prompt 31
- **Explorar** (conceito B, `design/v9/ExplorarB-*.png`, `Must/Features/Explorar/`): cada bairro é uma página de foto com o **recorte do mapa** (snapshot do MapLibre em cache) e o **trilho de estações** na borda direita (ordem por tempo de trem; hoje/feito marcados); régua "↓ quero em <bairro>"; recorte aberto = único mapa vivo, 4 camadas (aberto agora · seus Musts · fora do board · trilha do dia). Absorveu o Guia (`.guia` abre o Explorar no bairro); o mapa completo (busca, packs offline) fica na rota `.mapa`.
- **Presentes mora na aba Viagem** (linha fixa "Presentes · 5 faltam de 6" abaixo de "Minhas viagens" em `ProximosView`; saiu da aba Musts) e é uma **lista fácil** estilo Lembretes no visual do corte (09/11/2026): cabeçalho baixo, filtro Faltam · Todos · pessoa, uma linha por presente (caixa quadrada, nome, "loja · preço", marcador laranja "perto" só quando a loja está a ≤10 min e aberta), comprado riscado e no fim do grupo, deslizar = comprado/apagar com desfazer, campo "Novo presente…" no fim ("nome pra Ana", "nome — Ana", link colado; lógica em `GiftQuick`/`GiftFilter`, `Models/GiftList.swift`); detalhes na ficha `PresenteItemView`.
- **Presentes** (`Gift`, `Must/Features/Presentes/`): lista por pessoa com checklist; adicionar por nome/link/vídeo/local/foto; loja perto (≤10 min, aberta) vira linha laranja na capa, faixa no quero e micro-parada no dia; `gifts` no JSON do board (schema v3).
- **Relógio único e plano vivo** (`DayClock`, `DayReplanner`): capa, Linha, Agora e Explorar leem a mesma parada/saia às; passou da hora sem "feito" → o resto do dia se refaz sozinho (âncoras fixas). Nunca "você deveria".
- **Confiança do dado** (`DataConfidence`): "horário estimado"/"local aproximado" nas linhas; "aberto agora" e "não dá hoje" só afirmam com dado confirmado; "não dá hoje" sempre com motivo.
- **Quero sem vazio à toa** (`WantOrigin`): origem = GPS só dentro da cidade da viagem, senão o bairro/cidade da viagem; verbo sozinho vale; fontes externas aprovadas na faixa tinta; vazio sempre com motivo.
- **Ingressos**: camada de texto do PDF › `RecognizeDocumentsRequest` › extrator de campos › Foundation Models só pros campos incertos; corpus em `MustTests/Fixtures/tickets/`, relatório em `docs/ingressos-leitura.md`. Sem modelo de terceiros por ora.
- **Testes: rodar com `scripts/test.sh [simulador] [derivedData]`** — fecha o app e reinicia o simulador se o XCTest não conectar no `testmanagerd` (falha conhecida do simulador depois de sessões de prints).

## Grupo (08/11/2026, pedido do Vinicius)
- Sem servidor: tudo passa pelo compartilhar do iOS (WhatsApp) e fica só no aparelho. Bloco **Grupo** na aba Viagem: Pessoas (`Companion`) · Votar (`PlacePoll`, cartaz "A ou B?" 1080×1920, você marca os votos; vencedor ganha "+ dia") · Acertar contas (`Expense.paidBy`/`splitWith`, lógica em `Must/Services/Group/Settlement.swift`, em centavos inteiros) · Mandar o dia.
- O quero responde perguntas sem IA com `QuestionAnswerer` (dá tempo, preço, horário, como chego, vale a pena, agora) a partir do board, `DayClock` e `DaySolver`; nunca inventa número.
- Rótulos do mapa só em letras latinas: o style usa `name:en` quando a feição tem `script` (não latina), senão `name`.
