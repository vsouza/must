import Foundation

/// Um lugar achado no texto de um link.
struct ExtractedPlace: Equatable, Sendable, Identifiable {
    var name: String
    var nameLocal: String?
    var area: String?
    var category: MustColor?
    /// Sub-lista sugerida ("Ramen", "Café"…).
    var sub: String?
    /// Por que achei (frase curta pra mostrar).
    var hint: String

    var id: String { name.lowercased() }
}

/// (c) Extrai nomes de lugares de uma legenda.
/// Até o prompt 08 (Foundation Models): heurística por regex — 📍, @menções, "no/na/em/at" + Nome Próprio,
/// linhas curtas em Title Case e nomes em japonês com sufixo de loja. O usuário confere antes de salvar.
enum PlaceExtractor {
    static func extract(from caption: Caption, knownAreas: [String] = [], limit: Int = 5) -> [ExtractedPlace] {
        if let name = caption.placeName, !name.isEmpty {
            return [ExtractedPlace(name: name, nameLocal: nil, area: area(in: caption.text, known: knownAreas),
                                   category: category(in: name), sub: sub(in: name), hint: "link do Maps")]
        }
        return extract(text: caption.text, knownAreas: knownAreas, limit: limit)
    }

    static func extract(text raw: String, knownAreas: [String] = [], limit: Int = 5) -> [ExtractedPlace] {
        let text = String(raw.prefix(CaptionFetcher.maxLength))
        var found: [(name: String, hint: String)] = []

        func add(_ candidate: String, _ hint: String) {
            let name = clean(candidate)
            guard isPlausible(name) else { return }
            let key = name.lowercased()
            if found.contains(where: { $0.name.lowercased() == key }) { return }
            found.append((name, hint))
        }

        // 1. Pinos: "📍 Menya Kaijin, Shinjuku"
        for m in text.matches(of: /(?:📍|📌|🍜|🍣|☕|🍸)\s*([^\n,.|•·–—!?#]+)/) {
            add(String(m.1), "marcado com 📍 na legenda")
        }
        // 2. Menções: "@menyakaijin" → "Menyakaijin"
        for m in text.matches(of: /@([A-Za-z0-9_.]{3,30})/) {
            let handle = String(m.1)
            add(humanize(handle), "menção @\(handle)")
        }
        // 3. "no Fuunji", "at Sushi Dai", "em Kissa Sabouru"
        let connector = /(?:^|\s)(?:no|na|em|at|in|from|do|da)\s+((?:\p{Lu}[\p{L}'’&\-]+)(?:\s+(?:\p{Lu}[\p{L}'’&\-]+|de|do|da|no|of|the|&)){0,4})/
        for m in text.matches(of: connector) {
            add(String(m.1), "citado na legenda")
        }
        // 4. Linhas curtas em Title Case: "Menya Kaijin"
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.split(separator: " ").map(String.init)
            guard (1...5).contains(words.count), line.count <= 40 else { continue }
            let capitalized = words.filter { $0.first?.isUppercase == true }.count
            if capitalized == words.count || (words.count >= 3 && capitalized >= words.count - 1) {
                add(String(line), "linha da legenda")
            }
        }
        // 5. Nomes em japonês com sufixo de loja: "麺屋 海神", "寿司大"
        var locals: [String] = []
        for m in text.matches(of: /([\p{Han}\p{Hiragana}\p{Katakana}ー・\s]{2,14}(?:店|屋|亭|庵|鮨|寿司|ラーメン|喫茶|珈琲|カフェ|堂|館|寺|神社))|((?:麺屋|鮨|喫茶|珈琲)\s?[\p{Han}\p{Hiragana}\p{Katakana}ー]{1,8})/) {
            let s = String(m.0).trimmingCharacters(in: .whitespaces)
            if !locals.contains(s) { locals.append(s) }
        }

        let area = area(in: text, known: knownAreas)
        var results = found.prefix(limit).enumerated().map { index, item in
            ExtractedPlace(name: item.name, nameLocal: index < locals.count ? locals[index] : nil, area: area,
                           category: category(in: item.name + " " + text), sub: sub(in: item.name + " " + text), hint: item.hint)
        }
        if results.isEmpty, let local = locals.first {
            results = [ExtractedPlace(name: local, nameLocal: local, area: area, category: category(in: text), sub: sub(in: text),
                                      hint: "nome em japonês na legenda")]
        }
        return results
    }

    // MARK: Heurísticas

    private static let stopwords: Set<String> = [
        "tokyo", "tóquio", "japan", "japão", "japao", "kyoto", "osaka", "brasil", "brazil", "belo horizonte", "bh", "minas",
        "the", "best", "top", "melhor", "melhores", "dica", "dicas", "reel", "reels", "video", "vídeo", "link", "bio",
        "follow", "siga", "salva", "salve", "hoje", "amanhã", "ontem", "instagram", "tiktok", "youtube", "shorts",
        "eu", "você", "a gente", "aqui", "lá", "esse", "essa", "isso", "não", "sim", "obrigado", "obrigada",
        "segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo",
    ]

    private static func clean(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        out = out.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Tira hashtags e emojis no fim.
        if let hash = out.firstIndex(of: "#") { out = String(out[..<hash]).trimmingCharacters(in: .whitespaces) }
        return out
    }

    private static func isPlausible(_ name: String) -> Bool {
        guard (2...40).contains(name.count) else { return false }
        let lower = name.lowercased()
        if stopwords.contains(lower) { return false }
        if lower.hasPrefix("http") || lower.contains("www.") { return false }
        if name.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isWhitespace }) { return false }
        let words = lower.split(separator: " ")
        if words.allSatisfy({ stopwords.contains(String($0)) }) { return false }
        return true
    }

    private static func humanize(_ handle: String) -> String {
        let parts = handle.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").filter { !["tokyo", "jp", "japan", "official", "oficial", "bh"].contains($0.lowercased()) }
        return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func area(in text: String, known: [String]) -> String? {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return known.sorted { $0.count > $1.count }.first { area in
            folded.contains(area.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))
        }
    }

    private static let categories: [(MustColor, [String])] = [
        (.coffee, ["kissa", "kissaten", "喫茶", "珈琲", "coffee", "café ", "cafe ", "cafeteria", "espresso", "pour-over"]),
        (.eat, ["ramen", "ラーメン", "麺", "sushi", "寿司", "鮨", "omakase", "izakaya", "居酒屋", "tsukemen", "udon", "soba",
                "tonkatsu", "yakitori", "restaurante", "comida", "mineira", "boteco", "almoço", "jantar", "feijoada", "pão de queijo"]),
        (.drink, ["bar ", "cocktail", "coquetel", "drink", "cerveja", "beer", "sake", "wine", "vinho", "whisky", "highball"]),
        (.listen, ["listening", "vinyl", "vinil", "jazz", "record bar", "música ao vivo", "live music", "kissa jazz"]),
        (.temple, ["temple", "templo", "shrine", "santuário", "寺", "神社", "torii"]),
        (.see, ["museu", "museum", "galeria", "gallery", "exposição", "mirante", "view", "parque", "park", "igreja"]),
        (.shop, ["loja", "shop", "store", "vintage", "brechó", "feira", "market", "mercado", "camera", "câmera", "discos", "records"]),
        (.night, ["club", "boate", "balada", "karaoke", "karaokê", "dj "]),
    ]

    static func category(in text: String) -> MustColor? {
        let lower = " " + text.lowercased() + " "
        return categories.first { _, words in words.contains { lower.contains($0) } }?.0
    }

    private static let subs: [(String, [String])] = [
        ("Ramen", ["ramen", "ラーメン", "tsukemen", "麺"]), ("Sushi", ["sushi", "寿司", "鮨", "omakase"]),
        ("Café", ["café", "cafe", "coffee", "kissa", "珈琲"]), ("Bar", ["bar ", "cocktail", "coquetel", "highball"]),
        ("Mineiro", ["mineir", "feijão tropeiro", "pão de queijo"]), ("Mercado", ["mercado", "market"]),
        ("Templos", ["temple", "templo", "shrine", "寺", "神社"]), ("Arte", ["museu", "museum", "galeria", "gallery"]),
        ("Câmeras", ["camera", "câmera"]), ("Discos", ["discos", "records", "vinyl", "vinil"]),
    ]

    static func sub(in text: String) -> String? {
        let lower = " " + text.lowercased() + " "
        return subs.first { _, words in words.contains { lower.contains($0) } }?.0
    }
}
