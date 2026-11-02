# Rodada 14–16 · central da viagem

Prompts 01–13 estão feitos (último: `36edef1`). Esta rodada implementa as telas novas do design v5:
board completo, por perto, experiências e ingresso (prompt 14) e o fluxo de importar ingresso, carteira e voos (prompt 15).
Leia `CLAUDE.md` (decisões "Central da viagem", "Experiências", "Por perto") e os dois prompts inteiros antes de começar.
Telas: `design/screens/` — AdicionarMapa (prompt 16), Board, Descobrir, Experiencias, Ingresso, TicketEntrada, TicketScan, TicketRevisar, Carteira, Voos, e as atualizadas Musts (botão "Ver tudo · editar") e Viagem (botão de calendário → Voos/Reservas).

## Antes de começar
1. Commit dos arquivos de design e prompts que estão sem commit (`design/`, `prompts/`, `CLAUDE.md`, `Secrets.example.plist`, `.gitignore`) num commit só: "Design e prompts da rodada 14–15".
2. **Decisão de 02/11: por enquanto a única API externa nova é a AeroDataBox** (`AERODATABOX_KEY` no `Secrets.plist`). **Não** implemente clientes de Viator, GetYourGuide nem aviationstack nesta rodada: experiências entram só por **colar link** (Viator, Klook, Airbnb, GetYourGuide, e-plus, Peatix, Sympla) e à mão; status de voo é AeroDataBox → senão só o horário programado. Deixe o protocolo `ExperienceSource` pronto pra plugar uma API depois.
3. `xcodegen generate` depois de qualquer mudança no `project.yml` (o Share Extension da fatia 3 é um target novo).

## Fatias — nesta ordem, um commit (ou mais) por fatia
Cada fatia termina com build verde, testes verdes e prints das telas dela via `scripts/qa-screens.sh` comparados com os PNGs. Se algo do prompt conflitar com o código que já existe, o código existente ganha; anote a diferença no commit.

| # | Fatia | Prompt | Por quê nesta ordem |
|---|---|---|---|
| 0 | **Correção do Adicionar por link + preview com mapa**: lista sem empilhar, stopwords (meses etc.), categoria por lugar e não pela legenda, merge por `placeId`/distância, tudo conferido no Places, mapa papel em relevo com pinos numerados | 16 | Bug que já aparece no iPhone; pequeno e isolado. Fazer primeiro. |
| 1 | **Board completo**: `BoardView`, modo edição, seleção, arrastar entre listas, ações em lote, swipe; botão "Ver tudo · editar" no hub; editar lista | 14 · A | Independente, só modelo local. Aquece no código atual. |
| 2 | **Modelo de experiência e ingresso**: `ListKind.experience` (Must do, cor night), `ExperienceInfo`, `Session`, `Ticket`; ingresso como âncora no solver; tela **Ingresso** com ingresso criado à mão, QR via CoreImage, PDF, "Mostrar QR grande"; Reservas mostra ingressos | 14 · C (itens 8, 11, 12) | Fundação do 15. Tudo depois usa `Ticket`. |
| 3 | **Importar ingresso**: target `MustShare` (Share Extension, App Group), `must://import?id=`, `TicketEntrada` / `TicketScan` (VisionKit `DataScannerViewController`) / `TicketRevisar`; `TicketReader` (PDFKit, Vision, `.pkpass`, URL) + extrator `ExtractedTicket` com confiança por campo + combinação com o board | 15 · A | Depende da fatia 2. É o fluxo mais usado. |
| 4 | **Experiências e Por perto**: `Services/Experiences` só com **colar link** (+ protocolo `ExperienceSource` pra API futura), tela Experiências com o card de colar link no topo, a lista das experiências já salvas (ordenadas por data, com aviso de conflito) e a busca filtrando as salvas; `NearbyService` (board + Google Nearby + Wikipedia + Foursquare), tela Descobrir e a linha "Por perto:" na Home | 14 · C (9, 10) e B | Depende da 2 (adicionar experiência) e reaproveita o extrator da 3. |
| 5 | **Carteira**: `WalletItem`, tela Carteira, saldo anotado com aviso, "Abrir no Wallet" (`shoebox://`), documentos protegidos (`FileProtectionType.complete`); entrada pelo fluxo da fatia 3 (`.pkpass` de trem → railPass) | 15 · B | Pequena; depende da 3 pra importar. |
| 6 | **Voos e checklist**: `Flight` com pernas, importação pelo fluxo da 3 (`kind: .flight`), `FlightStatusService` (AeroDataBox → senão só programado), checklists em `Must/Data/checklists/intl-japan.json` e `domestic-br.json`, itens automáticos pela Carteira, lembretes locais, tela Voos e aba Voos/Reservas na Viagem, voo como âncora no solver | 15 · C | Depende da 3 e da 5. |
| 7 | **QA da rodada**: `scripts/qa-screens.sh` com as 9 telas novas (BH e JP), `QA.md` com os cenários dos dois blocos "Verificar", README com as chaves novas | 14 + 15 | Fecha a rodada. |
| 8 | **Google Maps Platform + Compras**: `ApiBudget`, Places IDs Only/Details/Photos/Autocomplete, Routes transit (Como chegar) e Route Matrix no solver, Street View da porta; Buscar por nome; Compras (vitrine por categoria, previsão, cota) e Regras da volta | 17 | Depois do QA da rodada. Usa a `GOOGLE_PLACES_KEY` que já existe. |

## Testes mínimos (além dos que os prompts pedem)
- `TicketReaderTests` com fixtures em `MustTests/Fixtures/`: um PDF gerado no próprio teste com PDFKit (texto + QR desenhado via CoreImage), um `.pkpass` montado no teste (zip com `pass.json`, sem assinatura — só a leitura importa) e um texto de e-mail LATAM com PNR e duas pernas.
- `TicketMatcherTests`: "Sushi Making Class with a Chef in Tsukiji" casa com "Aula de sushi com chef em Tsukiji" pelo endereço/placeId, não pelo nome.
- `SolverTests`: ingresso às 10:00 é âncora; experiência às 19:00 conflita com reserva às 19:00 e o solver avisa; dia de voo vira `rest` até partida − 4 h.
- `ChecklistTests`: item "Visit Japan Web" marca sozinho quando há `WalletItem.entryQR`.

## Fora do escopo desta rodada
- Comprar experiência dentro do app (é sempre por link do fornecedor).
- Ler saldo da Suica ou abrir um passe específico no Wallet (não há API pública).
- TripAdvisor Content API e Gemini pra vídeo (continuam TODO com flag).

## Ao terminar
Mensagem final com: commits por fatia, o que ficou diferente do design e por quê, e as chaves que faltam no `Secrets.plist` pra ligar cada fonte.
