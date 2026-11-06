import CoreLocation
import Foundation

/// Ficha técnica do Lugar v8 (`LugarFoto.png`, `Lugar.png`, `LugarIT.png`, `MuseuFoto.png`, `MuseuIT.png`): 3×2 de
/// rótulo + valor, as etiquetas de cima e a âncora (reserva/ingresso). Puro (lê o `Place`, não grava nada).
@MainActor
enum PlaceFicha {
    struct Cell: Hashable, Sendable {
        var label: String
        var value: String
    }

    /// Reserva ou ingresso que fazem do lugar uma âncora (hoje ou depois). `nil` = lugar comum.
    struct Anchor: Hashable, Sendable {
        enum Kind: Sendable { case reservation, ticket }
        var kind: Kind
        var at: Date
        var people: Int?
        var note: String?
        var ticketId: String?
        var hasQR: Bool
        /// Duração do turno (Borghese: 2 h; teamLab: 2 h 30).
        var minutes: Int?
    }

    static func anchor(_ place: Place, now: Date, calendar: Calendar) -> Anchor? {
        let start = calendar.startOfDay(for: now)
        let duration = place.extra?.art?.durationMinutes ?? place.extra?.experience?.durationMinutes
        if let ticket = place.tickets.filter({ $0.at >= start }).min(by: { $0.at < $1.at }) {
            return Anchor(kind: .ticket, at: ticket.at, people: ticket.people, note: ticket.confirmation, ticketId: ticket.id,
                          hasQR: ticket.qrPayload != nil || ticket.pdfName != nil, minutes: duration)
        }
        if let r = place.reservation, r.at >= start {
            return Anchor(kind: .reservation, at: r.at, people: r.party, note: r.note, ticketId: nil, hasQR: false,
                          minutes: duration ?? turnMinutes(r.note ?? "") ?? turnMinutes(place.notes))
        }
        return nil
    }

    /// "turno de 2 h", "Só 2 horas" → 120.
    static func turnMinutes(_ text: String) -> Int? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard let range = folded.range(of: #"(\d+)\s?(h\b|horas?)"#, options: .regularExpression) else { return nil }
        let digits = folded[range].prefix { $0.isNumber }
        return Int(digits).map { $0 * 60 }
    }

    /// "2 h", "2 h 30".
    static func durationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }

    /// "Must eat · ramen", "Shinjuku · saída sul".
    static func specLines(_ place: Place) -> [String] {
        let first = [place.list?.displayName, place.sub?.lowercased()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        var lines = [first.isEmpty ? "Must" : first]
        if let area = place.area, !area.isEmpty { lines.append(area) }
        return lines
    }

    /// Linha de baixo do nome: nome local "mostre ao atendente" (só quando é outra escrita) + o que o lugar é.
    static func localLine(_ place: Place) -> String {
        var parts: [String] = []
        if let local = place.nameLocal?.trimmingCharacters(in: .whitespaces), !local.isEmpty,
           local.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            != place.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) {
            parts.append(local)
            parts.append("mostre ao atendente")
        }
        if let about = about(place) { parts.append(about) }
        return parts.joined(separator: " · ")
    }

    /// A primeira frase das notas que não é pedido nem logística ("Bernini (Apollo e Dafne) e Caravaggio").
    static func about(_ place: Place) -> String? {
        let sentences = place.notes.split(whereSeparator: { ".\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let first = sentences.first(where: { s in
            !["pedir", "levar", "chegar", "nao aceita", "reserva"].contains { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).hasPrefix($0) }
        }) {
            return first.prefix(1).lowercased() + first.dropFirst()
        }
        return place.sub?.lowercased()
    }

    /// A ficha 3×2. `queueFirst` (layout sem foto): fila no lugar do "pedir".
    static func cells(_ place: Place, region: Region, now: Date, here: CLLocation?, walkMaxKm: Double,
                      queueFirst: Bool) -> [Cell] {
        var cells: [Cell] = []
        if queueFirst, let q = place.queueMinutes, q > 0 { cells.append(Cell(label: "fila agora", value: "~\(q) min")) }
        if let cost = cost(place, region: region, now: now) { cells.append(cost) }
        let eats = ["eat", "drink", "coffee"].contains(place.list?.id ?? "")
        if region == .it && eats {
            cells.append(Cell(label: "coperto", value: "€ 1–3 · sem gorjeta"))
        } else {
            cells.append(Cell(label: "pagamento", value: payment(place, region: region)))
        }
        cells.append(Cell(label: "horário", value: hours(place, region: region, now: now)))
        if let here, let distance = place.distance(from: here) {
            let minutes = travelMinutes(place, from: here, walkMaxKm: walkMaxKm)
            cells.append(Cell(label: "distância", value: "\(Walk.distanceText(distance)) · \(minutes) min"))
        } else {
            cells.append(Cell(label: "distância", value: "sem GPS"))
        }
        if !queueFirst, let order = order(place) { cells.append(Cell(label: "pedir", value: order)) }
        cells.append(Cell(label: "veio de", value: origin(place)))
        return Array(cells.prefix(6))
    }

    /// Quanto custa (pedido do Vinicius, 06/11/2026: "mostrar quanto custa pra entrar, não só o pagamento").
    /// Comer/beber: "preço" por pessoa. O resto: "entrada" — inteira e meia do museu, a próxima sessão com preço,
    /// "a partir de" da experiência, ou o gasto previsto. `price == 0` é grátis de propósito (o seed marca assim);
    /// sem nenhum dado, `nil` (não inventa preço).
    static func cost(_ place: Place, region: Region, now: Date) -> Cell? {
        let listId = place.list?.id ?? ""
        let eats = ["eat", "drink", "coffee"].contains(listId)
        let label = ["art", "see", "temple", "sport", "do", "experience", "night", "listen"].contains(listId) ? "entrada" : "preço"
        func free(_ note: String?) -> String { note.map { "grátis · \($0)" } ?? "grátis" }
        if !eats, let art = place.extra?.art {
            if let adult = art.priceAdult {
                if adult <= 0 { return Cell(label: label, value: free(nil)) }
                var value = region.money(adult)
                if let student = art.priceStudent, student < adult {
                    value += student <= 0 ? " · meia grátis" : " · meia \(region.money(student))"
                }
                return Cell(label: label, value: value)
            }
            if let next = art.sessions.filter({ $0.at >= now && $0.price != nil }).min(by: { $0.at < $1.at }),
               let price = next.price {
                return Cell(label: label, value: price <= 0 ? free(nil) : "sessão \(region.money(price))")
            }
        }
        if let exp = place.extra?.experience, let from = exp.priceFrom, from > 0 {
            let money = exp.currency.map { $0 == region.currency ? region.money(from) : from.formatted(.money($0)) }
                ?? region.money(from)
            return Cell(label: label, value: "a partir de \(money)")
        }
        if let price = place.price {
            if price <= 0 { return Cell(label: label, value: free(place.extra?.art?.freeNote)) }
            return Cell(label: label, value: region.money(price) + (eats && region == .it && listId == "eat" ? " / pessoa" : ""))
        }
        if let level = place.priceLevel {
            return Cell(label: label, value: level <= 0 ? free(nil) : String(repeating: region.currencySymbol, count: min(level, 4)))
        }
        return nil
    }

    /// Minutos até o lugar (a pé até `walkMaxKm`, metrô depois), sem rede.
    static func travelMinutes(_ place: Place, from here: CLLocation, walkMaxKm: Double) -> Int {
        DaySolver.leg(here.coordinate, place.coordinate, walkMax: walkMaxKm).minutes
    }

    static func payment(_ place: Place, region: Region) -> String {
        if PocketRules.cashOnly(notes: place.notes) { return "só cash" }
        switch region {
        case .bh: return "cartão e Pix"
        case .jp: return "cartão e cash"
        case .it: return "cartão"
        }
    }

    static func hours(_ place: Place, region: Region, now: Date) -> String {
        if let h = place.hours, h.hasPeriods, let today = h.todayText(now, timeZone: region.timeZone) {
            return today.replacingOccurrences(of: ":00", with: "").replacingOccurrences(of: ", ", with: " · ")
        }
        let windows = DayWindow.allCases.filter(place.windows.contains).map(\.label)
        return windows.isEmpty ? "sem horário" : windows.joined(separator: " · ")
    }

    /// "normal, com ovo" (o pedido das notas, sem o "Pedir o").
    static func order(_ place: Place) -> String? {
        guard var hint = PlacePanelChoice.orderHint(notes: place.notes) else { return nil }
        for prefix in ["Pedir o ", "Pedir a ", "Pedir os ", "Pedir as ", "Pedir "] where hint.hasPrefix(prefix) {
            hint.removeFirst(prefix.count)
            break
        }
        return hint
    }

    /// "Reel · @tokyo.eats", "board".
    static func origin(_ place: Place) -> String {
        guard let source = place.source, source.kind != .board else { return "board" }
        return [source.kind.label, source.author].compactMap { $0 }.joined(separator: " · ")
    }

    /// Etiqueta de horário do layout sem foto ("aberto até 15:00", "abre 17:00", "fechado").
    static func openTag(_ place: Place, region: Region, now: Date) -> String? {
        switch place.openState(at: now, timeZone: region.timeZone) {
        case .open(let until): return until.map { "aberto até \($0)" } ?? "aberto"
        case .closed(_, let at): return at.map { "abre \($0)" } ?? "fechado"
        case .unknown: return nil
        }
    }

    /// "fila ~20 min" / "sem reserva · fila ~40 min" (Roma, onde reserva é a regra).
    static func queueTag(_ place: Place, region: Region) -> String? {
        guard let q = place.queueMinutes, q > 0 else { return nil }
        return region == .it && place.reservation == nil ? "sem reserva · fila ~\(q) min" : "fila ~\(q) min"
    }
}
