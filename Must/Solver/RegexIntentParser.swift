import Foundation

/// "ou diga: templo cedo, ramen, café e andar pouco" → `DayIntent`, por palavras-chave.
/// Fallback do `IntentParser` com Foundation Models (prompt 08).
enum RegexIntentParser {
    static func parse(_ raw: String, placeNames: [String] = []) -> DayIntent {
        let text = " " + raw.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR")) + " "
        var intent = DayIntent()
        func has(_ words: String...) -> Bool { words.contains { text.contains($0) } }

        // Tipo de dia
        if has("compras", "comprar", "shopping") && !has("sem compras", "nada de compras") { intent.kind = .shopping }
        if has(" noite", "balada", "night") && !has("sem noite") { intent.kind = .night }
        if has("foto", "fotograf") { intent.kind = .photo }
        if has("templo", "santuario", "shrine") { intent.kind = .temples }
        if has("descans", "cansad", "dia leve", "devagar", "preguica") { intent.kind = .rest }
        if has("dia livre") { intent.kind = .free }

        // Começo
        if has("cedo", "madrug") { intent.startEarly = true }
        if has("tarde demais", "acordar tarde", "sem pressa", "comecar tarde") { intent.startEarly = false }

        // Andar
        if has("andar pouco", "pouco a pe", "sem andar", "nao quero andar", "andar menos", "cansad") { intent.walk = .low }
        if has("andar muito", "andar bastante", "caminhar muito", "bater perna") { intent.walk = .high }

        // Papéis
        let roleWords: [(StopRole, [String])] = [
            (.eat, ["comer", "comida", "almoco", "jantar", "ramen", "sushi", "mineir", "restaurante"]),
            (.drink, ["cafe", "coffee", "kissa", " bar ", "drink", "cerveja", "coquetel", "sake"]),
            (.see, ["museu", "arte", "templo", "mirante", "exposic", "galeria", "igreja"]),
            (.listen, ["musica", "jazz", "show", "listening", "ao vivo", "vinil"]),
            (.shop, ["compra", "loja", "feira", "camera", "disco"]),
            (.photo, ["fotografar", "spot de foto", "golden", "por do sol"]),
            (.sport, ["correr", "corrida", "pedalar", "trilha", "treino", "nadar"]),
        ]
        for (role, words) in roleWords {
            for word in words {
                if text.contains("sem \(word.trimmingCharacters(in: .whitespaces))") || text.contains("nada de \(word.trimmingCharacters(in: .whitespaces))") {
                    intent.roles[role] = .off
                } else if text.contains(word), intent.roles[role] == nil {
                    intent.roles[role] = .on
                }
            }
        }

        // Sub-listas
        let subs: [(String, [String])] = [
            ("Ramen", ["ramen", "tsukemen"]), ("Sushi", ["sushi", "omakase"]), ("Café", ["cafe", "coffee", "kissa"]),
            ("Bar", [" bar ", "drink", "coquetel"]), ("Templos", ["templo", "santuario"]), ("Arte", ["museu", "arte", "galeria"]),
            ("Mirante", ["mirante", "por do sol", "vista"]), ("Mineiro", ["mineir"]), ("Mercado", ["mercado"]),
        ]
        intent.preferSubs = subs.filter { _, words in words.contains { text.contains($0) } }.map(\.0)

        // Refeições e exceção
        if has("dois almocos", "duas refeicoes", "dois jantares", "comer duas vezes", "sushi e ramen", "ramen e sushi") {
            intent.mealsException = true
        }
        if has("jantar bom", "jantar especial", "caprich", "especial", "excecao", "splurge", "omakase", "chique") {
            intent.splurge = true
            if has("jantar", "jantinha") { intent.splurgeWindow = .dinner } else if has("almoco") { intent.splurgeWindow = .lunch }
        }

        // Orçamento: "R$ 150", "15k", "10 mil", "¥8000"
        if let m = text.firstMatch(of: /(?:r\$|¥|yen|orcamento de|ate)\s*(\d+(?:[.,]\d{3})*)\s*(k|mil)?/) {
            let n = Double(String(m.1).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")) ?? 0
            intent.budget = m.2 == nil ? n : n * 1000
        } else if let m = text.firstMatch(of: /\b(\d+)\s*(k|mil)\b/) {
            intent.budget = (Double(String(m.1)) ?? 0) * 1000
        }

        // Nomes do board
        for name in placeNames {
            let folded = name.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pt_BR"))
            let words = folded.split(separator: " ").map(String.init)
            let keys = [folded, words.prefix(2).joined(separator: " "), words.first.flatMap { $0.count >= 5 ? $0 : nil }]
                .compactMap { $0 }.filter { $0.count >= 4 }
            guard let key = keys.first(where: { text.contains($0) }) else { continue }
            if text.contains("sem \(key)") || text.contains("nao \(key)") || text.contains("menos \(key)") {
                intent.mustExclude.append(name)
            } else {
                intent.mustInclude.append(name)
            }
        }
        return intent
    }
}
