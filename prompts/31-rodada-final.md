# Prompt 31 · Rodada final: fluxos, Explorar, Presentes, ingressos e o corte em tudo (08/11/2026)

Pedido do Vinicius antes de dormir (08/11, madrugada): "caminhe para finalizarmos o projeto, a viagem está chegando". Agentes trabalham a noite toda; ele olha de manhã. Tudo segue `CLAUDE.md` e o **corte** (`prompts/30-corte.md`, `design/v8/screens/Corte*.png`): foto em bloco, régua preta, papel, índice com réguas de 2 pt, cor só em bloco inteiro (laranja = seu/ação, tinta = de fora), um numeral gigante com significado, nada de cápsula/raio/degradê/sombra. Meta dele: **"quero ser referência de layout de app na loja da Apple"**.

## Pedidos (cada um vira tarefa de um agente)
1. **Tirar a dica do gesto de puxar** (passo a passo "Mudou o plano?" e o cutucão). A régua continua puxável, com o pegador e o rótulo curto "↓ quero"; nada de sobreposição ensinando. *(decisão do Claude: some o passo a passo e o cutucão; o rótulo fica, curto.)*
2. **Quero nunca volta vazio à toa** — "cliquei em comer em Nakano e não achou nada; qual o sentido? Não teria que ter APIs externas? O mesmo pros outros Musts." Regras:
   - Origem da busca: GPS **só se estiver na cidade da viagem**; senão o centro do bairro escolhido/da capa (ou da cidade de hoje, ou da primeira cidade da viagem futura). Nunca buscar "perto" do Brasil numa viagem ao Japão.
   - Faixa laranja: Musts do board que batem com o pedido na cidade (qualquer distância), também quando a viagem ainda não começou.
   - Faixa tinta: **fontes externas já aprovadas** (Google Places Text/Nearby com field mask mínimo e `ApiBudget`; Wikipedia geosearch pra "ver"; eventos do Em cartaz pra "ouvir/noite"), por vontade e por tipo de Must (comer, beber, café, ver, comprar, ouvir, noite, foto, arte, fazer). Sem rede ou sem chave: diz isso na faixa ("sem internet · só seus Musts") em vez de "nada".
   - Vazio real: diz o porquê e oferece ampliar o raio / trocar de bairro.
3. **Foto em carrossel**: tocar numa foto (Lugar, Lista, Em cartaz, Coleção, resultado do quero…) abre o visualizador em tela cheia com **todas as fotos daquele lugar** e deslize pro lado (`PhotoViewer` já existe; ligar em todo lugar que abre foto).
4. **Minhas viagens com bandeira e moeda**: cada linha mostra a bandeira (`TripFlag`) e a moeda (código + símbolo, ex.: "EUR €") além do nome/datas.
5. **Botão de IA da capa**: hoje abre Dicas; tem que abrir o **Assistente**. O Assistente está escondido: repensar como se chega nele (ver item 9).
6. **Ingressos (importar, ler PDF, foto)**: ainda rudimentar. Avaliar a leitura atual (`Must/Features/Ticket/Import/`, PDFKit, Vision). Usar primeiro o que o iOS 26 já dá: camada de texto do PDF (PDFKit) antes de OCR; Vision com `RecognizeDocumentsRequest`/`.accurate` + idiomas (pt, en, ja, it) + correção; `DataDetector` pra datas/horários; `.pkpass`; **Foundation Models (no aparelho) com `@Generable`** pra estruturar os campos a partir do texto. Modelo de IA de terceiros dentro do app **só com relatório comparativo** (o Claude decide de manhã com o Vinicius). Montar um corpus de teste (PDFs/imagens sintéticos de ingresso: museu JP, show, trem, Coliseu, voo) e medir acerto por campo antes/depois.
7. **Lista de presentes** (feature nova, com telas desenhadas): item a comprar adicionado por **nome, link, vídeo, local (lugar/loja do board ou do mapa), foto** e **pra quem** (nome da pessoa); vira **checklist** (comprado / não), com preço estimado e onde comprar; agrupado por pessoa; entra no "quero comprar…" e no dia (sugere passar na loja quando estiver perto). Dados no container da viagem; export/import no JSON do board (aditivo, versão do schema sobe).
8. **Explorar** (menu novo, substitui a aba Mapa): "mapa mais inteligente, layout bem brutalista com imagens + navegação inovadora; traga um conceito novo". O designer propõe; o Claude escolhe.
9. **Repensar os fluxos de tela no geral** e **desenhar pra visualizar**: mapa de navegação (abas, o que abre o quê, gestos), Assistente acessível, IA, quero, Explorar, Presentes, Bolso, Ingressos. Entregar desenhos (HTML + PNG) e o mapa de fluxo.
10. **O corte em todas as telas que ainda não estão nele** (Ajustes, folhas, Nova viagem, Carteira, Voos, Dicas, Guia, Musts, Em cartaz, Coleção, Filmes, Compras, Ingresso…), "se houver necessidade" — e há.
11. **Agente viajante**: um agente usa o app como um viajante real (Japão, 11–24 nov, Tóquio → Kyoto → Tóquio; e um dia em BH) e escreve um **relatório de uso honesto**: o app é útil? a abordagem (board de Musts → dia montado, corte, quero) está certa? o que faria um viajante desistir? O Vinicius quer validar a abordagem, não ouvir elogio.
12. **Testes que falham na primeira rodada** depois de prints no simulador (o app de teste não conecta no `testmanagerd`): o Claude investiga e corrige o processo (scripts).

## Ordem
- **Leva 1 (paralelo)**: designer (8, 9, 7-telas, 4-tela) · viajante (11) · ingressos (6) · consertos (1, 2, 3, 4, 5-provisório) · corte nas telas restantes (10).
- **Leva 2 (depois dos desenhos)**: Explorar (8) · Presentes (7) · fluxos e Assistente (9, 5).
- O Claude mescla cada entrega no `main`, roda a suíte, confere prints e instala no iPhone de manhã.

## Regras de sempre
Sem API/chave nova (Google Places, Open-Meteo, Wikipedia, Commons, AeroDataBox, eventos já existentes valem; Anthropic só Haiku low pra links difíceis); nada de scraping; sem `tiles.sh`; sem push; `Secrets.plist` nunca commitado; pt-BR; nada em japonês na interface além do nome local "mostre ao atendente"; xcodegen; testes Swift Testing pra toda lógica nova; prints com `-debugScreen` em `scripts/qa-screens.sh`; Dynamic Type até XXXL (`mustCap`) e Reduzir movimento.
