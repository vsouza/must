# Prompt 26 · Capa inteligente — "Agora vale" (05/11/2026)

Pedido do Vinicius: "a home deveria ser mais inteligente, entender o bairro que estou, ver se tem algo que deveria estar fazendo; sugestões, eventos". Tela: `design/v8/screens/CapaInteligente.png`. Faça depois da RODADA-22 (precisa da capa v8, do `DayEngine` e do `NearbyService`). Pode rodar junto com o prompt 25 (fronteiras diferentes: aqui é `Must/Services/Suggest/**`, `Must/Services/Events/**` e a capa).

## 1. O que a capa passa a saber
- **Onde você está**: bairro por reverse geocoding em célula de ~300 m (já previsto no prompt 21), com fallback no último conhecido. "Você está em Lourdes" substitui "Hoje é X" quando não há dia montado ou quando você saiu do bairro do plano.
- **O que deveria estar fazendo**: se há dia aceito, a parada corrente e o atraso ("você deveria estar no Mercado Novo desde 17:40"); se não há, "nada marcado" e a sugestão de montar o resto do dia/noite ("Montar a noite · Lourdes e Savassi", só com o que ainda cabe até o fim do dia).
- **O que vale agora**: uma fileira de **até 4 cartões**, escolhidos por um ranker local, cada um com o motivo em uma linha ("perto · no board · hora certa").

## 2. `SuggestionEngine` (local, determinístico, sem rede no momento de abrir)
Candidatos (todos já em cache no aparelho):
1. **Plano**: parada corrente/atrasada do dia aceito.
2. **Musts perto e abertos**: do board, a ≤ 15 min a pé do bairro atual, abertos agora, com janela compatível (jantar depois das 19h, café até 11h…), que você ainda não fez.
3. **Fecha logo**: Must perto que fecha em ≤ 60 min (último horário).
4. **Eventos hoje**: do `EventsService` (abaixo), a ≤ 20 min, começando nas próximas 4 h, filtrados pelo seu gosto (listas que você mais usa: drink, listen, art…).
5. **Luz e tempo**: golden de hoje (se ainda não passou) ou de amanhã, com o Must photo mais perto e a previsão; chuva nas próximas 2 h → sugerir Musts cobertos (museu, kissaten).
6. **Indicados por perto** (fora do board): só quando sobra vaga e com o motivo ("em alta hoje", "quem foi: …").
Pontuação: `relevância = proximidade (0–3) + encaixe de horário (0–3) + no board (2) + gosto (0–2) + urgência (fecha logo / começa logo: +2) − repetição (já sugerido hoje: −2)`. Empate: o que fecha antes. Nunca mais de um evento e um indicado entre os 4. Recalcula ao mudar de célula, a cada 15 min com o app aberto e ao aceitar/fechar o dia. Tudo em `SuggestionEngineTests` com cenários fixos (Lourdes 18:10 nublado = os 4 cartões do PNG).

## 3. `EventsService` — fontes de eventos, por cidade
Decisão: **sem API paga** e sem depender de uma fonte só. Ordem de tentativa, tudo cacheado por 6 h no Wi-Fi (Modo de Pouco Dados: só cache):
- **Bandsintown Events API** (shows por lat/lng, grátis pra apps com `app_id`) — música em qualquer cidade; validar cobertura em BH e Tóquio.
- **Ticketmaster Discovery API** (grátis, 5.000 chamadas/dia; `latlong` + `radius`) — boa nos EUA/Europa (Roma), fraca no Japão e no Brasil; usar como complemento.
- **Feeds públicos por cidade** (RSS/Atom, sem chave, lidos com `FeedParser` próprio): Tóquio — Time Out Tokyo, Tokyo Cheapo (events), Tokyo Weekender; Roma — Time Out Roma, Romeing; BH — Sympla (página pública da cidade), Curta Mais, agenda do Palácio das Artes. **URLs a validar na implementação** (o agente confirma cada feed e registra em `EventsSources.json`; feed quebrado é ignorado em silêncio).
- **Fallback nuvem** (só com rede e só 1×/dia por cidade): Haiku, effort low, com os títulos dos feeds pra extrair `{título, lugar, lat/lng?, início, fim, preço, link, categoria}` quando o feed vem sem estrutura. Nunca gera eventos do nada.
Modelo: `Event { id, title, venue, lat, lng, start, end, price, url, source, category }`, guardado no SwiftData por região com `expiresAt`. Evento vira parada como "experiência" ao tocar "Encaixar" (mesmo fluxo do Quero…).
Fora: Peatix e e+ (sem API pública), PredictHQ (pago), Eventbrite (API de busca descontinuada).

## 4. A capa
- Blocos: ficha técnica (dia, cidade, tempo, pôr do sol com "já foi"), "você está em <bairro>", linha de estado ("18:10 · nada marcado · 6 Musts a 15 min"), **Agora vale** (fileira horizontal de cartões: Must = tinta, evento = laranja, demais = papel; cada um com rótulo, nome, meta e o motivo), card "Noite, pra onde? → Montar a noite", numeral do dia, barra.
- Toque no cartão abre o Lugar/evento; toque longo = "não me sugere isso hoje". Rodapé micro com as fontes usadas ("board · Places · Sympla · previsão · sol").
- Sem GPS: usa o bairro do hotel. Sem rede: só candidatos 1, 2, 3 e 5 (tudo local) — a capa nunca fica vazia.

## Verificar
- Cenário "Lourdes 18:10 nublado, sem dia montado" reproduz o PNG. "Shinjuku 14:20 com dia montado" mostra a parada atual primeiro. Modo avião: 3–4 cartões sem evento. Troca de célula recalcula em < 200 ms.
- `qa-screens.sh`: `capa-inteligente` em BR e JP. Testes do ranker e do parser de feeds (fixtures em `MustTests/Fixtures/feeds/`).
