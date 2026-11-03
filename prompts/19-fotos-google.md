Leia `CLAUDE.md`. Pedido do Vinicius (03/11): **foto de verdade de cada lugar**. Testado em 03/11 com a `GOOGLE_PLACES_KEY` do projeto: Text Search IDs Only → Place Details `id,photos` (10 fotos pro Fuunji) → `/media?maxWidthPx=800&skipHttpRedirect=true` → JPEG 800×1067 da **fachada certa** (placa FUUNJI, cortina 風雲児). A integração já existe (`Must/Services/Google/GooglePlacePhotos.swift`), mas hoje só entra quando o Wikimedia não acha nada — e o Wikimedia quase sempre acha *alguma coisa* que não é o lugar.

Siga a seção **Premissa: visual e econômico em dados** do `CLAUDE.md` (cache primeiro, uma foto por lugar, pré-download só no Wi-Fi, Modo de Pouco Dados).

## Mudança de prioridade
1. **Lugar com `placeId` → foto do Google primeiro.** Wikimedia Commons fica pra: bairros (card do dia, Bairros), listas (hub Musts), lugares sem `placeId` e como reserva se o Google falhar/sem cota. Ajuste `PlaceView.swift:171` e onde mais o hero é escolhido; atualize o texto do `ApiBudget` (".placePhotos: 1 mil grátis/mês · foto principal de cada lugar").
2. **Onde a foto aparece** (sempre a mesma foto principal do lugar, do cache): hero do Lugar; miniatura na Lista, no Board, no Guia do bairro, na Proposta/Hoje, no card "Agora" da Home; pin selecionado do Mapa (card inferior); Adicionar por link/Texto/Nome antes de salvar. Galeria de até **5 fotos** só no Lugar, carregada quando o usuário desliza (sob demanda).
3. **Custo** (cota grátis: Details Essentials 10 mil/mês; Place Photos 1 mil/mês):
   - `photos` vem no mesmo Place Details que já buscamos (Essentials) — não faça uma chamada só pra isso; acrescente `photos` ao field mask da resolução/sync existente e guarde os `photos[].name` (+ autor) no `Place` (ex.: `photoRefs`).
   - **Uma** chamada de `/media` por lugar pra foto principal, `maxWidthPx=800` (hero) e gere localmente a miniatura (240 px) a partir dela — nunca uma segunda chamada pra thumb.
   - Cache em disco de 30 dias (`Caches/must-place-photos`), e **pré-baixar** a foto principal dos lugares do dia aceito e do bairro escolhido (offline do prompt 18); o resto, só quando aparecer na tela.
   - Os nomes de foto expiram: se `/media` responder 400/404, refaz o Details (só `photos`) uma vez e tenta de novo.
   - `ApiBudget`: teto diário de 60 em `placePhotos`; acima de 80% do mês, só hero do Lugar (sem miniaturas novas).
4. **Crédito obrigatório**: chip "foto · Google · <autor>" no hero e na galeria (vem de `authorAttributions[0].displayName`; tocar abre `authorAttributions[0].uri`). Nas miniaturas, sem chip (o crédito está no Lugar).
5. **Sync em lote**: botão em Ajustes › Dados "Baixar fotos dos lugares" (com contador "84 de 130 · usa 84 da cota de 1.000 do mês"), em `Task` de baixa prioridade, 4 por vez, pausável, só em Wi-Fi por padrão.
6. Tratamento visual: hero com a foto **sem tingir** (o gradiente da cor do Must fica só como faixa de 30% embaixo, pra legibilidade); miniaturas com cantos 14 pt; lugares sem foto continuam com o gradiente da cor.

## Verificar
- Fuunji, Udatsu, Mercado Central e Museu Inimá abrem com a foto do Google certa e crédito; um lugar sem `placeId` mostra Commons ou gradiente.
- Contador do `ApiBudget` sobe 1 por lugar novo (não 2), e zero ao reabrir (cache).
- Modo avião: fotos já vistas e as do dia aceito aparecem; as outras mostram o gradiente sem travar.
