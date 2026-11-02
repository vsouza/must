Leia `CLAUDE.md` e a tela `design/screens/AdicionarMapa.png` (substitui o miolo de `Adicionar.png` depois que o link é lido). Correção + melhoria do **Adicionar por link** (`Must/Features/Add/AddLinkView.swift`, `Must/Services/Ingest/PlaceExtractor.swift`, `Must/Services/Intelligence/AIPlaceExtractor.swift`).

## Bugs que o Vinicius viu (print em 02/11, Reel de Tsukiji)
1. **Lista parece duplicada**: os cards secundários usam `VStack(spacing: -22)` + rotação; com 2+ resultados um cobre o outro. → Trocar o empilhamento por uma **lista simples** (sem spacing negativo, sem rotação) como no PNG.
2. **"November" virou lugar**: a regra 4 do `PlaceExtractor` (linha curta em Title Case) aceita meses. → Adicionar meses (pt/en/ja: janeiro…dezembro, january…december, jan…dec, 1月…12月), dias da semana em inglês, e palavras de legenda comuns ("Part", "Day", "Vlog", "Guide", "Itinerary", "Food", "Tour") aos `stopwords`; e **nenhum candidato sobrevive sem confirmação no Places** (item 4) — o que não for achado aparece riscado "não achei no mapa" com botão "manter".
3. **Todos marcados "mercado"**: `category(in: item.name + " " + text)` deixa a legenda inteira decidir a categoria de cada lugar. → Categoria e sub vêm, em ordem: do `primaryType` do Places, do **nome** do lugar, de uma janela de ±80 caracteres em volta da menção, e só por último da legenda inteira.

## Dedupe
4. Antes de mostrar: resolver cada candidato no **Places Text Search** restrito à cidade/área (`locationBias` círculo de 5 km no centro da área citada, ou da cidade da região). Fundir candidatos que caem no **mesmo `placeId`** ou a < 60 m com nomes parecidos (um contém o outro, ou Jaro-Winkler ≥ 0,85): "Tsukiji" + "Tsukiji Market" → **Tsukiji Outer Market**, com a meta "juntei 2 menções". Preferir o `displayName` do Places e guardar o nome da legenda como alias. Marcar "já no board" quando o `placeId` (ou nome+distância) já existe — vem desmarcado e com a tag "no board".
5. `ExtractedPlace.id` hoje é `name.lowercased()` → passar a ser `placeId` quando houver (é a chave do `ForEach`; nomes iguais em lugares diferentes quebram a lista).

## Preview com mapa (`AdicionarMapa.png`)
6. Topo compacto: chip da fonte (IG/TT/YT/Maps), título da legenda em uma linha, "N lugares · conferidos no Places", botão "Trocar" (volta pro campo do link).
7. **Mapa** 226 pt de altura com o estilo **papel em relevo** (o mesmo `MapLibreView` do Mapa, interação desligada, sem chrome): pinos pretos numerados 1…N na ordem da lista, pílula com o nome do selecionado, área citada como elipse verde tracejada a 8% (o retângulo que contém os pontos + 20%), estação de metrô mais próxima, e um chip em vidro embaixo "Tsukiji · 380 m entre eles · 34 min de você" (distância máxima entre os pontos e ETA do `RoutesService` até o centroide). Câmera enquadra todos os pontos com padding de 28 pt. Botão de expandir abre o mapa em tela cheia (mesma tela do Mapa, só com esses pinos). Tocar num pino destaca a linha correspondente e vice-versa. Sem rede/tiles: placeholder `#E9EBEF` com os pinos posicionados mesmo assim (projeção simples).
8. Linha "Lista": pílula verde com a sugestão (`Must eat · Mercado`) e "um por lugar…" (cada item ganha seu próprio seletor de lista na linha).
9. **Lista** em card branco: número (mesmo do pino), nome + nameLocal, meta de uma linha (categoria · horário de hoje · fila/preço quando conhecidos · "juntei N menções"), check verde (incluído) ou tag "no board"; itens não achados no mapa riscados a 50% com "manter".
10. Botão: "Adicionar N ao <lista>" contando só os marcados.

## Testes
- `PlaceExtractorTests`: legenda com "November", "Part 2", "Day 3" não gera candidatos; "Tsukiji" e "Tsukiji Market" na mesma legenda viram um item após o merge (com Places fake devolvendo o mesmo `placeId`); categoria de "Maguroya Kurogin" não vira "Mercado" só porque a legenda diz "market".
- Print da tela nova no `scripts/qa-screens.sh` (BH com um link do Maps e JP com uma legenda fake de 3 lugares + "November").
