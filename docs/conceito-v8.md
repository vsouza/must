# Must v8 — conceito "guia de bolso, o dia inteiro" (05/11/2026)

## 1. O fluxo atual atende? Diagnóstico curto
O Must v5–v7 é um **banco de lugares com um montador de dia**: board → listas → lugar, e um solver que escolhe ~4 paradas. Funciona pra planejar, mas falha como companhia de dia inteiro em cinco pontos:
1. **Não tem começo nem fim de dia.** O app só aparece quando você abre. Falta o briefing da manhã (tempo, o que já está marcado, o que levar, primeiro trem) e o fechamento (o que foi feito, gasto, amanhã).
2. **Poucas paradas e sem "entre".** 4 paradas num dia de 14 horas deixa 10 horas sem guia. O que acontece entre elas (café, konbini antes da fila, descanso, compra rápida, a vista no caminho) é onde um guia ajuda de verdade.
3. **"Agora" não é uma tela.** O momento mais usado numa viagem — "onde estou, pra onde vou, a que horas saio, como chego" — está diluído entre Hoje, Mapa e Lugar.
4. **Dicas e utilidades são parágrafos, não ferramentas.** Câmbio, saldo da Suica, frases, tax-free, último trem, banheiro: coisas consultadas dez vezes por dia sem uma tela própria.
5. **Visualmente, tudo igual.** Fundo branco, cards cinza e gradientes por lista: as telas não têm hierarquia de momento (manhã, caminho, lugar, noite).

## 2. Padrões que valem (pesquisa)
- **Timeline por dia com deslocamentos entre itens** (TripIt, Wanderlog): o trajeto é um item, não um detalhe do lugar. Adotado na Linha do dia.
- **Momento "Go" com saída calculada e último trem** (Citymapper): o número que importa é "saia às", não a distância. Adotado como numeral gigante no Agora.
- **Contagem regressiva e capa por dia** (Polarsteps): cada dia tem uma cara; o número do dia é a identidade da tela. Adotado na capa.
- **Essencial do Japão no chão** (guias 2026): cash em shrines, izakaya e lockers; Suica no Wallet; ticket na máquina antes da fila; tax-free ¥ 5.000 por loja/dia com passaporte; sem lixeira na rua; trem em silêncio; Google Maps até a plataforma; reservar com o concierge. Virou o Bolso e as Dicas por momento.
- **Brutalismo editorial** (tendência 2026): cor sólida, numeral gigante, micro-rótulos técnicos, uma textura só. É a linguagem das referências que o Vinicius trouxe.

## 3. Decisões de design
1. **Cinco momentos, não cinco abas.** Acordar → No caminho → No lugar → Explorar → Fechar. A barra tem 4 abas (Hoje, Guia, Musts, Viagem) + `+`; os momentos entram por gesto e por aviso.
2. **9 paradas por padrão**, com ritmo 6 / 9 / 12 escolhido ao montar. Micro-paradas tracejadas.
3. **Um numeral gigante por tela**, sempre com significado: dia, hora de sair, minutos, quantidade.
4. **Três cores.** Tinta, papel, laranja. A cor do lugar entra só na capa e na Boa noite. Nada de lima, azul, verde-ação ou cor por lista: a hierarquia vem do preto/papel e do laranja como único acento.
5. **Três fontes, três vozes.** Bricolage Grotesque (display e numeral), Schibsted Grotesk (texto), Martian Mono (ficha técnica).
6. **Listas por bairro, com índice.** Índice grande, nome, uma linha de meta, estado à direita. Sem foto quando a lista é longa (economia de dado e de atenção).
7. **O app fala sozinho.** Live Activity e quatro avisos locais por dia: bom dia, saia às, golden, último trem.
8. **Nada em japonês na interface.** Selos com sigla latina; o nome local só na ficha do lugar, pra mostrar a alguém.
9. **Ícone universal:** arcos e um ponto laranja — "você está aqui". Não muda com a viagem.

## 4. Fontes consultadas
- Migaku — Japan travel tips for 2026 (pagamentos, IC card, trens, tax-free, etiqueta): https://migaku.com/blog/language-fun/japan-travel-tips-for-2026-what-actually-matters-on-the-ground
- Polarsteps — screens e release de verão 2026: https://screensdesign.com/apps/polarsteps/ · https://www.polarsteps.com/news/polarsteps-launches-summer-2026-release-new-tools-for-planning-privacy-and-sharing
- Wanderlog — showcase: https://screensdesign.com/showcase/wanderlog-travel-planner
- Tendência brutalista/editorial 2026: https://studio2am.co/blogs/news/raw-by-design-how-brutalism-is-reshaping-the-visual-language-of-digital-assets-in-2026
- Fontes (Google Fonts, OFL, Latin Extended confirmado): Bricolage Grotesque, Schibsted Grotesk, Martian Mono.
