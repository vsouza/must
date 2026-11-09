# Relatório do viajante v9 · QA da rodada 32, fase 1 (09/11/2026)

Build: `775c527` (A, B, C e E mesclados) no simulador iPhone 17 Pro, fakes de Places/Nearby/voo/dicas/rotas/eventos, data e GPS simulados. Prints em `docs/qa-v9/` (JPEG reduzido; prefixos `jp-`/`bh-`, `claro`/`escuro`, nomes `v9-*` do prompt 32; `c2`/`c3`/`c4`/`c9` = cenários do relatório de 08/11; `ir-j05`, `off-quero-onsen`). Gerados por `ONLY=v9 EXTRA=1 scripts/qa-screens.sh` e `ONLY=v9cenarios scripts/qa-screens.sh`.

Limites honestos: só `-debugScreen` (não toquei na tela), Places/Nearby fake (resultados do Quero em BH vêm de lugares japoneses do fake: efeito do fake, não bug), sem iPhone real (hitches e GPS de verdade não medidos). O app limita Dynamic Type em `.xxxLarge`, então o "XXXL de acessibilidade" do simulador não passa disso.

Já corrigidos no `main` (c9ed42f), não re-testados aqui: motivo das linhas "Agora vale" em uma linha sem jargão; pinos do mapa com o nome do lugar no VoiceOver. Nos prints deste build (775c527) os dois ainda aparecem como eram.

## Notas dos cenários (antes → agora)

| Cenário | Antes | Agora | O que melhorou | O que ainda falha |
|---|---|---|---|---|
| 2 · Dia 1, pousou em Shinjuku, chuva | 2/5 | 3/5 | Hoje sem plano não finge dia normal: "Pouso 15:40 NRT T2 · hotel em Shinjuku · sem plano pesado hoje", 3 lugares perto e "Ir pra um bairro" (`c2-hoje-sem-plano.jpg`). | A linha de pouso é texto cinza pequeno; falta o cartão "pousou" (Wi-Fi/eSIM, trem do aeroporto, endereço do hotel em japonês). "Agora vale" mostra presentes em vez de comer leve perto do hotel. A faixa inferior "Montar o dia de hoje" repete o botão. |
| 3 · Dia cheio, reserva às 19:00 | 3/5 | 4/5 | **Problema 1 resolvido** (abaixo). A reserva aparece na Hoje e em "Reservas e ingressos de hoje". Às 16:45 o dia se refaz: "Seu dia · ajustei, faltam 3", "Agora: Descanso no hotel · saia às 18:35 · Depois: Depachika" (`c3-atrasou-hoje.jpg`), sem "você deveria". | "Saia às 14:16" aparece com a hora simulada já em 14:20 (passado) sem "saia agora". A reserva não é marcada como âncora (só texto). |
| 4 · 16h, o grupo mudou, café/comer em Nakano | 3/5 | 3,5/5 | Contexto estável (Naka-Meguro, hotel) e Quero em duas faixas: "Seus Musts" e "Aqui perto agora"; "Ver no mapa" abre o Explorar só com os pinos. Offline sem cache: "sem internet · seus Musts" explícito (`off-quero-onsen.jpg`). | O cabeçalho do Quero diz "Naka-Meguro" mesmo pedindo Nakano. "Encaixa hoje depois do Bar Trench 22:05" para um café às 16:00 (sugestão sem sentido). "Relógios usados em Nakano" aparece na lista de comer. |
| 9 · Sábado em BH sem viagem | 3/5 | 3,5/5 | BH abre em BH (Savassi, R$, pôr do sol 18:07, "20° chuva"), próxima parada com Ir e "saia às 14:36", coerente com a faixa (`bh-claro-v9-hoje-plano.jpg`). | Cabeçalho "Sáb, 7 nov · Belo Horizonte" quebra em duas linhas (`c9-hoje.jpg`). Quero em BH com o fake lista lugares do Japão com "20519 min" (efeito do fake). |

### Problema 1 (telas contradizem o relógio): resolvido
Mesmo instante (JP, dom 15 nov, dia montado; `jp-claro-v9-hoje-plano`, `-linha`, `-agora`): Hoje (cartão Próxima) "14:21 · saia às 14:16"; faixa "agora" "Próxima: Menya Kaijin · saia às 14:16"; Agora "O dia começa às 14:21. Saia às 14:16"; Linha "14:21 Menya Kaijin". Mesmo horário nas quatro. Igual em BH (14:41 / 14:36) e offline (14:23 / 14:18). Obs.: a Linha mostra só a chegada (14:21), não o "saia às"; não contradiz.

## Modo avião (`-debugNetwork offline`)
Hoje, Explorar (mapa e "Agora vale"), Quero, Lugar e SOS abriram; nada travou nem ficou em branco (`jp-claro-v9-off-*.jpg`, `off-quero-onsen.jpg`).
- Quero com cache quente (consulta já feita online) mostra o guardado sem aviso, por desenho (cache primeiro). Consulta nova offline mostra "sem internet · seus Musts" e só os Musts. OK.
- Falta o chip "sem internet · offline ok" na Hoje e no Explorar offline (previsto no CLAUDE.md).
- Lugar e SOS offline idênticos ao online (esperado, tudo local).

## Dynamic Type (simulador em accessibility XXXL; app limitado a .xxxLarge)
Hoje, Explorar (médio e pino), Quero, Lugar e Viagem sem texto cortado nem sobreposto. Quebras: cabeçalho da Hoje ("Dom, 15 nov / · Shinjuku", chevron solto), título do pino, botão "Não cabe hoje" do Quero. Prints `jp-claro-v9-xxxl-*.jpg`.

## Zero gesto escondido (item 1)
O grep achou 9 usos. Os 6 que já estavam no QA.md continuam com equivalente visível. Dois novos faltavam na lista:
- `Explorar/ExplorarMapaView.swift:349` (pegador do painel de três alturas): o pegador é também botão (toque sobe um degrau) e tem `accessibilityAdjustableAction`; arrastar é atalho redundante. OK.
- `Home/TripSwitcherSheet.swift:195`: **deslizar a linha da viagem revela Arquivar/Apagar e não há botão visível equivalente** (só ações de VoiceOver, l.51-53). Problema 5.
Nada abre por deslize lateral na Hoje.

## Problemas, por gravidade

### Bloqueia a viagem
Nenhum neste build. Hoje, Explorar, Quero, Lugar, SOS e Viagem não travaram, não ficaram em branco e funcionam offline.

### Atrapalha
1. **Tela Ir ainda V8** (fundo #121212 mesmo no claro, numeral gigante laranja, cantos quadrados). `ir-j05.jpg`. Passos: Hoje › Ir (`-debugScreen ir:j05`). Funciona, mas destoa do V9. Na primeira abertura fria o print saiu em branco após 8 s (re-tirado com 20 s e abriu): conferir no iPhone se há demora.
2. **"Não cabe hoje" sem motivo** no card do pino (`jp-claro-v9-explorar-pino.jpg`, botão cinza em HARBS) e no fim do Quero (`jp-claro-v9-quero-seiko.jpg`). Contraria "não dá hoje sempre com motivo". Passos: Explorar › tocar o pino de um Must sem horário confirmado.
3. **Sem chip "sem internet · offline ok"** em Hoje e Explorar offline (`jp-claro-v9-off-hoje-plano.jpg`, `jp-claro-v9-off-explorar-media.jpg`).
4. **"Saia às" no passado sem tratamento** (`jp-claro-v9-hoje-plano.jpg`: hora 14:20, "saia às 14:16"). Deveria dizer "saia agora".
5. **Minhas viagens: Arquivar/Apagar só por deslize** (`TripSwitcherSheet.swift:195`). Contraria "zero gesto escondido". Sugestão: menu ⋯ na linha ou `swipeActions` numa `List`.
6. **Sugestão de horário sem sentido no Quero:** "Encaixa hoje depois do Bar Trench 22:05" para um café às 16:00 (`c4-quero-cafe.jpg`, `c4-quero-comer-nakano.jpg`).
7. **Faixa "agora" repete o botão principal** ("Montar o dia de hoje" sob "Montar o dia"; "Próxima:…" sob o cartão Próxima), e a linha "14:20 · nada marcado · 11 sem horário confirmado" fica parcialmente atrás do vidro (`jp-claro-v9-hoje-sem-plano.jpg`, `c2-hoje-sem-plano.jpg`).

### Cosmético
8. Modo escuro no Explorar: mapa continua claro, faixa "Próxima" e abas ficam claras, painel vira bloco cinza opaco (`jp-escuro-v9-explorar-pino.jpg`). Hoje, Viagem e Lugar no escuro estão ok.
9. Chips do Explorar cortam "Ph" seco junto ao botão de camadas (`jp-claro-v9-explorar-media.jpg`).
10. SOS ainda V8 (escuro no claro, textos truncados "fica só…", "toque pra c…"); japonês só no endereço "mostre ao atendente" (permitido) (`jp-escuro-v9-sos.jpg`).
11. Cabeçalho da Hoje em BH quebra em 2 linhas (`c9-hoje.jpg`).
12. Painel do pino com espaço vazio embaixo.
13. Texto do plano visível abaixo da barra de abas (`jp-claro-v9-hoje-plano.jpg`, "Udatsu Sushi" no rodapé).
14. Foto do Lugar do fake (rua, não ramen): efeito de `-debugPhotos`/Commons, não bug.

### Já corrigidos no `main` (c9ed42f)
- Motivo das linhas "Agora vale" longo e com jargão ("hora certa", "horário estimado · local aproximado" em 2 linhas). Visível ainda neste build em `jp-claro-v9-hoje-sem-plano.jpg` e `c9-hoje.jpg`.
- Pinos do mapa com rótulo de VoiceOver = id do lugar (`MapPins.swift:277`).
