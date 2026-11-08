# Relatório do viajante (08/11/2026)

Persona: brasileiro, 2 semanas no Japão (11–24 nov, Tóquio → Kyoto → Tóquio), com amigos, usa Google Maps e Instagram. Build do `main` b2dd173 no iPhone Air (simulador), data/GPS simulados, fakes de Places/Nearby/voo/dicas. Prints em `docs/relatorio-viajante/` (prefixo `cN-` = cenário N; caminho base: `/Users/vsouza/Code/must/.claude/worktrees/agent-ad0be0fc1f0c2232a/docs/relatorio-viajante/`).

Limites honestos: não toquei na tela (só `-debugScreen`), então gestos (puxar a régua, deslizar) e importação real (colar PDF, Takeout) eu avaliei pelo código e pela tela de entrada, não usando. Tudo com dados fake, que escondem a qualidade real do Google. Onde algo é efeito do fake, digo.

## Veredito (5 linhas)
1. Útil para um viajante organizado e solitário que já tem uma lista salva e quer "o que faço agora aqui", não para quem precisa de um mapa/rota: é um **guia de bolso offline-first**, não um substituto do Google Maps.
2. A aposta certa: board curado → capa "agora" → régua "quero" (a pergunta "tô aqui, o que tem?" é real e o Google Maps responde mal pra *meus* lugares); o corte visual é forte e memorável.
3. A aposta frágil: o dia montado pelo solver. Na tela, o plano contradiz a si mesmo (capa × Linha × Agora) e fica pra trás do relógio; um viajante abandona na primeira vez que o app disser "você deveria estar no ramen desde 12:45" às 14h20.
4. Tudo depende de dados que o seed não tem: 104 de 105 lugares do Japão são `approx` e só 2 têm horário. Sem a primeira sincronização boa com o Google, "aberto agora/não dá hoje" é chute. O app não deixa claro o que é chute.
5. Para virar app de uso diário: cortar o que é largura (Colecionáveis, 3D, Filmes, Em cartaz como aposta), dobrar em **confiança do dado + um dia que se refaz sozinho + Quero que nunca decepciona**, e fazer o grupo (amigos) existir.

## Cenários

### 1. Semana antes: board, voos, hotel, ingressos — nota 3/5
Funcionou: "Cola o link" aceita Reel/TikTok/YT/Maps e nome (`c1-adicionar.png`); a conferência do ingresso é boa: campos com ponto de confiança, "lido do texto", cancelamento grátis até sex 13 nov, vincula ao Must do (`c1-ingresso-revisar.png`); checklist por voo com modelo "internacional + Japão" (Visit Japan Web, avisar banco, eSIM) é exatamente o que eu esqueceria (`c1-voos.png`); Bolso/Carteira guardam Suica, JR Pass etc.
Travou: não há "colar lista do ChatGPT" visível como caminho principal (existe aba Texto, escondida em 3 abas); Takeout do Google só existe como importador de arquivo GeoJSON/KML em `Must/Services/Ingest/SavedPlacesImporter.swift:15` (CSV do "Lugares salvos" do Takeout, que é o formato real que o Google entrega hoje, não aparece). Hotel: não achei lugar para cadastrar hotel como âncora do dia 1 (o dia 5 usa "Café perto do hotel" e "Descanso no hotel" sem eu ter dito qual é). O voo exibido (CNF 18:25, "2 conexões", chegada "—", "saia às 15:25") mistura fake e real: sem chegada em HND não dá pra planejar o dia 1.
Faltou: reserva de hotel/Airbnb por link (endereço em japonês pro táxi), tela "o que falta cadastrar" antes da viagem.

### 2. Dia 1, chegando cansado em Shinjuku, chuva — nota 2/5
Capa às 15:30 (`c2-capa-dia1.png`): bloco vermelho gigante sem foto, "Shinjuku", "nada marcado · 12 Musts a 15 min" e o numeral laranja "2". Bom Dia (`c2-bomdia.png`) às 15:30 diz "ACORDOU", "Sem previsão no aparelho", "Nada marcado ainda": o app não sabe que é o dia da chegada. Não existe modo "acabei de pousar": Narita → hotel (Narita Express/Skyliner, Suica, mala, check-in só às 15h) é o momento de maior ansiedade e o app só tem checklist de voo *antes* do embarque ("pouso" é uma fase do modelo, mas não aparece na capa). Chuva: o app só mostra clima na Bom Dia, e sem previsão no aparelho (fake/offline). Nenhuma sugestão de "dia 1 leve, perto do hotel, comer algo".
O que ajudaria: capa "pousou" (Wi-Fi/eSIM, trem do aeroporto, endereço do hotel, "hoje: só comer perto e dormir").

### 3. Dia cheio em Shinjuku/Harajuku com reserva às 19:00 — nota 3/5
Linha do dia (`c3-linha.png`) é a melhor tela do app: 8 paradas, micro-paradas tracejadas, "Trem ou metrô 18 min", "JY Yamanote · Harajuku → Shinjuku · 11 min", golden hour como âncora (SOL 15:57), ¥0 de 15.000. Agora (`c3-agora.png`) tem a ação certa ("Ir · a pé 11 min"), banheiro na estação, barra de distância. Guia (`c3-guia.png`) com bairros vizinhos "Nakano · 5 min" é ótimo.
Problemas: (a) as telas discordam. Às 14:20 a Linha mostra Ramen Hōsenka 11:30 (laranja "AGORA"), a capa diz "você deveria estar em Ramen Hōsenka desde 12:45" (`c3-capa.png`), a Agora diz "Saia às 15:46" (em 86 min) e o Guia põe o ramen em "Manhã 11:30 → 12:45". Três horários pro mesmo almoço, e almoço às 15:46. (b) O dia foi montado às 08:30 e não se refaz quando passo da hora: fica "atrasado" em vez de reajustar. (c) Minha reserva das 19:00 não apareceu como âncora na capa nem na Agora; só vi "2 ÂNCORAS" no topo da Linha (uma é o pôr do sol, não reserva). (d) Fotos do Guia são quadrados cinza (`c3-guia.png`), cache frio, ok com a premissa mas pobre. (e) "Ir" abre deep link; ok.

### 4. 16h, "o grupo mudou o plano": café/comer perto, inclusive Nakano — nota 3/5
A régua "↓ PUXE · QUERO…" (`c2-capa-dia1.png`) é uma ótima ideia e o resultado em duas faixas (`c4-cafe.png`) é claro: laranja "SEUS MUSTS · 6 · MESMO LONGE" com distância gigante, tempo e modo, ação "IR" ou "AMANHÃ"; faixa tinta "AQUI PERTO AGORA · 0" (esperado com fake). Em Nakano (`c4-nakano-cafe.png`) a origem muda (5,5 km em vez de 2,5), então o código de origem funciona (`Must/Features/Quero/QueroModel.swift:309`: GPS só se na cidade, senão centro do bairro).
Problemas: (a) o pior caso do dono: "quero comer em Nakano". O seed só tem 3 lugares em Nakano (compras e foto: `data/seed-jp.json` j15, j26, j27, nenhum de comida), então a faixa laranja vem vazia/longe e *tudo* depende da faixa tinta (Google). Com a cota de 1.000 chamadas/mês, ela some por `ApiBudget`/offline e o viajante vê vazio. (b) "HARBS (Lumine Est Shinjuku) · Doces · 100 m" aparece na capa como o item mais próximo, mas "café" não o devolve (café 2,5 km). Doce não é café; faz sentido, mas ele estava a 100 m e o café a 14 min de trem. (c) 4 de 6 cafés dizem "não dá hoje" sem motivo legível (fecha às? longe demais?). (d) A foto do bloco é sempre a de Shinjuku mesmo em "QUERO · NAKANO" (reutiliza a foto em cache). (e) o ponto: "Nakano" no `c4-nakano-capa.png` mostra "agora: Shinjuku Gyoen", ou seja, a capa em Nakano ainda empurra o plano de Shinjuku e nenhum Must de Nakano, mesmo havendo 3.

### 5. Ida pra Kyoto: trem, mala, templos, fechamento — nota 2/5
`c5-kyoto-capa.png`: "Gion", % Arabica a 730 m (bom), "DIA 8 DE 14". Não há nada sobre o *deslocamento* Tóquio → Kyoto: Shinkansen (reserva existe como item em `Must/Features/Trip/ProximosDemo.swift:18`, "carro 7 · 12A-12B · lado direito: Fuji", ótimo), mas o dia de troca de cidade não vira um dia (mala, takkyubin, check-out 10h, check-in 15h, "ande com 1 mala"). Não achei nada sobre "mandar mala pro hotel" nem sobre fechamento de templos (a maioria fecha 16:30–17:00: regra crítica; o solver tem janelas e `saveForEnd`, mas sem horário real, 2/105 com `hours`, não há fechamento de verdade). Solver sem "Kyoto" no código (`grep` em `Must/Solver` não acha), só pelas `Area` curadas; funciona por bairro.

### 6. Sem internet no metrô / pouca bateria — nota 4/5
Melhor ponto do app: "OFFLINE OK" na Agora, Bolso "TUDO FUNCIONA OFFLINE", `c4-cafe-offline.png` mostra a faixa laranja inteira sem rede, mapas offline por cidade, último trem 23:58, frases com áudio. Faltou: modo "bateria baixa" (diminuir zoom lento, GPS, widgets) e um jeito de ver "o que está baixado" na capa; o chip "sem internet" quase não aparece fora da Agora.

### 7. Presentes pros amigos — nota 2/5 (feature ainda não existe; prompt 31 item 7)
Existe **Compras** (`c8-compras.png`): previsto ¥158.100, cota do Brasil US$1.035 de US$1.000 (alerta!), tax-free a receber ¥2.545, categorias. É bom pro *eu* comprador. Falta: **pra quem** (cada amigo), checklist por pessoa, "passe na Don Quijote quando estiver perto" no dia, foto do item vindo do Instagram. Quem viaja com amigos compra pros amigos mais do que pra si; Compras é de uso individual.

### 8. Último dia: fica pro fim, tax-free, voo de volta — nota 2/5
`c8-ultimo-capa.png` (dia 13 de 14): capa igual a qualquer dia ("nada marcado · 12 Musts a 15 min", HARBS). Nada diz "último dia inteiro: sobrou isto do fica-pro-fim, malas, tax-free (passaporte!), saia pro aeroporto às X". A regra `saveForEnd` existe no solver (`Must/Solver/DaySolver.swift:219-223`) mas o viajante só a vê dentro do "Montar". Bolso tem "TAX-FREE ¥5.000" (`c2-bolso.png`), útil. O voo de volta e a cota de bagagem não aparecem juntos.

### 9. Sábado em BH (Savassi) sem viagem — nota 3/5
`c9-bh-capa.png`: verde, "Savassi", "Dona Lucinha · Mineiro · 780 m", show MPB às 20:00 em cartaz. Funciona como "tem algo bom perto" e é a melhor prova de uso diário. Mas o numeral laranja diz "4" e o texto "10 Musts a 15 min": dois números pra mesma coisa. Em BH eu já tenho Google Maps "Salvos" e 4 Musts de comida não substituem. Usaria uma vez por semana, não todo dia.

## Os 10 problemas mais graves
1. **Telas contradizem o relógio.** 14:20: Linha "Ramen 11:30 AGORA", capa "deveria estar desde 12:45", Agora "saia 15:46", Guia "Manhã 11:30". Prints `c3-linha.png`, `c3-capa.png`, `c3-agora.png`, `c3-guia.png`. Mata a confiança no dia.
2. **O dia não se refaz sozinho** quando o viajante atrasa ou a chuva muda; vira culpa ("deveria estar"). Ver mesmos prints. Ação "Outra" é manual.
3. **Dado de lugar quase todo chute:** 104/105 `approx`, 2/105 com horário (`data/seed-jp.json`). "Aberto agora" e "não dá hoje" parecem certos e não são; sem a 1ª sincronização com chave Google, o produto inteiro é decoração. Nenhuma tela mostra "dados ainda não confirmados".
4. **Dois números diferentes pra mesma coisa na capa:** "12 Musts a 15 min" × numeral laranja "2" (`c2-capa-dia1.png`, `c3-capa.png`: 2 × 3, `c9-bh-capa.png`: 10 × 4). Confunde a promessa central.
5. **Quero vazio/fraco onde importa:** Nakano sem comida no seed; a faixa tinta depende de Google com cota e fica "0" (`c4-nakano-cafe.png`); 4 de 6 "não dá hoje" sem motivo; foto de Shinjuku em "QUERO · NAKANO".
6. **Capa em outro bairro puxa o plano do bairro errado:** em Nakano mostra "agora: Shinjuku Gyoen · saia 16:29" (`c4-nakano-capa.png`), e nenhum Must de Nakano.
7. **Nenhuma capa pro dia de chegada, dia de trem nem último dia** (`c2-capa-dia1.png`, `c5-kyoto-capa.png`, `c8-ultimo-capa.png`): são os 3 dias mais estressantes e o app trata como um dia qualquer.
8. **Hotel e reserva de jantar não aparecem como âncoras visíveis** (nenhum cadastro de hotel encontrado; a reserva das 19:00 não está na capa/Agora). Âncora é a promessa do solver.
9. **Hero vermelho enorme e vazio quando não há foto** (`c2-capa-dia1.png`, `c4-quero`, `c1-board.png`): metade da tela sem informação; 12 telas com o mesmo bloco. Brutalista, mas cansa e esconde conteúdo.
10. **Grupo não existe**: "viajo com amigos" não tem votação, divisão de gasto nem "mandar o dia" visível; Presentes e Quero são só do dono. (Cartaz/PDF existem no prompt 25, mas não aparecem no fluxo principal.)

Outros menores: Bom Dia às 15:30 diz "acordou" (`c2-bomdia.png`); fotos do Guia são quadrados cinza; ingresso importa em 3 passos mesmo com tudo certo; o `+` abre Quero e o botão ✦ abre Dicas/Assistente sem ícone que explique.

## Usaria todo dia vs. nunca abriria
Todo dia: capa "agora" com o índice duro (distância + motivo); Quero ("café", "comer já"); Agora com "Ir"; Bolso (câmbio, último trem, banheiro, frases); ingressos/Carteira no portão; Compras com cota do Brasil.
Uma ou duas vezes: Guia do bairro, Reservas, voos/checklist, Bom dia/Boa noite.
Nunca: Colecionáveis, 3D do lugar, Filmes, Bairros como tela de gestão, Mapa offline fora a hora de baixar, Ajustes › Dados, Em cartaz (só como bônus na capa).

## Google Maps faz melhor × só o Must faz
Google faz melhor: rota/transporte em tempo real (plataforma, linha, atraso), horário e fechamento reais, fila/popularidade, fotos e avaliações recentes, busca de qualquer lugar, compartilhar lista com amigos.
Só o Must: um board *meu* com motivo ("Must eat · ¥1.000"), "o que dos meus lugares dá hoje agora" com tempo de trem, golden hour como âncora, regras locais (tax-free, cota do Brasil, último trem, coperto), tudo funcionando offline, e o formato curado ("Ramen 13 · Sushi 9 · Izakaya 1…").

## Recomendações de abordagem (o que cortar, o que dobrar)
Dobrar a aposta:
- **Confiança do dado**: chip "horário confirmado/estimado" em cada linha; sincronização obrigatória e guiada antes da viagem (uma tela "100 lugares: 94 confirmados"); nunca dizer "não dá hoje" sem motivo.
- **Plano vivo**: um único relógio de verdade (uma fonte pra capa, Linha, Agora, Guia) e replanejamento automático do resto do dia ao passar da hora ("Atrasou? Já ajustei."). Menos "você deveria".
- **Quero como produto principal**: garantir que nunca volta vazio (fontes externas em cache no Wi-Fi do hotel, por bairro, *antes* de sair; texto de por quê vazio), e usar o bairro de GPS pra capa também.
- **Dias-problema** (pouso, troca de cidade, último dia) como cartões próprios.
- **Grupo**: "mandar o dia"/votação de dois lugares e Presentes por pessoa pesam mais que o 3D.
Cortar/adiar: Colecionáveis, 3D, Filmes, Em cartaz como pilar (manter só como linha tinta eventual), três capas/estilos, número de telas de Ajustes. Consolidar Dicas + Assistente + ✦ em um lugar com nome claro.

## Correções pequenas
- Unificar o numeral laranja com o texto "N Musts a 15 min" (`Must/Features/Home/Corte/CorteIndex.swift`), ou tirar um dos dois.
- Bom Dia: não dizer "acordou" depois do meio-dia; trocar para "Boa tarde".
- Foto do bloco de resultado do Quero acompanha o bairro buscado.
- Motivo em "não dá hoje" ("fecha 15h", "a 26 min e fecha 17h").
- Quando o dia está atrasado, mostrar "faltam N paradas" em vez de "deveria estar".
- Hero sem foto: usar o espaço pra mostrar a próxima ação (ex.: "saia às 15:46").
- Voo: mostrar chegada e terminal de pouso; "saia às" só se a data é hoje.
- Placeholder cinza do Guia: usar cor da lista/ícone em vez de quadrado escuro.
- Aviso de "approx: true" visível no Lugar e em "Ir" (coordenada chute).
