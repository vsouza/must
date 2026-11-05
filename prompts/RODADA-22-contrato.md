# Rodada 22 · contrato da fase 0 (05/11/2026)

Commit `v8/0: contrato`. Tudo abaixo compila e a suíte passa (560 testes). Os agentes programam contra estas assinaturas;
quem é dono de um arquivo pode trocar o miolo, **não** a assinatura pública, sem avisar o orquestrador no relatório final.

## O que o contrato criou
| Arquivo | O quê | Dono |
|---|---|---|
| `Must/DesignSystem/V8/V8Palette.swift` | `enum V8 { ink, paper, orange, orangeDeep, mute, muteDark, graphite, white }` + `V8.Hex` | A |
| `Must/DesignSystem/V8/V8Type.swift` | `V8Font.display(_:width:)`, `.numeral(_:)`, `.text(_:weight:)`, `.mono(_:)` (por ora Archivo/Geist) | A |
| `Must/DesignSystem/V8/V8TripTheme.swift` | `extension TripTheme { cover, coverInk, flag: AnyView }` + `TripTheme.italy` em `TripTheme.swift`; `TripTheme.forRegion(_:)` já existia | A |
| `Must/DesignSystem/V8/V8Components.swift` | `Rings`, `BigNumeral`, `SpecLabel`, `V8NavBar(active:onSelect:onPlus:)`, `TicketCard(tone:top:bottom:)`, `IndexRow(index:title:meta:state:trailing:)` + `IndexRowState`, `CutBand`, `V8Button(_:_:icon:action:)`, `V8Pill(_:active:onInk:)` | A |
| `Must/DesignSystem/V8/V8StubScreen.swift` | tela-stub; some quando ninguém mais usar | A apaga no fim (QA confere) |
| `Must/Services/Day/DayPlanV8.swift` | `StopKind`, `DayStop`, `DayLegMode`, `DayLeg`, `DayLastTrain`, `Pace` (6/9/12), `DayInclude`, `DayPlan`, `DayNow`, `protocol DayEngine`, `DayEngineStub` (dia de QA do `Dia.png`), `\.dayEngine` no ambiente | B |
| `Must/Data/Region.swift` | `case it` (Roma, Europe/Rome, EUR, €, centro de Roma) | E |
| `Must/Data/AreasIT.swift` | `AreasIT.all` (vazio) — `Areas.areas(for: .it)` já aponta pra cá | E |
| `Must/DesignSystem/Components.swift` | `MustTab` virou `hoje, guia, musts, viagem` (v8, `Nav.png`) | A |
| `Must/App/RootView.swift` | `V8NavBar` no lugar da `MustTabBar`; raízes: Hoje = `HomeView` (capa), Guia = `GuiaTabView`, Musts = `MustsHubView`, Viagem = `ProximosView` | orquestrador (C pode mexer nos gestos/raiz do Hoje) |
| `Must/App/Router.swift` | rotas `.bomDia`, `.agora`, `.linha(date:)`, `.ir(placeId:)`, `.boaNoite`, `.dicas`, `.bolso`, `.proximos`, `.mapa` | orquestrador |
| `Must/App/MustApp.swift` | `-debugScreen` `capa`, `bom-dia`, `agora`, `dia`/`linha`, `ir:<id>`, `noite`, `bolso`, `proximos`, `museu:<id>`, `dicas` (sem arg = tela Dicas) | orquestrador |
| Telas-stub | C: `Features/Today/{BomDia,Agora,LinhaDoDia}View.swift`, `Features/Transporte/IrView.swift`, `Features/Night/BoaNoiteView.swift`. D: `Features/Guia/GuiaTabView.swift`, `Features/Tips/DicasView.swift`, `Features/Pocket/BolsoView.swift`, `Features/Trip/ProximosView.swift` | C / D |
| `scripts/qa-screens.sh` | seção v8 (`ONLY=v8`), 20 prints × 3 regiões, cada linha marcada com o agente | cada agente só as suas linhas |
| `project.yml` | `data/seed-it.json` no bundle | E (seções de dados), A (fontes/ícone) |
| `MustTests/BoardCodecTests.swift` | testes por região limitados a BH/JP (`TODO(v8:E)`: o seed-it ainda não decodifica — janela `evening`) | E |

Diferenças do texto da RODADA-22: nomes de arquivo com prefixo `V8` (o Xcode não aceita dois `Components.swift`/`TripTheme.swift` no mesmo target); `LegMode`/`LastTrain`/`Pill` já existiam, então o contrato usa `DayLegMode`, `DayLastTrain`, `V8Pill`; `now` virou `now(in:at:) -> DayNow?` (o motor não guarda estado) e ganhou `plan(for:region:context:)` pra as telas lerem o dia aceito; `TripTheme` estende o tipo do prompt 20 em vez de criar outro.

## Fronteiras reais (os caminhos da RODADA-22 traduzidos pro repo)
- **A · Identidade**: `Must/DesignSystem/**` (inclui `V8/`, `Stamps.swift`, `TripTheme.swift`, `TripFlag.swift`, `Fonts.swift`, `Colors.swift`, `Typography.swift`, `Components.swift`), `Must/Resources/**`, `Must/Info.plist` (só `UIAppFonts`), `project.yml` (fontes e ícone), `Must/Data/Areas.swift`, `Must/Data/areas/{tokyo,kyoto,bh}.json`, `Must/Models/AreaStamps.swift`, `scripts/gen-icons.py`, testes `MustTests/{TripTheme,AreaStamps,Design*,V8*}Tests.swift`.
- **B · Motor do dia**: `Must/Services/Day/**`, `Must/Solver/**`, `Must/Features/Plan/DayPlanner.swift`, `Must/Services/Guide/**`, `Must/Services/Notifications/**` (novo), `Must/Shared/MustShared.swift` (atributos da Live Activity), `Must/Widgets/**`, `Must/Services/OutsideBridge.swift`, uma linha em `Must/App/MustApp.swift` (injetar `\.dayEngine`), testes `MustTests/{Day*,Upcoming*,Solver*,AreaFocusSolver*,GuideNudges*}Tests.swift`. Ajustes › Avisos do guia: B entrega a view da seção em `Services/Notifications/`; o orquestrador liga no Ajustes no merge.
- **C · Telas do dia**: `Must/Features/Home/**`, `Must/Features/Today/**`, `Must/Features/Plan/{MontarView,ProposalView}.swift`, `Must/Features/Transporte/**`, `Must/Features/ComoChegar/**`, `Must/Features/Night/**`, `Must/App/RootView.swift` (só a raiz/gestos do Hoje), casos `-debugScreen` das suas telas em `MustApp.swift` se faltar algum, linhas (C) do `qa-screens.sh`.
- **D · Lugar e explorar**: `Must/Features/{Guia,Tips,Pocket,Place,Musts,List,Trip,Bairros}/**`, `Must/Services/Tips/**`, `Must/Data/PocketRules*.swift` (novo), testes `MustTests/{Pocket*,Tips*,PlacePanel*,ListCover*}Tests.swift`, linhas (D) do `qa-screens.sh`.
- **E · Roma**: `Must/Data/**` menos o que é do A e do D (`Areas.swift`, `areas/{tokyo,kyoto,bh}.json`, `PocketRules*`), ou seja `Region.swift`, `RegionStore.swift`, `AreasIT.swift`, `areas/roma.json` (novo), `rules/` (IT), `checklists/` (IT), `data/**`, `Must/Features/Settings/**`, `Must/Features/Shopping/**` (regras IT), `Must/Services/Ingest/PlaceExtractor.swift`, `Must/Services/Intelligence/AssistantSnapshot.swift`, `scripts/tiles.sh`, `project.yml` (recursos de dados IT), testes `MustTests/{Region*,Seed*,BoardCodec*,Shopping*}Tests.swift`.
- Fora da fronteira: `TODO(v8:<letra>)` com uma linha do que falta, e segue.
