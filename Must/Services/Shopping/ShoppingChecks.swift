import Foundation

// Checagem ao salvar um item (prompt 17 · B, item 9). Função pura: nome e ingredientes → marcas; nome e notas → volume.
// Sinal, não diagnóstico: o que for dúvida vira "declare" na regra. Só comida passa pela checagem de comida;
// álcool é checado em qualquer categoria (um saquê de presente também conta).
enum ShoppingChecks {
    static let porkTokens: Set<String> = [
        "tonkotsu", "butadon", "chashu", "bacon", "presunto", "pork", "porco", "porcos", "suíno", "suino", "ham", "lardo",
        "banha", "pancetta",
    ]
    static let porkPhrases = ["豚", "ポーク"]
    static let rawMilkPhrases = ["leite cru", "queijo cru", "raw milk", "não pasteurizado", "nao pasteurizado", "unpasteurized", "生乳", "生チーズ"]
    static let fruitTokens: Set<String> = [
        "fruta", "frutas", "fruit", "fruits", "semente", "sementes", "seed", "seeds", "muda", "mudas", "planta", "plantas",
        "mikan", "ichigo", "morango", "uva", "apple", "maçã",
    ]
    static let fruitPhrases = ["果物", "果実", "種子"]
    static let alcoholTokens: Set<String> = [
        "sake", "saquê", "whisky", "whiskey", "uísque", "umeshu", "shochu", "cerveja", "beer", "vinho", "wine", "vodka", "gin",
    ]
    static let alcoholPhrases = ["日本酒", "梅酒", "焼酎", "ビール", "ワイン"]

    /// Marcas do item. `food` = categoria comida: aí entram suíno, leite cru e fruta; álcool entra sempre.
    static func flags(name: String, ingredients: String, food: Bool) -> [RuleFlag] {
        let text = name + " " + ingredients
        var out: [RuleFlag] = []
        if food {
            if hasPork(text) { out.append(.pork) }
            if hasRawMilk(text) { out.append(.rawMilk) }
            if hasFruit(text) { out.append(.fruitOrSeed) }
        }
        if isAlcohol(text) { out.append(.alcohol) }
        return out
    }

    static func hasPork(_ text: String) -> Bool { matches(text, tokens: porkTokens, phrases: porkPhrases) }
    static func hasFruit(_ text: String) -> Bool { matches(text, tokens: fruitTokens, phrases: fruitPhrases) }
    static func isAlcohol(_ text: String) -> Bool { matches(text, tokens: alcoholTokens, phrases: alcoholPhrases) }

    static func hasRawMilk(_ text: String) -> Bool {
        let lowered = normalizedSpaces(text.lowercased())
        return rawMilkPhrases.contains { lowered.contains($0) }
    }

    /// Volume da bebida em litros ("720 ml" → 0,72 · "1,8 L" → 1,8 · "1.8l" → 1,8 · "2 lojas" → nil).
    static func volumeLitres(in text: String) -> Double? {
        guard let m = text.lowercased().firstMatch(of: /(\d+(?:[.,]\d+)?)\s*(ml|cl|l)(?!\p{L})/),
              let value = Double(String(m.1).replacingOccurrences(of: ",", with: ".")) else { return nil }
        switch String(m.2) {
        case "ml": return value / 1_000
        case "cl": return value / 100
        default: return value
        }
    }

    /// Chave de "item igual" (sem acento, caixa e espaços): "KitKat matcha" = "kitkat  Matcha".
    static func identityKey(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Um termo casa se for uma palavra do texto (sem pegar "hamburger" por "ham") ou se aparecer como trecho (kana, kanji).
    private static func matches(_ text: String, tokens: Set<String>, phrases: [String]) -> Bool {
        let lowered = text.lowercased()
        if phrases.contains(where: { lowered.contains($0) }) { return true }
        let words = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return words.contains { tokens.contains($0) }
    }

    private static func normalizedSpaces(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
