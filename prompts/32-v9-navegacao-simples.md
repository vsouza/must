# Prompt 32 · v9: navegação simples, sem gesto escondido, mapa como casa (09/11/2026)

**Pare o que estiver em andamento** (agentes, worktrees do prompt 31) num ponto que compila, faça commit do que está verde e leia isto antes de seguir. Esta rodada **substitui a direção visual do corte** (prompt 30) e a navegação de `design/v9/README.md` nos pontos abaixo. Base: `docs/v9-analise-e-navegacao.md` (ler inteiro) e o artefato https://claude.ai/artifact/PYBf8NMiBukvnyuD1wHL1A (fluxogramas e wireframes).

Pedido do Vinicius (09/11): "o design passou da conta, impressiona mas exagera. O app está confuso: abro e tem ações que não sei onde disparou, swipe lateral abre algo que não sei, o bairro que ele detecta talvez seja no momento que estou no metrô. Estou com o sentimento que o app não vai me ajudar." Premissas da Mad Owl: **simplicidade, sofisticação e inovação; zero UX; Human Interface Guidelines é regra; offline é premissa; nenhum travamento é aceitável; IA é obrigatória**. "Não fique com medo de ter telas simples; a funcionalidade maior é ser útil nesse momento."

**A viagem começa em 11/11.** Por isso duas fases: a **Fase 1** tem que estar no iPhone até a noite de 10/11, segura e testada; a **Fase 2** pode seguir durante/depois da viagem. Nunca deixar o `main` sem build verde: cada agente em worktree, merge só com suíte verde, e o build instalado no iPhone continua sendo o último verde.

## O que já está certo e fica
- Barra nativa do iOS 26 (`RootView`): Hoje · Explorar · Musts · Viagem + aba de busca (`role: .search`) = Quero. **Não mexer na estrutura da barra.**
- Faixa "agora" na `tabViewBottomAccessory` (`NowAccessory`, lida do `DayClock`).
- Serviços: `DayEngine`/`DaySolver`, `DayClock`, `QueroModel`/`WantSearch`, `CapaSuggestState` (ranker), eventos, Presentes, Assistente, SOS, Bolso, Carteira, Minhas viagens, seeds (JP, BR, IT). Tudo isso é lógica boa; muda só **onde aparece**.

## Fase 1 · até 10/11 à noite (o app tem que ajudar na viagem)

### 1. Zero gesto escondido
Regra nova (vai pro `CLAUDE.md`): **todo destino tem um controle visível com nome; gesto é atalho redundante, nunca o único caminho; nada abre por deslize lateral.**
- `HomeView`: remover o `DragGesture` de 4 direções (`CapaSwipe`) e a alça do Bolso na borda. Linha do dia, Assistente, Bolso e Bom dia/Boa noite viram **botões visíveis** (ver item 2). As `accessibilityAction` continuam.
- **Régua puxável → campo tocável.** O quero da capa abre por **toque** num campo "Pedir algo…" (aparência de campo de busca do sistema), não por arrasto. Tirar o pegador, o rótulo "↓ puxe · quero", o cutucão, o passo a passo e o contador de puxadas (código e prints). A aba de busca da barra continua abrindo o mesmo Quero.
- Bom dia / Boa noite **não trocam a capa sozinhos**: viram um cartão no topo de Hoje no horário certo (antes das 10h / depois das 21h), com "abrir" e "dispensar", e as notificações locais de sempre.
- Varredura: `grep -rn "DragGesture\|onLongPress\|LongPressGesture" Must/Features` e listar no `QA.md` cada gesto que sobrou com o controle visível equivalente. Só ficam gestos padrão do sistema (voltar pela borda, puxar sheet, `swipeActions` em lista, arrastar mapa).

### 2. Hoje = uma resposta, sem cartaz
A capa deixa de ser um cartaz com foto em bloco. Hoje é uma `List`/`ScrollView` simples, nesta ordem:
1. **Cabeçalho pequeno**: "Qua, 13 nov · Shinjuku" (contexto do item 3), tempo e pôr do sol em uma linha; à direita, dois botões de barra de ferramentas: ✦ Assistente e ⋯ (Bolso, SOS, Minhas viagens).
2. **Campo "Pedir algo…"** (abre o Quero).
3. **Com dia montado**: cartão "Próxima: Fuunji · 12:10 · saia às 11:55 · a pé 6 min" com **Ir**; embaixo, as próximas 3 paradas e "ver o dia" (Linha do dia). **Sem dia**: "Agora vale" com **3** linhas do ranker (`CapaSuggestState`), cada uma com nome, distância/tempo e o **motivo** em uma linha ("seu Must · aberto até 22h · 6 min"), e o botão **Montar o dia**.
4. **Reservas e ingressos de hoje** (se houver), com o QR a um toque.
- Fora da Fase 1: numeral gigante, bloco de foto P&B × cor do lugar, trama, arcos, régua preta. A foto do bairro pode aparecer pequena (miniatura 56 pt) nas linhas, nunca como fundo de texto.
- **Um número só** por promessa (relatório do viajante, problema 4): se a linha diz "6 abertos a 10 min", não existe outro número diferente na tela.

### 3. Contexto estável (o bairro não pula no metrô)
`resolveCurrentArea()` deixa de trocar o título sozinho. Regra (Swift Testing, `ContextRuleTests`):
- O contexto de Hoje é, em ordem: bairro **escolhido à mão** (válido até o fim do dia ou até trocar) › bairro da **parada corrente/próxima** do dia › último bairro **confirmado** › hotel/cidade do dia.
- O GPS só **propõe**: com precisão horizontal < 100 m, velocidade < 1,5 m/s por ≥ 2 min e bairro diferente do mostrado → faixa discreta "Você chegou em Nakano · ver perto" (toque troca o contexto; ✕ dispensa por 1 h). No metrô/indoor (precisão ruim, ou trocando de célula rápido) nada muda.
- GPS fora da cidade da viagem nunca vira contexto (regra do prompt 31 §2 continua).
- No Explorar, o contexto é o **centro do mapa** (item 4).

### 4. Explorar = o mapa (a casa do "o que tem aqui")
O Explorar conceito B (páginas de bairro com recorte e trilho) **sai da raiz da aba**. A raiz vira o **mapa** (`MLNMapView`, estilo papel em relevo aprovado em 01/11, PMTiles offline) com uma **sheet nativa** de três alturas (`presentationDetents([.height(120), .medium, .large])`, `presentationBackgroundInteraction(.enabled(upThrough: .medium))`, material do sistema):
- **Recolhida**: campo "Pedir algo…" + uma linha "Agora vale · 3 perto".
- **Média**: os 3 cartões do ranker para o **centro do mapa** (arrastou o mapa → recalcula ao parar, com debounce de 400 ms, fora do main).
- **Grande**: lista do que está visível no mapa, agrupada por lista do board.
- **Topo do mapa**: filtros de lista em chips do sistema (Todos · Eat · Drink · See · Shop · Photo) e um botão de **camadas** (menu): Meus Musts (sempre), Hoje (rota numerada), Agora (aberto agora, fecha logo, eventos de hoje, golden), Indicados (fora do board; desligada por padrão; só com rede e cota).
- Pinos: Must = cor da lista; feito = cinza; evento = marcador próprio; você = ponto azul do sistema. Toque no pino → a sheet mostra o Lugar resumido (nome, motivo, Ir, Encaixar hoje, Abrir).
- As páginas de bairro do conceito B continuam acessíveis por "Bairros" no menu ⋯ do Explorar (não apagar o código; só tirar da raiz).
- Desempenho: um só `MLNMapView`, anotações em lote, nada de recalcular ranking no `body`. Arrastar o mapa a 120 Hz sem queda.

### 5. Visual calmo (dose certa)
Novo `Must/DesignSystem/V9/` (o V8 fica pros prints antigos até a Fase 2 limpar):
- **Fundos e texto do sistema** (`.background`, `.secondarySystemBackground`, `.primary`, `.secondary`); **modo escuro funciona** (era fora de escopo; agora é obrigatório, o sistema faz quase tudo).
- **Uma cor de acento** pra ação e "agora": o laranja **dessaturado e mais escuro**, `#D9572B` no claro e `#F07A4E` no escuro, aplicado como `.tint` do app. Nunca como fundo de tela inteira; no máximo em botão primário, ponto do "agora" e pino selecionado. Alerta (SOS, atraso) usa `.red` do sistema.
- **Tipografia**: SF Pro do sistema com Dynamic Type pra tudo; a Bricolage fica só no título grande de Hoje e do Lugar (se ficar estranho com o resto, sai também). Sem Martian Mono em rótulo de canto; mono só em número tabular (horário, distância).
- **Materiais**: sheets, barra e acessório com o vidro do sistema; cartões com `.secondarySystemBackground` e raio padrão do sistema. Sem trama, sem arcos, sem sombra desenhada à mão.
- Cor do país: só a bandeira na aba Viagem e em Minhas viagens.
- Aplicar o V9 em: Hoje, Explorar (mapa + sheet), Quero (resultado), Lugar, Linha do dia, Viagem. O resto pode ficar no visual atual até a Fase 2.

### 6. Pedir (Quero) sempre termina num lugar no mapa
- O resultado do Quero mantém as duas faixas (seus Musts mesmo longe / aqui perto agora), mas com o visual V9 e um botão **Ver no mapa** que abre o Explorar com só esses pinos.
- Pergunta (termina com "?" ou começa com "como", "que", "qual", "dá tempo"…) → resposta curta do modelo no aparelho + "Continuar no Assistente" (regra do prompt 31) **e**, quando a resposta envolve um lugar, o lugar mais perto pra fazer aquilo.
- Testes de aceitação com os exemplos do Vinicius (em `QueroAcceptanceTests`, com fakes): "quero comprar um Seiko" (só loja física, nunca site), "que drink monto no 7-Eleven?" (resposta + 7-Eleven aberto mais perto; as receitas vêm de `data/guia-konbini.json`, criar com 5–8 combinações simples em pt-BR, sem marca em japonês), "rua pra tirar foto" (camada Photo + luz), "presente perto daqui" (Presentes + lojas), "onde almoço perto" (Must eat aberto + indicados), "tem algo rolando hoje?" (eventos de hoje).

### 7. Verificar (Fase 1)
- Suíte inteira verde; build de aparelho; **instalar no iPhone** e deixar o `QA.md` com "rodada 32 · fase 1".
- Prints novos em `scripts/qa-screens.sh` (JP e BH, claro e escuro): `v9-hoje-plano`, `v9-hoje-sem-plano`, `v9-explorar-recolhida`, `v9-explorar-media`, `v9-explorar-pino`, `v9-quero-seiko`, `v9-quero-konbini`, `v9-lugar`, `v9-chegou-em` (faixa do GPS).
- Rodar de novo os cenários 2, 3, 4 e 9 do `docs/relatorio-viajante.md` e anotar a nota nova de cada um. **Problema 1 do relatório (telas contradizem o relógio) tem que estar resolvido**: Hoje, Linha do dia, acessório e Agora leem o mesmo `DayClock` e mostram o mesmo horário; teste que garante.
- Modo avião: Hoje, Explorar (mapa e Musts), Quero (só seus Musts, com o aviso), Lugar e SOS funcionam.
- Nenhum `DragGesture` de navegação sobrando (lista no `QA.md`).

## Fase 2 · durante/depois da viagem
- Desenhos v9 completos (canvas novo do Claude) e aplicar o V9 nas telas restantes (Musts, Viagem, Bolso, Carteira, Presentes, Assistente, Ajustes, Nova viagem).
- Limpar o corte: `CutBand`, `CutRule`, passo a passo, prints e tokens V8 que ninguém usa.
- Dias especiais do relatório: chegada (pousou), troca de cidade, último dia.
- Dia que se refaz sozinho quando atrasa (problema 2 do relatório), com "Ajustar" em um toque.

## Agentes (Fase 1)
| Agente | Branch | Modelo | Faz | Fronteira |
|---|---|---|---|---|
| **0 · Orquestrador** | `main` | Opus | Para o que estiver rodando; cria `DesignSystem/V9/` (tokens, `.tint`, estilos de cartão/linha) e o protocolo do contexto (`ContextResolver`), commit `r32/0: contrato`; depois merge A → C → B, QA. | `Must/DesignSystem/V9/**`, `Must/Services/Context/**` (stub), `CLAUDE.md`, `QA.md` |
| **A · Hoje e gestos** | `r32/a-hoje` | Sonnet | Itens 1, 2 e o uso do contexto em Hoje; cartão Bom dia/Boa noite; um número só; prints de Hoje. | `Must/Features/Home/**`, `Must/Features/Today/**`, `Must/App/NowAccessory.swift`, `MustTests/Home*`, `Capa*`, `DayClock*` |
| **B · Explorar mapa** | `r32/b-mapa` | Opus | Item 4 (mapa + sheet, camadas, pinos, recálculo pelo centro, Lugar resumido). | `Must/Features/Explorar/**`, `Must/Features/Map/**`, `MustTests/Explorar*`, `Map*` |
| **C · Contexto e Pedir** | `r32/c-pedir` | Sonnet | Item 3 (`ContextResolver` real + `ContextRuleTests`), item 6 (Quero V9, Ver no mapa, perguntas com lugar, `guia-konbini.json`, `QueroAcceptanceTests`). | `Must/Services/Context/**`, `Must/Features/Quero/**`, `Must/Services/Intelligence/**`, `data/guia-konbini.json`, `MustTests/Quero*`, `Context*` |
| **D · QA viajante** | `r32/d-qa` | Sonnet | Depois do merge: item 7 inteiro, relatório curto em `docs/relatorio-viajante-v9.md`. | `scripts/qa-screens.sh`, `docs/**`, `QA.md` |

## Regras de sempre
Nenhuma API ou chave nova (Places, Open-Meteo, Wikipedia/Wikidata, Commons, AeroDataBox e as fontes de eventos já existentes valem); CloudBoost só `claude-haiku-5-5` effort low; nada de scraping; `Secrets.plist` nunca commitado; sem push; `xcodegen generate` ao mexer no `project.yml`; pt-BR; nada em japonês na interface além do nome local "mostre ao atendente"; Swift Testing pra toda lógica nova; Dynamic Type até XXXL; Reduzir movimento; offline é estado normal; nada pesado no main thread.
