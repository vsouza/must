# Must — memória do projeto para o Claude Code

App iOS pessoal (um usuário: Vinicius) que transforma um board de "Musts" (Must eat, drink, see, listen, shop…) num guia de dia: monta o roteiro a partir de intenção, GPS, horário de funcionamento, tempo e orçamento. Primeira versão roda em **Belo Horizonte** (pra testar com GPS real); a viagem ao **Japão** (11–24 nov 2026, Tóquio → Kyoto → Tóquio) é a segunda região. Um menu escondido troca a região.

## Decisões que não mudam sem conversar
- **iOS only, SwiftUI, SwiftData, iOS 26+, Xcode 26.** Sem backend. Sem conta. Tudo no iPhone.
- **Uma `Region` por vez** (`bh` | `jp`). Cada região tem o próprio `ModelContainer` (arquivo `must-bh.store`, `must-jp.store`), moeda, fuso, cidades, board e gastos. Trocar região = trocar container, não apaga nada.
- **Menu escondido:** em Ajustes, 5 toques no rótulo de versão abrem a sheet "Região" (BH / Japão + simular data/GPS + dados ao vivo on/off + zerar board). Nada disso aparece na UI normal.
- **Solver determinístico** monta o dia (regras abaixo). O modelo de linguagem só interpreta pedido em texto/voz → parâmetros, e conversa no Assistente. Nunca inventa lugares: só escolhe entre os do board.
- **IA no aparelho primeiro:** Apple Foundation Models (`FoundationModels` framework, iOS 26) com *tool calling* sobre o catálogo. Fallback opcional na nuvem: Claude Haiku (structured outputs) só pra links difíceis — chave em `Secrets.plist` (gitignored), e desligável em Ajustes.
- **Dados vivos:** Google Places API (New) só pra horários/preço/placeId (snapshot em cache, 1.000 chamadas grátis/mês — pedir `id`-only quando não precisar de detalhes); Open-Meteo pro tempo (JMA no Japão); rotas por deep link (Apple Maps / Google Maps) + MapKit ETA; Flickr (`flickr.photos.search`, licenças CC 4,5,7,9,10) pra foto de fundo das listas e heroes, sempre com crédito visível.
- **Regras do dia** (ver `prompts/05-dia.md`): uma refeição por janela (almoço, jantar) salvo exceção explícita; reservas são âncoras fixas; "fica pro fim" só entra nos últimos dias da cidade; orçamento diário com exceções marcadas por lugar; lugar de outra cidade nunca entra; respeita tipo de dia (livre, compras, noite, fotografia, templos, descanso) e quanto andar.
- **Importação/exportação** pelo JSON em `data/board.schema.json`. Seeds em `data/seed-bh.json` e `data/seed-jp.json` (coordenadas `approx: true` são chute — resolver no Places na primeira sincronização).

## Design (v5, tema claro) — fonte da verdade em `design/`
- Telas: `design/screens/*.png` (render) e `*.html` (HTML de referência, abrir no navegador; os links entre telas funcionam). `must-light.css` tem os tokens.
- Fundo branco `#FFFFFF`, tinta `#121316`, secundário `#7A7F87`, superfícies `#F1F2F4` / `#F6F7F9`, borda `#EEF0F3`.
- Acentos: verde `#22DD7E` (texto sobre ele `#0B2A18`) e azul `#2B7BFF` (texto `#0F3B8C`). Formas 3D (elipses com gradiente) atrás, cards de vidro empilhados e girados 1–2°.
- Cor por Must (claro → forte, texto escuro): eat `#B9F5CF→#22DD7E/#0B2A18`, drink `#9FD6FF→#2B7BFF/#0F3B8C`, coffee `#FFD2BF→#FF7A45/#5A2200`, see `#DCCFFF→#8B5CF6/#2E1065`, temple `#B8F2EA→#14B8A6/#063F3A`, listen `#FFC6DA→#FF4D8D/#5A0F2E`, shop `#FFE3A3→#FFB020/#4A2E00`, night `#C9D2FF→#5B6CFF/#161C66`. Foto Flickr por trás com o gradiente a 82% de opacidade.
- Fontes (bundle, OFL): **Archivo** (UI), **Instrument Serif Italic** (voz do usuário, legendas), **Geist Mono** (horas, ¥/R$, códigos de estação), **Zen Kaku Gothic New** (kanji). Escala: título 30/600, nome de lista 20, lugar 17/600, corpo 15, meta 13, serif 18–20, mono 13, micro 11 mono caixa alta com tracking .1em.
- Ícones: set próprio em `design/icons/*.svg` (traço 1.6, viewBox 24). Importar como *custom SF Symbols*; `design/icons/README.md` dá o SF Symbol de fallback de cada um.
- 済 (feito) é o selo do app: círculo verde com o kanji.

## Convenções de código
- Pastas: `App/`, `DesignSystem/`, `Models/`, `Data/` (import/export, seeds, Region), `Services/` (Places, Weather, Flickr, Routes, Location, Intelligence), `Solver/`, `Features/<Tela>/`, `Widgets/` (extension). Todas ficam dentro de `Must/` (o APFS não diferencia `Data/` de `data/`); testes em `MustTests/`.
- Projeto gerado por **xcodegen**: edite `project.yml` e rode `xcodegen generate` (nunca edite o `.pbxproj` à mão). Arquivo novo dentro de `Must/` entra sozinho no target do app; `Must/Widgets/` é só da extensão. Team `BS5ZUHVH99` (Personal Team).
- Views pequenas; estado em `@Observable` por feature; nada de singletons globais além de `RegionStore` e `Services`.
- Tudo em pt-BR na UI. Datas e moeda via `FormatStyle` com o locale/currency da região.
- Sem dependências externas de UI. Pacotes permitidos: nenhum obrigatório; se precisar de Markdown no chat, usar o nativo.
- Chaves: `Secrets.plist` (não commitado) com `GOOGLE_PLACES_KEY`, `FLICKR_KEY`, `ANTHROPIC_KEY` (opcional). `Secrets.example.plist` commitado.
- Testes: unitários do Solver e do parser de JSON obrigatórios; UI tests não.
- Commits pequenos, mensagem em português, um prompt = um ou mais commits.

## Como o trabalho está dividido
Os prompts em `prompts/` são executados em ordem (01 → 10). Cada um diz o que entregar e como verificar. Antes de cada prompt, olhar os PNGs das telas citadas.
