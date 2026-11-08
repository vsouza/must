# Prompt 30 · O corte: foto em bloco, régua preta e "quero…" puxando (07/11/2026)

Pedido do Vinicius: a capa não pode ser cor chapada; quer a foto do lugar **sutil, com um efeito nosso** e as linhas do design por cima, num estilo **brutalista** (cores fortes, separações fortes). E o momento que importa: **"estou aqui agora, em grupo, mudamos o roteiro, queremos algo"**: abrir o app e saber o que tem perto, e buscar uma vontade ("café") que junte **os cafés perto** e **os cafés do board, mesmo longe**. A busca não pode ser um botão óbvio. **Aprovado em 07/11/2026**: opção C ("corte brutalista") como linguagem de **todas as telas**, gesto de puxar a régua pra pedir, passo a passo na primeira vez e na primeira entrada de cada viagem.

Referências (abrir antes de começar): `design/v8/screens/CorteFundo.png` (as três opções; **a escolhida é a C**), `CorteFluxo.png` (capa → puxar → resultado), `CorteGesto.png` (passo a passo, gesto no meio, cutucão). HTML ao lado de cada PNG (abre no navegador, fotos em `design/v8/screens/photos/`).

## 1. A linguagem: o corte
Toda tela principal tem **foto em cima, papel embaixo**, separados por uma **régua preta grossa**. Nada de degradê, sombra ou foto lavada atrás de texto no papel.

- **Bloco da foto (`CutBand`)**: a foto do lugar/bairro em **preto e branco com contraste alto** (≈ grayscale + contrast 1,6) **multiplicada sobre a cor do lugar** (`TripTheme`: Japão #D7000F, Brasil #007A33, Itália #1F5FB4, viagem nova = `colorHex`), com **trama de pontos** de tinta (#121212, ponto ~0,9 pt a cada 4 pt, 25 %) e os **arcos de 1 pt** (branco ~50 %) por cima. Texto do bloco em branco. Sem foto no disco: o mesmo bloco só com a cor do lugar, a trama e os arcos (estado normal, não erro). **Nunca baixa foto por causa disso**: usa a que o app já tem (`CapaState.photo`/`AreaHeroes`, foto do Lugar, capa da lista via `ListCover`).
- **Processar a foto uma vez**: o tratamento (P&B, contraste, multiplicar, trama) é feito fora do main (Core Image) e guardado no cache de disco por `foto + cor`; o `body` só mostra a imagem pronta. Nada de filtro recalculado a cada frame, nada de JSON/decodificação no `body`.
- **Régua (`CutRule`)**: faixa #121212 de largura total.
  - **Estática** (12 pt): só estrutura; sem pegador, sem texto.
  - **Puxável** (26 pt): pegador laranja #FF4A1C no centro + micro-rótulo mono "↓ puxe · quero…" (vira "↓ quero" depois de 3 usos). **Regra de ouro: só puxa a régua que tem pegador e texto.**
- **Papel embaixo**: #F2F0EA, linhas de índice separadas por **réguas de 2 pt** de tinta (sem cartões arredondados nem carrossel). Cor só em **linha/bloco inteiro**: **laranja = seu** (Must do board, ação), **tinta = o mundo lá fora** (fora do board, Google, evento), papel = o resto.
- **Um numeral gigante por tela**, sempre com significado (Bricolage 800). Mono (Martian) pros cantos e distâncias.
- Fontes, tinta, papel e laranja da v8 não mudam; a cor do lugar continua só no bloco da foto (e no anel do selo).
- Reduzir movimento: sem zoom, sem cutucão, sem dedo animado; transições viram fade.

## 2. Capa (Hoje) · `CorteFluxo.png` 1
Substitui as três capas atuais (cor, foto, inteligente) por uma só.
- **Bloco da foto (~half da tela)**: cantos mono (dia · data · hora / tempo · pôr do sol), "PAÍS · VOCÊ ESTÁ EM" e o **nome do bairro gigante** no pé do bloco (bairro por GPS/célula como hoje; sem GPS, a cidade do dia). Viagem que ainda não começou: o título é "Faltam N dias" e o bairro vira "Primeiro dia · <cidade>" (corrige o bug em que os cartões "Agora vale" passavam por cima disso).
- **Régua puxável** logo abaixo.
- **Papel**: cabeçalho "ABERTO AGORA · A 10 MIN" + uma linha do plano ("próxima: Fuunji 19:30", "nada marcado", "plano solto desde 17h") e, à direita, o **numeral gigante laranja = quantas coisas abertas a 10 min** (board + fora). Embaixo, **índice duro** com as escolhas do ranker atual (`CapaSuggestState`, prompt 26): cada linha = distância/hora em número grande (240 m, 20h, 6 min) + nome + motivo. Linha laranja se é Must seu, tinta se é de fora do board/evento, papel se é o plano. Toque abre o Lugar/evento como hoje.
- Gestos da capa continuam: pra cima = Linha do dia; pra esquerda = Dicas; pra direita/alça = Atalhos; pra baixo **fora da régua** = Bom dia/Boa noite. **Arrastar começando na régua = quero…** (o arrasto da régua tem prioridade dentro da faixa dela; fora dela nada muda).
- Tirar o que só servia às capas antigas (modo `-capaFoto`, `smartCover`, `colorCover`), sem quebrar os prints que dependem deles (atualizar `scripts/qa-screens.sh`).

## 3. Puxar a régua = "quero…" · `CorteFluxo.png` 2 e `CorteGesto.png` 2
- O arrasto é **interativo**: a régua segue o dedo, o bloco da foto encolhe, o título vira frase **"<Bairro>, quero"** e uma **fenda laranja** abre entre a foto e a régua. Passou do limite (~110 pt): trava aberta, foca o campo (teclado) e dá um **háptico** (`.sensoryFeedback`). Antes do limite: volta com mola. **Tocar no nome do bairro** faz o mesmo (atalho sem gesto).
- Na fenda: campo grande (Bricolage) com cursor laranja; microfone (`SpeechInput`); "digite ou fale · só lugares físicos".
- No papel: **vontades de agora** em chips quadrados de borda 2 pt (sem raio): café, comer já, beber, sentar 1 h, fugir da chuva, barato, pra 4 (mapear pros `WantVerb`/intents do `QueroModel`; os que não existirem viram texto livre).
- Por baixo é o **Quero… do prompt 25** (`QueroModel`, `WantSearch`): nada de serviço novo, nada de API nova. O `+` da barra continua abrindo o Quero (mesma tela, já aberta).

## 4. Resultado em duas faixas · `CorteFluxo.png` 3
- Bloco da foto encolhido (~120 pt) com o que foi pedido em gigante ("café") e "N achados".
- **Faixa laranja "SEUS MUSTS · N · MESMO LONGE"**: Musts do board que batem com o pedido **na cidade de hoje, a qualquer distância** (hoje o Quero pode cortar por raio: não cortar o board). Ordem: dá hoje (aberto quando você chega) › tempo pra chegar. Cada linha: distância grande (mono) + tempo/modo embaixo ("2,1 km · 9 min trem"), nome, motivo ("aberto até 19h", "fecha 20h · não dá"), ação **"ir"** (rota por deep link como hoje); se não dá hoje, ação **"amanhã"** (ou o dia em que abre). Nunca entra lugar de outra cidade.
- **Faixa tinta "AQUI PERTO AGORA · N"**: o que o Google/fontes do Quero acharam **fora do board**, perto, aberto; ação **"+ board"**. Respeita orçamento/cota e cache (`ApiBudget`), Modo de Pouco Dados e offline: sem rede, a faixa vira uma linha "sem internet · só seus Musts" e a laranja funciona inteira.
- "Encaixar hoje" (prompt 25) continua disponível por toque longo na linha ou no Lugar.
- Vazio: "nenhum café seu nesta cidade" na laranja e a tinta normal (ou vice-versa).

## 5. Ensinar o gesto · `CorteGesto.png`
- **Passo a passo** na **primeira vez que a capa abre** e na **primeira entrada em cada viagem** (guardar os ids de viagem já apresentados; não por região/abertura). Passo 1: tela tinta a ~93 %, só a régua acesa com contorno laranja, título "Mudou o plano?", texto curto, **dedo fantasma** descendo até uma **linha tracejada laranja** ("até aqui"); **só avança quando o usuário puxa de verdade**; "pular" sempre visível. Passo 2: a fenda aberta com "café" sugerido; ao enviar mostra o resultado real e "pronto". Reduzir movimento: seta parada no lugar do dedo.
- **Durante o gesto**: rótulo da régua troca pra "mais um pouco" antes do limite.
- **Cutucão**: parado na capa ~5 s sem rolar nem tocar → a régua desce ~22 pt e volta (uma vez por aparição da capa). Depois de **3 puxadas com resultado**, o texto encurta pra "↓ quero" e o cutucão para. Reduzir movimento desliga.
- VoiceOver: a régua é um botão "Quero…" com dica "abre a busca do que tem perto"; o passo a passo é anunciado e tem a ação "Abrir quero" no lugar do gesto.

## 6. Etapa 2 · o corte nas outras telas (depois da capa mergeada)
Mesmo `CutBand`/`CutRule`; cada tela escolhe a foto e o numeral.
- **Lugar** (`PlaceView`): bloco = foto do lugar (a que já está no disco) com o nome; **régua puxável** "↓ perto daqui, quero…" → o mesmo Quero com origem no Lugar (perto do lugar, não do GPS). Ficha, horários, custo etc. viram linhas de índice no papel com réguas de 2 pt.
- **Listas** (`BoardView`, `ListView`): no Board, cada lista é uma **faixa inteira** (nome gigante, contagem, foto da capa só no bloco do topo); na Lista, bloco = capa da lista e **régua puxável** "↓ quero <tipo>" → Quero já filtrado pela lista. Linhas dos lugares no padrão índice (distância grande, nome, motivo).
- **Dia** (`TodayView`/`LinhaDoDiaView`/`AgoraView`/`BomDiaView`/Boa noite, `MontarView`/`ProposalView`): bloco = bairro do dia (ou da próxima parada), régua **estática**; paradas como índice com hora em número grande; o "Outra" mantém a animação do que mudou (prompt de 06/11).
- **Bolso** (`BolsoView`): bloco = cor do lugar + trama (sem foto se não houver), régua estática, cartões viram faixas.
- **Fora**: Mapa (o mapa já é a imagem), Ajustes, folhas/sheets, SOS (fica tinta, é emergência), Nova viagem.

## 7. Dados, desempenho, premissas
- Nenhuma API nova, nenhuma chave nova, nenhum download novo de foto; cache primeiro; offline é estado normal.
- O arrasto da régua a 60 fps (ProMotion 120): só `offset`/altura animados; imagem tratada já pronta.
- Tudo em pt-BR; nada em japonês na interface.

## 8. Verificar
- Testes (Swift Testing): divisão board × fora no resultado (board a qualquer distância na cidade de hoje, nunca de outra cidade; fora só o que não está no board), ordem "dá hoje › tempo"; limite do arrasto (abre/volta); regra do passo a passo (primeira vez + primeira entrada por viagem); contador do cutucão (para depois de 3, rótulo encurta); cache do tratamento da foto (mesma chave não reprocessa).
- Prints (`scripts/qa-screens.sh`, com `-debugScreen`): `corte-capa` (BH, JP, IT, Portugal futura), `corte-capa-sem-foto`, `corte-puxando` (régua no meio), `corte-quero` (fenda aberta), `corte-cafe` (resultado com as duas faixas), `corte-cafe-offline`, `corte-walk1`, `corte-walk2`, e na etapa 2 `corte-lugar`, `corte-lista`, `corte-board`, `corte-dia`, `corte-bolso`. Conferir com Dynamic Type grande e Reduzir movimento.
- Suíte inteira verde; build no aparelho.
