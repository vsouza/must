import Foundation
import FoundationModels

// Página de museu/galeria/show (ou post sobre uma exposição) → Must art com temporada, preço e sessões.
// Ingressos (Sympla em BH; e-plus, Lawson Ticket, Peatix, Pia no Japão) são só links — nada de API.

@Generable
struct GeneratedSession {
    @Guide(description: "Data e hora no formato yyyy-MM-ddTHH:mm, ou vazio")
    var at: String
    @Guide(description: "Título da sessão (show, palestra, jogo)")
    var title: String
    @Guide(description: "Preço em número inteiro na moeda do texto, ou 0 se não houver")
    var price: Int
}

@Generable
struct ExtractedArtEvent {
    @Guide(description: "Título da exposição, show ou evento")
    var title: String
    @Guide(description: "Museu, galeria ou casa onde acontece, ou vazio")
    var venue: String
    @Guide(description: "Até 5 palavras de estilo em português (ex.: fotografia, pb, rua)", .maximumCount(5))
    var style: [String]
    @Guide(description: "Preço da entrada inteira em número inteiro, ou 0 se não aparecer")
    var priceAdult: Int
    @Guide(description: "Preço de estudante/meia em número inteiro, ou 0")
    var priceStudent: Int
    @Guide(description: "Quando é grátis (ex.: 1ª quinta do mês), ou vazio")
    var freeNote: String
    @Guide(description: "Último dia da temporada no formato yyyy-MM-dd, ou vazio")
    var runsUntil: String
    @Guide(description: "Horário de funcionamento como aparece, ou vazio")
    var hours: String
    @Guide(description: "Minutos antes de fechar da última entrada (ex.: 30), ou 0")
    var lastEntry: Int
    @Guide(description: "Sessões com ingresso (shows, palestras, jogos)", .maximumCount(6))
    var sessions: [GeneratedSession]
}

enum EventExtractor {
    /// Sites de ingresso: o link vira `ticketURL`.
    static let ticketHosts = ["sympla.com.br", "eplus.jp", "l-tike.com", "peatix.com", "t.pia.jp", "eventim.com.br", "ingresse.com"]

    static let keywords = ["exposição", "exposicao", "mostra", "retrospectiva", "galeria", "museu", "em cartaz", "ingresso", "sympla",
                           "exhibition", "retrospective", "gallery", "museum", "tickets", "展", "美術館", "博物館", "ギャラリー", "チケット", "入場料"]

    static func isTicketSite(_ url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return ticketHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Texto (ou link) com cara de exposição/evento.
    static func looksLikeEvent(_ text: String, url: URL?) -> Bool {
        if isTicketSite(url) { return true }
        let lower = text.lowercased()
        let hits = keywords.filter { lower.contains($0) }.count
        let hasPrice = lower.range(of: #"(¥|r\$|円)\s?\d"#, options: .regularExpression) != nil
            || lower.range(of: #"\d[\d,]*\s?円"#, options: .regularExpression) != nil
        return hits >= 2 || (hits >= 1 && hasPrice)
    }

    // MARK: Sem modelo (regex)

    /// Preço, estudante e fim da temporada lidos direto do texto.
    static func parse(_ text: String, url: URL?, timeZone: TimeZone, now: Date = AppClock.now) -> ArtEvent {
        var art = ArtEvent()
        let prices = self.prices(in: text)
        art.priceAdult = prices.adult
        art.priceStudent = prices.student
        art.runsUntil = runsUntil(in: text, timeZone: timeZone, now: now)
        if text.range(of: #"(?i)grátis|gratuit|free admission|無料"#, options: .regularExpression) != nil, art.priceAdult == nil {
            art.priceAdult = 0
            art.freeNote = "entrada gratuita"
        }
        if isTicketSite(url) {
            art.ticketURL = url
            art.needsBooking = true
        }
        if let m = text.range(of: #"(?i)(última entrada|last entry|最終入場)[^\d]{0,12}(\d{1,2})\s?min"#, options: .regularExpression) {
            art.lastEntryMinutes = Int(text[m].filter(\.isNumber).suffix(2))
        }
        return art
    }

    static func prices(in text: String) -> (adult: Double?, student: Double?) {
        let pattern = #"(?:¥|R\$)\s?(\d{1,3}(?:[.,]\d{3})*|\d+)|(\d{1,3}(?:,\d{3})*|\d+)\s?円"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return (nil, nil) }
        let ns = text as NSString
        var found: [(value: Double, location: Int)] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
            var digits = ns.substring(with: r)
            // "1.400" e "1,400" são milhar; "R$ 12,50" é centavo.
            if digits.range(of: #"^\d{1,3}([.,]\d{3})+$"#, options: .regularExpression) != nil {
                digits = digits.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
            } else {
                digits = digits.replacingOccurrences(of: ",", with: ".")
            }
            if let v = Double(digits) { found.append((v, m.range.location)) }
        }
        guard let first = found.first else { return (nil, nil) }
        // Estudante/meia: o preço logo depois da palavra.
        let studentWords = ["estudante", "meia", "student", "学生", "大学生"]
        var student: Double?
        for w in studentWords {
            let r = ns.range(of: w, options: .caseInsensitive)
            guard r.location != NSNotFound else { continue }
            student = found.first { $0.location > r.location && $0.location - r.location < 40 }?.value
            if student != nil { break }
        }
        let adult = found.first { $0.value != student }?.value ?? first.value
        return (adult, student)
    }

    /// "até 16/11", "2026.10.3〜2026.11.30", "〜11月30日", "until Nov 30".
    static func runsUntil(in text: String, timeZone: TimeZone, now: Date) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let year = cal.component(.year, from: now)
        func make(_ y: Int?, _ m: Int, _ d: Int) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = .gmt
            var date = utc.date(from: DateComponents(year: y ?? year, month: m, day: d))
            // Sem ano e já passou há mais de um mês: é do ano que vem.
            if y == nil, let d0 = date, d0 < now.addingTimeInterval(-30 * 86_400) {
                date = utc.date(from: DateComponents(year: year + 1, month: m, day: d))
            }
            return date
        }
        func ints(_ s: Substring) -> [Int] { s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) } }

        // Intervalo com ano: "2026.10.3〜2026.11.30" / "2026/10/03 - 2026/11/30" / "2026年10月3日〜11月30日"
        let range = #"(\d{4})[./年-](\d{1,2})[./月-](\d{1,2})日?\s*[〜~～–—-]\s*((\d{4})[./年-])?(\d{1,2})[./月-](\d{1,2})日?"#
        if let r = text.range(of: range, options: .regularExpression) {
            let n = ints(text[r])
            // 6 números = ano dos dois lados; 5 = o fim herda o ano do começo.
            if n.count >= 6 { return make(n[3], n[4], n[5]) }
            if n.count == 5 { return make(n[0], n[3], n[4]) }
        }
        // "até 16/11(/2026)" / "até 16 de novembro"
        if let r = text.range(of: #"(?i)(até|ate|em cartaz até)\s+(\d{1,2})/(\d{1,2})(/(\d{2,4}))?"#, options: .regularExpression) {
            let n = ints(text[r])
            if n.count >= 2 { return make(n.count >= 3 ? (n[2] < 100 ? 2000 + n[2] : n[2]) : nil, n[1], n[0]) }
        }
        let months = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]
        if let r = text.range(of: #"(?i)até\s+(\d{1,2})\s+de\s+([a-zç]+)"#, options: .regularExpression) {
            let part = text[r].lowercased()
            if let d = ints(text[r]).first, let m = months.firstIndex(where: { part.contains($0) }) { return make(nil, m + 1, d) }
        }
        // "〜11月30日"
        if let r = text.range(of: #"[〜~～]\s*(\d{1,2})月(\d{1,2})日"#, options: .regularExpression) {
            let n = ints(text[r])
            if n.count == 2 { return make(nil, n[0], n[1]) }
        }
        let en = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        if let r = text.range(of: #"(?i)until\s+([a-z]{3})[a-z]*\.?\s+(\d{1,2})"#, options: .regularExpression) {
            let part = text[r].lowercased()
            if let d = ints(text[r]).first, let m = en.firstIndex(where: { part.contains(" " + $0) }) { return make(nil, m + 1, d) }
        }
        return nil
    }

    // MARK: No aparelho (Foundation Models)

    static let instructions = """
    Você lê a página ou legenda de uma exposição, show ou evento com ingresso e extrai os dados. \
    Use só o que está no texto; deixe vazio (ou 0) o que não aparecer. Datas em yyyy-MM-dd.
    """

    static func onDevice(_ text: String, url: URL?, timeZone: TimeZone) async throws -> ExtractedPlace? {
        let session = LanguageModelSession(instructions: instructions)
        let g = try await session.respond(to: "Texto:\n\(text)", generating: ExtractedArtEvent.self).content
        return map(g, text: text, url: url, timeZone: timeZone)
    }

    /// Junta o que o modelo leu com o que a regex garante (o modelo não inventa preço nem data).
    static func map(_ g: ExtractedArtEvent, text: String, url: URL?, timeZone: TimeZone) -> ExtractedPlace? {
        let title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var art = parse(text, url: url, timeZone: timeZone)
        art.style = g.style.map { $0.lowercased() }.filter { !$0.isEmpty }
        if art.priceAdult == nil, g.priceAdult > 0, text.contains(String(g.priceAdult)) || text.contains(g.priceAdult.formatted()) {
            art.priceAdult = Double(g.priceAdult)
        }
        if art.priceStudent == nil, g.priceStudent > 0 { art.priceStudent = Double(g.priceStudent) }
        if art.freeNote == nil, !g.freeNote.isEmpty { art.freeNote = g.freeNote }
        if art.runsUntil == nil, !g.runsUntil.isEmpty { art.runsUntil = BoardDates(timeZone: .gmt).day(from: g.runsUntil) }
        if art.lastEntryMinutes == nil, g.lastEntry > 0 { art.lastEntryMinutes = g.lastEntry }
        art.sessions = g.sessions.compactMap { s in
            guard !s.title.isEmpty, s.at.count >= 16 else { return nil }
            let dates = BoardDates(timeZone: timeZone)
            guard let day = dates.day(from: String(s.at.prefix(10))), let at = dates.time(String(s.at.suffix(5)), on: day) else { return nil }
            return EventSession(at: at, title: s.title, price: s.price > 0 ? Double(s.price) : nil, url: art.ticketURL)
        }
        let venue = g.venue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !g.hours.isEmpty { art.note = "Horário na página: \(g.hours)" }
        return ExtractedPlace(name: title, nameLocal: nil, area: nil, category: .art,
                              sub: art.style.contains { $0.contains("foto") } ? "Fotografia" : nil,
                              hint: venue.isEmpty ? "evento lido no aparelho" : "evento · \(venue)", art: art, venue: venue.isEmpty ? nil : venue)
    }
}
