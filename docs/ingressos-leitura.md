# Leitura de ingressos no aparelho (prompt 31 · 6)

Avaliação do que o app lia antes, o que mudou e o que ainda falha. Tudo roda no aparelho: PDFKit, Vision, `NSDataDetector`,
Foundation Models. Nenhum modelo de terceiros, nenhuma API nova, nenhuma rede.

## Veredito: o OCR da Apple não era o problema

Medido no simulador com o corpus abaixo (texto em camada, PDF só imagem, foto limpa e foto torta/escura/borrada a 5°, JPEG 0,35):
a taxa de acerto **não mudou entre as quatro formas**, nem antes nem depois. O Vision leu a foto escura com a mesma qualidade
do PDF com texto. O que estava "rudimentar" era o **extrator**: ele só conhecia título, data (sem hora rotulada), código,
pessoas, preço e ponto de encontro. Local, assento, portão e titular não existiam; hora quase nunca saía; título falhava em 4 de 6 tipos.

Limite honesto: o corpus é sintético e limpo (fonte do sistema, bom contraste). Foto real de papel amassado, reflexo em tela,
fonte decorativa ou ingresso em japonês vertical vão ficar abaixo disso. Por isso a conferência mostra em laranja o que é incerto.

## Corpus

`MustTests/TicketCorpus.swift` gera tudo com CoreGraphics/PDFKit (nada baixado): 6 tipos × 4 formas = 24 arquivos.
Museu JP (teamLab), show (BH, assento/portão), Shinkansen (carro/assento/plataforma), Coliseu (turno, titular, IT), cartão de
embarque (LA 8084, portão, assento, localizador) e restaurante (reserva). Exportar os arquivos:
`TEST_RUNNER_TICKET_CORPUS_DIR=/pasta xcodebuild … -only-testing:MustTests/TicketCorpusTests test`
(`TEST_RUNNER_TICKET_REPORT_PATH` grava a tabela). Gabarito por campo em `TicketCase.Truth`; pontuação em `TicketScoring.swift`.
Mais `TicketHardCasesTests`: 7 frases de outros fornecedores (pm, "às 21h", 開演, "ore 09.30", ISO, sem ano).

## Antes × depois (acerto por campo, 24 arquivos)

| campo | antes | depois |
|---|---|---|
| título | 33% | 100% |
| data | 100% | 100% |
| hora | 0% | 100% |
| local | 0% | 100% |
| assento | 0% | 100% |
| portão | 0% | 100% |
| código de confirmação | 100% (só pelo QR) | 100% |
| QR | 100% | 100% |
| nome do titular | 0% | 100% |
| **total** | **43%** | **100%** |

Por tipo, antes → depois: museu 57 → 100, show 33 → 100, trem 43 → 100, Coliseu 38 → 100, voo 38 → 100, restaurante 57 → 100.
Por forma: as quatro iguais (43 → 100). Tempo médio ~0,75 s por arquivo no simulador.
O "antes" no código de reserva só funcionava porque o QR traz o código; sem QR a regex não conhecia "Ticket No.", "Pedido", "Codice".

## O que mudou

1. **PDF**: camada de texto primeiro; página com menos de 30 caracteres vai pro OCR rasterizada a 3×.
2. **OCR**: `RecognizeDocumentsRequest` (iOS 26, idioma automático, pt/en/ja/it, correção) e, se vier vazio, `VNRecognizeTextRequest .accurate`
   com os mesmos idiomas. Se saiu pouco texto ou nenhum QR, segunda passada na imagem realçada (auto-ajuste, cinza, contraste, 2000 px)
   e vale a que leu mais.
3. **QR/barras**: Vision, com `CIDetector` de reserva (já existia), agora também na imagem realçada.
4. **Regras** (`TicketFields.swift`): hora escolhida pelo rótulo (início/partida/turno ganham de abertura de portões/embarque/chegada;
   "21h", "ore 09.30", 開演), local, assento (carro + fila + poltrona), portão/plataforma, titular, voo sem "(GRU)" na mesma linha,
   nome do trem, "party of N", meses em italiano, título por pontuação de linha (ignora cabeçalho genérico e "rótulo: valor").
5. **`NSDataDetector`**: datas quando a regra não achou nada; endereço como local de reserva (confiança 0,6).
6. **Foundation Models**: `GeneratedTicket` ganhou local, assento, portão, titular e início. O modelo só completa o que ficou abaixo de 0,8,
   e todo valor precisa aparecer literalmente no texto (a data, o dia). Sem Apple Intelligence o resultado é o das regras
   (o simulador não tem os assets do modelo: o catálogo falha e o fallback entra; os testes usam `useModel: false`).
7. **Conferência**: linhas de índice com réguas de 2 pt, incerto em laranja ("conferir · origem"), numeral gigante = campos lidos,
   linha de resumo diz quantos estão em dúvida. Local, assento, portão e titular aparecem quando lidos e vão pra observação da sessão.

## O que ainda falha

- Tabela com rótulo numa linha e valor na outra ("Portões" / "19:00" / "Início" / "21:00"): pega a primeira hora (caso `known` em `TicketHardCasesTests`).
- QR de cartão de embarque real (BCBP, IATA): o payload é guardado, mas não decodificado em voo/assento/PNR.
- Vários passageiros ou vários ingressos no mesmo PDF viram um só.
- Sem hora no ingresso (só data): a hora fica em branco com confiança baixa; "Adult x 2" não vira número de pessoas.
- Japonês vertical, manuscrito, foto com reflexo forte, página com vários ingressos lado a lado: sem corpus, não medido.
- Preço sem rótulo fica em 0,6 (laranja); o ingresso do Japão em ienes sem símbolo ("4200") não é lido.
- O ganho do modelo no aparelho não foi medido (o simulador não tem o modelo): precisa de rodada no iPhone.

## Avaliação de modelos de terceiros (só recomendação, nada integrado)

| modelo | tamanho Core ML | o que daria | custo de integrar |
|---|---|---|---|
| Donut (extração de documento sem OCR) | ~200 MB (fp16, base) | campos direto da imagem, bom em recibo/nota; fraco em layout de ingresso e sem japonês/português afinado | conversão e decodificação autoregressiva no Core ML, treino com exemplos de ingresso: dias de trabalho, risco alto |
| Florence-2 base | ~460 MB (fp16), large ~1,5 GB | OCR + localização de região; ganho sobre o Vision é pequeno em texto limpo | tokenizer e decoder em Swift, 3 modelos encadeados, memória alta: semanas |
| PaddleOCR (det + rec, PP-OCRv4/v5) | 10 a 20 MB | melhor em japonês vertical e texto curvo/pequeno; empata em latim | conversão ONNX→Core ML, pós-processamento de caixas à mão: ~1 semana |

Ganho esperado: o gargalo medido é o extrator, não o OCR, então nenhum dos três mexe nos 43% iniciais. Só o PaddleOCR faria sentido,
e só se foto real em japonês vertical falhar no iPhone.
**Recomendação:** não trazer modelo agora. Primeiro rodar o corpus no iPhone com Apple Intelligence ligada (mede o ganho do `@Generable`
sobre as regras) e juntar 10 a 15 ingressos reais do Vinicius (JR, teamLab, Colosseo) como segundo corpus. Se o OCR da Apple falhar ali,
considerar PaddleOCR rec+det (~15 MB); Donut e Florence-2 não valem o peso.
