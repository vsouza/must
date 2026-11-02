# Must

App iOS pessoal que transforma um board de "Musts" (eat, drink, see, listen, shop…) num guia de dia: monta o roteiro a partir
do que você quer, do GPS, do horário de funcionamento, do tempo e do orçamento. Roda tudo no iPhone — sem backend, sem conta.

Primeiro em **Belo Horizonte** (dia a dia, GPS real); a viagem ao **Japão** (11–24 nov 2026) é a segunda região.

## Rodar

1. Xcode 26, iOS 26. O projeto é gerado pelo [xcodegen](https://github.com/yonaskolb/XcodeGen) — depois de mudar `project.yml`:
   `xcodegen generate`. O `Must.xcodeproj` já está no repo.
2. Abra `Must.xcodeproj`, escolha o iPhone e ⌘R. Sem Apple Developer Program: Xcode → Settings → Accounts → seu Apple ID
   (Personal Team); no iPhone, Ajustes → Geral → VPN e Gerenciamento de Dispositivo → confiar no desenvolvedor. O build grátis
   expira em 7 dias.
3. Mapas offline por cidade (`data/map-packs.json`): `brew install pmtiles && ./scripts/tiles.sh` gera `dist/tiles/`
   (BH 11 MB, Tóquio 107 MB, Kyoto/Nara 64 MB, Osaka 28 MB…; fora do git) e `./scripts/tiles-upload.sh` sobe pro R2.
   No app, Ajustes › Mapas offline baixa/apaga cada cidade; sem baixar, o mapa lê do R2 (`MAP_TILES_URL`). Ver `data/map-packs.md`.
   Glyphs e sprite do style: `scripts/gen-glyphs.py` e `scripts/gen-sprites.py` (já commitados).
4. Testes: `xcodebuild -project Must.xcodeproj -scheme Must -destination 'platform=iOS Simulator,name=iPhone 17' test`.
5. Prints de revisão no simulador: `./scripts/qa-screens.sh` (ver `QA.md`).

## Chaves

Copie `Secrets.example.plist` para `Secrets.plist` (na raiz; fica fora do git) e preencha:

| Chave | Pra quê | Obrigatória? |
|---|---|---|
| `GOOGLE_PLACES_KEY` | Places API (New): horários, preço e placeId, e o Por perto (Nearby) | não — sem ela o app usa só o board |
| `AERODATABOX_KEY` | status de voo (AeroDataBox, 400 unidades/mês) | não — sem ela, só o horário programado |
| `FOURSQUARE_KEY` | Dicas de quem foi · Foursquare (tier grátis) | não |
| `MAP_TILES_URL` | servidor de mapas offline (bucket R2 com os PMTiles), pra baixar mapa de cidade | não — sem ele, só os mapas já baixados |
| `ANTHROPIC_KEY` | "Reforço na nuvem" só com Claude Haiku (effort low, sem thinking) pra lugar de link difícil | não — desligado por padrão |
| `PROTOMAPS_KEY` | tiles hospedados quando faltam os PMTiles no bundle | não |
| `REDDIT_CLIENT_ID` | Dicas de quem foi · Reddit (app "installed", sem segredo) | não |

Não usados nesta rodada (decisão de 02/11): Viator, GetYourGuide e aviationstack. Experiências entram por link, e o status de voo é só AeroDataBox.

Na chave do Google: ative a **Places API (New)**, inclua-a nas restrições de API da chave e, se restringir por app iOS, use o
bundle `dev.viniso.must`. O tempo (Open-Meteo) e as fotos (Wikimedia Commons) não precisam de chave.

## Trocar de região

O app abre na região onde você está (GPS no Brasil → BH, no Japão → Japão). Pra fixar uma, Ajustes → **Região** →
Automático / BH / Japão.

Ferramentas de teste: Ajustes → **5 toques em "Must · 1.0 · só pra mim"** → sheet Região:
Belo Horizonte / Japão, dados ao vivo on/off, simular data e hora, simular GPS, simular nuvens (golden), exportar logs,
zerar o board da região.
Cada região tem o próprio arquivo (`must-bh.store`, `must-jp.store`): trocar não apaga nada.

## Importar o board do Japão antes da viagem

1. Edite `data/seed-jp.json` (ou exporte o board atual em Ajustes → Exportar board e edite o arquivo). O formato está em
   `data/board.schema.json`; reservas viram âncoras do dia, `saveForEnd` entra nos últimos dias da cidade,
   `allowBudgetException` deixa estourar a meta quando você pede.
2. Troque pra Japão no menu escondido.
3. Ajustes → **Reimportar** → Escolher .json. O import faz upsert por `id`: não duplica e não apaga o que já existe
   (horários e 済 resolvidos no aparelho ficam).
4. Com a chave do Places funcionando: Ajustes → Sincronizar, pra resolver coordenadas e horários.

Eventos sem lugar (Shinkansen, voo, "Nara · dia inteiro") entram pela tela Reservas (Viagem → calendário → +).

Listas `photo`, `art` e `sport` (`"kind"` na lista) têm painel próprio no Lugar; os dados ficam em `extra` do lugar
(`{ "photo": { "facing": 248, "bestLight": ["golden-pm"] } }`, `{ "art": { "runsUntil": "2026-11-30", "priceAdult": 1400 } }`,
`{ "sport": { "activity": "run", "distanceKm": 7 } }`). Também dá pra preencher em Editar.

## Estrutura

`Must/` — `App/` (raiz, rotas), `DesignSystem/`, `Models/`, `Data/` (região, codec do board, metrô), `Services/` (Places,
tempo, fotos, rotas, sincronização, inteligência), `Solver/` (monta o dia), `Features/<Tela>/`, `Widgets/` (extensão),
`Shared/` (app + extensão). Decisões e convenções em `CLAUDE.md`; prompts de construção em `prompts/`.
