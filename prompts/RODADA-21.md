# Rodada 21 · pré-viagem: acabamento e pendências (03/11/2026)

Prompts 01–20 estão feitos (último merge: `f088c76`, design realinhado em `866a365`). A viagem começa em **11/11**: esta rodada fecha o que ficou pendente no `QA.md` e deixa o app pronto pra usar todo dia no Japão.
Leia `CLAUDE.md` (principalmente "Premissa: visual e econômico em dados", "Tema da viagem" e "Layout das telas") antes de começar.

## Modo de trabalho (pedido do Vinicius: não ficar parado)
- Execute as fatias **em sequência, sem parar entre elas** e sem perguntar "posso seguir?". Ao terminar uma, faça o commit e comece a próxima.
- Pare só pra decisão que não dá pra desfazer (apagar dados do usuário, mexer em chave, criar repositório remoto, gastar cota grande de API).
- Antes de cada item, confira no código se já existe; se já estiver feito, anote no `QA.md` e pule.
- Regras que continuam valendo: CloudBoost só `claude-haiku-5-5` com effort low; nenhuma API externa nova além da AeroDataBox; `Secrets.plist` nunca entra em commit; `xcodegen generate` depois de mexer no `project.yml`.
- Cada fatia termina com build verde, testes verdes e, quando tem tela, prints do `scripts/qa-screens.sh` comparados com os PNGs.

## Fatias — nesta ordem

| # | Fatia | O quê |
|---|---|---|
| 0 | **Layout igual aos PNGs novos** | As telas de `design/screens/` foram realinhadas (`866a365`). Passe por todas as telas do app comparando com os PNGs: stacks no lugar de posições fixas; `lineLimit(1)` + truncamento nos metadados; títulos com no máximo 2 linhas; listas terminando num fade branco antes da tab bar e dos botões; fileiras de chips rolando na horizontal; placeholder de cor em toda foto enquanto carrega. Corrigir também o `NewListView`/editar lista que sai ~22 pt deslocado pra esquerda (`QA.md` §19). Teste com Dynamic Type grande (xxxLarge) nas 6 telas principais: nada pode sobrepor. |
| 1 | **Performance que ficou de fora (prompt 18 · A)** | Memo do `HomeModel` (não montar a cada `body`), memo dos pinos do Mapa, `LazyVStack` na Lista/Board, `Calendar` reutilizado em `PlaceHours.weekMinute`, cancelar a requisição quando todos os interessados saem do dedupe. Medir antes/depois com `PerformanceMeasureTests` e anotar no `QA.md`. |
| 2 | **Bairro pelo GPS** | Reverse geocoding com `CLGeocoder` (cache por célula de ~300 m, só quando muda de célula, funciona sem rede com o último valor) pra saber em que bairro você está: "Hoje em <bairro>" e "Por perto" usam isso. Pré-baixar no Wi-Fi a foto de capa dos bairros do board (uma por bairro, 800 px + miniatura, respeitando Modo de Pouco Dados). |
| 3 | **Colar texto, acabamento** | Fallback na nuvem (Haiku, effort low, só quando o parser local achar menos de 2 lugares e houver rede) pro fluxo de Texto; nomes em japonês (`nameLocal`) no parser; selo de estação (`StationStamp`) nos grupos por bairro. |
| 4 | **Tema e selos** | Selo com a tinta do país (`TripTheme.stampInk`) onde ainda usa `StampPalette` neutro; coleção de selos na Viagem com a borda em `trip`. Conferir JP e BH nos prints. |
| 5 | **Prontidão da viagem** | Checar e corrigir o que falta pra 11/11: `TripInfo` 11–24/11 (Tóquio → Kyoto 17–20 → Tóquio), seed JP completo, mapas offline de Tóquio e Kyoto disponíveis em Ajustes › Mapas offline, voos importáveis, checklist intl-japan ativo, Carteira com Suica/JR Pass, export do board funcionando. Gere `docs/checklist-viagem.md` com o que o Vinicius precisa fazer no iPhone antes de embarcar (baixar mapas no Wi-Fi, lote de fotos, permissão de avisos, exportar backup). |
| 6 | **QA da rodada** | `qa-screens.sh` com JP e BH para Início, Hoje, Guia, Bairros, Lugar, Musts, Viagem, Carteira, Voos, Compras; suíte completa; resumo no `QA.md`. |

## Fora do escopo
- Criar repositório remoto ou dar push (o Vinicius decide).
- Viator/GetYourGuide/TripAdvisor e transcrição de vídeo (continuam TODO com flag).
- Dark mode.

## Ao terminar
Mensagem final curta: commits por fatia, o que ficou diferente do design e por quê, e a lista do que só dá pra testar no iPhone.
