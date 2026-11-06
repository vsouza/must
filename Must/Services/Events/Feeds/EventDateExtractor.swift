import Foundation

/// Datas escritas no texto de um item de feed ("Saturday, November 21, 2026", "15 de novembro", "12 novembre", "15/11/2026").
/// Sem hora: o dia vale a partir das 00:00 da região. Feed que não diz a data fica sem data (não vai pra "hoje").
enum EventDateExtractor {
    private static let months: [String: Int] = {
        var table: [String: Int] = [:]
        let sets: [[String]] = [
            ["january", "jan", "janeiro", "gennaio", "janvier"], ["february", "feb", "fevereiro", "febbraio"],
            ["march", "mar", "março", "marco", "marzo"], ["april", "apr", "abril", "aprile"],
            ["may", "maio", "maggio"], ["june", "jun", "junho", "giugno"], ["july", "jul", "julho", "luglio"],
            ["august", "aug", "agosto"], ["september", "sep", "sept", "setembro", "settembre"],
            ["october", "oct", "outubro", "ottobre"], ["november", "nov", "novembro", "novembre"],
            ["december", "dec", "dezembro", "dicembre"],
        ]
        for (i, names) in sets.enumerated() { for name in names { table[name] = i + 1 } }
        return table
    }()

    /// Todas as datas citadas, em ordem, sem repetir. `reference` decide o ano quando o texto não diz.
    static func dates(in text: String, reference: Date, calendar: Calendar) -> [Date] {
        let names = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let patterns: [(String, Bool)] = [
            // "November 21, 2026" / "Nov 21"
            ("\\b(\(names))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(20\\d{2}))?\\b", true),
            // "21 November 2026" / "15 de novembro de 2026"
            ("\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:de\\s+|of\\s+)?(\(names))\\.?(?:,?\\s+(?:de\\s+)?(20\\d{2}))?\\b", false),
        ]
        var found: Set<Date> = []
        let lower = text.lowercased()
        let ns = lower as NSString
        for (pattern, monthFirst) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
                let a = ns.substring(with: match.range(at: 1)), b = ns.substring(with: match.range(at: 2))
                let year = match.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: match.range(at: 3)))
                guard let month = months[monthFirst ? a : b], let day = Int(monthFirst ? b : a), (1...31).contains(day) else { continue }
                if let date = make(year: year, month: month, day: day, reference: reference, calendar: calendar) { found.insert(date) }
            }
        }
        // "15/11/2026"
        if let regex = try? NSRegularExpression(pattern: "\\b(\\d{1,2})/(\\d{1,2})/(20\\d{2})\\b") {
            for match in regex.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
                let d = Int(ns.substring(with: match.range(at: 1))) ?? 0, m = Int(ns.substring(with: match.range(at: 2))) ?? 0
                let y = Int(ns.substring(with: match.range(at: 3)))
                if (1...12).contains(m), let date = make(year: y, month: m, day: d, reference: reference, calendar: calendar) { found.insert(date) }
            }
        }
        return found.sorted()
    }

    private static func make(year: Int?, month: Int, day: Int, reference: Date, calendar: Calendar) -> Date? {
        let refYear = calendar.component(.year, from: reference)
        var comps = DateComponents(year: year ?? refYear, month: month, day: day)
        guard var date = calendar.date(from: comps), calendar.component(.day, from: date) == day else { return nil }
        // Sem ano e a data já passou há mais de 60 dias: é do ano que vem.
        if year == nil, date < reference.addingTimeInterval(-60 * 86_400) {
            comps.year = refYear + 1
            guard let next = calendar.date(from: comps) else { return nil }
            date = next
        }
        return date
    }

    /// Início e fim (temporada) a partir das datas citadas que ainda não passaram. Mais de 90 dias à frente não conta.
    static func span(from dates: [Date], now: Date, calendar: Calendar) -> (start: Date, end: Date?)? {
        let today = calendar.startOfDay(for: now)
        let horizon = today.addingTimeInterval(90 * 86_400)
        let upcoming = dates.filter { $0 >= today && $0 <= horizon }
        guard let first = upcoming.first else { return nil }
        let last = upcoming.last
        return (first, last == first ? nil : last)
    }
}
