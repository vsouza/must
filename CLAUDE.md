# Must — memória do projeto para o Claude Code

App iOS pessoal (um usuário: Vinicius) que transforma um board de "Musts" (Must eat, drink, see, listen, shop…) num guia de dia: monta o roteiro a partir de intenção, GPS, horário de funcionamento, tempo e orçamento. Primeira versão roda em **Belo Horizonte** (pra testar com GPS real); a viagem ao **Japão** (11–24 nov 2026, Tóquio → Kyoto → Tóquio) é a segunda região. Um menu escondido troca a região.

## Decisões que não mudam sem conversar
- **iOS only, SwiftUI, SwiftData, iOS 26+, Xcode 26.** Sem backend. Sem conta. Tudo no iPhone.
- **Uma `Region` por vez** (`bh` | `jp`). Cada região tem o próprio `ModelContainer` (arquivo `must-bh.store`, `must-jp.store`), moeda, fuso, cidades, board e gastos. Trocar região = trocar container, não apaga nada.
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
Os prompts em `prompts/` são executados em ordem (01 → 22; depois da RODADA-21, o `prompts/22-inicio-v7.md`). Cada um diz o que entregar e como verificar. Antes de cada prompt, olhar os PNGs das telas citadas.

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
