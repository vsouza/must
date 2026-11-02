Leia `CLAUDE.md` e as telas `design/screens/TicketEntrada.png`, `TicketScan.png`, `TicketRevisar.png`, `Carteira.png`, `Voos.png` (e `Viagem.png`, onde o botão de calendário agora abre Voos/Reservas). O Must vira a **central da viagem**: tudo que tem data, código ou cartão entra por um fluxo só e vira âncora, documento ou checklist. Depende do 14 (modelo `Ticket`).

## A — Fluxo de importar ingresso (3 telas)
1. **Entradas** (`TicketEntrada.png`): sheet "Trazer ingresso" com seis fontes:
   - **Compartilhar** → um **Share Extension** de verdade (`MustShare`, target novo no `project.yml`, App Group compartilhado) aceitando PDF, imagem, `.pkpass`, URL e texto; grava o item no container do grupo e abre o app em `must://import?id=` (o `must://add` continua pra links de lugares). É o caminho do Mail/Arquivos/Safari/app do fornecedor.
   - **Escanear** → `TicketScan.png`: `DataScannerViewController` (VisionKit) com `recognizedDataTypes: [.barcode(symbologies: [.qr, .aztec, .pdf417, .code128]), .text()]`, destaque verde no código e azul nos blocos de texto; ao reconhecer, card inferior "Encontrei: …" e "Conferir e salvar". Fallback sem DataScanner: `AVCaptureSession` + `VNDetectBarcodesRequest`/`VNRecognizeTextRequest`.
   - **Fotos** (`PhotosPicker`), **Colar** (pasteboard: URL ou código), **Arquivo** (`.fileImporter` PDF/.pkpass/imagem), **À mão** (form mínimo).
   - Card "lendo" com os passos (texto lido · QR · campos · combinando com o board · conferir), igual ao Adicionar por link.
2. **Leitura** (`Services/Tickets/TicketReader.swift`), tudo no aparelho:
   - PDF: `PDFKit` texto por página + rasterizar a 2× e `VNDetectBarcodesRequest`; guardar o PDF em `Application Support/tickets/<id>.pdf`.
   - Imagem: `VNRecognizeTextRequest` (pt, en, ja; `.accurate`) + barcodes.
   - `.pkpass`: unzip (é zip) → `pass.json`: `organizationName`, `description`, `relevantDate`, `locations[]`, `barcode(s).message/format`, campos `primaryFields/secondaryFields`. Sem chave nem rede.
   - URL: `og:*` + texto da página → extrator.
   - Texto → **extrator** `@Generable struct ExtractedTicket { title, supplier, confirmation, date, time, people, price, currency, venueName, meetingPoint, address, cancellation, kind: .experience/.event/.flight/.train/.other }` com **confiança por campo** (0–1); regras determinísticas antes do modelo pra data/hora/código (regex de PNR 6 chars, códigos `XX-XXXX-XXXX`, ISO/`DD MMM YYYY`, moedas).
   - **Combinar com o board**: nome normalizado + endereço vs `Place` (Jaro-Winkler ≥ 0,85 ou mesmo `placeId`); sem match → Places Text Search restrito à cidade; sem resultado → "Criar novo".
3. **Conferir** (`TicketRevisar.png`): lista de campos com o ponto de confiança (verde ≥ 0,8, âmbar abaixo) e a origem ("pelo QR", "lido do texto"); toque edita inline; anexos (PDF/QR/+.pkpass); bloco **Vincular a** com o match sugerido (percentual, "vira âncora de sáb 15"), "Outro lugar do board" (busca) e "Criar novo" (abre Editar com os campos preenchidos e o tipo certo); toggles "Vale a exceção" e "Avisar saia às + Live Activity"; "Salvar ingresso" → `Ticket` + `Session`/`Reservation` no `Place` → aparece em Reservas, Hoje e na Live Activity.
4. Voo/trem detectado (`kind: .flight/.train`) vai pra parte C em vez de virar ingresso de lugar.

## B — Carteira da viagem (`Carteira.png`)
5. Modelo `WalletItem { kind: .transitCard/.railPass/.creditCard/.esim/.entryQR/.insurance/.passport/.other, name, nameLocal?, subtitle, balance?: Money, balanceNotedAt?, validFrom?, validUntil?, attachment?: (PDF/imagem/QR payload), openURL?: URL, color }`, por região. Tela: cards empilhados com leve rotação (Suica verde, JR Pass grafite, cartão azul) e lista de documentos embaixo.
6. **Sem integração com o Wallet** além de abrir: o botão "Abrir no Wallet ↗" usa `shoebox://` (abre o app Wallet; não há deep link público pra um passe específico). Saldo da Suica é **anotado à mão** (campo rápido com data: "saldo (você anotou ontem)") com aviso quando abaixo do limite que você definir; cartão de crédito mostra o gasto da viagem somado dos `Expense` com `method == .card`. eSIM: link `App-Prefs:` não é permitido — botão abre as instruções salvas. Visit Japan Web: os dois QRs ficam como `entryQR` com imagem offline. Passaporte e seguro: só no aparelho, `FileProtectionType.complete`.
7. Entrada: "+" → tipo → campos; qualquer item pode vir do fluxo da parte A (um `.pkpass` de trem vira `railPass`; um PDF de seguro vira `insurance`).

## C — Voos e checklist (`Voos.png`)
8. Modelo `Flight { pnr, carrier, number, from, to, departs, arrives, terminal?, gate?, seat?, baggage: (checkedKg, cabinKg), status: .scheduled/.onTime/.delayed/.boarding/.departed/.landed/.cancelled, legs: [Flight] (conexões), checklist: [ChecklistItem { phase: .h72/.bags/.airport/.arrival, title, note?, done, dueAt?, auto: Bool }] }`.
9. **Importar**: PNR + voo vêm do e-mail/PDF pelo fluxo A (`kind: .flight`; extrator lê PNR, voos, horários, assento, franquia). Sem conta de companhia nem scraping.
10. **Status ao vivo** (`FlightStatusService`): **AeroDataBox** (RapidAPI, plano gratuito com cota mensal pequena) `GET /flights/number/{number}/{date}` → status, terminal, portão, atrasos; cache 30 min, consultar só de 48 h antes até o pouso, e a cada 10 min nas 3 h em volta da partida. Fallback: **aviationstack** free (100/mês). Chaves em `Secrets`; sem chave, mostra só o programado. Nada de FlightAware (pago).
11. **Checklist por fase**, gerado de modelos (`Data/checklists/intl-japan.json`, `domestic-br.json`) e editável: *72 h* (Visit Japan Web, avisar banco, check-in online com `dueAt` = partida − 48 h → lembrete local), *Malas* (câmeras e filmes na mão + "pedir inspeção manual" porque ISO 400+ não passa no CT, pesar ≤ franquia, power banks na mão), *Aeroporto* (imigração, conexão: reconferir portão, tempo de conexão), *Ao pousar* (QR imigração → QR alfândega, ativar eSIM, recarregar Suica, trocar JR Pass na data certa). Itens com `auto: true` se marcam sozinhos quando a Carteira já tem o documento (Visit Japan Web → QRs presentes). Lembretes por `UNUserNotificationCenter` só pros `dueAt`.
12. Card do próximo voo (preto, girado) com rota GRU → DOH → HND, horários, terminal, assento, franquia, "portão em N dias" e a linha de como chegar ao aeroporto a partir de casa (BH → GRU: "ônibus 14:00" é um `ChecklistItem` com nota). Viagem → calendário abre uma tela com abas **Voos / Reservas** (Reservas é a tela existente).
13. Voos entram no solver como âncoras duras: dia de voo = tipo `rest` até a partida − 4 h, e o Hoje mostra "saia pro aeroporto às" com o `RoutesService`.

## Verificar
- Compartilhar um PDF de reserva do Mail pro Must → fluxo lê QR + campos, sugere o lugar certo, salva, aparece em Reservas e na Live Activity do dia.
- Escanear a tela de outro app com QR → "Encontrei" com código e data.
- `.pkpass` de teste → campos de `pass.json` preenchidos, QR gerado igual ao do passe.
- Carteira: Suica com saldo anotado e aviso < ¥1.000; "Abrir no Wallet" abre o Wallet.
- Voo GRU→HND importado de um PDF LATAM: PNR, 2 pernas, checklist com 12 itens; marcar Visit Japan Web na Carteira marca o item sozinho; com `AERODATABOX_KEY`, status e portão atualizam.
