# Must — análise de produto: o app atende um viajante no dia a dia? (05/11/2026)

## 1. Veredito curto
Como **banco de lugares + montador de dia**, atende. Como **companheiro de viagem**, ainda não, por quatro buracos que aparecem no primeiro dia de uso real:

| Situação real | O que acontece hoje | O que precisa acontecer |
|---|---|---|
| Acordo e penso "quero comprar um Seiko" | Adicionar por nome busca texto solto; aparece a loja online / o site da marca. Não sabe que "quero comprar" pede uma **loja física na cidade**, nem que entrega no Airbnb não é opção. | Uma **vontade** vira uma busca por lugar físico perto do dia de hoje, com horário, tax-free e distância, e um botão "Encaixar hoje". |
| Viajo com alguém (ou quero mostrar o plano pra família) | Não há compartilhamento. O roteiro vive só no meu iPhone. | **Mandar o dia** como cartaz (imagem bonita pro WhatsApp), como link que abre no app de quem tem, ou PDF; e **viajar junto** (board e dia compartilhados). |
| Passei mal / fui roubado / perdi o passaporte | Nada no app. Eu teria que lembrar o número, o seguro, achar hospital com inglês. | **SOS** a um toque, com os números do país onde estou, o seguro já cadastrado, hospital perto com inglês, meu endereço em japonês e o consulado. |
| Quero a Suica, o ingresso, o mapa offline, a linha de trem mais perto — **agora** | Cada coisa está em uma aba diferente (Carteira, Reservas, Ajustes › Mapas, Mapa). | **Atalhos** a um deslize da capa: o que se usa dez vezes por dia, sem navegar. E "indicados por perto", mesmo fora do board. |

## 2. O que o mercado faz (e o que vale copiar)
- **Vontade → lugar físico.** Google Maps resolve "relógio Seiko" com busca por tipo de lugar perto de você, não por marca na web. A Places API (New) tem exatamente isso: `Text Search` com `locationBias` (círculo na cidade atual), `includedType` + `strictTypeFiltering`, `openNow` e `rankPreference: DISTANCE` ([doc](https://developers.google.com/maps/documentation/places/web-service/text-search)). O que o Must deve fazer é **interpretar a vontade antes de buscar**: "comprar um Seiko" → objeto "relógio Seiko", tipos `watch_store | electronics_store | department_store | shopping_mall`, cidade de hoje, só lojas físicas; sites e lojas online ficam fora por construção. Para marcas com loja própria (Seiko House Ginza, Seiko Dream Square) a lista local de "lojas de marca" complementa o Places.
- **Compartilhar.** Wanderlog e TripIt compartilham por link e convidam pro app; a pessoa sem app cai num site. O que falta neles, e o que o Must faz melhor com a identidade v8: **o cartaz do dia como imagem** (9:16, horários, mapa do percurso, o numeral do dia), que é o formato que de fato circula no WhatsApp ([comparativo Wanderlog × TripIt](https://wanderlog.com/blog/2024/11/26/wanderlog-vs-tripit), [guia de grupo do Wanderlog](https://www.whistleout.com/CellPhones/Guides/wanderlog-group-trip-planning-app)). O link `must.app/d/<id>` abre no app (Universal Link) e, na web, mostra o mesmo cartaz. "Viajar junto" usa CloudKit compartilhado (sem servidor próprio), em linha com a premissa offline.
- **Emergência.** Nenhum app de roteiro faz isso bem; os guias oficiais fazem em texto. Os números que valem no Japão: **119** ambulância/bombeiros, **110** polícia, **118** guarda costeira, **#7119** pra saber se precisa de ambulância, **Japan Visitor Hotline 050-3816-2787** (JNTO, 24 h em inglês), Japan Helpline 0570-000-911, achados e perdidos JR East 050-2016-1603 e Tokyo Metro 03-5227-5741 ([Japan Experience](https://www.japan-experience.com/plan-your-trip/to-know/before-you-travel/japan-phone-numbers)). A JNTO recomenda: saber quem ligar, ligar pro seguro **antes** do hospital e usar o AMDA pra tradução médica ([JNTO](https://www.japan.travel/en/plan/travel-insurance-in-japan/)). Itália: **112** pra tudo; Brasil: 192 SAMU, 190 polícia, 193 bombeiros. O app guarda a apólice e o telefone 24 h do seguro e **fala o endereço atual no idioma local** (reverse geocoding em japonês, com áudio).
- **Atalhos.** Citymapper mostra "linhas perto" com o próximo trem e o último; Apple Wallet abre a Suica por `shoebox://`. Google Maps e Foursquare mostram o que está "em alta" por perto. O Must já tem Descobrir (board + Google Nearby + Wikipedia + Foursquare): o que falta é **trazer três indicados pra um toque da capa**, com o motivo ("quem foi: vá antes das 18").

## 3. Navegação: o que muda
- A capa ganha **dois deslizes**: pra direita, **Atalhos** (Suica, ingressos, mapa offline, SOS, linhas perto, indicados, Quero…, Mandar); pra baixo, Bom dia / Boa noite (já no v8). Nada novo na barra.
- O **+** passa a abrir **Quero…** primeiro (vontade em linguagem natural, por voz ou texto), com Link / Texto / Nome como abas secundárias. Montar o dia continua no + por toque longo.
- **SOS** também entra como item fixo em Bolso e como ação rápida no ícone do app (Home Screen Quick Action) e na Live Activity à noite.
- **Compartilhar** aparece na Linha do dia (ícone de enviar), na Viagem (viagem inteira) e nos Atalhos.

## 4. Jornadas que passam a funcionar
1. "Quero comprar um Seiko" (09:40) → Quero… → Bic Camera a 300 m, aberto até 22h, tax-free → Encaixar hoje → entra às 18:10 entre Gyoen e Golden Gai, com aviso "saia às".
2. Ana chega amanhã e quer ver o plano → Mandar o dia → cartaz no WhatsApp; ela instala o Must → Viajar junto → vê o mesmo dia e marca o que ela quer.
3. Passei mal em Kabukichō → SOS → 119 com o endereço em japonês na tela, ou #7119 → seguro ligado antes → hospital com inglês a 1,1 km.
4. Saí do hotel → Atalhos → Suica no Wallet, ingresso de hoje, linhas perto (último trem) → "indicados por perto" sugere a Disk Union que não estava no board.

## 5. O que não fazer
- Não transformar o Quero… num chat: é uma busca com intenção, três toques, sem conversa.
- Não compartilhar via servidor próprio: CloudKit compartilhado cobre "viajar junto"; o link web é uma página estática gerada do cartaz.
- Não ligar automaticamente pra ninguém: SOS mostra, o usuário toca.

## 6. Fontes
- Places API Text Search (New): https://developers.google.com/maps/documentation/places/web-service/text-search
- Japan Experience — números úteis: https://www.japan-experience.com/plan-your-trip/to-know/before-you-travel/japan-phone-numbers
- JNTO — seguro e assistência médica: https://www.japan.travel/en/plan/travel-insurance-in-japan/
- Wanderlog vs TripIt: https://wanderlog.com/blog/2024/11/26/wanderlog-vs-tripit · grupo no Wanderlog: https://www.whistleout.com/CellPhones/Guides/wanderlog-group-trip-planning-app
