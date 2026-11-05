Leia `CLAUDE.md` e as telas `design/screens/Home6.png` (Japão) e `Home6BH.png` (Brasil). Pedido do Vinicius (03/11): **bandeira do país da viagem** e um **tom leve do país** em alguns itens, pra dar clima, **sem perder a identidade** do Must.

## Regras
1. `TripTheme` por região/país, no design system (`Must/DesignSystem/TripTheme.swift`), injetado no ambiente pelo `RegionStore` (troca junto com a região, com animação de 0,4 s):
   - **Japão**: `trip #BC002D` (vermelho da bandeira), `tripInk #8A0021`, `tripSoft #FDECEF`, `tripSoft2 #FFF6F7`, `stampInk #C8102E` (o vermelho dos carimbos de estação).
   - **Brasil**: `trip #009C3B`, `tripInk #00692A`, `tripSoft #E6F6EC`, `tripSoft2 #FFF9DB` (verde → amarelo bem claro), `stampInk #00692A`.
   - Tabela aberta pra outros países (bandeira + 4 tons), escolhida pelo país da cidade do dia (`City.country`, ISO 3166).
2. **Onde o tom entra** (e só aí):
   - **Lavado no topo** das telas principais (Início, Hoje, Guia, Musts, Viagem): gradiente vertical `tripSoft → tripSoft2 → transparente` em 300 pt, atrás de tudo.
   - **Selos** (`StationStamp`): tinta = `stampInk` (Japão vermelho; Brasil verde). No card do dia o selo ganha fundo `stampInk` a 55%.
   - **Rótulo da cidade/dia** no topo (micro) em `tripInk`.
   - **Ponto** antes dos títulos de seção e **ponto da aba ativa** da tab bar em `trip`.
   - Coleção de selos na Viagem com a borda em `trip`.
3. **Onde NÃO entra**: botões primários (continuam verde `#22DD7E`), links e seleção (azul `#2B7BFF`), texto (tinta `#121316`), cores das listas Must, cores das linhas de trem, pinos do mapa. A identidade não muda; muda o clima.
4. **Bandeira**: círculo 22 pt ao lado da data no topo do Início (e na Viagem, no card de cada trecho de cidade), desenhada como vetor no app (não emoji — consistência), com contorno branco de 1,5 pt e sombra leve. Japão: disco vermelho em branco. Brasil: versão simplificada (verde, losango amarelo, círculo azul com faixa branca). Ela não precisa de rede.
5. **Selo (todos os países)**: sem kanji — sigla do bairro em Archivo 800 (Brasil: SAV, PAM, STA, CEN…; Japão: código JR da estação, SJK, SBY, UEN) com uma linha pequena "BH · 1897" (ano de fundação da cidade); o `Area` ganha `stampCode` e `stampSub` opcionais (no Japão: o nome latino do bairro, nunca kanji).
6. Dark mode não existe; a lavagem respeita o "Reduzir transparência" (vira cor sólida `tripSoft2` em 120 pt).

## Verificar
- Trocar a região em Ajustes › Região muda bandeira, lavado, selos e pontos — e **nada** dos botões, links, listas e mapa.
- Prints de Início, Hoje e Guia em JP e BH no `scripts/qa-screens.sh`, comparados com `Home6.png` / `Home6BH.png`.
