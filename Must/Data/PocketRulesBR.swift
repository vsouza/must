import Foundation

// Bolso e Dicas de BH: o equivalente sensato do Japão pra quem já fala a língua — cartão de ônibus, último metrô,
// gorjeta de 10 %, segurança, cafés e botecos. Valores aproximados de 2026.
extension PocketRules {
    static let br = PocketCountry(
        name: "Brasil",
        speechLanguage: "pt-BR",
        fallbackBRLPerUnit: 5.5,
        exchangeUnit: 1,
        cards: [
            PocketCard(kind: .exchange, label: "Câmbio · hoje", value: "", detail: "dólar de referência · toque pra converter", tone: .ink),
            PocketCard(kind: .transitCard, label: "Ônibus · anotado", value: "R$ 5,75", detail: "cartão BHBUS · recarga no app ou na banca",
                       tone: .orange, more: [
                           "Passagem do ônibus municipal: R$ 5,75 (cartão BHBUS ou Pix no validador).",
                           "Metrô (linha 1, Eldorado ↔ Vilarinho): R$ 5,50, cartão ou dinheiro na bilheteria.",
                       ]),
            PocketCard(kind: .phrases, label: "Frases", value: "Uai, sô", detail: "mineirês · 20 frases, com áudio"),
            PocketCard(kind: .lastTrain, label: "Último metrô", value: "23:00", detail: "linha 1 · Eldorado ↔ Vilarinho", more: [
                "Metrô funciona das 5h15 às 23h. Depois, aplicativo de carro.",
                "Ônibus noturno passa de hora em hora nas linhas principais.",
            ]),
            PocketCard(kind: .tipping, label: "Gorjeta", value: "10 %", detail: "já vem na conta · opcional", more: [
                "Os 10 % do garçom vêm na conta e são opcionais.",
                "Couvert artístico (música ao vivo) é cobrado à parte; pergunte antes.",
            ]),
            PocketCard(kind: .nearby, label: "Perto de você", value: "Banheiro\nFarmácia\nCaixa", detail: "shopping · drogaria 24 h · Banco 24 Horas", more: [
                "Banheiro: shoppings e padarias grandes; em boteco, peça licença.",
                "Farmácia 24 h em toda avenida grande (Drogaria Araujo).",
                "Caixa: Banco 24 Horas dentro de shopping e supermercado; Pix vale em quase tudo.",
            ]),
            PocketCard(kind: .caution, label: "Cuidado", value: "Celular\nna mão", detail: "Centro e Praça Sete · à noite, de carro", more: [
                "No Centro e na Praça Sete, celular no bolso da frente.",
                "À noite, prefira aplicativo de carro a andar entre bairros.",
            ]),
            PocketCard(kind: .riposo, label: "Domingo", value: "Feira\nHippie", detail: "Afonso Pena · 7h–14h · muita coisa fecha", more: [
                "Feira de Artes da Afonso Pena aos domingos de manhã.",
                "Muitos restaurantes fecham domingo à noite e segunda.",
            ]),
        ],
        phrases: [
            PocketPhrase(latin: "Uai, sô", meaning: "espanto, ênfase (serve pra tudo)", speech: "Uai, sô"),
            PocketPhrase(latin: "Trem", meaning: "qualquer coisa", speech: "Trem"),
            PocketPhrase(latin: "Cê tá doido", meaning: "você está louco? (espanto)", speech: "Cê tá doido"),
            PocketPhrase(latin: "Pão de queijo quentinho", meaning: "o pedido certo na padaria", speech: "Pão de queijo quentinho"),
            PocketPhrase(latin: "Me vê um pingado", meaning: "café com um pouco de leite", speech: "Me vê um pingado"),
            PocketPhrase(latin: "Uma Brahma e dois copos", meaning: "o pedido de boteco", speech: "Uma Brahma e dois copos"),
            PocketPhrase(latin: "Tira o gelo?", meaning: "a cerveja tá trincando?", speech: "Tira o gelo?"),
            PocketPhrase(latin: "Fecha a conta, por favor", meaning: "a conta", speech: "Fecha a conta, por favor"),
            PocketPhrase(latin: "Aceita Pix?", meaning: "aceita Pix?", speech: "Aceita Pix?"),
            PocketPhrase(latin: "Onde é o banheiro?", meaning: "banheiro", speech: "Onde é o banheiro?"),
            PocketPhrase(latin: "Tem mesa pra dois?", meaning: "mesa pra dois", speech: "Tem mesa pra dois?"),
            PocketPhrase(latin: "Qual é a porção da casa?", meaning: "o petisco que todo mundo pede", speech: "Qual é a porção da casa?"),
            PocketPhrase(latin: "Fígado com jiló", meaning: "o clássico do Mercado Central", speech: "Fígado com jiló"),
            PocketPhrase(latin: "Queijo canastra meia-cura", meaning: "o queijo pra levar", speech: "Queijo canastra meia-cura"),
            PocketPhrase(latin: "É longe daqui?", meaning: "é longe?", speech: "É longe daqui?"),
            PocketPhrase(latin: "Dá pra ir a pé?", meaning: "dá pra ir a pé?", speech: "Dá pra ir a pé?"),
            PocketPhrase(latin: "Até que horas abre?", meaning: "horário", speech: "Até que horas abre?"),
            PocketPhrase(latin: "Bão?", meaning: "tudo bem?", speech: "Bão?"),
            PocketPhrase(latin: "Nó!", meaning: "nossa! (espanto)", speech: "Nó!"),
            PocketPhrase(latin: "Valeu demais", meaning: "muito obrigado", speech: "Valeu demais"),
        ],
        tips: [
            CountryTip(id: "br-cafe", moment: .morning, title: "Pão de queijo sai do forno às 7h",
                       detail: "Padaria de bairro antes das 9h tem a fornada boa; café coado no balcão."),
            CountryTip(id: "br-fila", moment: .beforeQueue, title: "Mercado Central lota de sábado depois das 11h",
                       detail: "Chegue cedo, coma no balcão e deixe as compras pro fim."),
            CountryTip(id: "br-tarde", moment: .afternoon, title: "Chuva de verão vem às 16h e passa em 40 min",
                       detail: "De outubro a março, guarda-chuva na bolsa e um café pra esperar."),
            CountryTip(id: "br-noite", moment: .night, title: "Boteco: cerveja de garrafa, mesa na calçada",
                       detail: "Petisco pra dividir; os 10 % vêm na conta e são opcionais.", etiquette: true),
            CountryTip(id: "br-volta", moment: .back, title: "Metrô fecha às 23h: volte de carro de aplicativo",
                       detail: "Na Savassi e no Centro, espere o carro dentro do bar."),
            CountryTip(id: "br-pix", moment: .anytime, title: "Pix vale em quase tudo, até na feira",
                       detail: "Cartão também; dinheiro só pra flanelinha e gorjeta pequena."),
            CountryTip(id: "br-feira", moment: .anytime, title: "Domingo de manhã é a Feira Hippie na Afonso Pena",
                       detail: "Das 7h às 14h; muita coisa fecha domingo à noite e segunda."),
        ]
    )
}
