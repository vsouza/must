import Foundation

// Bolso e Dicas de Roma (prompt 24 §2, `BolsoIT.png`). Valores aproximados de 2026 — conferir antes da viagem.
extension PocketRules {
    static let it = PocketCountry(
        name: "Itália",
        speechLanguage: "it-IT",
        fallbackBRLPerUnit: 6.4,
        exchangeUnit: 1,
        cards: [
            PocketCard(kind: .exchange, label: "Câmbio · hoje", value: "", detail: "toque pra converter", tone: .ink),
            PocketCard(kind: .ticket, label: "Bilhete BIT", value: "€ 1,50", detail: "100 min · validar na máquina", tone: .orange, more: [
                "BIT: € 1,50, vale 100 minutos em ônibus e tram e uma entrada no metrô.",
                "Validar sempre: na maquininha amarela do ônibus/tram ou no torniquete do metrô. Sem validar, multa de € 50+.",
                "Cartão por aproximação no torniquete do metrô já vale como bilhete (tap & go).",
            ]),
            PocketCard(kind: .phrases, label: "Frases", value: "Il conto,\nper favore", detail: "a conta · 20 frases, com áudio"),
            PocketCard(kind: .lastTrain, label: "Último metrô", value: "23:30", detail: "sex e sáb até 01:30 · bus noturno N", more: [
                "Metrô (A, B, C) até 23:30; sexta e sábado até 01:30.",
                "Depois, ônibus noturno (linhas com N): passa a cada 30 min, saindo de Termini e Piazza Venezia.",
            ]),
            PocketCard(kind: .tipping, label: "Coperto e gorjeta", value: "€ 1–3\nsem gorjeta", detail: "já está na conta · \"al banco\" é mais barato",
                       more: [
                           "Coperto (pão e lugar à mesa) de € 1–3 por pessoa vem na conta. Gorjeta não se espera.",
                           "Café \"al banco\" (no balcão, em pé) custa menos que \"al tavolo\". Paga no caixa primeiro, depois pede.",
                       ]),
            PocketCard(kind: .water, label: "Água", value: "Nasoni\nde graça", detail: "2.500 fontes · tape o cano e beba do furo", more: [
                "Os nasoni (bebedouros de ferro) têm água potável e gelada, de graça.",
                "Tape a saída de baixo com o dedo: a água sobe pelo furinho de cima.",
            ]),
            PocketCard(kind: .churches, label: "Igrejas", value: "Ombro e\njoelho", detail: "cobertos · fecham 12:30–15:30", more: [
                "Ombro e joelho cobertos (leve uma echarpe). Vale pro Vaticano também.",
                "Muitas igrejas fecham no meio do dia, das 12:30 às 15:30.",
                "Pantheon: € 5, compre online pra pular a fila.",
            ]),
            PocketCard(kind: .caution, label: "Cuidado", value: "Bus 64\ne Termini", detail: "batedor de carteira · bolsa na frente", more: [
                "Bus 64 (Termini ↔ Vaticano) e a estação Termini são os lugares clássicos de batedor de carteira.",
                "Mochila na frente no ônibus lotado; celular nunca na mesa da calçada.",
            ]),
            PocketCard(kind: .riposo, label: "Riposo", value: "13–16", detail: "lojas pequenas fecham · museus abertos", more: [
                "Lojas pequenas e alguns cafés fecham das 13h às 16h. Museus e restaurantes do centro seguem abertos.",
                "Museus estatais fecham segunda (a Galleria Borghese abre, com reserva).",
            ]),
            PocketCard(kind: .booking, label: "Pantheon", value: "€ 5", detail: "online · pula a fila · 9h–19h", more: [
                "Ingresso do Pantheon: € 5, compre online no site oficial e escolha o horário.",
                "Colosseo entra pelo Foro Romano: fila menor e o mesmo bilhete.",
            ]),
        ],
        phrases: [
            PocketPhrase(latin: "Il conto, per favore", meaning: "a conta, por favor", speech: "Il conto, per favore"),
            PocketPhrase(latin: "Buongiorno", meaning: "bom dia (até umas 15h)", speech: "Buongiorno"),
            PocketPhrase(latin: "Buonasera", meaning: "boa tarde / boa noite", speech: "Buonasera"),
            PocketPhrase(latin: "Grazie mille", meaning: "muito obrigado", speech: "Grazie mille"),
            PocketPhrase(latin: "Permesso", meaning: "com licença (pra passar)", speech: "Permesso"),
            PocketPhrase(latin: "Scusi", meaning: "desculpe / com licença", speech: "Scusi"),
            PocketPhrase(latin: "Un caffè al banco", meaning: "um café no balcão", speech: "Un caffè al banco"),
            PocketPhrase(latin: "Un cappuccino e un cornetto", meaning: "o café da manhã romano", speech: "Un cappuccino e un cornetto"),
            PocketPhrase(latin: "Un tavolo per due", meaning: "mesa pra dois", speech: "Un tavolo per due"),
            PocketPhrase(latin: "Ho una prenotazione", meaning: "tenho reserva", speech: "Ho una prenotazione"),
            PocketPhrase(latin: "Acqua naturale / frizzante", meaning: "água sem / com gás", speech: "Acqua naturale, frizzante"),
            PocketPhrase(latin: "Il vino della casa", meaning: "o vinho da casa", speech: "Il vino della casa"),
            PocketPhrase(latin: "Quanto costa?", meaning: "quanto custa?", speech: "Quanto costa?"),
            PocketPhrase(latin: "Posso pagare con la carta?", meaning: "aceita cartão?", speech: "Posso pagare con la carta?"),
            PocketPhrase(latin: "Dov'è il bagno?", meaning: "onde fica o banheiro?", speech: "Dov'è il bagno?"),
            PocketPhrase(latin: "Un biglietto, per favore", meaning: "um bilhete, por favor", speech: "Un biglietto, per favore"),
            PocketPhrase(latin: "Dov'è la fermata?", meaning: "onde fica o ponto?", speech: "Dov'è la fermata?"),
            PocketPhrase(latin: "È lontano?", meaning: "é longe?", speech: "È lontano?"),
            PocketPhrase(latin: "Non capisco", meaning: "não entendo", speech: "Non capisco"),
            PocketPhrase(latin: "Buonissimo!", meaning: "delicioso!", speech: "Buonissimo"),
        ],
        tips: [
            CountryTip(id: "it-cappuccino", moment: .morning, title: "Cappuccino só até as 11h, cornetto no balcão",
                       detail: "Depois das 11h, café é espresso. \"Al banco\" custa menos: paga no caixa e pede no balcão.", etiquette: true),
            CountryTip(id: "it-colosseo", moment: .beforeQueue, title: "Colosseo: entre pelo Foro Romano",
                       detail: "O mesmo bilhete, fila bem menor. Água nos nasoni da Via dei Fori Imperiali."),
            CountryTip(id: "it-riposo", moment: .afternoon, title: "Riposo das 13h às 16h: lojas pequenas fecham",
                       detail: "Museus seguem abertos; igrejas fecham das 12:30 às 15:30. Bom horário pra museu ou descanso."),
            CountryTip(id: "it-aperitivo", moment: .night, title: "Aperitivo das 19h às 21h, jantar a partir das 20h",
                       detail: "Spritz com petisco no balcão; restaurante antes das 19:30 é de turista.", etiquette: true),
            CountryTip(id: "it-volta", moment: .back, title: "Último metrô 23:30 (sexta e sábado 01:30)",
                       detail: "Depois, ônibus noturno N de Termini e Piazza Venezia. Táxi só no ponto ou pelo app."),
            CountryTip(id: "it-coperto", moment: .anytime, title: "Coperto não é gorjeta: já está na conta",
                       detail: "€ 1–3 por pessoa pelo pão e pelo lugar. Gorjeta não se espera; arredondar é gentileza.", etiquette: true),
            CountryTip(id: "it-igrejas", moment: .anytime, title: "Igreja pede ombro e joelho cobertos",
                       detail: "Leve uma echarpe na bolsa; vale pra São Pedro e Museus Vaticanos.", etiquette: true),
            CountryTip(id: "it-bit", moment: .anytime, title: "Valide o BIT ao entrar no ônibus",
                       detail: "€ 1,50 por 100 min; sem validar é multa. No metrô, aproximar o cartão já vale."),
        ]
    )
}
