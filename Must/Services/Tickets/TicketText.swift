import Foundation

/// Regex, datas e valores de texto de ingresso (prompt 15 · A). Tudo pura: sem modelo, sem rede, testável.
enum TicketText {
    /// Grupos de cada ocorrência (índice 0 = casamento inteiro). Grupo ausente vira "".
    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [(location: Int, groups: [String])] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : ns.substring(with: range)
            }
            return (match.range.location, groups)
        }
    }

    static func first(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String]? {
        matches(pattern, in: text, options: options).first?.groups
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Minúsculas, sem acento, espaço colapsado: pra checar se um valor aparece no texto.
    static func folded(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Um valor vale se aparece no texto (o modelo não pode inventar campo).
    static func appears(_ value: String, in text: String) -> Bool {
        let needle = folded(value)
        guard !needle.isEmpty else { return false }
        return folded(text).contains(needle)
    }

    /// Código de confirmação: 5 a 24 caracteres sem espaço, com letra maiúscula ou dígito, e pelo menos um dígito
    /// ou 6 letras (um localizador de voo ou um código "BR-7K2M-9931").
    static func looksLikeCode(_ value: String) -> Bool {
        guard (5...24).contains(value.count), !value.contains(" ") else { return false }
        let hasDigit = value.contains { $0.isNumber }
        let upper = value.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "-" }
        return upper && (hasDigit || value.count == 6)
    }
}

/// Datas em português, inglês, ISO e japonês, no fuso da região (prompt 15 · A).
enum TicketDates {
    private static let months: [String: Int] = [
        "jan": 1, "fev": 2, "feb": 2, "mar": 3, "abr": 4, "apr": 4, "mai": 5, "may": 5, "jun": 6, "jul": 7,
        "ago": 8, "aug": 8, "set": 9, "sep": 9, "out": 10, "oct": 10, "nov": 11, "dez": 12, "dec": 12,
    ]

    /// A primeira data do texto (a mais cedo na leitura), com a hora se houver.
    static func first(in text: String, region: Region) -> (date: Date, hasTime: Bool)? {
        var hits: [(location: Int, year: Int, month: Int, day: Int, hour: Int?, minute: Int?)] = []

        // 2026-11-15 10:00 · 2026-11-15T10:00
        for m in TicketText.matches(#"(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}):(\d{2}))?"#, in: text) {
            hits.append((m.location, int(m.groups[1]), int(m.groups[2]), int(m.groups[3]), optionalInt(m.groups[4]), optionalInt(m.groups[5])))
        }
        // 15/11/2026 10:00 (dia primeiro, como no Brasil e no Japão)
        for m in TicketText.matches(#"(\d{1,2})/(\d{1,2})/(\d{4})(?:[ ,·-]+(\d{1,2}):(\d{2}))?"#, in: text) {
            hits.append((m.location, int(m.groups[3]), int(m.groups[2]), int(m.groups[1]), optionalInt(m.groups[4]), optionalInt(m.groups[5])))
        }
        // 2026年11月15日 10:00
        for m in TicketText.matches(#"(\d{4})年(\d{1,2})月(\d{1,2})日(?:\D{0,8}?(\d{1,2}):(\d{2}))?"#, in: text) {
            hits.append((m.location, int(m.groups[1]), int(m.groups[2]), int(m.groups[3]), optionalInt(m.groups[4]), optionalInt(m.groups[5])))
        }
        // 15 Nov 2026 · 10:00 AM · 15 de novembro de 2026 · sáb 15 nov 2026 10h30
        let monthWord = #"(jan|fev|feb|mar|abr|apr|mai|may|jun|jul|ago|aug|set|sep|out|oct|nov|dez|dec)[a-zç]*\.?"#
        for m in TicketText.matches(#"(?i)\b(\d{1,2})\s*(?:de\s+)?"# + monthWord + #",?\s*(?:de\s+)?(\d{4})(?:[^\d\n]{0,12}?(\d{1,2}):(\d{2})\s*([ap]m)?)?"#, in: text) {
            hits.append((m.location, int(m.groups[3]), months[m.groups[2].lowercased().prefix(3).description] ?? 0, int(m.groups[1]),
                         clock(m.groups[4], m.groups[5], m.groups[6]).hour, clock(m.groups[4], m.groups[5], m.groups[6]).minute))
        }
        // Nov 15, 2026 10:00 AM
        for m in TicketText.matches(#"(?i)\b"# + monthWord + #"\s+(\d{1,2}),?\s+(\d{4})(?:[^\d\n]{0,12}?(\d{1,2}):(\d{2})\s*([ap]m)?)?"#, in: text) {
            hits.append((m.location, int(m.groups[3]), months[m.groups[1].lowercased().prefix(3).description] ?? 0, int(m.groups[2]),
                         clock(m.groups[4], m.groups[5], m.groups[6]).hour, clock(m.groups[4], m.groups[5], m.groups[6]).minute))
        }

        guard let hit = hits.filter({ $0.month >= 1 && $0.month <= 12 && $0.day >= 1 && $0.day <= 31 }).min(by: { $0.location < $1.location }) else {
            return nil
        }
        var parts = DateComponents(year: hit.year, month: hit.month, day: hit.day)
        parts.hour = hit.hour ?? 0
        parts.minute = hit.minute ?? 0
        guard let date = region.calendar.date(from: parts) else { return nil }
        return (date, hit.hour != nil)
    }

    private static func int(_ s: String) -> Int { Int(s) ?? 0 }

    private static func optionalInt(_ s: String) -> Int? { Int(s) }

    /// Hora de "10:00 AM", "23:55" ou "10:00 pm". Sem hora, nil.
    private static func clock(_ hour: String, _ minute: String, _ meridiem: String) -> (hour: Int?, minute: Int?) {
        guard let h = Int(hour), let m = Int(minute) else { return (nil, nil) }
        switch meridiem.lowercased() {
        case "am": return (h == 12 ? 0 : h, m)
        case "pm": return (h == 12 ? 12 : h + 12, m)
        default: return (h, m)
        }
    }
}

/// Valor e moeda ("¥24,000", "R$ 1.234,50", "24.000 JPY") — separador decimal pelo último ponto/vírgula.
enum TicketMoney {
    struct Amount: Equatable, Sendable {
        var value: Double
        /// ISO ("JPY", "BRL", "USD", "EUR"), ou nil se o texto não disse.
        var currency: String?
        /// Veio ao lado de "total", "pago", "preço"…
        var labelled: Bool
    }

    static func first(in text: String) -> Amount? {
        let keywords = #"(?i)(total|pago|paid|pre[çc]o|price|valor|amount|cobrado|charged)"#
        var candidates: [(amount: Amount, location: Int)] = []
        let number = #"([0-9]{1,3}(?:[.,'][0-9]{3})+(?:[.,][0-9]{1,2})?|[0-9]+(?:[.,][0-9]{1,2})?)"#
        for m in TicketText.matches(#"(R\$|US\$|¥|￥|€|\$)\s?"# + number, in: text) {
            let around = window(text, around: m.location, before: 40, after: 0)
            let labelled = TicketText.matches(keywords, in: around).isEmpty == false
            candidates.append((Amount(value: parse(m.groups[2]), currency: code(m.groups[1]), labelled: labelled), m.location))
        }
        for m in TicketText.matches(number + #"\s?(JPY|BRL|USD|EUR|円)"#, in: text) {
            let around = window(text, around: m.location, before: 40, after: 0)
            let labelled = TicketText.matches(keywords, in: around).isEmpty == false
            candidates.append((Amount(value: parse(m.groups[1]), currency: code(m.groups[2]), labelled: labelled), m.location))
        }
        return candidates.sorted { ($0.amount.labelled ? 0 : 1, $0.location) < ($1.amount.labelled ? 0 : 1, $1.location) }.first?.amount
    }

    static func code(_ symbol: String) -> String? {
        switch symbol.uppercased() {
        case "R$", "BRL": "BRL"
        case "¥", "￥", "円", "JPY": "JPY"
        case "US$", "$", "USD": "USD"
        case "€", "EUR": "EUR"
        default: nil
        }
    }

    /// "1.234,50" → 1234.5 · "24,000" → 24000 · "12,50" → 12.5 · "24.000" → 24000.
    static func parse(_ raw: String) -> Double {
        var s = raw.replacingOccurrences(of: "'", with: "")
        let lastDot = s.lastIndex(of: "."), lastComma = s.lastIndex(of: ",")
        if let dot = lastDot, let comma = lastComma {
            // Os dois: o último é o decimal.
            if dot > comma { s = s.replacingOccurrences(of: ",", with: "") } else { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        } else if let separator = lastDot ?? lastComma {
            let tail = s[s.index(after: separator)...]
            if tail.count == 3 {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")
            }
        }
        return Double(s) ?? 0
    }

    private static func window(_ text: String, around location: Int, before: Int, after: Int) -> String {
        let ns = text as NSString
        let start = max(0, location - before)
        return ns.substring(with: NSRange(location: start, length: min(location, ns.length) - start + after))
    }
}
