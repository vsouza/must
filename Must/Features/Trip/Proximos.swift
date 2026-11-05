import Foundation

/// O que a aba Viagem mostra (prompt 23 §2 · 12, `Proximos.png`): só o que ainda vai acontecer, em ordem.
/// Passou, some. Função pura (sem SwiftData) pra testar: a tela converte os modelos nas entradas abaixo.
enum Proximos {
    enum Kind: String, Sendable, Hashable {
        case reservation, ticket, train, flight, event

        var label: String {
            switch self {
            case .reservation: "reserva"
            case .ticket: "ingresso"
            case .train: "trem"
            case .flight: "voo"
            case .event: "evento"
            }
        }
    }

    /// Um bilhete da lista.
    struct Item: Identifiable, Hashable, Sendable {
        var id: String
        var kind: Kind
        var at: Date
        /// "Udatsu Sushi · omakase", "Shinkansen Nozomi 219", "Checklist · 2 de 12".
        var title: String
        /// Linha de baixo ("2 pessoas · ¥ 22.000").
        var detail: String
        /// Rótulo à direita da etiqueta ("NAKA-MEGURO", "QR OFFLINE", "JR PASS", "LATAM · PROGRAMADO").
        var corner: String?
        /// Rota ao lado da hora ("TOKYO → KYOTO · 2H15", "HND → GRU · VIA DOH").
        var route: String?
        var placeId: String?
        var ticketId: String?
        var flightId: String?
    }

    // MARK: Entradas (sem @Model)

    struct ReservationInput: Sendable {
        var placeId: String
        var name: String
        var sub: String?
        var area: String?
        var at: Date
        var party: Int?
        var price: Double?
        var note: String?
    }

    struct TicketInput: Sendable {
        var placeId: String
        var ticketId: String
        var name: String
        var area: String?
        var at: Date
        var people: Int?
        var offline: Bool
        var confirmation: String?
    }

    struct EventInput: Sendable {
        var id: String
        var kind: TripEventKind
        var title: String
        var note: String
        var at: Date
        var allDay: Bool
    }

    struct FlightInput: Sendable {
        var id: String
        var carrier: String
        var legs: [FlightSegment]
        var checklistDone: Int
        var checklistTotal: Int
        var checkedKg: Int?
    }

    /// Itens futuros (início depois de `now`), em ordem de horário. Um voo vira um item só (o próximo trecho que
    /// ainda não saiu, com as conexões na rota). Eventos de voo do board antigo só entram se não há voo cadastrado.
    static func items(now: Date, reservations: [ReservationInput], tickets: [TicketInput], events: [EventInput],
                      flights: [FlightInput], money: (Double) -> String, calendar: Calendar) -> [Item] {
        var out: [Item] = []

        for r in reservations where r.at > now {
            var parts: [String] = []
            if let party = r.party { parts.append(party == 1 ? "1 pessoa" : "\(party) pessoas") }
            if let price = r.price, price > 0 { parts.append(money(price)) }
            if parts.isEmpty, let note = r.note, !note.isEmpty { parts.append(note) }
            // "Udatsu Sushi · omakase": o tipo só entra quando não repete o nome.
            let sub = r.sub?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
            let title = sub.isEmpty || r.name.localizedCaseInsensitiveContains(sub) ? r.name : "\(r.name) · \(sub)"
            out.append(Item(id: "res-\(r.placeId)", kind: .reservation, at: r.at, title: title, detail: parts.joined(separator: " · "),
                            corner: r.area, placeId: r.placeId))
        }

        for t in tickets where t.at > now {
            var parts = [t.area].compactMap { $0 }.filter { !$0.isEmpty }
            if let people = t.people { parts.append(people == 1 ? "1 pessoa" : "\(people) pessoas") }
            if let code = t.confirmation, parts.count < 2 { parts.append(code) }
            out.append(Item(id: "tk-\(t.ticketId)", kind: .ticket, at: t.at, title: t.name, detail: parts.joined(separator: " · "),
                            corner: t.offline ? "QR offline" : nil, placeId: t.placeId, ticketId: t.ticketId))
        }

        let hasFlights = !flights.isEmpty
        for e in events where e.at > now {
            let kind: Kind
            switch e.kind {
            case .train: kind = .train
            case .flight:
                if hasFlights { continue }
                kind = .flight
            default: kind = .event
            }
            let (route, detail) = splitRoute(e.note)
            out.append(Item(id: "ev-\(e.id)", kind: kind, at: e.at, title: e.title, detail: detail,
                            corner: kind == .train && e.title.localizedCaseInsensitiveContains("shinkansen") ? "JR Pass" : nil,
                            route: route))
        }

        for f in flights {
            guard let index = f.legs.firstIndex(where: { $0.departsNow > now }) else { continue }
            let leg = f.legs[index]
            let rest = Array(f.legs[index...])
            var route = "\(leg.from) → \(rest.last?.to ?? leg.to)"
            if rest.count > 1 { route += " · via " + rest.dropLast().map(\.to).joined(separator: ", ") }
            let title = f.checklistTotal > 0 ? "Checklist · \(f.checklistDone) de \(f.checklistTotal)" : leg.number
            var parts: [String] = []
            if let kg = f.checkedKg { parts.append("bagagem ≤ \(kg) kg") }
            let checkIn = leg.departsNow.addingTimeInterval(-24 * 3600)
            if checkIn > now { parts.append("check-in abre \(dayLabel(checkIn, now: now, calendar: calendar)), \(time(checkIn, calendar))") }
            else { parts.append(leg.number) }
            let status = leg.status == .scheduled ? "programado" : leg.status.label
            let corner = [f.carrier.isEmpty ? nil : f.carrier, status].compactMap { $0 }.joined(separator: " · ")
            out.append(Item(id: "fl-\(f.id)-\(leg.id)", kind: .flight, at: leg.departsNow, title: title, detail: parts.joined(separator: " · "),
                            corner: corner, route: route, flightId: f.id))
        }

        return out.sorted { $0.at != $1.at ? $0.at < $1.at : $0.id < $1.id }
    }

    /// "Tokyo → Kyoto · 2h15 · carro 7 · assentos 12A" → ("Tokyo → Kyoto · 2h15", "carro 7 · assentos 12A").
    static func splitRoute(_ note: String) -> (route: String?, detail: String) {
        let parts = note.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = parts.first, first.contains("→") else { return (nil, note) }
        var route = [first]
        var rest = Array(parts.dropFirst())
        if let duration = rest.first, duration.range(of: #"^\d+\s?h(\d{2})?$|^\d+\s?min$"#, options: .regularExpression) != nil {
            route.append(duration)
            rest.removeFirst()
        }
        return (route.joined(separator: " · "), rest.joined(separator: " · "))
    }

    /// "hoje", "amanhã", "dom 16".
    static func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "hoje" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "amanhã" }
        let names = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
        let weekday = calendar.component(.weekday, from: date)
        return "\(names[(weekday - 1) % 7]) \(calendar.component(.day, from: date))"
    }

    static func time(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Cabeçalho: "11 → 24 nov · dia 3 de 14" (antes: "faltam 6 dias"; depois: "viagem feita").
    static func tripLine(start: Date?, end: Date?, now: Date, calendar: Calendar, month: (Date) -> String) -> String? {
        guard let start, let end else { return nil }
        let s = calendar.startOfDay(for: start), e = calendar.startOfDay(for: end), today = calendar.startOfDay(for: now)
        let range = "\(calendar.component(.day, from: s)) → \(calendar.component(.day, from: e)) \(month(e))"
        let total = (calendar.dateComponents([.day], from: s, to: e).day ?? 0) + 1
        if today < s {
            let left = calendar.dateComponents([.day], from: today, to: s).day ?? 0
            return "\(range) · faltam \(left) dias"
        }
        if today > e { return "\(range) · viagem feita" }
        let index = (calendar.dateComponents([.day], from: s, to: today).day ?? 0) + 1
        return "\(range) · dia \(index) de \(total)"
    }
}
