Leia `CLAUDE.md` e as telas `design/screens/Home6.png`, `Bairros.png`, `GuiaBairro.png`, `ColarTexto.png`. Feedback do Vinicius usando no iPhone (02/11, noite): **o app trava muito**, principalmente com internet lenta, intermitente ou sem internet; a Home dá peso demais ao orçamento; ele quer planejar **por bairro** e que o app seja **guia**, não banco de dados; quer **colar a resposta de uma IA** e o app interpretar tudo; as telas estão **muito iguais**.

Faça nesta ordem. **A parte A é pré-requisito de tudo**: não comece B antes de medir e corrigir os travamentos.

## A — Travamentos e resiliência (medir → corrigir → medir)
0. **Medir antes**: rode no iPhone com Instruments (Time Profiler + Hangs + SwiftUI) abrindo Início, Mapa, Lista, Lugar e voltando pro app depois de 20 min em background; também com Network Link Conditioner em "Very Bad Network" e em "100% Loss". Salve os números (hangs > 250 ms, tempo de abertura, frames) em `QA.md` › Performance.
1. **JSON decodificado a cada leitura** (causa provável nº 1): `Place.hours`, `Place.extra`, `Place.tickets` e `TripInfo.cities` decodificam `Data` toda vez que são lidos, e Home/Mapa/Lista chamam `openState` pra todos os lugares a cada redesenho. → Cache por objeto (`@Transient` com o valor decodificado + invalidação no `set`), **ou** pré-computar campos derivados na escrita: `opensAtToday`, `closesAtToday`, `weekSchedule` compacto, `kind` e `area` como colunas simples. Nunca decodificar JSON dentro de `body`.
2. **Bússola redesenhando o mapa**: `startUpdatingHeading()` publica várias vezes por segundo no `LocationService` observável e invalida o `MapView` inteiro. → `headingFilter = 10`, heading num `@Observable` separado só lido pelo cone do "você", e o `body` do mapa não pode depender de heading. Location: ignorar atualização < 50 m **antes** de publicar (hoje compara depois).
3. **Trabalho pesado fora do `body`**: abertos-agora, perto-de-você, distância e ordenação vão pra um `@Observable` por tela, recalculado só quando mudam lugares, minuto do relógio (timer de 60 s) ou posição (> 50 m), em `Task.detached`/actor com cópias `Sendable` (não `@Model`). Lista e Board com `LazyVStack`; `@Query` com `predicate` e `fetchLimit` em vez de filtrar tudo em memória.
4. **Rede**: hoje cada chamada espera 15 s na `URLSession.shared`, sem saber se há conexão, e vários serviços são `@MainActor`.
   - `Connectivity` (`NWPathMonitor`) observável: `online / constrained / offline`. Offline → nenhuma chamada sai; a UI usa cache e mostra o chip "sem internet · offline ok" (Home6).
   - Uma `URLSession` própria: `timeoutIntervalForRequest` 8 s, `timeoutIntervalForResource` 20 s, `waitsForConnectivity = false`, `httpMaximumConnectionsPerHost = 4`, `allowsConstrainedNetworkAccess` true mas `allowsExpensiveNetworkAccess` respeitando Modo de Pouco Dados pra fotos.
   - Retry com backoff exponencial + jitter (máx. 2) só pra GET idempotente; **circuit breaker** por serviço (3 falhas seguidas → pausa 2 min); deduplicação de requisições em voo pela mesma URL; cancelar `Task`s quando a tela some (`.task(id:)`).
   - Serviços deixam de ser `@MainActor`: viram `actor` (ou `nonisolated` + `Sendable`) e só publicam o resultado final no main.
   - **Fila de saída persistente** pra tudo que o usuário fez offline e que depende de rede (resolver lugar no Places, ler link, status de voo): grava em SwiftData, reenvia quando volta a conexão, mostra "3 esperando internet" no Adicionar.
5. **Offline de verdade**: o que o dia precisa tem que estar no aparelho antes de sair de casa — ao aceitar o dia (ou às 07:00 com Wi-Fi), baixar horários, fotos pequenas, rota do Routes e Street View das paradas, previsão do dia e tiles do bairro. Tela mostra "dia salvo offline ✓".
6. **Arranque**: nada de rede nem `SyncCoordinator` antes do primeiro frame; abrir com o último estado salvo e sincronizar 2 s depois. MapLibre: criar a view uma vez e reaproveitar entre abas.
7. **Foundation Models**: sessão criada sob demanda, `prewarm()` só quando o Assistente/Colar texto abre, nunca no main; cancelar se a tela fechar.
8. **Medir depois** e comparar no `QA.md`. Meta: nenhum hang > 250 ms nas 5 telas; abrir o app em < 1 s com o último estado; com "100% Loss" tudo navega e o Hoje funciona.

## B — Início objetivo (`Home6.png`)
9. **Orçamento sai da Home**: vai pra Ajustes › Dia (meta diária, exceções) e Viagem. Na Home fica só uma linha discreta "gasto hoje ¥ X".
10. **Card do dia** (um só, grande): foto do bairro do dia (Wikimedia/Place Photo do ponto mais famoso, escurecida), "Hoje em **Shinjuku**" + vizinhos + hora + tempo, **selo do bairro** (ver D), e o bloco **Agora**: a parada atual/próxima com o essencial (fila, saia às, minutos) + progresso do dia em selos (済 / atual / próximas) + botão verde "Ir agora" (abre Como chegar). Sem dia montado: "Hoje, pra onde?" com os 3 bairros com mais musts abertos agora e o botão "Montar por bairro".
11. **Amanhã, pra onde?**: 3 cards de bairro (cor do que domina, kanji grande ao fundo, contagem, um chip de contexto: tempo, golden, "museus seg ✕", reserva). "ver todos" → Bairros.
12. Uma linha de "Por perto" (prompt 14) e o FAB verde "+" que abre Adicionar (com Link / Texto / Nome).

## C — Planejar por bairro e guiar (`Bairros.png`, `GuiaBairro.png`)
13. **Modelo de bairro**: `Area { id, name, nameLocal (kanji), cityId, centroid, polygon? , stationIds }`. Gerar de: `Place.area` existente + reverse geocoding (MapKit `CLGeocoder`, offline-tolerante com cache) + uma tabela curada em `Must/Data/areas/tokyo.json`, `kyoto.json`, `bh.json` com os bairros principais, kanji, estação principal e **vizinhos com tempo de trem/a pé** (ex.: Shinjuku ↔ Nakano 5′ JC, ↔ Shin-Okubo 3′ JY, ↔ Harajuku 4′ JY). BH: Savassi, Lourdes, Funcionários, Centro, Santa Tereza, Pampulha, Santo Agostinho, Mangabeiras.
14. **Bairros** (`Bairros.png`): mapa papel em relevo com **bolhas por bairro** (raio ∝ √musts, cor = categoria dominante, contagem em mono, kanji no maior), linhas de trem principais (Yamanote/Chūō; metrô BH), tempos entre vizinhos, você. Sheet do bairro escolhido: selo, nome, musts/abertos agora/tempo/distância, **barra de mistura** por categoria, "Junto, a poucos minutos" (chips com a cor e o código da linha), uma frase do assistente com a ordem sugerida, "Ajustar" e "Montar <bairro>+".
15. **Solver por área**: novo modo `DayRequest.focus = .area(id, includeNeighbors: true, maxHopMinutes: 15)` — candidatos do bairro + vizinhos; ordena por **horário** (o que abre/fecha cedo primeiro, golden na hora, noite no fim) e **contiguidade** (minimiza idas e voltas entre bairros, usa a matriz do Routes quando há rede, a tabela de vizinhos offline); explica a ordem numa frase.
16. **Guia do dia** (`GuiaBairro.png`): mini-mapa no topo com o percurso (trecho de trem na cor da linha, a pé pontilhado), "Guia de hoje · Shinjuku+" com selo; **capítulos por hora** com o kanji do bairro de cada parada, cards de atividade com foto e a cor do tipo (feito a 50%, atual em verde com "Como chegar · 9 min", golden em dourado, noite em cinza) e, **entre eles, o deslocamento**: chip da linha (código + cor), minutos, plataforma/saída, ou "a pé N min · saída sul". Fim com o último trem pra casa. Botões "trocar" e "Ir pro <próximo> · saia HH:MM". O Hoje continua existindo; o Guia é a visão "por bairro" do mesmo `PlannedDay`.
17. **Ser guia**: o app avisa sem você abrir (notificação local) "saia em 5 min pro Fuunji", "golden em 20 min, você está a 11 min do Gyoen", "Golden Gai abre agora, está a 6 min" — no máximo 1 a cada 45 min, só no dia aceito, desligável.

## D — Visual: as telas estão iguais
18. **Selo de estação/bairro (eki stamp)** como componente (`StationStamp`): círculo com borda dupla tracejada, kanji do bairro, leve rotação (−6° a −10°), cor da linha principal ou do tipo. Aparece no card do dia, Bairros, Guia, Colar texto e no 済 de cada bairro concluído (coleção de selos na Viagem).
19. **Kanji grande de fundo** nos cards de bairro e lista (18% de opacidade), **cor oficial da linha** em todo chip de transporte (`LineChip`: bolinha com código JY/JC/H/G + nome), **foto escurecida do bairro** no card do dia, **mini-mapa** no topo do Guia e do Adicionar.
20. Cada tela principal ganha **um** elemento-assinatura diferente (Início: foto + selo; Bairros: bolhas; Guia: trilho com linhas; Hoje: selos de progresso; Lugar: painel do tipo; Compras: vitrine), pra não repetirem o mesmo card branco + vidro.

## E — Colar texto (`ColarTexto.png`)
21. Adicionar ganha o seletor **Link · Texto · Nome**. Em **Texto**, cola qualquer coisa (resposta do ChatGPT/Claude/Gemini, lista do WhatsApp, nota). Pipeline no aparelho:
   - extrair **URLs** (regex + `NSDataDetector`) e mandar cada uma pro leitor de link existente (IG/TT/YT/Maps/site/ingresso);
   - Foundation Models com `@Generable struct ParsedTravelText { days: [SuggestedDay { title, area, items: [String] }], places: [ExtractedPlace { name, nameLocal, area, category, sub, why, priceHint, hoursHint }], tips: [Tip { text, target: .place(name)/.area/.wallet/.general }] }`; texto longo em blocos de ~3.000 caracteres com merge;
   - classificar categoria pela palavra do texto e pelo `primaryType` do Places (restaurante → eat, museu → art, templo → see/temple, bar → drink…);
   - conferir tudo no Places (IDs Only, grátis) e juntar duplicados como no prompt 16;
   - sem modelo no aparelho: regex de listas/títulos + Places Text Search por linha.
22. Tela: o texto colado aparece com os achados **marcados por cor** (eat verde, ver violeta, beber azul, área sublinhada tracejada, link em preto, dica sublinhada âmbar); contadores coloridos (comer/ver/beber/links/dicas); grupos por **dia sugerido** ("Asakusa e Ueno · virar dia 2") com os itens e status (no board / novo + nota); dicas vão pras notas do lugar ou pra Carteira ("Tokyo Subway Ticket 72h"). Botões "Só salvar" e "Adicionar N e criar dia 2" (cria `PlannedDay` com `focus = .area`).
23. Funciona offline: guarda o texto, faz o que dá no aparelho e põe o resto na fila de saída (A.4).

## Verificar
- `QA.md` › Performance com antes/depois; nenhum hang > 250 ms; "100% Loss" navegável; "Very Bad Network" sem tela presa.
- Home sem orçamento em destaque; card do dia com "Ir agora" abrindo Como chegar.
- "Shinjuku+" monta Nakano → Fuunji → Gyoen (golden) → Golden Gai com os trechos de trem certos; offline usa a tabela de vizinhos.
- Colar uma resposta real do ChatGPT com 2 dias e 8 lugares: lugares classificados, links lidos, dicas nas notas, 2 dias criados.
