import Foundation

/// Categoria de uma vontade → tipos de lugar do Places (prompt 25 · A.2) e a lista onde ela é guardada.
/// `includedType` só quando há um tipo só, seguro, da Tabela A (vai no pedido com `strictTypeFiltering`); com vários tipos,
/// o pedido sai sem tipo e o filtro é local (um tipo da lista basta). Assim é sempre **uma** chamada por vontade.
struct WantCategory: Hashable, Sendable {
    /// Rótulo em pt ("relógio", "pão de queijo"): o que a tela diz em "Entendi".
    var label: String
    /// Palavras que levam a esta categoria (sem acento, minúsculas).
    var keywords: [String]
    var verb: WantVerb
    /// Tipos aceitos (filtro local). Vazio = qualquer lugar físico.
    var types: [String]
    var includedType: String? = nil
    /// Lista do board ("shop", "eat"…). `nil` = a do verbo.
    var listId: String? = nil
    /// Palavra que entra no texto da busca junto com a marca ("relógio" + "Seiko").
    var queryWord: String? = nil
    /// "loja física" / "restaurante" / "lugar pra ver": a frase do "Entendi".
    var kind: String

    // MARK: Tabela

    static let shopping = ["department_store", "shopping_mall"]

    static let all: [WantCategory] = [
        WantCategory(label: "relógio", keywords: ["relogio", "relogios", "watch"], verb: .comprar,
                     types: ["watch_store", "jewelry_store", "electronics_store"] + shopping, listId: "shop", queryWord: "relógio",
                     kind: "loja física"),
        WantCategory(label: "roupa", keywords: ["roupa", "roupas", "camiseta", "camisa", "jaqueta", "casaco", "moletom", "vestido", "calca"],
                     verb: .comprar, types: ["clothing_store"] + shopping, listId: "shop", queryWord: "roupa", kind: "loja física"),
        WantCategory(label: "tênis", keywords: ["tenis", "sapato", "sapatos", "sandalia", "chinelo"], verb: .comprar,
                     types: ["shoe_store", "clothing_store", "sporting_goods_store"] + shopping, listId: "shop", queryWord: "tênis",
                     kind: "loja física"),
        WantCategory(label: "eletrônicos", keywords: ["eletronico", "eletronicos", "fone", "camera", "lente", "iphone", "celular", "notebook"],
                     verb: .comprar, types: ["electronics_store", "cell_phone_store", "camera_store"] + shopping, listId: "shop",
                     queryWord: "loja", kind: "loja física"),
        WantCategory(label: "games", keywords: ["game", "games", "videogame", "brinquedo", "brinquedos", "gundam", "figure", "pelucia"],
                     verb: .comprar, types: ["toy_store", "electronics_store", "store"] + shopping, listId: "shop", queryWord: "loja",
                     kind: "loja física"),
        WantCategory(label: "livro", keywords: ["livro", "livros", "livraria", "manga", "mangas", "revista", "vinil", "disco", "discos"],
                     verb: .comprar, types: ["book_store", "music_store", "store"] + shopping, listId: "shop", kind: "loja física"),
        WantCategory(label: "cachaça", keywords: ["cachaca", "cachacas", "pinga", "vinho", "vinhos", "sake", "whisky", "uisque", "licor"],
                     verb: .comprar, types: ["liquor_store", "grocery_store", "supermarket", "market", "food_store", "store"],
                     listId: "shop", kind: "loja física"),
        WantCategory(label: "doces", keywords: ["queijo", "queijos", "doce de leite", "goiabada", "chocolate", "kit kat", "doces", "wagashi",
                                                "biscoito", "biscoitos", "cafe em grao"],
                     verb: .comprar, types: ["grocery_store", "market", "food_store", "confectionery", "candy_store", "supermarket",
                                             "dessert_shop"] + shopping, listId: "shop", kind: "loja física"),
        WantCategory(label: "pão de queijo", keywords: ["pao de queijo", "coxinha", "pastel", "salgado", "salgados", "biscoito de polvilho"],
                     verb: .comer, types: ["bakery", "cafe", "coffee_shop", "snack_bar", "brazilian_restaurant", "restaurant",
                                           "confectionery", "food_store"], listId: "eat", kind: "padaria ou lanchonete"),
        WantCategory(label: "doce", keywords: ["gelato", "sorvete", "taiyaki", "mochi", "crepe", "bolo", "torta", "parfait"],
                     verb: .comer, types: ["ice_cream_shop", "dessert_shop", "confectionery", "bakery", "cafe"], listId: "eat",
                     kind: "doceria"),
        WantCategory(label: "café", keywords: ["cafe", "cafezinho", "coffee", "espresso", "expresso", "capuccino", "cappuccino", "matcha"],
                     verb: .beber, types: ["cafe", "coffee_shop", "bakery", "tea_house"], listId: "drink", kind: "café"),
        WantCategory(label: "bar", keywords: ["cerveja", "chopp", "chope", "drink", "drinks", "coquetel", "cocktail", "bar", "highball",
                                              "gin", "caipirinha"],
                     verb: .beber, types: ["bar", "pub", "wine_bar", "night_club", "brewery", "cocktail_bar", "izakaya_restaurant"],
                     listId: "drink", kind: "bar"),
        WantCategory(label: "templo", keywords: ["templo", "templos", "santuario", "igreja", "shrine", "temple", "basilica"], verb: .ver,
                     types: ["place_of_worship", "buddhist_temple", "hindu_temple", "shinto_shrine", "church", "tourist_attraction",
                             "historical_landmark"], listId: "see", kind: "lugar pra ver"),
        WantCategory(label: "museu", keywords: ["museu", "museus", "museum", "exposicao", "galeria", "arte"], verb: .ver,
                     types: ["museum", "art_gallery", "cultural_center"], listId: "art", kind: "museu"),
        WantCategory(label: "vista", keywords: ["fuji", "monte", "mirante", "vista", "por do sol", "skyline", "observatorio", "serra"],
                     verb: .ver, types: ["observation_deck", "tourist_attraction", "park", "hiking_area", "national_park", "scenic_spot",
                                         "historical_landmark"], listId: "see", kind: "lugar pra ver"),
        WantCategory(label: "onsen", keywords: ["onsen", "sento", "spa", "banho", "massagem"], verb: .fazer,
                     types: ["spa", "public_bath", "sauna", "wellness_center"], listId: "do", kind: "lugar"),
        // Genéricos por verbo: entram quando o objeto não casa com nada acima.
        WantCategory(label: "comer", keywords: ["comer", "restaurante", "almoco", "jantar", "comida"], verb: .comer, types: ["restaurant"],
                     includedType: "restaurant", listId: "eat", kind: "restaurante"),
        WantCategory(label: "beber", keywords: ["beber"], verb: .beber, types: ["bar", "pub", "wine_bar", "cafe", "coffee_shop"],
                     listId: "drink", kind: "bar ou café"),
        WantCategory(label: "ver", keywords: ["ver"], verb: .ver,
                     types: ["tourist_attraction", "museum", "park", "observation_deck", "historical_landmark", "art_gallery"],
                     listId: "see", kind: "lugar pra ver"),
    ]

    /// Comida que pede restaurante (tipo único, vai no pedido com `strictTypeFiltering`).
    static let dishes = ["tonkatsu", "ramen", "sushi", "yakitori", "tempura", "okonomiyaki", "udon", "soba", "wagyu", "yakiniku",
                         "katsu", "gyoza", "curry", "unagi", "kaiseki", "izakaya", "feijoada", "feijao tropeiro", "tropeiro",
                         "frango com quiabo", "torresmo", "pizza", "carbonara", "cacio e pepe", "amatriciana", "supli",
                         "carciofi", "massa", "hamburguer", "churrasco", "picanha", "moqueca", "tutu"]

    /// Como se fala em pt-BR → o prato da tabela ("lámen" é o ramen; o Places e o board usam os dois nomes).
    static let dishAliases: [String: String] = ["lamen": "ramen", "lamens": "ramen", "tsukemen": "ramen", "sushis": "sushi",
                                                "hamburger": "hamburguer", "burger": "hamburguer"]

    static func dish(_ label: String) -> WantCategory {
        let key = fold(label)
        let aliases = dishAliases.filter { $0.value == key }.map(\.key).sorted()
        return WantCategory(label: label, keywords: [key] + aliases, verb: .comer, types: ["restaurant"], includedType: "restaurant",
                            listId: "eat", kind: "restaurante")
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
    }

    /// Categoria pelo texto (palavra inteira ou expressão). `nil` = nenhuma.
    static func match(_ text: String) -> WantCategory? {
        let t = " " + fold(text).replacingOccurrences(of: "-", with: " ") + " "
        func has(_ word: String) -> Bool { t.contains(" \(word) ") }
        // Expressões de mais de uma palavra primeiro ("pão de queijo" antes de "queijo").
        let ordered = all.flatMap { c in c.keywords.map { (c, $0) } }.sorted { $0.1.count > $1.1.count }
        if let dish = dishes.sorted(by: { $0.count > $1.count }).first(where: has) { return Self.dish(dish) }
        if let alias = dishAliases.keys.sorted(by: { $0.count > $1.count }).first(where: has), let dish = dishAliases[alias] {
            return Self.dish(dish)
        }
        return ordered.first { has($0.1) }?.0
    }

    /// Categoria de uma vontade: a do objeto, senão a da marca, senão a genérica do verbo.
    static func of(_ intent: WantIntent) -> WantCategory? {
        if let label = intent.category, let c = all.first(where: { $0.label == label }) { return c }
        if let label = intent.category, dishes.contains(fold(label)) { return dish(label) }
        if let c = match(intent.object) { return c }
        if let brand = intent.brand.flatMap(WantBrand.named), let c = match(brand.category) { return c }
        return all.first { $0.label == intent.verb.rawValue }
    }
}

/// Marca conhecida → categoria (só pra entender "um Seiko"; a lista de lojas de cada marca está no `brand-stores.json`).
struct WantBrand: Hashable, Sendable {
    var name: String
    var category: String
    var aliases: [String] = []

    static let all: [WantBrand] = [
        WantBrand(name: "Grand Seiko", category: "relógio"),
        WantBrand(name: "Seiko", category: "relógio"),
        WantBrand(name: "Casio", category: "relógio"),
        WantBrand(name: "G-Shock", category: "relógio", aliases: ["g shock", "gshock"]),
        WantBrand(name: "Citizen", category: "relógio"),
        WantBrand(name: "Orient", category: "relógio"),
        WantBrand(name: "Uniqlo", category: "roupa"),
        WantBrand(name: "GU", category: "roupa"),
        WantBrand(name: "Muji", category: "roupa"),
        WantBrand(name: "Onitsuka Tiger", category: "tênis", aliases: ["onitsuka"]),
        WantBrand(name: "Asics", category: "tênis"),
        WantBrand(name: "Havaianas", category: "tênis"),
        WantBrand(name: "Apple", category: "eletrônicos"),
        WantBrand(name: "Sony", category: "eletrônicos"),
        WantBrand(name: "Canon", category: "eletrônicos"),
        WantBrand(name: "Nikon", category: "eletrônicos"),
        WantBrand(name: "Fujifilm", category: "eletrônicos"),
        WantBrand(name: "Nintendo", category: "games"),
        WantBrand(name: "Pokémon", category: "games", aliases: ["pokemon"]),
        WantBrand(name: "Kit Kat", category: "doces", aliases: ["kitkat"]),
        WantBrand(name: "Bulgari", category: "relógio", aliases: ["bvlgari"]),
        WantBrand(name: "Fendi", category: "roupa"),
    ]

    static func named(_ name: String) -> WantBrand? {
        let key = WantCategory.fold(name)
        return all.first { WantCategory.fold($0.name) == key || $0.aliases.contains(key) }
    }

    /// A marca mais longa que aparece no texto como palavra ("Grand Seiko" antes de "Seiko").
    static func find(in text: String) -> WantBrand? {
        let t = " " + WantCategory.fold(text).replacingOccurrences(of: "-", with: " ") + " "
        return all.sorted { $0.name.count > $1.name.count }.first { brand in
            ([brand.name] + brand.aliases).contains { t.contains(" \(WantCategory.fold($0).replacingOccurrences(of: "-", with: " ")) ") }
        }
    }
}
