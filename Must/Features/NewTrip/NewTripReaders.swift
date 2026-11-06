import Foundation

/// Leitores puros do fluxo Nova viagem (prompt 28 · F3): hospedagem e voo a partir de texto colado ou OCR do cartão.
/// Reaproveitam `TicketReader`/`TicketExtractor`/`TicketDates` (Must/Services/Tickets). Tudo no aparelho; o usuário confere.
enum NewTripReaders {
    /// Região só pra ler data/hora do texto (as funções de ingresso pedem uma). Os horários são reinterpretados depois no
    /// fuso certo (aeroporto ou cidade), então o fuso desta região não vaza.
    static let parseRegion: Region = .it

    /// Mesma hora de parede, em outro fuso ("22:05 em Rome" → "22:05 em São Paulo").
    static func rezone(_ date: Date, from: TimeZone, to: TimeZone) -> Date {
        var source = Calendar(identifier: .gregorian)
        source.timeZone = from
        let parts = source.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        var target = Calendar(identifier: .gregorian)
        target.timeZone = to
        return target.date(from: parts) ?? date
    }

    /// Dia/hora de parede num fuso (a partir do dia do calendário em UTC do rascunho).
    static func wall(day: Date, hour: Int, minute: Int = 0, zone: TimeZone) -> Date {
        let parts = NewTripModel.calendar.dateComponents([.year, .month, .day], from: day)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: hour, minute: minute)) ?? day
    }

    // MARK: Hospedagem

    struct Lodging: Equatable {
        var name = ""
        var address = ""
        var checkIn: Date?
        var checkOut: Date?
        var isEmpty: Bool { name.isEmpty && address.isEmpty && checkIn == nil && checkOut == nil }
    }

    /// E-mail/PDF de reserva de hotel ou Airbnb. Nome: rótulo ("Hotel: …", "Acomodação") ou o título do extrator;
    /// endereço: "Endereço: …"; entrada/saída: a data da linha com "check-in/entrada" e "check-out/saída".
    static func lodging(from raw: String, zone: TimeZone) -> Lodging {
        let reading = TicketReader.readText(raw)
        let text = reading.text.isEmpty ? raw : reading.text
        var out = Lodging()
        if let hit = TicketText.first(#"(?i)(?:hotel|hospedagem|acomoda[cç][aã]o|property|propriedade|alojamento|stay|apartamento)\s*:\s*([^\n]{3,80})"#, in: text)?[1] {
            out.name = hit.trimmingCharacters(in: .whitespaces)
        } else {
            let extracted = TicketExtractor.extract(TicketReading(text: text), region: parseRegion)
            out.name = extracted.title?.value ?? ""
        }
        if let hit = TicketText.first(#"(?i)(?:endere[cç]o|address|morada)\s*:\s*([^\n]{4,120})"#, in: text)?[1] {
            out.address = hit.trimmingCharacters(in: .whitespaces)
        }
        for line in TicketText.lines(text) {
            let low = TicketText.folded(line)
            let isIn = low.contains("check-in") || low.contains("checkin") || low.hasPrefix("entrada") || low.contains("chegada")
            let isOut = low.contains("check-out") || low.contains("checkout") || low.hasPrefix("saida")
            guard isIn || isOut, let when = date(in: line, defaultYear: nil, zone: parseRegion.timeZone) else { continue }
            let moved = rezone(when, from: parseRegion.timeZone, to: zone)
            if isOut, out.checkOut == nil { out.checkOut = moved } else if isIn, out.checkIn == nil { out.checkIn = moved }
        }
        return out
    }

    // MARK: Voo

    struct Leg: Equatable {
        var number: String
        var from: String
        var to: String
        var departure: Date?
        var arrival: Date?
    }

    /// Pernas de voo do texto: "TP 82 · 11 mar 22:05 → 12 mar 11:20 · GRU → LIS", "LA 8084 (GRU) … (DOH)".
    /// `defaultYear`: ano quando o texto não traz (cartão de embarque costuma ter só dia e mês).
    static func flightLegs(from raw: String, defaultYear: Int?, fallbackZone: TimeZone) -> [Leg] {
        let text = TicketReader.readText(raw).text
        var legs: [Leg] = []
        for line in TicketText.lines(text) {
            guard let number = TicketText.first(#"\b([A-Z][A-Z0-9])\s?(\d{2,4})\b"#, in: line) else { continue }
            var from = "", to = ""
            let parens = TicketText.matches(#"\(([A-Z]{3})\)"#, in: line)
            if parens.count >= 2 {
                from = parens[0].groups[1]; to = parens[1].groups[1]
            } else if let route = TicketText.first(#"\b([A-Z]{3})\s*(?:→|->|–|—|-|/|para|to)\s*([A-Z]{3})\b"#, in: line) {
                from = route[1]; to = route[2]
            }
            guard !from.isEmpty, !to.isEmpty else { continue }
            let dates = allDates(in: line, defaultYear: defaultYear, zone: parseRegion.timeZone)
            func instant(_ d: Date?, _ iata: String) -> Date? {
                guard let d else { return nil }
                let zone = Airports.airport(iata)?.timeZone ?? fallbackZone
                return rezone(d, from: parseRegion.timeZone, to: zone)
            }
            legs.append(Leg(number: "\(number[1]) \(number[2])", from: from, to: to,
                            departure: instant(dates.first, from), arrival: instant(dates.dropFirst().first, to)))
        }
        return legs
    }

    // MARK: Datas

    private static let months = ["jan": 1, "fev": 2, "feb": 2, "mar": 3, "abr": 4, "apr": 4, "mai": 5, "may": 5, "jun": 6, "jul": 7,
                                 "ago": 8, "aug": 8, "set": 9, "sep": 9, "out": 10, "oct": 10, "nov": 11, "dez": 12, "dec": 12]

    /// Data (com ou sem ano) e hora opcional, em hora de parede no fuso `zone`.
    static func date(in text: String, defaultYear: Int?, zone: TimeZone) -> Date? {
        allDates(in: text, defaultYear: defaultYear, zone: zone).first
    }

    static func allDates(in text: String, defaultYear: Int?, zone: TimeZone) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let monthWord = "(jan|fev|feb|mar|abr|apr|mai|may|jun|jul|ago|aug|set|sep|out|oct|nov|dez|dec)[a-zç]*\\.?"
        // "11 mar 2027 22:05", "11 de mar. 22:05", "11 mar" — depois a hora solta que segue ("→ 11:20" herda o dia anterior).
        let pattern = "(?i)\\b(\\d{1,2})\\s*(?:de\\s+)?\(monthWord)(?:,?\\s*(?:de\\s+)?(\\d{4}))?(?:[^\\d\\n]{0,10}?(\\d{1,2})[:h](\\d{2}))?"
        var found: [(loc: Int, date: Date)] = []
        var lastDay: DateComponents?
        for m in TicketText.matches(pattern, in: text) {
            guard let day = Int(m.groups[1]), let month = months[m.groups[2].lowercased().prefix(3).description] else { continue }
            let year = Int(m.groups[3]) ?? defaultYear ?? cal.component(.year, from: AppClock.now)
            var parts = DateComponents(year: year, month: month, day: day, hour: Int(m.groups[4]) ?? 0, minute: Int(m.groups[5]) ?? 0)
            if let date = cal.date(from: parts) { found.append((m.location, date)) }
            parts.hour = nil; parts.minute = nil
            lastDay = parts
        }
        // ISO e dd/mm/aaaa (só se o texto não tinha mês por extenso).
        if found.isEmpty, let hit = TicketDates.first(in: text, region: parseRegion) {
            found.append((0, rezone(hit.date, from: parseRegion.timeZone, to: zone)))
            var c = Calendar(identifier: .gregorian); c.timeZone = zone
            lastDay = c.dateComponents([.year, .month, .day], from: found[0].date)
        }
        var dates = found.sorted { $0.loc < $1.loc }.map(\.date)
        // Hora solta depois da primeira data ("12 mar 11:20"): já pega acima. "→ 18:15" sozinho herda o dia da última data.
        if dates.count == 1, let day = lastDay,
           let m = TicketText.matches("(?:→|->|–|—|-)\\s*(\\d{1,2})[:h](\\d{2})\\b(?!\\s*(?:de\\s+)?\(monthWord))", in: text).first,
           let h = Int(m.groups[1]), let mi = Int(m.groups[2]) {
            var parts = day; parts.hour = h; parts.minute = mi
            if let arrival = cal.date(from: parts) { dates.append(arrival) }
        }
        return dates
    }
}
