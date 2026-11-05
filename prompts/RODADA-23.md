# Rodada 23 · Em cartaz, Mapa, Colecionáveis, Amigos, Filmes e Trocar viagem com agentes em paralelo (05/11/2026)

Esta rodada implementa o **`prompts/27-em-cartaz-mapa-colecao.md`** (itens 1–7) com **4 agentes em paralelo**, no formato da `RODADA-22.md`. O **`prompts/28-nova-viagem.md` fica pra depois**: depende da decisão do Vinicius sobre a migração `Region` → `Trip` (seção 3 do 28). Leia `CLAUDE.md` inteiro, `docs/conceito-v8.md`, o prompt 27 e as 14 telas novas de `design/v8/screens/` antes de começar.

## Modo de trabalho
- Não pare entre as fases nem pergunte "posso seguir?". Pare só pra decisão irreversível (apagar dados, chave, repositório remoto, API paga) ou pra uma **[DECISÃO]** do Vinicius.
- Continuam valendo: CloudBoost só `claude-haiku-5-5` effort low; **nenhuma API externa nova além do Wikidata (decidido em 05/11/2026)**; nada de scraping; `Secrets.plist` nunca entra em commit; `xcodegen generate` depois de mexer no `project.yml`; offline e pouco dado são premissa; nada em japonês na interface.
- **Um agente = um worktree = um branch** (`r23/<letra>-<nome>`, em `.claude/worktrees/`). Cada agente só toca os arquivos da sua fronteira; se precisar de algo fora dela, deixa `TODO(r23:<letra>)` e segue. Merge só pelo orquestrador, na ordem abaixo, com build e testes verdes a cada merge. Commits pequenos, em português, com a letra: `r23/A: …`.

## Fase 0 · Contrato (orquestrador) — 1 commit
Crie com assinaturas e stubs que compilam, pra B, C e D programarem contra eles enquanto A trabalha:
1. `Must/Services/Events/ShowEvent.swift`: `struct ShowEvent`, `enum ShowKind`, `enum ShowSource`; `protocol ShowEventsProviding { func today(in:) -> [ShowEvent]; func upcoming(in:) -> [ShowEvent]; func events(for place: Place) -> [ShowEvent] }` + `ShowEventsStub` com os dados de `EmCartaz.png`; `PlaceExtra.program: [EventSession]` (aditivo).
2. `Must/Services/Films/FilmsProviding.swift`: `struct Film`, `protocol FilmsProviding { func films(near: CLLocationCoordinate2D, radiusKm: Double) async -> [Film] }` + `FilmsStub` (3 filmes de `Filmes.png`).
3. `Must/Services/Friends/FriendsProviding.swift`: `struct FriendVisit`, `protocol FriendsProviding`, `MockFriendsSource` (já completo; é pequeno).
4. `Must/Features/Collection/Collectible.swift`: `struct Collectible` (ordem, total, variante, lugar) + `CollectibleVariant`, e `Collectible.make(from: Place, in: [Place])`.
5. `Must/DesignSystem/V8/ButtonMetrics.swift`: `enum ButtonMetrics { static func fontSize(...) }` com a regra numérica (o D completa).
Build verde, commit `r23/0: contrato`. Só então dispare os agentes.

## Fase 1 · Quatro agentes em paralelo
| Agente | Branch | Modelo | Faz | Fronteira (só estes arquivos) |
|---|---|---|---|---|
| **A · Dados** | `r23/a-dados` | **Sonnet** | Prompt 27 §1 (modelo e montagem de `ShowEvent` a partir de `PlaceExtra`/`Ticket`, `PlaceExtra.program`, colar link/texto/cartaz → `EventExtractor` + Vision, regras da micro-parada "em cartaz" no `DayEngine`), §6 (Wikidata: `WikidataFilms`, `FilmCache` 30 dias, fixture), §5 (`FriendsProviding` real do mock), e o schema `data/board.schema.json` (`program`). Sem UI. | `Must/Services/Events/**`, `Must/Services/Films/**`, `Must/Services/Friends/**`, `Must/Services/Ingest/EventExtractor.swift`, `Must/Services/Day/MicroStops.swift`, `Must/Models/Extras.swift` (só `program`), `data/board.schema.json`, `MustTests/ShowEvent*`, `Films*`, `Friends*`, `BoardCodecTests` |
| **B · Em cartaz, Lugar, Filmes (UI)** | `r23/b-lugar` | **Sonnet** | §1 telas `EmCartaz` e bloco no Lugar; §5 `FriendsSection`; §6 `FilmsSection` e tela `Filmes`/`FilmesVazio`; Dicas com linha de amigos. Programa contra os protocolos do contrato. | `Must/Features/EmCartaz/**`, `Must/Features/Films/**`, `Must/Features/Place/**`, `Must/Features/Tips/**`, `Must/Features/Add/**` (só os atalhos "Colar link / Foto do cartaz"), `MustTests/EmCartazUI*`, `Place*` |
| **C · Mapa e busca** | `r23/c-mapa` | **Opus** | §2: card do pino, filtro por Must, busca "o melhor X agora", ranking, `qualidade`/`raio` no `IntentParser`, `placesEnterprise` atrás de flag. É a parte com estado de câmera/MapLibre e ranking, onde a arquitetura é mais delicada. | `Must/Features/Map/**`, `Must/Features/Quero/**`, `Must/Services/Intelligence/IntentParser.swift`, `Must/Services/Nearby/**`, `Must/Services/ApiBudget.swift` (só o SKU novo), `MustTests/Map*`, `IntentParserTests`, `ApiBudgetTests` |
| **D · Coleção, capa e botões** | `r23/d-colecao` | **Sonnet** | §4 (cards, renderer, momento, página, vitrine), §7 (botão e folha "Minhas viagens"), §3 (`V8Button`/`V8Pill`/redondos + auditoria dos tamanhos fixos nas telas), chip "Em cartaz" na capa e item na Linha do dia (UI), link da Coleção na aba Viagem. | `Must/Features/Collection/**`, `Must/Features/Share/**`, `Must/Features/Home/**`, `Must/Features/Trip/**`, `Must/Features/Settings/RegionSheet.swift`, `Must/DesignSystem/**`, `MustTests/Collectible*`, `ButtonMetricsTests`, `TripSwitcherTests` |

Fronteiras que se cruzam e como evitar: o **Lugar** é do B (o "Feito" que dispara o colecionável chama `CollectibleCelebration.present(for:)`, do D, deixado como stub no contrato); a **capa** e a **Linha do dia (UI)** são do D (leem `ShowEventsProviding`); o **card do mapa** é do C e só **lê** `FriendsProviding`/`PlaceFicha` (do B), sem editar. Quem precisar de arquivo fora da fronteira deixa `TODO(r23:<letra>)`.
Cada agente termina com: build verde no simulador, testes da sua fronteira verdes, prints das suas telas comparados com os PNGs de `design/v8/screens/` e uma mensagem curta com commits e `TODO(r23:*)`.

## Fase 2 · Merge (orquestrador), nesta ordem
1. **A** (dados, sem UI) → build, testes. 2. **D** (design system e capa; os botões novos valem pra todos) → build, testes. 3. **B** (Lugar e telas de dados) → resolver `TODO(r23:B)` que dependiam de A/D, build, testes. 4. **C** (mapa) → idem. Conflito em arquivo compartilhado: o merge mais recente adapta ao que já entrou; o design (`design/v8/screens/*.png`) desempata.

## Fase 3 · QA (um agente só, `r23/f-qa`, Sonnet)
- `scripts/qa-screens.sh` com as 9 telas novas (`emcartaz`, `lugar-emcartaz`, `mapa-pino`, `mapa-filtro`, `colecao`, `colecionavel-novo`, `lugar-amigos`, `filmes`, `trocar-viagem`) em JP e BH, comparadas com os PNGs; Dynamic Type xxxLarge em Quero, Compartilhar, MapaPino e Lugar; modo avião (Em cartaz, Filmes em cache, busca só no board); Modo de Pouco Dados; "cache quente gasta 0 KB".
- Suíte completa verde; build de aparelho (`generic/platform=iOS`) ok; `ApiBudgetTests` verde.
- `QA.md` ganha a seção "rodada 23" com o que ficou diferente do design e por quê, e o que só dá pra testar no iPhone (share sheet no Instagram/Facebook, voz no mapa).
- Commit final e mensagem de fechamento.

## Decisões do Vinicius que a rodada deixa abertas (não bloqueiam o merge)
1. API de eventos: o `prompts/26-capa-inteligente.md` cria o `EventsService` (Bandsintown + Ticketmaster, chaves opcionais) — rodar o 26 antes desta rodada e o "Em cartaz" lê dele.
2. SKU Enterprise da Places (nota e nº de avaliações) na busca do mapa: começa sem, atrás de flag (§2).
3. Fonte real dos "amigos que foram" (provável CloudKit do "Viajar junto") (§5).
4. Contato no `User-Agent` do Wikidata (§6).
5. Atalho direto pros Stories do Instagram (exige App ID da Meta) (§4).
6. Migração `Region` → `Trip` e o fluxo Nova viagem: `prompts/28-nova-viagem.md`, **depois** desta rodada.

## Fora do escopo
Dark mode; push remoto; nova viagem (prompt 28); API de eventos; SDK do Facebook/Instagram.
