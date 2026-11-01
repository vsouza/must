Leia `CLAUDE.md`. Este prompt define a abertura/zoom do Mapa e adiciona "Dicas de quem foi" ao Lugar. Telas: `design/screens/Mapa.png`, `MapaLonge.png` e `Dicas.png`.

## Parte A — Abertura e zoom inteligentes do mapa
A base do mapa (estilo, tiles, relevo) e os pinos ficam no **prompt 12**. Aqui é só a lógica de câmera, que vale pra qualquer base. Telas: `design/screens/Mapa.png` (perto) e `MapaLonge.png` (nada perto). Se ainda não rodou o 12, faça o 12 antes desta parte.

**Abertura e zoom inteligentes** (`Must/Features/Map/MapCamera.swift`):
1. Ao abrir (e ao voltar pro app com o mapa em foco): calcule a distância do usuário a todos os pinos das camadas ligadas.
2. Se houver pino a ≤ 500 m → **escala de bairro**: câmera centrada no usuário, ~900 m de largura de tela (a barra mostra "300 m"). Sheet mostra "Perto de você · 500 m" com até 3 mini-cards (nome, ponto na cor da lista, lista, aberto/abre às, distância) ordenados por distância, e abaixo a próxima parada de hoje (se houver).
3. Se não houver → **zoom out até o mais perto**: câmera enquadra usuário + pino mais próximo com padding (topo 170pt pela busca+legenda+aviso, base 300pt pela sheet), desenha uma **linha de distância** tracejada preta 1.6 (4/6) do usuário ao pino com uma pílula preta no meio em mono ("2,1 km · 9 min de metrô" — ETA do `RoutesService`; a pé quando < 1,2 km), rótulo "<nome> · mais perto" ao lado do pino, e um aviso em vidro no topo em serif: "Nada a menos de 500 m. Abri o mapa até o mais perto: **Inimá de Paula**, parada 3 de hoje." A sheet vira o card desse lugar com distância, ETAs, hora prevista e botões Apple Maps / Google Maps / Ver o dia. A escala acompanha (1 km, 2 km…). Prioridade pro "mais perto": próxima parada de hoje se estiver a < 3× a distância do pino mais próximo; senão o mais próximo de qualquer camada ligada.
4. Reavaliar quando o usuário se mover > 100 m, quando uma camada for ligada/desligada e quando um stop for marcado 済. Nunca mexer na câmera enquanto o usuário estiver arrastando ou nos 20 s seguintes a um gesto; o botão ⌖ volta ao comportamento automático, o botão `300` força escala de bairro.
5. Animação de câmera 600 ms ease-out; a linha de distância aparece depois que a câmera para.

## Parte B — Lugar › Dicas de quem foi (`Dicas.png`)
Seção rolável no fim da tela do Lugar (o header comprime: nome + "Dicas de quem foi" + tag de horário).
1. **Fontes** (`Must/Services/Tips/`), cada uma com protocolo + fake, todas com cache de 24 h e **sem armazenar além de 30 dias** (regra do Google):
   - `GoogleReviews`: Place Details com field mask `reviews` (até 5, `rating`, `text`, `originalText`, `authorAttribution`, `relativePublishTimeDescription`) + `rating`, `userRatingCount`. Mostrar autor, nota e "G"; é SKU Enterprise + Atmosphere, então **só buscar quando o usuário rola até a seção** e nunca no sync.
   - `FoursquareTips`: Places API `GET /places/{fsq_place_id}/tips` (match por `GET /places/search?query=&ll=&radius=`, cache do `fsq_place_id` no `Place`). Chave `FOURSQUARE_KEY` em `Secrets`; tier gratuito.
   - `RedditThreads`: OAuth *installed app* (chave `REDDIT_CLIENT_ID`), `GET /search?q="<nome>" <cidade>&sort=relevance&limit=10` em `r/JapanTravel`, `r/Tokyo`, `r/Kyoto`, `r/belohorizonte`, `r/brasil` conforme a região; pegar os 3 comentários mais votados que citam o nome. Mostrar subreddit, ↑ e data. Se a chave não existir, pular a fonte sem erro.
   - `SourceCaption`: a legenda do Reel/TikTok/YouTube de onde o lugar veio (já salva em `Place.source`) vira o **primeiro card**, em verde: "de onde veio este must".
   - TripAdvisor Content API fica como `TODO` com flag (5k chamadas grátis/mês; precisa de aprovação).
2. **Resumo no aparelho**: Foundation Models com `@Generable struct TipsSummary { summary: String (≤ 60 palavras, pt-BR, negrito nos substantivos-chave), themes: [Theme { word, count, sentiment }] }` a partir de todas as dicas (cortar em 3.500 caracteres, priorizando as mais úteis/recentes). Chips de tema: verde = positivo, terracota = crítica, cinza = neutro, com "× N". Tudo acontece depois que as fontes respondem; enquanto isso, skeleton.
3. **Tradução**: dica em japonês mostra o original em serif e, abaixo, a tradução pt-BR em Archivo 12 cinza, com tag "traduzido no aparelho" (Foundation Models; se indisponível, mostra só o original e usa o `text` já traduzido do Google quando existir).
4. **Cards**: citação em Instrument Serif itálico 16.5, linha de autor com avatar-inicial, fonte como chip mono (`G`, `FSQ`, `Reddit`, `IG`), nota/↑ e data relativa. Filtros: Mais úteis / Recentes / Em japonês / Críticas (nota ≤ 3 ou sentimento negativo).
5. Rodapé de atribuição obrigatório: "Avaliações do Google, Foursquare e Reddit mostradas com autor e fonte, não armazenadas além de 30 dias. Traduções e resumo gerados no aparelho." Logo do Google não é exigido em apps nativos quando o nome "Google" aparece — mantenha o chip `G`.
6. Toggle em Ajustes → Dados: "Dicas de pessoas" (desliga tudo isso e economiza chamadas).

## Verificar
- Em BH, abrindo o mapa na Savassi com algo a ≤ 500 m: escala de bairro centrada em você e a sheet com os 3 mais perto; ligar/desligar camadas na legenda faz a câmera reavaliar.
- Simulando GPS em Santo Agostinho sem nada perto: zoom out até o mais perto, linha de distância com ETA, aviso em serif; arrastar o mapa não briga com a câmera; ⌖ volta ao automático.
- Lugar "Mercado Central" rolado até o fim: resumo + chips + dicas do Google e Foursquare; um lugar japonês do seed mostra tradução.
