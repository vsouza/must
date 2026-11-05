# Prompt 24 · Itália — Roma como terceira região (05/11/2026)

Pedido do Vinicius: "vamos planejar a nossa viagem para Roma, adicione um json de Roma no projeto e as telas". Datas ainda **[A CONFIRMAR]**: o seed usa 10–18/04/2027 como placeholder.
Telas: `design/v8/screens/CapaIT.png`, `DiaIT.png`, `LugarIT.png`, `MuseuIT.png`, `BolsoIT.png`. Seed: `data/seed-it.json` (63 Musts, 7 reservas, 3 voos placeholder). Faça depois do prompt 23 (a identidade v8 precisa existir).

## 1. Região `it`
- `Region`: `case bh, jp, it`. Calendário gregoriano, `tz Europe/Rome`, moeda **EUR** (formato "€ 12,50", separador europeu; câmbio em R$ pela mesma `ApiBudget`/fonte do iene). Schema `data/board.schema.json`: `region` enum ganha `"it"`, `currency` enum ganha `"EUR"`.
- Container SwiftData próprio (`it`), igual ao bh/jp. Ajustes › Região lista Itália; troca com o mesmo fade de 0,4 s.
- `TripTheme.it`: cor do lugar **azzurro #1F5FB4** + branco (a cor nacional da Itália, escolhida de propósito pra não repetir o verde do Brasil nem o vermelho do Japão). Bandeira: círculo tricolor (verde #008C45 / branco / vermelho #CD212A) em vetor.
- `Areas` de Roma (sigla + nome latino): Centro Storico CEN, Trastevere TRA, Monti MON, Prati PRA, Vaticano VAT, Testaccio TES, Ghetto GHE, Campo Marzio CMA, Aventino AVE, Esquilino ESQ, Flaminio FLA, Ostiense OST, Appia APP, Villa Borghese VBO, Monteverde MVE. Vizinhos e tempos entre eles na tabela de `AreaFocusPlan` (Centro ↔ Ghetto 6′, Ghetto ↔ Trastevere 8′, Monti ↔ Centro 12′, Prati ↔ Vaticano 8′, Testaccio ↔ Aventino 10′, Esquilino ↔ Monti 8′).
- `map-packs.json`: `{"id":"it-roma","region":"it","title":"Roma","subtitle":"centro, Vaticano, Appia e Ostiense","center":[41.895,12.48],"bbox":[12.40,41.83,12.56,41.95]}`. `scripts/tiles.sh` recorta e sobe pro R2 como os outros.
- `PlaceExtractor` e `AssistantSnapshot`: adicionar "roma", "rome", "itália", "italia", "italy", "trastevere", "vaticano" às listas de cidade/país.
- Seed: carregar `seed-it.json` no primeiro uso da região (mesmo caminho dos outros). Lista `do` tem `kind: experience`.

## 2. Regras de Roma no app (Bolso, Dicas, solver)
- **Bolso (IT)**: câmbio €; bilhete **BIT € 1,50 / 100 min**, validar na máquina (ônibus e tram) ou no torniquete; último metrô 23:30 (sex/sáb 01:30), bus noturno "N"; coperto € 1–3, gorjeta não se espera, "al banco" mais barato que "al tavolo"; **nasoni**: água de graça (tapar o cano pra beber); igrejas: ombro e joelho cobertos, fecham 12:30–15:30; cuidado: bus 64 e Termini (carteira); Pantheon € 5 online; sem lixo nas ruas? não se aplica (há lixeiras); riposo: lojas pequenas fecham 13–16.
- **Dicas por momento**: manhã = cappuccino só até 11h, cornetto no balcão; antes de fila = Colosseo entra pelo Foro; tarde = riposo, museus abertos; noite = aperitivo 19–21, jantar a partir das 20; volta = último metrô.
- **Solver**: janelas italianas — almoço 12:30–15, jantar 19:30–23 (nunca marcar jantar antes das 19:30); `riposo` 13–16 pra lojas; domingo: Appia fecha pra carros (virar âncora de manhã); museus estatais fecham segunda (Borghese não, mas exige reserva). Reservas com `turno de 2 h` (Borghese) viram âncora com fim fixo.
- **Compras › Regras da volta (IT)**: queijo curado e embalado a vácuo pode; salame/presunto **não** (Vigiagro); vinho dentro dos 12 L; tax-free na UE só acima de € 70 por loja (Global Blue), passaporte, carimbo no aeroporto.

## 3. Telas (as cinco do design, com os dados do seed)
- **CapaIT**: azzurro + branco, numeral do dia, "Hoje é Trastevere / e o Gianicolo no golden", Agora "Da Enzo · chegue 12:15" (lugar sem reserva com fila: o "saia às" vira "chegue às" = abertura + 0).
- **DiaIT**: dia 4 (Monti + Colosseo), 8 paradas: cornetto (micro) → metrô B → Colosseo (âncora QR) → pizza al taglio (micro) → Capitolini → gelato (micro) → descanso (micro) → Ai Tre Scalini → Emma (âncora reserva) → último metrô.
- **LugarIT**: Da Enzo al 29 em tela cheia (foto grande, faixa preta, ficha com coperto).
- **MuseuIT**: Galleria Borghese com reserva de turno (11:00, 2 h), "chegar 10:30", "saia de Monti 09:50 · bus 910".
- **BolsoIT**: a grade acima.

## Verificar
- Trocar pra Itália em Ajustes: capa azzurra, bandeira tricolor, selos com sigla (CEN, TRA, MON…), moeda em €, Bolso de Roma. Japão e BH intactos.
- `qa-screens.sh` com `capa`, `dia`, `lugar:r02`, `museu:r46`, `bolso` na região `it`, comparados aos PNGs. Testes: `RegionTests` (3 regiões), `SeedTests` (63 lugares, 7 reservas carregam), `SolverTests` (jantar nunca antes das 19:30; Borghese termina em 2 h).
