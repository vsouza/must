import Foundation

// Bolso e Dicas do Japão (`Utilidades.png`, `Dicas.png`). Valores aproximados de 2026 — conferir antes da viagem.
extension PocketRules {
    static let jp = PocketCountry(
        name: "Japão",
        speechLanguage: "ja-JP",
        fallbackBRLPerUnit: 0.036,
        exchangeUnit: 100,
        cards: [
            PocketCard(kind: .exchange, label: "Câmbio · hoje", value: "", detail: "toque pra converter", tone: .ink),
            PocketCard(kind: .transitCard, label: "Suica · anotado", value: "—", detail: "recarregar · 7-Eleven, FamilyMart, máquina da estação",
                       tone: .orange, more: [
                           "Saldo anotado à mão na Carteira (o app não lê o cartão).",
                           "Recarga só em dinheiro: konbini (7-Eleven, FamilyMart, Lawson) ou máquina amarela da estação.",
                           "Suica no Wallet do iPhone recarrega com cartão, direto no app Carteira.",
                       ]),
            PocketCard(kind: .phrases, label: "Frases", value: "Sumimasen", detail: "com licença · 20 frases, com áudio"),
            PocketCard(kind: .lastTrain, label: "Último trem", value: "00:40", detail: "Yamanote · Shinjuku → Shibuya", more: [
                "Horário da tabela do app (aproximado): confira no Google Maps antes de sair.",
                "Perdeu? Táxi pra Naka-Meguro fica em ~¥ 3.500; depois da meia-noite a bandeira sobe 20 %.",
            ]),
            PocketCard(kind: .taxFree, label: "Tax-free", value: "¥ 5.000", detail: "por loja, por dia · passaporte na mão", more: [
                "Acima de ¥ 5.000 (sem imposto) na mesma loja, no mesmo dia.",
                "Passaporte físico no caixa; o selo fica no sistema, sem papel.",
                "Consumíveis (cosmético, comida) vêm lacrados: não abrir até sair do Japão.",
            ]),
            PocketCard(kind: .nearby, label: "Perto de você", value: "Banheiro\nLixeira\nCaixa", detail: "estação · konbini · 7 Bank", more: [
                "Banheiro: toda estação e todo konbini têm, de graça e limpo.",
                "Lixeira: quase não tem na rua; guarde o lixo até um konbini ou estação.",
                "Caixa com cartão estrangeiro: 7 Bank (7-Eleven) e Japan Post. Muitos lugares ainda são só cash.",
            ]),
            PocketCard(kind: .etiquette, label: "Etiqueta", value: "Trem em\nsilêncio", detail: "sem ligação · sem comer", more: [
                "Celular no silencioso, nada de ligação no vagão.",
                "Comer andando é mal visto: pare perto da máquina ou do konbini.",
                "Fila na plataforma nas marcas do chão; escada rolante: em Tóquio, fique à esquerda.",
                "Sem gorjeta: deixar dinheiro na mesa confunde.",
            ]),
            PocketCard(kind: .lockers, label: "Armário · locker", value: "¥ 400–700", detail: "Shinjuku saída sul · moedas ou Suica", more: [
                "Pequeno ¥ 400, médio ¥ 500–600, grande ¥ 700 por dia.",
                "Estações grandes enchem cedo: tente antes das 10h ou use o app ecbo cloak.",
            ]),
        ],
        phrases: [
            PocketPhrase(latin: "Sumimasen", meaning: "com licença / desculpa", speech: "すみません"),
            PocketPhrase(latin: "Arigatō gozaimasu", meaning: "muito obrigado", speech: "ありがとうございます"),
            PocketPhrase(latin: "Kore o kudasai", meaning: "este, por favor", speech: "これをください"),
            PocketPhrase(latin: "Okaikei onegaishimasu", meaning: "a conta, por favor", speech: "お会計お願いします"),
            PocketPhrase(latin: "Kādo wa tsukaemasu ka?", meaning: "aceita cartão?", speech: "カードは使えますか"),
            PocketPhrase(latin: "Toire wa doko desu ka?", meaning: "onde fica o banheiro?", speech: "トイレはどこですか"),
            PocketPhrase(latin: "Futari desu", meaning: "somos dois", speech: "二人です"),
            PocketPhrase(latin: "Menyū o kudasai", meaning: "o cardápio, por favor", speech: "メニューをください"),
            PocketPhrase(latin: "Eigo no menyū wa arimasu ka?", meaning: "tem cardápio em inglês?", speech: "英語のメニューはありますか"),
            PocketPhrase(latin: "Oishii!", meaning: "delicioso!", speech: "おいしい"),
            PocketPhrase(latin: "Mizu o kudasai", meaning: "água, por favor", speech: "水をください"),
            PocketPhrase(latin: "Ikura desu ka?", meaning: "quanto custa?", speech: "いくらですか"),
            PocketPhrase(latin: "Menzei dekimasu ka?", meaning: "dá pra fazer tax-free?", speech: "免税できますか"),
            PocketPhrase(latin: "Fukuro wa iranai desu", meaning: "não preciso de sacola", speech: "袋はいらないです"),
            PocketPhrase(latin: "Eki wa doko desu ka?", meaning: "onde fica a estação?", speech: "駅はどこですか"),
            PocketPhrase(latin: "Kono basho ni ikitai desu", meaning: "quero ir pra este lugar", speech: "この場所に行きたいです"),
            PocketPhrase(latin: "Shashin o totte mo ii desu ka?", meaning: "posso tirar foto?", speech: "写真を撮ってもいいですか"),
            PocketPhrase(latin: "Yoyaku shite imasu", meaning: "tenho reserva", speech: "予約しています"),
            PocketPhrase(latin: "Wakarimasen", meaning: "não entendo", speech: "わかりません"),
            PocketPhrase(latin: "Daijōbu desu", meaning: "tudo bem / não precisa", speech: "大丈夫です"),
        ],
        tips: [
            CountryTip(id: "jp-lixo", moment: .anytime, title: "Não tem lixeira na rua: guarde o lixo até um konbini",
                       detail: "Konbini e estações têm lixeiras separadas. Beber andando é mal visto; pare perto da máquina.", etiquette: true),
            CountryTip(id: "jp-cafe", moment: .morning, title: "Café da manhã no konbini sai por ¥ 500",
                       detail: "Onigiri, ovo cozido e café na máquina do balcão. Kissaten abrem às 8h com o \"morning set\"."),
            CountryTip(id: "jp-fila", moment: .beforeQueue, title: "Antes de fila longa: água e banheiro no konbini",
                       detail: "Fila de ramen não guarda lugar; quem sai, volta pro fim. Ticket na máquina antes de entrar."),
            CountryTip(id: "jp-tarde", moment: .afternoon, title: "Depachika das 17h em diante: descontos de 20–50 %",
                       detail: "O subsolo das lojas de departamento cola etiqueta de desconto antes de fechar."),
            CountryTip(id: "jp-noite", moment: .night, title: "Izakaya cobra otōshi: o petisco de entrada é o cover",
                       detail: "¥ 300–600 por pessoa, vem sem pedir. Muitos bares pequenos são só cash.", etiquette: true),
            CountryTip(id: "jp-volta", moment: .back, title: "O último trem sai antes da meia-noite em muitas linhas",
                       detail: "Confira o horário da volta antes do segundo drink. Táxi de madrugada custa 20 % a mais."),
            CountryTip(id: "jp-gorjeta", moment: .anytime, title: "Sem gorjeta, em lugar nenhum",
                       detail: "Pague no caixa da frente, não na mesa. Dinheiro vai na bandejinha, não na mão.", etiquette: true),
            CountryTip(id: "jp-escada", moment: .anytime, title: "Escada rolante: em Tóquio, fique à esquerda",
                       detail: "Em Kyoto e Osaka é à direita. Na plataforma, fila nas marcas do chão.", etiquette: true),
        ]
    )
}
