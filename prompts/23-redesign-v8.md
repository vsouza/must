# Prompt 23 · Redesign v8 — "guia de bolso, o dia inteiro" (05/11/2026)

Pedido do Vinicius: o app precisa auxiliar **durante todo o dia** (dicas, utilidades, guia, montar o dia); o dia tem poucas paradas; o fundo das telas está fraco; quer um layout mais rico, conceitual, com cores fortes e fontes fortes; o ícone não pode ser japonês. Depois: a paleta estava aberta demais → fechada em **três cores**.

Telas: `design/v8/screens/*.png` (HTML ao lado, CSS em `design/v8/screens/v8.css`). Pranchas de identidade: `Identidade.png`, `Icone.png`, `Fluxo.png`. Conceito completo em `docs/conceito-v8.md`.
Leia `CLAUDE.md` › "Identidade v8" antes. Esta rodada **substitui** o visual v5–v7; o modelo de dados, os serviços, o solver, o mapa MapLibre e as premissas (offline, pouco dado, Haiku low) continuam.

## 1. Identidade (design system) — `Must/DesignSystem/`
- **Cores (tokens em `Palette.swift`)**: `ink #121212`, `paper #F2F0EA`, `orange #FF4A1C` (a única cor: ação e "agora"), `orangeDeep #C8330A` (laranja como texto sobre papel), `mute #6B6B66` (texto secundário sobre papel), `muteDark #A3A39C` (sobre tinta), `graphite #2B2B2B` (card sobre tinta). **Apague** lima, azul, verde-ação, as cores por lista Must e as cores oficiais de linha de trem (as linhas viram badge preto com a sigla).
- **Cor do lugar (`TripTheme`)**: só a **capa do dia**, a **Boa noite** e o **anel do selo**. Japão `#D7000F` + branco; Brasil `#007A33` + branco; sem viagem: papel + tinta. Nunca em botão, lista, mapa ou aba.
- **Tipografia (bundle as três, Google Fonts, OFL)**: `Bricolage Grotesque` variável (display: títulos em wdth 92/700; **numeral gigante** e índices em wdth 78/800), `Schibsted Grotesk` (texto 400–700, números tabulares), `Martian Mono` (micro-rótulos em caixa alta, horários, códigos). Remover Archivo, Geist Mono, Instrument Serif e Zen Kaku.
- **Texturas (só três)**: `Rings` (2–3 círculos de 1 pt, 420–560 pt, opacidade 25–55 %, sobrepostos, sangrando a tela), `BigNumeral` (um por tela, sangra a borda inferior ou direita, conta algo: dia, hora, minutos, quantidade), `SpecLabel` (micro-rótulos nos cantos, Martian Mono 8,5 pt, tracking .1em). Nada de degradê nem foto lavada atrás de texto.
- **Componentes novos**: `NavBar` (cápsula preta 66 pt; aba ativa = pílula laranja com rótulo; inativas = ícone; `+` = círculo papel), `TicketCard` (picote nas laterais, linha tracejada), `IndexRow` (índice grande em laranja escuro, nome, meta, estado à direita), `CutCornerCard` sai (v7), `StationStamp` ganha anel na cor do lugar e sigla latina.
- **Ícone**: opção A da prancha `Icone.png` — fundo tinta, dois arcos brancos, ponto laranja ao centro. Gerar o asset em `Must/Resources/AppIcon` (1024, sem alpha). O ícone nunca muda com a viagem.

## 2. O dia inteiro — telas e momentos (ver `Fluxo.png`)
| # | Tela | Momento | O que é | Arquivo |
|---|---|---|---|---|
| 01 | **Hoje (capa)** | sempre | Cor do lugar, ficha técnica nos cantos, "Hoje é <bairro> / e <noite>", numeral do dia sangrando, card preto "Agora · k de n · saia às" com ↗. Deslizar pra cima → Linha do dia. Deslizar pra baixo → Bom dia (antes das 10h) ou Boa noite (depois das 21h). | `CapaJP.png`, `CapaBR.png` |
| 02 | **Bom dia** | 07–09h | Laranja. Tempo + golden, "Hoje você já tem" (âncoras do dia), "Antes de sair" (checklist gerado: passaporte se há ingresso/tax-free, Suica abaixo de ¥1.500, cash se há lugar só-cash, guarda-chuva se chuva), primeiro trem útil. Botões: Ver o dia / Ajustar o dia. Aviso local 07:20. | `Manha.png` |
| 03 | **Agora** | no caminho | Tinta. Numeral gigante "saia às", lugar atual e meta, chips de contexto (konbini/caixa/banheiro no caminho, só cash), barra do trajeto, card "Depois", pílulas "e mais". Ações: trocar · **Ir** · feito. | `Agora.png` |
| 04 | **Linha do dia** | sempre | Papel. 9 paradas: âncoras (card tinta), musts (card branco), **micro-paradas** (tracejadas: café, konbini, descanso, compra rápida), deslocamentos entre elas (linha + trem/a pé + minutos), último trem no fim. Toggle Linha/Mapa. Estados: feito (50 %), agora (laranja). | `Dia.png` |
| 05 | **Montar o dia** | manhã / ajuste | Tinta. Bairro (chips com contagem + vizinhos), **ritmo 6 / 9 / 12 paradas**, grana, até que horas, incluir (micro-paradas, foto no golden, compras). "Gerar o dia · N paradas". | `Montar.png` |
| 06 | **Guia do bairro** | entre paradas | Faixa preta com o percurso do dia (mapa papel em relevo existente, tema escuro), nome, texto de 2 linhas, vizinhos, capítulos por período (Tarde/Noite) com os Musts e horários. | `Guia.png` |
| 07 | **Dicas** | no lugar | Papel. Numeral "7 pra hoje". Filtros Agora/Bairro/Japão/Etiqueta/Salvas. Cards: a dica do lugar de agora (laranja), do próximo (branco), "Sabia que" (tinta), noite, volta. Fonte: notas do lugar + regras do país + Dicas de quem foi. | `Dicas.png` |
| 08 | **Bolso (utilidades)** | no lugar | Grade 2×N: câmbio (conversor), Suica anotado + onde recarregar, frases com áudio, último trem, tax-free, perto de você (banheiro/lixeira/caixa), etiqueta, lockers. Tudo offline. | `Utilidades.png` |
| 09 | **Lugar** | no lugar | Foto grande com faixa preta sólida embaixo (nome latino + nome local "mostre ao atendente"), ficha 3×2 (fila, preço, pagamento, horário, distância, veio de), "Sua nota" (laranja), pílulas (dicas, caixa perto, trocar), Ir agora / Feito. | `Lugar.png` |
| 10 | **Musts** | explorar | Índice gigante por lista (01 Eat 23 …), meta, contagem/feitos. Filtros Tóquio/Kyoto/Perto/Abertos/Sem foto. | `Musts.png` |
| 11 | **Lista** | explorar | Agrupada **por bairro** ("Shinjuku · 6 · você está aqui"), `IndexRow` com estado (agora / aberto / abre 17h / fechado / feito / reserva) e distância. | `Lista.png` |
| 12 | **Próximos (Viagem)** | sempre | Tinta. Só o que ainda vai acontecer, em ordem: reserva (laranja), ingresso (papel), trem (papel), voo (papel). Passou, some. Entrada pra Carteira. | `Proximos.png` |
| 13 | **Ir** | no caminho | Tinta. Numeral "9 minutos", modos (a pé/metrô/táxi), passos numerados com o que tem no caminho (caixa 7 Bank antes de um lugar só-cash), aviso "saia às" via Live Activity, Apple Maps / Cheguei. | `Transporte.png` |
| 14 | **Boa noite** | 22h+ | Cor do lugar. "8 das 9 paradas", km a pé, gasto, uma linha pro diário, "Amanhã" já com a âncora e o conselho do tempo, chips do que fazer antes (Suica, guarda-chuva). Aviso 23:50 "último trem em 50 min". | `Noite.png` |
| 15 | **Barra** | — | Regras da navegação e gestos. | `Nav.png` |

## 3. Regras do dia (solver)
- Ritmo padrão **9 paradas**: 3–4 âncoras (ingresso, reserva, golden, trem) + 2–3 Musts livres + **3–4 micro-paradas** geradas: café da manhã perto do hotel, konbini/água antes de fila longa, descanso de 40 min no hotel quando a noite tem âncora depois das 19h, compra rápida (depachika/tax-free) a caminho, vista/foto no caminho.
- Micro-paradas são tracejadas na Linha e entram/saem sem recalcular o resto; têm duração fixa (10–40 min) e nunca viram âncora.
- Deslocamentos aparecem como linhas entre paradas, com modo, minutos e plataforma (Routes transit quando houver rede; senão a estimativa).
- "Agora" é a parada cujo horário de saída é o próximo; "saia às" = início da próxima − deslocamento − margem (fila: +20 min do Places quando houver).
- Último trem do dia vira a última linha da Linha e um aviso.

## 4. Avisos e Live Activity (o app aparece sem ser aberto)
- 07:20 "Bom dia — hoje é <bairro>" (abre o briefing). "Saia em 5 min pro <lugar>" (Live Activity com saia às, próxima parada, último trem). "Golden em 20 min". "Último trem em 50 min" (23:50 ou 50 min antes do horário real). Tudo local, no máximo um a cada 45 min, Ajustes › Avisos do guia.

## 5. O que sai
- Visual v5–v7 (cores por lista, gradientes, selos com kanji, foto lavada). A Home v7 (`Home7*.png`) é substituída pela capa. "Por perto" sai da Home e fica em Guia/Lista.

## Verificar
- Trocar a região em Ajustes muda só a capa, a Boa noite e o anel do selo; nada mais. Datas simuladas: 15/11 14:20 em Tóquio = `CapaJP.png`/`Agora.png`; 07/11 em BH = `CapaBR.png`.
- Dynamic Type xxxLarge nas 6 telas principais: numeral gigante não quebra (ele é decorativo e tem `accessibilityHidden`), textos não sobrepõem.
- Modo avião: capa, Linha, Lugar, Bolso e Dicas completos; Agora sem matriz usa a estimativa.
- `scripts/qa-screens.sh` com todas as 15 telas em JP e BH comparadas aos PNGs; suíte completa verde.
