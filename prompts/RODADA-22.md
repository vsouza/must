# Rodada 22 · v8 com vários agentes em paralelo (05/11/2026)

Esta rodada implementa o **redesign v8** (`prompts/23-redesign-v8.md`) e **Roma** (`prompts/24-italia-roma.md`) com **agentes em paralelo**, cada um no seu worktree e com uma fronteira de arquivos clara. O orquestrador (você, nesta sessão) prepara o contrato, dispara os agentes, faz os merges na ordem e roda o QA.
Leia `CLAUDE.md` inteiro (principalmente "Identidade v8" e "Itália · Roma"), `docs/conceito-v8.md` e os dois prompts antes de começar. O último estado do repo é o merge `5660a09` (fotos vivas); **o v8 substitui o visual das fotos vivas**: foto inteira com faixa preta sólida por baixo do texto, sem cor do Must atrás do texto.

## Modo de trabalho
- Não pare entre as fases nem pergunte "posso seguir?". Pare só pra decisão irreversível (apagar dados, chave, repositório remoto).
- Regras que continuam valendo: CloudBoost só `claude-haiku-5-5` effort low; nenhuma API externa nova; `Secrets.plist` nunca entra em commit; `xcodegen generate` depois de mexer no `project.yml`; offline e pouco dado são premissa.
- **Um agente = um worktree = um branch** (`v8/<letra>-<nome>`), como já foi feito nas rodadas anteriores (`.claude/worktrees/`). Cada agente só toca os arquivos da sua fronteira; se precisar de algo fora dela, cria um `TODO(v8:<letra>)` e segue. Merge só pelo orquestrador, na ordem abaixo, com build e testes verdes a cada merge.
- Commits pequenos e com a letra do agente no início: `v8/A: …`.

## Fase 0 · Contrato (orquestrador, antes de disparar qualquer agente) — 1 commit
Crie os arquivos abaixo **com assinaturas e stubs que compilam**, pra que os agentes C e D programem contra eles enquanto A e B trabalham:
1. `Must/DesignSystem/V8/Palette.swift`: `enum V8 { static let ink, paper, orange, orangeDeep, mute, muteDark, graphite: Color }`.
2. `Must/DesignSystem/V8/Type.swift`: `enum V8Font { static func display(_ size: CGFloat, width: CGFloat = 92) -> Font; static func numeral(_ size: CGFloat) -> Font; static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font; static func mono(_ size: CGFloat) -> Font }` (por enquanto devolvendo as fontes atuais; o agente A troca pelas novas).
3. `Must/DesignSystem/V8/TripTheme.swift`: `struct TripTheme { let cover: Color; let coverInk: Color; let flag: AnyView; static func forRegion(_ r: Region) -> TripTheme }` com jp/br/it/none.
4. `Must/DesignSystem/V8/Components.swift`: stubs públicos de `Rings`, `BigNumeral`, `SpecLabel`, `V8NavBar(active: Tab)`, `TicketCard`, `IndexRow`, `CutBand` (faixa preta das telas de foto), `V8Button(.orange/.ink/.line)`, `Pill`.
5. `Must/Services/Day/DayPlanV8.swift`: tipos novos do dia — `enum StopKind { anchor, must, micro }`, `struct DayStop { id, placeId, kind, start, end, label, note }`, `struct DayLeg { mode, minutes, from, to, detail }`, `struct DayPlan { stops, legs, lastTrain, pace: Pace }`, `enum Pace { calm = 6, normal = 9, intense = 12 }`, `protocol DayEngine { func build(area:, pace:, budget:, until:, includes:) async -> DayPlan; func now(at: Date) -> (current: DayStop, leaveAt: Date, next: DayStop?) }` + `DayEngineStub` que devolve o seed do dia de QA (Shinjuku, 9 paradas, do `Dia.png`).
6. `Region` ganha `case it` **só com o enum e o calendário** (o resto é do agente E), pra que tudo compile.
Build verde, commit `v8/0: contrato`. Só então dispare os agentes.

## Fase 1 · Quatro agentes em paralelo
| Agente | Branch | Faz | Fronteira (só estes arquivos) |
|---|---|---|---|
| **A · Identidade** | `v8/a-identidade` | Prompt 23 §1 inteiro: paleta, fontes (bundle das três, OFL, `Info.plist`), `TripTheme` real, `Rings`/`BigNumeral`/`SpecLabel`/`V8NavBar`/`TicketCard`/`IndexRow`/`CutBand` de verdade, `StationStamp` com sigla + anel, ícone do app (opção A). Remove Archivo/Geist/Instrument/Zen Kaku e as cores por lista. | `Must/DesignSystem/**`, `Must/Resources/**`, `project.yml` (fontes e ícone), `Must/Data/Areas*.swift` (siglas) |
| **B · Motor do dia** | `v8/b-dia` | Prompt 23 §3 e §4: `DayEngine` real sobre o solver atual (ritmo 6/9/12, micro-paradas geradas, deslocamentos como `DayLeg` com Routes quando há rede, "saia às"/"chegue às", último trem), Live Activity "saia às" e os 4 avisos locais (bom dia 07:20, saia em 5 min, golden, último trem), regras italianas do solver (jantar ≥ 19:30, riposo, turno de 2 h) atrás de `region`. Testes `DayEngineTests`, `UpcomingTests`. | `Must/Services/Day/**`, `Must/Services/Solver*/**`, `Must/Services/Notifications/**`, `Must/LiveActivity/**`, `MustTests/Day*` |
| **C · Telas do dia** | `v8/c-telas-dia` | Prompt 23 §2 telas 01, 01b/01c, 02, 03, 04, 05, 13, 14: Capa (cor do lugar / com foto), Bom dia, Agora, Linha do dia, Montar, Ir, Boa noite; gestos da capa; `qa-screens.sh` dessas telas. Programa contra o contrato da fase 0 (`V8`, `V8Font`, `DayEngine`). | `Must/Features/Home/**`, `Must/Features/Today/**`, `Must/Features/Montar/**` (ou onde o Montar vive hoje), `Must/Features/Transporte/**`, `Must/Features/Night/**`, `scripts/qa-screens.sh` (só as linhas dessas telas) |
| **D · Lugar e explorar** | `v8/d-lugar` | Prompt 23 §2 telas 06–12: Guia, Dicas, Bolso (`Must/Features/Pocket/`), Lugar em tela cheia (restaurante e museu com ingresso), Musts, Lista por bairro (`IndexRow`), Próximos (`TicketCard`), + Bolso IT do prompt 24 §2. | `Must/Features/Guia/**`, `Must/Features/Tips/**`, `Must/Features/Pocket/**`, `Must/Features/Place/**`, `Must/Features/Musts/**`, `Must/Features/Lists/**`, `Must/Features/Trip/**`, `Must/Data/PocketRules*.swift` |

Em paralelo com esses quatro, um quinto pequeno:

| **E · Roma** | `v8/e-roma` | Prompt 24 §1: `Region.it` completo (container, moeda EUR, Ajustes, `AssistantSnapshot`/`PlaceExtractor`), `data/board.schema.json`, `map-packs.json` (`it-roma`), áreas de Roma com vizinhos, carregamento do `seed-it.json`, Compras › Regras da volta (IT). Testes `RegionTests`, `SeedTests`. | `Must/Data/**` (menos `Areas*` do A — combine: A escreve as siglas JP/BR, E acrescenta as de Roma no mesmo formato, em arquivo separado `AreasIT.swift`), `data/**`, `Must/Features/Settings/**`, `Must/Features/Compras/**` (só regras IT), `Must/Services/Ingest/PlaceExtractor.swift`, `Must/Services/Intelligence/AssistantSnapshot.swift` |

Cada agente termina com: build verde no simulador, testes da sua fronteira verdes, prints das suas telas comparados aos PNGs de `design/v8/screens/`, e uma mensagem curta com commits e `TODO(v8:*)` deixados.

## Fase 2 · Merge (orquestrador), nesta ordem
1. **A** (identidade) → build, testes. 2. **B** (motor) → build, testes. 3. **E** (Roma) → build, testes. 4. **C** (telas do dia) → resolver os `TODO(v8:C)` que dependiam de A/B, build, testes. 5. **D** (lugar) → idem.
Conflito em arquivo compartilhado: o merge mais recente adapta ao que já entrou; o design (`design/v8/screens/*.png`) desempata.

## Fase 3 · QA (um agente só, `v8/f-qa`)
- `scripts/qa-screens.sh` completo nas três regiões (JP, BR, IT) com as 20 telas, comparadas aos PNGs; Dynamic Type xxxLarge nas 6 principais; modo avião; troca de região (só capa, Boa noite e anel do selo mudam).
- Suíte completa verde; build de aparelho (`generic/platform=iOS`) ok.
- `QA.md` ganha a seção "v8" com o que ficou diferente do design e por quê, e a lista do que só dá pra testar no iPhone.
- Commit final e mensagem de fechamento.

## Fora do escopo
Dark mode; APIs novas; push remoto (o Vinicius decide); o prompt 22 (substituído pelo 23).
