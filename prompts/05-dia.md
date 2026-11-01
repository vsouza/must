Leia `CLAUDE.md` e as telas `Montar.png`, `Proposta.png`, `Trocar.png`, `Hoje.png`, `Gasto.png`. Vamos construir o coração do app: montar o dia.

## Solver (`Solver/DaySolver.swift`, puro, testável)
Entrada: `DayRequest { date, kind: DayKind, budget, walk: WalkLevel, enabledLists: [MustList: ListMode(on/off/auto)], freeText? → parâmetros extras, startAt, origin: CLLocationCoordinate2D, city, weather? }` + catálogo de `Place` + `Expense` + dias já aceitos. Saída: `DayProposal { stops: [ProposedStop(place, at, window, reason)], predictedSpend, walkKm, transitLegs, leftOut: [(place, reason)] , explanation }`.
Regras, nesta ordem:
1. **Âncoras**: lugares com `reservation` na data entram fixos no horário. O resto se organiza em volta (chegar 10 min antes; nada que termine depois de `reservation.at − deslocamento`).
2. **Cidade**: só lugares da `city` do dia. Outra cidade → `leftOut("outra cidade")`.
3. **Fica pro fim**: `saveForEnd` só é elegível nos 2 últimos dias da cidade (ou qualquer dia em BH, onde não há viagem, salvo se o usuário ligou a lista explicitamente).
4. **Janelas**: manhã 09:30–11:30, almoço 11:30–14:30, tarde 14:30–18:00, jantar 18:00–21:00, noite 21:00–00:30 (ajustáveis em Settings). **Uma refeição por janela** (almoço e jantar): só um `Place` de lista `eat` por janela, exceto quando o pedido em texto diz explicitamente ("dois almoços", "sushi e ramen") → marca `exception`.
5. **Horários**: usa `hours` do cache; lugar sem horário entra com `reason: "horário não confirmado"`; lugar fechado no dia/horário não entra. `queueMinutes` soma ao tempo da parada.
6. **Orçamento**: soma `price` das paradas ≤ `budget`; lugares com `allowBudgetException` podem estourar mas ficam **fora da meta do dia** (mostrados separados, como o omakase na Home). Nunca dois exceção no mesmo dia.
7. **Tipo de dia**: `shopping` prioriza `shop` à tarde e corta `listen`; `night` empurra início pra 12:00 e garante `listen`/bar; `photo` prioriza `see` com janela manhã e mirantes ao pôr do sol (usa `weather.sunset`); `temples` idem com `see/temple` cedo; `rest` no máximo 3 paradas e `walk = low`; `free` equilibra 1 see + 1 eat + 1 drink + 1 opcional.
8. **Andar**: `low` ≤ 2 km no dia, `normal` ≤ 4,5, `high` sem limite; agrupa por proximidade (greedy por vizinho mais próximo a partir de `origin`, com metrô quando > `walkMaxKm` entre paradas — tempo estimado 4 min/km a pé, 2,5 min/km + 6 min de metrô).
9. **Tempo**: chuva forte → troca mirantes/parques por museus; `Fuji`-tipo (`notes` com "só se céu limpo" ou tag `weatherDependent`) só com céu limpo.
10. **Explicação**: uma frase em pt-BR sobre o que ficou de fora e por quê (template, não LLM), ex.: "Deixei o Nakano de fora: domingo lota e o jantar é cedo."
Testes: pelo menos 12 casos cobrindo cada regra com o seed JP e 4 com o seed BH (ex.: domingo em BH deve puxar Feira Hippie; Inhotim nunca entra num dia `free`).

## Telas
1. **Montar o dia** (`Montar.png`): data/hora de acordar no topo, h1, subtítulo serif com tempo + "dia N de M" (ou "Belo Horizonte · sábado") + "nada reservado"/"1 reserva"; pílulas de tipo de dia; card com toggles por lista (on/off/auto com a linha de contexto: "Ramen hoje · Fuunji, Menya Kaijin" vem do solver em modo prévia); cards Orçamento (chips 8k/15k/25k ou, em BH, R$ 100/200/400) e Andar; campo serif "ou diga: …" com mic (ditado via `SFSpeechRecognizer` ou o teclado) → texto vai pro `IntentParser` (prompt 08; até lá, regex de palavras-chave: "cedo", "ramen", "andar pouco", "sem compras"). Botão verde "Montar o dia" → **Proposta**.
2. **Proposta** (`Proposta.png`): três mini-cards (Previsto / Andar / Metrô), lista de paradas com hora mono, nome, tag "almoço"/"reserva", meta (lista · sub · fila · preço), botão ⇅ "Trocar" em cada parada (âncora mostra cadeado), card serif da explicação, botões "Ajustar" (volta) e "Aceitar o dia" (persiste `PlannedDay.accepted = true`, vira Hoje). Ícone ↻ gera outra proposta (seed diferente no desempate).
3. **Trocar** (`Trocar.png`): sheet sobre a proposta escurecida; título "No lugar do X"; pílulas (mesma sub / qualquer eat / mais barato / sem fila); até 3 alternativas elegíveis na mesma janela e perto do trajeto, com delta de preço e tempo e, quando a fonte for Reel/TikTok, a frase serif "o que o Reel de ontem mostrou"; opção "Pular <refeição> no roteiro"; "Manter X".
4. **Hoje** (`Hoje.png`): barra de gasto (verde = dia, azul = exceção aceita) com meta; timeline em card branco: feitos a 55% com 済, parada atual em card verde (com "saia 18:50 · 4 min a pé"), próximas com pino cinza, linha final "Último metrô pra casa 00:12" (do serviço de rotas; em BH, "último metrô" vira "metrô até 23:00" ou some). Topo: "+ gasto" (verde) e ícone ⇅ pra refazer o dia (abre Montar com os valores atuais). FAB preto abre o Assistente. Tocar na parada atual → Lugar.
5. **Registrar gasto** (`Gasto.png`): valor grande mono com conversão (`Settings.fxRate`) e "cabe: sobram X"; card do lugar atual (detectado por GPS: parada do dia a < 150 m, senão "Outro lugar" abre busca); categoria; teclado numérico próprio (000, apagar); forma de pagamento; botão "Registrar R$ X e marcar 済" (cria `Expense`, marca `Stop.done` e `Place.done`).
6. Marcar 済 fora do fluxo de gasto (no Lugar ou na Lista) pede "quanto foi?" inline — pode ser 0.

## Verificar
- Testes do solver verdes.
- Em BH, com GPS simulado na Savassi, sábado 09:30, tipo "livre", orçamento R$ 200: a proposta tem 1 see + 1 eat + 1 drink, nenhum Inhotim, nenhuma exceção; trocar o almoço oferece alternativas abertas; aceitar vira Hoje; registrar gasto atualiza a barra e marca 済.
