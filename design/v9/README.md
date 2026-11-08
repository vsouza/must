# Must v9 · fluxos, Explorar, Presentes, Assistente e Minhas viagens (08/11/2026)

Desenhos do prompt 31 (itens 4, 5, 7, 8 e 9). Tudo no **corte** (`prompts/30-corte.md`): bloco da foto em cima, régua preta, papel embaixo com índice em réguas de 2 pt. Cada tela é um HTML autossuficiente de 390×844 pt com o PNG ao lado (2×, Chrome headless). Fotos de referência em `../v8/screens/photos/`.

**Comece por `Fluxos.png`** (o mapa de navegação) e por `ExplorarComparar.png` (a recomendação do Explorar).

## Telas

| Arquivo | Mostra |
|---|---|
| `Fluxos` | Mapa de navegação v9: a barra nova, a capa como centro (todos os gestos e as portas equivalentes), o que mora em cada aba, onde mora cada coisa, o que sai/junta/muda e as regras novas do corte. 1600 px de largura. |
| `ExplorarA-1` | Conceito A, meio a meio: mapa em cima, camadas em 4 células, régua de redimensionar, índice do que está na tela. |
| `ExplorarA-2` | Conceito A, mapa cheio com o pino 1 aberto: o papel vira o bloco da foto do lugar (sem cartão flutuante), ações Ir / Abrir / + dia. Sem barra de abas. |
| `ExplorarA-3` | Conceito A, lista cheia: mapa reduzido a uma faixa com o retângulo da área visível; ordem Perto / Aberto até tarde / Por bairro; grupos "aqui" e "vizinho a N min de trem". |
| `ExplorarA-4` | Conceito A, camada "fora do board" ligada: pinos e linhas em tinta, ação "+ board", cota do Google no rodapé, sem foto. |
| `ExplorarB-1` | Conceito B, página do bairro (Shinjuku): foto do bairro, recorte quadrado do mapa, trilho de estações na borda direita, selo SJK, nome gigante, régua puxável "↓ quero em shinjuku", índice do bairro. |
| `ExplorarB-2` | Conceito B, arrastando no trilho: o trilho vira um painel de tinta com os 23 bairros em ordem de tempo de trem; a linha sob o dedo fica laranja e grande. |
| `ExplorarB-3` | Conceito B, recorte aberto (Nakano, sem foto no disco): o mapa vivo cresce e a cor do lugar vira moldura de 14 pt; camadas no pé do mapa; índice sincronizado. |
| `ExplorarB-4` | Conceito B, outra cidade (Kyoto · Gion): segmentado Tóquio/Kyoto, trilho ordenado pelo hotel, faixa "outra cidade · nada daqui entra hoje", estado sem foto. |
| `ExplorarComparar` | Os dois conceitos lado a lado, prós e contras e a recomendação (B com duas peças do A). |
| `Presentes-Lista` | Musts › Presentes: numeral "7 faltam", agrupado por pessoa (faixa tinta com subtotal), checklist; linha laranja = dá pra comprar agora perto. |
| `Presentes-Adicionar` | Novo presente: o quê, de onde veio (Nome · Link · Vídeo · Local · Foto), leitura no aparelho do vídeo, pra quem, preço × quantidade, onde comprar. |
| `Presentes-Item` | Detalhe: bloco com a foto da loja (se já estiver no disco), ficha em linhas (pra quem, quanto, onde, veio de, tax-free com medidor, nota), Ir / Comprado. |
| `Presentes-Comprado` | Marcou comprado: painel de tinta pede o valor pago, mostra que entra em Gastos e na cota tax-free da loja; Desfazer / Ok. |
| `Presentes-Perto` | Capa (Hoje) com a linha laranja "presente · Don Quijote · Kit Kat de matcha × 3 pra Ana" no índice. Também mostra os botões quadrados ⇄ e ✦. |
| `Presentes-Quero` | Resultado do quero "presente": faixa laranja "seus presentes · dá pra comprar aqui", seus Musts shop mesmo longe, e a faixa tinta de fora. |
| `Assistente-1` | ✦ aberto: "O que eu sei de hoje" (as Dicas viram a primeira página), filtros, sugestões e o campo de pergunta. |
| `Assistente-2` | Conversa: pergunta em letra grande, resposta em texto e as mudanças do dia como índice (entra/sai/fica), Aceitar o dia novo / Ver na linha. |
| `Assistente-3` | Quero com uma pergunta digitada: faixa tinta "✦ isso é uma pergunta" com a resposta curta e "Continuar no Assistente". |
| `Viagens` | Minhas viagens: bandeira retangular + nome/datas/estado + coluna da moeda (código e símbolo), Automático, Nova viagem. |
| `fonte/` | Gerador dos HTML (`python3 design/v9/fonte/build.py design/v9 [Tela ...]`): macros da barra, mapa, pinos e bandeiras. Edite `fonte/src/*.html` e rode de novo. |

## Navegação nova (decisões)

1. **Barra: Hoje · Explorar · Musts · Viagem · +.** `MustTab.guia` vira `.explorar`; a raiz da aba é o Explorar (B). A barra é uma faixa de tinta de largura total (58 pt + área do indicador), **sem cápsula**: aba ativa = bloco de papel com filete laranja de 3 pt em cima, rótulo mono em caixa alta; `+` = célula laranja de 74 pt.
2. **`+` = Quero · Guardar.** Abre a sheet do Quero (campo em cima, como hoje) com as abas de guardar: Link, Vídeo, Texto, **Ingresso**, **Presente**, Nome. Segurar = Montar o dia de hoje (sem mudança).
3. **✦ abre o Assistente** (`router.sheet = .assistant`), nunca as Dicas. O ✦ mora **sempre no canto superior direito do bloco da foto** (capa, Lugar, Lista, Explorar, Presentes). Deslizar pra esquerda na capa também abre o Assistente. Somem os FABs de IA do Mapa e do `TodayView`.
4. **Dicas viram a primeira página do Assistente** ("O que eu sei de hoje", mesmo `DayTips` e filtros). A rota `.dicas` passa a abrir o Assistente nessa página; o `DicasView` vira o cabeçalho/estado vazio do `AssistantView`. Ao enviar a primeira pergunta, a página de dicas rola pra cima e vira a conversa; "← dicas" no topo volta.
5. **Atalhos + Bolso = Bolso.** Deslizar pra direita (ou a alça) abre o Bolso com o topo do painel de Atalhos (Suica, ingressos de hoje, mapa offline, SOS) e, embaixo, a grade do Bolso. Os "indicados fora do board" saem daqui (vão pra camada "fora do board" do Explorar e pra faixa tinta do quero).
6. **Quero × pergunta.** O quero só acha lugar físico. Se o texto termina com "?" ou começa com "dá tempo", "como", "quando", "vale", "e se", "o que", "por que" (lista em `QueroModel`), a primeira linha do resultado é a faixa tinta "✦ isso é uma pergunta" com a resposta curta do modelo no aparelho e a ação "Continuar no Assistente" (passa o texto). Os chips de vontade continuam embaixo. Nunca mistura resposta e lugares na mesma faixa.
7. **Minhas viagens**: ⇄ no canto superior esquerdo da capa (quadrado), linha fixa no fim da aba Viagem e Ajustes › Viagem.
8. **Presentes**: faixa fixa no topo do Board (aba Musts) e linha em Compras; entra pelo `+`, pelo quero ("presente", "comprar…", nome da pessoa) e aparece na capa/Linha do dia quando a loja está perto.

Portas de cada coisa: tabela "Onde mora cada coisa" em `Fluxos.png`.

## Gestos

| Onde | Gesto | Faz | Equivalente sem gesto (VoiceOver/Switch) |
|---|---|---|---|
| Capa | arrastar começando na régua com pegador | Quero (limite ~110 pt, háptico ao travar) | tocar no nome do bairro; `+` |
| Capa | ↑ | Linha do dia | ação "Linha do dia" |
| Capa | ↓ fora da régua | Bom dia (antes das 10h) / Boa noite (depois das 21h) | ação "Bom dia"/"Boa noite" |
| Capa | ← | Assistente | ✦ |
| Capa | → ou alça da borda | Bolso | ação "Bolso" |
| Explorar B | ← → no bloco | bairro anterior/próximo na ordem do trilho | trilho (lista) |
| Explorar B | tocar/segurar e arrastar no trilho | pula de bairro; háptico `.selection` a cada estação; soltar = vai | toque numa estação; VoiceOver: ajustável (rotor) |
| Explorar B | tocar no recorte | abre o mapa vivo (B-3) | botão "Abrir mapa" |
| Explorar B-3 | tocar num pino | o índice vira o bloco do lugar (como A-2); deslizar o bloco = próximo pino | linha do índice |
| Explorar | puxar a régua com pegador | quero com origem no **centro do bairro** da página (não no GPS) | tocar no nome do bairro |
| Presentes | tocar na caixa | comprado (abre o painel do valor) | ação "Marcar comprado" |
| Presentes | segurar a linha | Editar · Mudar pessoa · Apagar | menu de contexto |

Regra de ouro (mantida): **só puxa a régua que tem pegador laranja e rótulo**. A régua com pegador de papel (Explorar A, quero aberto) nunca abre o quero; no conceito escolhido (B) ela não existe.

## Explorar (recomendação: conceito B)

- **Ordem dos bairros**: tempo de trem a partir de onde você está (`Area` + tabela de tempos). GPS fora da cidade da viagem: a partir do bairro do dia; outra cidade: a partir do hotel ("KRS hotel"). Só entram bairros com Musts ou vizinhos dos dias montados.
- **Página**: `CutBand` com `AreaHeroes` (foto já no disco; sem foto = cor do lugar + trama + arcos, estado normal). Cantos: segmentado de cidades à esquerda, "bairro N de M" ou estado do mapa offline, ✦ à direita. Pé do bloco: selo (sigla latina, nunca kanji), "país · você está aqui" (ou "cidade · dias 6 a 9"), linhas de trem por sigla, nome gigante (Bricolage 800, `lineLimit(2)`, `minimumScaleFactor(0.5)`).
- **Recorte**: 176 pt quadrado, borda de tinta 3 pt, à esquerda no bloco. É um **snapshot** do MapLibre (`MLNMapSnapshotter`) por bairro + camadas ligadas, gerado fora do main e guardado no cache de disco (chave: bairro + camadas + versão do pack). Nunca dois mapas vivos; só o recorte aberto (B-3) é `MLNMapView`.
- **Trilho**: linha branca de 2 pt na borda direita do bloco, uma estação por bairro (sigla + minutos). Quadrado laranja = você está aqui; branco = bairro do dia (com "hoje 19h" ou "feito"); cor do lugar com borda = os outros. Ao segurar, vira o painel B-2 (largura 270 pt, tinta) e a página por trás troca ao vivo.
- **Recorte aberto (B-3)**: o mapa cresce até 14 pt da borda; o bloco vira moldura com o selo, o nome e ✕. Camadas em 4 células no pé do mapa (do conceito A). Índice embaixo = o que está visível no mapa.
- **Camadas**: aberto agora (filtro), seus Musts (laranja), fora do board (tinta; só com rede e cota; sem rede a célula fica riscada e o índice mostra "sem internet · só seus Musts"), trilha do dia (linha laranja 3 pt ligando as paradas).
- **Pinos** (quadrados, borda 2 pt, número mono 800): laranja = seu Must aberto; papel = seu Must fechado/não hoje ou parada do plano; tinta = fora do board; selecionado = 34 pt com dois arcos de 1 pt; você = ponto laranja com dois arcos (o ícone do app). Pontos de 8 pt pros que não cabem número.
- **Estilo do mapa "corte"** (proposta pro `must-relief.style.json`, só cores): fundo/ruas #F2F0EA, quadras #E4E0D5, avenidas linha #121212 2,4 pt, trilho #121212 6 pt com tracejado de papel, parque = quadra + trama de pontos 45 %, água = hachura 45° de tinta 35 %, rótulos Martian Mono 8 pt sobre caixinha de papel.
- **Offline**: recorte em cache sempre aparece; sem pack baixado, B-3 lê o PMTiles do R2 pela rede e, offline, mostra "sem mapa offline de <cidade>" com o comando do `tiles.sh` (regra atual).

## Presentes (spec do item 7)

- **Modelo** (container da viagem): `Gift { id, title, person, quantity, estimatedPrice (moeda da viagem), paidPrice?, boughtAt?, source (name|link|video|place|photo), sourceURL?, videoInboxId?, photoId?, placeId? (lugar do board) | store { name, coordinate?, chain: Bool }, note, order }`. Pessoas = nomes distintos (sem tabela própria; renomear atualiza todos). Export/import aditivo em `board.schema.json` (`gifts: []`, versão do schema sobe).
- **Lista**: numeral = faltam; subtítulo "N itens · N pessoas · N comprados" e o previsto na moeda + conversão (câmbio de Ajustes). Grupo por pessoa (faixa tinta: nome · contagem · subtotal), ordem: quem tem item perto primeiro, depois alfabética. Linha: caixa 22 pt borda 2 pt; nome (15/700); meta "loja · preço · origem"; à direita distância (se a loja tem coordenada) ou sigla do bairro + dia, ou "na volta" (aeroporto). Laranja = loja a ≤ 10 min e aberta. Comprado = caixa cheia, nome riscado, meta "comprado · loja · valor pago".
- **Adicionar**: o campo "o quê" já focado; "de onde veio" troca o bloco de origem: Link/Vídeo usam o leitor do `AddLink` (prompt 29, no aparelho) e preenchem nome, loja e preço com confiança; Local abre o seletor do board/Explorar; Foto usa Vision pra texto (nome/preço). "Qualquer <rede>" (chain) só vira loja concreta dentro do quero (busca sob demanda com `ApiBudget`), nunca em segundo plano.
- **Comprado**: painel de tinta pede o valor pago (teclado numérico, moeda da viagem), cria o gasto do dia (categoria "presentes") e soma na cota tax-free da loja no dia. "Desfazer" reverte gasto e estado.
- **Na capa e no dia**: o ranker da capa (`CapaSuggestState`) ganha o candidato "presente" quando a loja tem coordenada e está a ≤ 10 min, aberta; a linha leva o selo "presente". Na Linha do dia, vira micro-parada tracejada "passar na Don Quijote (presente da Ana)" quando a loja fica a ≤ 5 min de uma parada. Nunca push.
- **No quero**: "presente", "comprar…" ou o nome de uma pessoa → primeira faixa laranja "seus presentes · dá pra comprar aqui" (lojas na cidade de hoje, qualquer distância), depois seus Musts shop, depois a faixa tinta de fora.
- **Vazio**: bloco + "Nenhum presente ainda" + "cole um link ou vídeo de algo que alguém pediu" + `+ Presente`; numeral 0.

## Assistente

- **Abre por**: ✦ (todo bloco de foto), ← na capa, "Continuar no Assistente" no quero, Siri/`must://assistente`. Sheet em tela cheia (sem barra de abas).
- **Página 1 = Dicas** (`Assistente-1`): bloco curto com a foto do bairro e "O que eu sei de hoje"; filtros quadrados (Agora · bairro · país · Salvas); numeral laranja = dicas de agora; linhas de índice com número grande (hora, ¥, temperatura). Rodapé: duas sugestões em chip e o campo (tinta, 58 pt) com microfone e enviar laranja.
- **Conversa** (`Assistente-2`): sem balões. Pergunta do usuário em Bricolage 30; resposta em Schibsted 15,5 com a fonte ("com o seu board e o tempo da JMA"). Mudanças de plano como índice: laranja = entra, riscado = sai (com pra onde vai), papel = fica. "Aceitar o dia novo" grava pelo solver (âncoras e regras de sempre); o modelo nunca inventa lugar, só escolhe do board.
- **Offline**: o modelo é no aparelho (Foundation Models); sem modelo, o fallback por palavra-chave atual, com o rótulo "no aparelho · por palavra-chave".

## Minhas viagens

Cada linha: bandeira retangular 38×26 pt com borda de 2 pt (o `TripFlag` ganha o estilo retangular; o círculo continua no selo da capa), nome (17/800), meta (datas · estado · feitos), etiqueta "agora" (tinta) ou "gps" (contorno), e coluna da moeda de 76 pt com borda à esquerda: código ISO (Martian 11/800) e símbolo (Bricolage 28). Viagem atual = linha laranja. Embaixo: Automático (interruptor quadrado), "+ Nova viagem" (faixa tinta) e a nota "trocar não apaga nada". Viagem sem datas mostra "a confirmar".

## Regras novas do corte (somar ao `CLAUDE.md`)

1. **Cantos fixos**: superior esquerdo = ⇄ (capa), ← (tela empurrada) ou ✕ (tela cheia/sheet); superior direito = ✦. Botões quadrados de 40 pt, borda 2 pt, sem raio. Nada além de texto mono nos cantos.
2. **Cor por linha inteira**: laranja = seu e dá agora (aberto, perto, ação); tinta = de fora do board; papel = plano, fechado ou o resto. Pinos seguem a mesma regra.
3. **Foto só se já está no disco**; linha de fora do board não tem miniatura. Miniaturas do índice: 54 pt quadradas, mesmo tratamento do bloco (P&B × cor do lugar + trama), número do pino no canto.
4. **Rótulo da régua diz o recorte**: "↓ quero", "↓ quero em Nakano", "↓ presentes perto". Máximo ~20 caracteres pra não encostar no pegador.
5. **Um numeral por tela**, laranja no papel ou branco no bloco.
6. **Sem cápsula, raio, degradê ou sombra** em nada que é do app (barra, chips, botões, sheets, pinos). Elementos do sistema (teclado, indicador de início) ficam como o iOS desenha.
7. **Painéis por cima** (comprado, trilho) entram como faixa de tinta de largura total com filete laranja de 12 pt em cima, não como sheet arredondada.

## Dynamic Type, movimento e acessibilidade

- Tudo com `mustCap` até XXXL. Blocos de foto têm altura mínima, não fixa: o texto empurra a régua pra baixo. Nome do bairro/lugar: `lineLimit(2)` + `minimumScaleFactor(0.5)`. Metas de linha: `lineLimit(1)` com truncamento; nomes de linha: até 2 linhas.
- Coluna de número do índice (`.d`/`.n`) cresce com o texto; acima de XL o número vai pra cima do nome (empilha).
- Trilho do Explorar acima de XL mostra só as siglas; o painel B-2 continua com nomes.
- Barra: acima de XL os rótulos somem e ficam só os ícones (o VoiceOver lê o nome).
- Reduzir movimento: sem zoom do recorte (vira fade), sem animação do trilho, sem caret piscando.
- VoiceOver: trilho é um elemento ajustável ("Nakano, 5 minutos, hoje 19h"); pinos e linhas do índice são o mesmo elemento (ler a linha seleciona o pino); a caixa do presente é um botão "Marcar comprado".

## Estados

- **Offline**: chip "sem internet · offline ok" no canto do bloco (mono). Explorar: recortes do cache, camada "fora do board" riscada. Quero: faixa tinta vira "sem internet · só seus Musts". Assistente, Presentes e Minhas viagens funcionam inteiros.
- **Sem foto**: bloco com a cor do lugar, a trama e os arcos (Nakano, Gion, Presentes). Nunca baixa foto por causa do bloco.
- **Viagem futura**: Explorar abre no primeiro bairro do dia 1, sem "você está aqui"; o trilho ordena pelo hotel.
- **Cota do Google no fim**: camada "fora do board" mostra "cota do mês no fim" e desliga; nada some sem explicação.
