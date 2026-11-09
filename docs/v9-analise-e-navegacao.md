# Must v9 · Análise sóbria e navegação (09/11/2026)

Pedido do Vinicius: análise sóbria do v8, pesquisa de mercado e uma navegação simples. Artefato completo (com fluxogramas e wireframes): https://claude.ai/artifact/PYBf8NMiBukvnyuD1wHL1A

## Diagnóstico do v8
1. **Ações sem origem**: deslize da capa → Atalhos; long-press no `+` → Montar; capa troca sozinha (Bom dia/Boa noite). Regra: todo destino tem botão com nome; gesto é atalho redundante.
2. **Contexto errado**: bairro pelo GPS falha no metrô/indoor. Regra: o contexto é o centro do mapa; GPS só sugere ("Chegou em Shinjuku · ver perto") com precisão < 100 m e parado 2 min; só troca se tocar.
3. **Design acima da dose**: laranja saturado, numeral gigante, capa-cartaz. Fica: tipografia, hierarquia, uma cor de ação discreta, materiais do iOS 26 (vidro/blur).
4. **Núcleo errado**: a linha do dia virou o centro; o centro é o mapa (ideia original do Sunday).

**Métrica v9**: abrir em qualquer bairro/hora e, em 10 s, sem tocar, saber o que vale fazer agora e por quê; com plano, o que vem e quando sair. Tudo em modo avião.

## Mercado (resumo)
- Google Trips (2016–19): reservas do Gmail + Things to do + Day plans por cidade, offline. Acertava: abria já sabendo tudo. Faltava: curadoria pessoal, "agora", eventos.
- Wanderlog (mapa + dias, import Gmail, grupo) · TripIt (timeline de reservas) · Stippl/Mindtrip (IA roteiro) · Google Maps (listas, lê screenshots) · eventos fragmentados (Fever, DICE, RA, Bandsintown, Songkick, Eventbrite, Time Out, Meetup) · map-first novos (Radar7, Vibemaps, Shindig) confirmam demanda · Japão: Navitime, Tabelog, Suica, Papago, SmartEX, Klook, NERV (o Must aponta pra eles, não substitui).
- Lacuna: ninguém junta board curado + o que está rolando agora + o dia + offline.

## O que o whiteboard resolve (herdar como está)
Curadoria por intenção (Must eat/drink/see/shop/photo), memória espacial (mapa como casa) e confiança (fontes escolhidas). O app adiciona: quando, como chegar, o que está acontecendo.

## Conceito: o Sunday potencializado pela viagem
Mapa estilo GTA com 4 camadas: **Musts** (board), **Hoje** (rota numerada), **Agora** (eventos, aberto agora, fecha logo, golden), **Indicados** (fora do board, desligada por padrão). Sobre o mapa, folha com 3 alturas (como Apple Maps): recolhida = busca + linha Agora; média = 3 cartões "Agora vale" com motivo; cheia = lista.

## Abrir o app
Mapa centrado → tem dia montado? sim: folha com próxima parada (saia às, como ir, atraso; se atrasado, ajuste em um toque). não: folha "Agora vale" (3 cartões com motivo) + Montar o dia / Pedir. Sem rede: mesma tela com cache. **A capa deixa de existir**; Bom dia/Boa noite viram notificação + cartão no topo da folha.

## Navegação (iOS 26)
Tab bar nativa com 4 abas + aba de busca à direita; acessório fixo acima da barra (como o mini-player do Music) com a próxima parada ou "Agora vale", em todas as abas. Nenhuma aba é ação; nenhuma some.
- **Mapa** (casa): filtros por lista, camadas, folha Agora vale. 100% offline (PMTiles).
- **Hoje**: linha do dia, legs, reservas do dia, clima/sol; ações Montar, Ajustar, Encaixar, Mandar dentro dela.
- **Musts**: o board (listas, por bairro, feitos); adicionar por link, texto, voz, screenshot.
- **Viagem**: voos/hotéis/ingressos (futuros primeiro), Suica, SOS, mapa offline, Bolso, região (JP · BR · IT), ajustes.
- **Pedir** (busca): "quero comprar um Seiko", "drink de konbini", "rua pra foto", "presente perto", "almoço perto". IA on-device → lugar físico → "cabe HH:MM" → Encaixar / Ir / Guardar. Também responde dicas.
- **Lugar**: tela única, chegue por onde chegar: Ir · Encaixar hoje · Guardar · Dicas.
- Atalhos (painel escondido) deixa de existir: Suica/ingressos/SOS ficam em Viagem e no acessório quando fizer sentido.

## Princípios Mad Owl no Must
Simplicidade (uma pergunta por tela, 4 abas, zero gestos escondidos) · Sofisticação (cor é informação: quase monocromático + acento calmo de ação + acento de alerta; vidro/blur separam camadas) · Inovação (Agora vale com motivo; Pedir vira lugar e hora; board como filtro sobre o mapa) · Zero UX · iOS HIG como regra · Offline-first, sem travar · IA obrigatória e invisível (Foundation Models: intenção, ranker, resumo; nuvem só pra montar o dia e extrair eventos, custo baixo) · Simples primeiro, camada visual sobe depois.

## Sai / fica do v8
Sai: capa-cartaz, numeral gigante, selos, três capas por país, gestos escondidos, bairro pelo GPS como título. Fica: motor do dia, Quero, SOS, Mandar, eventos (prompts 23–26 como lógica, muda só onde aparece), Roma e seed, mapa papel em relevo (01/11) como casa.

## Próximos passos
1. Pausar agentes de tela da RODADA-22 (C e D); seguir só motor do dia, Região IT e seed de Roma.
2. Rodada de telas v9 (canvas novo): Mapa com folha, Hoje, Musts, Viagem, Pedir, Lugar; cinza primeiro, depois paleta calma + materiais iOS 26.
3. Protótipo navegável das seis telas pro iPhone.
4. Prompt 27: nova navegação + folha Agora sobre o mapa, reaproveitando os serviços já escritos.
