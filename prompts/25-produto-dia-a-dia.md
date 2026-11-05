# Prompt 25 · Produto no dia a dia: Quero…, Mandar o dia, SOS e Atalhos (05/11/2026)

Base: `docs/produto-dia-a-dia.md` (diagnóstico e pesquisa). Telas: `design/v8/screens/Atalhos.png`, `Quero.png`, `Compartilhar.png`, `SOS.png`. Faça depois da RODADA-22 (precisa da identidade v8 e do `DayEngine`). Pode rodar como **dois agentes em paralelo**: (1) Quero + Atalhos; (2) Mandar o dia + SOS.

## A. Quero… (vontade → lugar físico → parada)
1. Entrada: texto ou voz (Speech, pt-BR) no `+` da barra. `IntentParser` local (Foundation Models `@Generable`, sem rede): `{verb: comprar|comer|ver|fazer|beber, object: "relógio Seiko", brand?: "Seiko", category?: "relógio", when?: hoje|amanhã|qualquer}`. Sem modelo disponível: regex de verbos + o resto como objeto.
2. Busca **só de lugar físico**: Places Text Search com `locationBias` = círculo de 6 km no centro do bairro de hoje (ou GPS), `includedType` pelo mapa `categoria → tipos` (relógio → `watch_store, electronics_store, department_store, shopping_mall`; comer → `restaurant` + sub; ver → `tourist_attraction, museum, park`), `strictTypeFiltering: true`, `openNow` quando `when == hoje`, `rankPreference: DISTANCE`. Field mask Pro só (`displayName, formattedAddress, location, types, primaryType, businessStatus, photos`); horário e preço vêm do Details Essentials já em cache. Resultados sem `location` ou com `types` só de `website`/`online` são descartados. Complementa com `BrandStores.json` (lojas de marca por cidade: Seiko House Ginza, Seiko Dream Square, Apple Shinjuku, Uniqlo Ginza…).
3. Lista: índice, nome, meta (andar/seção quando houver, tax-free, aberto até, distância), à direita tempo e **"cabe HH:MM"** (o `DayEngine` tenta encaixar o lugar no dia de hoje entre duas paradas, como micro-parada de 25 min, sem mexer nas âncoras). Rodapé: "fora: lojas online · entrega no Airbnb não é opção".
4. Ações: **Encaixar hoje** (grava a parada e o aviso "saia às") e **Só guardar** (vai pra lista Shop/Eat/… com `source.kind = "quero"` e o texto original). Testes: `IntentParserTests` ("quero comprar um Seiko", "comer um tonkatsu bom perto", "ver o Fuji amanhã"), `WantSearchTests` (nunca devolve item sem coordenada).

## B. Mandar o dia (cartaz, link, PDF, viajar junto)
1. **Cartaz**: `DayPosterRenderer` (SwiftUI → `ImageRenderer`, 1080×1920): identidade v8 na cor do lugar, "Dia N · bairro", lista de paradas com horário, mini-mapa do percurso (MapLibre snapshot offline), numeral gigante, rodapé "must · guia de bolso". Opções: com horários / mapa / preços / QR dos ingressos. `ShareLink` com a imagem; "Mandar cartaz pelo WhatsApp" usa o share sheet com o WhatsApp primeiro quando instalado.
2. **Link**: Universal Link `https://must.app/d/<id>` (domínio a configurar; até lá, `must://d/<id>` + fallback). O payload do dia vai dentro do link (base64 comprimido, só paradas, horários e lugares; sem fotos) pra abrir **sem servidor**; na web, uma página estática no R2 renderiza o cartaz a partir do payload.
3. **PDF da viagem**: um dia por página, mesmo renderer.
4. **Viajar junto**: `CKShare` do board e dos dias (CloudKit compartilhado; conta iCloud de cada um). Quem aceita vê e edita; conflitos: última escrita vence por campo; feito/não feito é por pessoa. Fora do escopo: chat, votação.
5. Onde aparece: ícone de enviar na Linha do dia, "Mandar a viagem" na Viagem, botão nos Atalhos.

## C. SOS
1. `EmergencyKit.json` por país: números (JP 119/110/118/#7119, Japan Visitor Hotline 050-3816-2787; IT 112; BR 192/190/193), frases com áudio, consulado/embaixada do Brasil (endereço, telefone, plantão), e os campos do usuário: seguradora, apólice, telefone 24 h, instruções ("ligue antes do hospital, peça recibo e diagnóstico em inglês"), tipo sanguíneo e alergias **opcionais, só no aparelho** (não vão pro iCloud nem pro backup `.json` por padrão).
2. Tela: três botões grandes (ambulância, polícia, hotline em inglês), seguro com botão de ligar, **hospital perto com atendimento em inglês** (lista curada por cidade em `Hospitals.json` + Places `hospital` como fallback), **onde estou** no idioma local (reverse geocoding em `ja`/`it`, com "mostrar" em tela cheia e áudio TTS) e consulado. Tudo offline (o kit vem no app; o geocoding usa o último endereço conhecido quando não há rede).
3. Entradas: deslize da capa → Atalhos → SOS; Bolso; Home Screen Quick Action "SOS"; na Live Activity à noite. `tel:` só abre o discador: o app nunca liga sozinho.

## D. Atalhos (deslize da capa pra direita)
1. Painel sobre a capa (a capa fica atrás, deslocada): grade 2×2 — **Suica** (saldo anotado + `shoebox://` pro Wallet), **Ingressos e reservas de hoje**, **Mapa offline** (estado e tamanho; abre o Mapa), **SOS**; depois **Linhas perto** (estação mais próxima pelo GPS, chips das linhas com o próximo trem pro destino de agora e o último), **Indicados por perto** (3 lugares fora do board, do `NearbyService`, com o motivo em uma linha), e os botões **Quero…** e **Mandar**.
2. Tudo cacheado: linhas vêm da base de estações já usada pelo Guia; indicados vêm do último `NearbyService` no Wi-Fi.
3. Gesto: pan da capa pra direita (ou toque no canto). Dynamic Type xxxLarge: a grade vira 1 coluna.

## Verificar
- "quero comprar um Seiko" em Shinjuku → Bic Camera no topo, sem nenhum site; "Encaixar hoje" cria a parada entre Gyoen e Golden Gai e o aviso.
- Mandar o dia → imagem 1080×1920 igual ao `Compartilhar.png` (cartaz), link abre o dia no simulador (`xcrun simctl openurl`), PDF com 14 páginas.
- SOS em modo avião: tudo aparece, inclusive o endereço (último conhecido). Trocar pra Itália muda os números pra 112.
- Atalhos: deslize abre em < 100 ms com dados em cache; Suica abre o Wallet.
- `qa-screens.sh`: `atalhos`, `quero`, `compartilhar`, `sos` em JP e IT. Testes dos itens A1/A2, B1 (snapshot do cartaz), C1 (kit por país), D1 (gesto).
