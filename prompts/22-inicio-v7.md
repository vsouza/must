# Prompt 22 · Início v7 — organizado, com próximos ingressos e voos (05/11/2026)

Pedido do Vinicius: "quero a home do app mais organizada, com os tickets, voos (se eles já não aconteceram), um layout mais clean e bonito". Referências que ele mandou: navegação em pílula (aba ativa escura com rótulo, as outras em círculo) e cards de foto com recorte no canto e botão ↗.
Telas: `design/screens/Home7.png` (na viagem) e `design/screens/Home7Pre.png` (antes da viagem). HTML ao lado, CSS em `design/screens/must-light.css` (blocos `v7`).
Leia `CLAUDE.md` ("Layout das telas", "Tema da viagem", "Premissa: visual e econômico em dados") antes.

## 1. Três estados da Início (decidir por `TripInfo` + data de hoje)
- **Antes da viagem** (hoje < início da viagem, há voo de ida): `Home7Pre`.
  - Topo: bandeira e data da região atual; frase em dois tons "Faltam N dias / pro <país>" + bandeira do destino.
  - **Cartão de embarque do próximo voo**: códigos grandes (Archivo 800), horários, terminal, nº do voo, escala, duração, chip de status (AeroDataBox em cache, senão "programado"), "check-in online abre …". Toque → Voos.
  - **Checklist**: anel de progresso, "N de M" e o próximo item. Toque → checklist do voo.
  - **Ingressos e reservas**: os 3 próximos (bloco de data colorido pelo tipo, nome, meta, hora). "ver todos · N" → Reservas.
- **Na viagem** (dentro do período): `Home7`.
  - Topo: bandeira, "Sáb 15 nov · Tóquio · dia 3/5"; frase "Hoje é <bairro> / e <destaque da noite>".
  - **Card do dia** com foto, selo do bairro, chips (vizinhos, tempo), bloco "Agora · k de n", e o ↗ verde no recorte → Como chegar.
  - **Próximos**: fileira horizontal de cartões-ingresso (picote nas laterais) com reservas, ingressos, trens e voos, em ordem de horário. Rótulo "hoje"/"amanhã"/dia da semana. Cor: reserva = tom do país, ingresso = cor da lista Must, trem/voo = escuro.
  - **Amanhã, pra onde?**: cards de bairro com foto, selo, recorte e ↗ → Bairros.
- **Sem viagem** (BH no dia a dia): igual à "na viagem" com a região atual. "Próximos" só aparece se houver algo.

**Regra do "Próximos":** só entra o que ainda não aconteceu. Ingresso e reserva saem 30 min depois do horário de início (ou quando marcados como feitos); voo sai quando pousa (status `landed`, ou chegada programada + 1 h sem status); trem sai na chegada. Ordem por início; empate pelo tipo (voo > trem > ingresso > reserva). Tudo vem do SwiftData local: nada espera rede.

## 2. Navegação nova (todas as telas com tab bar)
- `MustNavBar` no lugar da tab bar atual: cápsula branca translúcida (blur, sombra leve, borda #EEF0F3), 64 pt, centralizada, 18 pt acima da área segura.
- Aba ativa: pílula #121316 com o ícone num círculo verde #22DD7E (38 pt) e o rótulo em branco 14/600. Abas inativas: círculos 50 pt #F1F2F4 com o ícone. Último item: "+" verde (abre Adicionar: Link / Texto / Nome).
- Troca de aba com `matchedGeometryEffect` na pílula (0,3 s spring) e haptic leve. Rótulos de acessibilidade em todas as abas; alvo mínimo de 44 pt.
- A FAB "+" que existia na Início sai (agora está na barra).

## 3. Componentes
- `CutCornerShape`: retângulo arredondado (raio 28 no card do dia, 24 nos bairros) com um furo circular (raio 30) a 24 pt do canto inferior direito; o botão ↗ (44 pt, ou 40 nos bairros) fica centrado no furo. Use em `.mask`/`.clipShape` com `eoFill`.
- `TicketShape`: raio 22, picotes de 9 pt nas duas laterais a 62% da altura, linha tracejada entre eles (1,5 pt, 25% de opacidade). Usado nos cartões de Próximos e no cartão de embarque.
- `DateBlock` (46 pt, raio 14): dia em mono 17/600 e dia da semana micro.
- Seção com ponto na cor do tema (`trip`) antes do título, "ver todos · N" à direita em micro.

## 4. O que sai da Início
- A linha "Por perto" (fica no Mapa e em Descobrir) e o "gasto hoje" (fica em Ajustes e no Hoje).

## Verificar
- Datas simuladas (menu escondido): 05/11 em BH mostra `Home7Pre` com o voo GRU→HND de 11/11; 15/11 14:00 em Tóquio mostra `Home7` com Udatsu 19:00 "hoje" primeiro e sem a aula de sushi das 10:00; 25/11 não mostra o voo de volta.
- Modo avião: a Início abre completa (status do voo do cache, fotos em cache ou placeholder).
- Dynamic Type xxxLarge: nada sobrepõe; os cartões de Próximos crescem na altura.
- Prints no `scripts/qa-screens.sh` (`home7`, `home7-pre`) comparados com os PNGs; testes do filtro de "Próximos" (`UpcomingTests`) cobrindo as regras de saída e a ordem.

## 5. Selos sem japonês (05/11)
- Todos os selos de bairro passam a mostrar sigla + nome latino (ver `CLAUDE.md` › "Selos sem japonês"): na Início, Bairros (bolha e sheet), Guia, Colar texto e Viagem. Os horários do Guia mostram o bairro em letras latinas.
