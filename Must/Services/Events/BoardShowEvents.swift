import CoreLocation
import Foundation

// Provedor real de "Em cartaz" (RODADA-23 · A). Monta `ShowEvent` só do que já está no aparelho: `PlaceExtra`
// (`art`, `sport`, `experience`, `program`) e `Ticket`. Zero rede. Vencidos somem da lista (ficam no lugar);
// "hoje" é o dia no fuso da região.
//
// Agente E: some os eventos dos feeds com `merging(_:)` (valor fixo) ou `merging(source:)` (lido a cada consulta).
// O que já está no board ganha de um externo igual (mesmo título, dia e lugar).

/// Fonte externa de eventos (Bandsintown, Ticketmaster, feeds). Leitura síncrona do cache.
@MainActor
protocol ShowEventSource {
    func events(region: Region, at date: Date) -> [ShowEvent]
}

@MainActor
struct BoardShowEvents: ShowEventsProviding {
    /// Lugares do board da região atual (cache primeiro: SwiftData já está no aparelho).
    var places: @MainActor () -> [SolverPlace]
    var external: [ShowEvent] = []
    var sources: [any ShowEventSource] = []
    /// Região do board em uso (um provedor por container; `MustApp` cria com a atual): fuso de `events(placeId:at:)`.
    var region: Region

    init(region: Region, places: @escaping @MainActor () -> [SolverPlace]) {
        self.region = region
        self.places = places
    }

    /// Com os eventos já em mãos (feeds baixados).
    func merging(_ external: [ShowEvent]) -> BoardShowEvents {
        var copy = self
        copy.external += external
        return copy
    }

    /// Com uma fonte consultada a cada leitura.
    func merging(source: any ShowEventSource) -> BoardShowEvents {
        var copy = self
        copy.sources.append(source)
        return copy
    }

    // MARK: ShowEventsProviding

    func today(region: Region, at date: Date) -> [ShowEvent] {
        let cal = region.calendar
        return all(region: region, at: date).filter { $0.occurs(on: date, calendar: cal) }
    }

    func upcoming(region: Region, from date: Date, days: Int) -> [ShowEvent] {
        let cal = region.calendar
        let start = cal.startOfDay(for: date)
        guard days > 0, let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        return all(region: region, at: date).filter { $0.overlaps(start..<end, calendar: cal) }
    }

    func events(placeId: String, at date: Date) -> [ShowEvent] {
        all(region: region, at: date).filter { $0.placeId == placeId }
    }

    // MARK: Montagem

    /// Tudo que ainda vale (board + externos), sem repetição, em ordem estável.
    func all(region: Region, at date: Date) -> [ShowEvent] {
        let cal = region.calendar
        var events = ShowEventBuilder.events(from: places(), region: region, now: date)
        var extra = external
        for source in sources { extra += source.events(region: region, at: date) }
        extra = extra.filter { !$0.isExpired(at: date, calendar: cal) }
        events = ShowEventBuilder.merge(board: events, external: extra, calendar: cal)
        return events.sorted(by: ShowEventBuilder.order)
    }
}

extension BoardShowEvents {
    /// O provedor ligado ao SwiftData da região (`MustApp`): lê os lugares do `ModelContext` a cada consulta.
    static func live(region: Region, fetch: @escaping @MainActor () -> [Place]) -> BoardShowEvents {
        BoardShowEvents(region: region, places: { fetch().map(SolverPlace.init) })
    }
}

// MARK: Janela de datas

extension ShowEvent {
    /// Dia inteiro (no calendário da região) em que a exposição termina.
    private func lastDay(_ cal: Calendar) -> Date? { runsUntil.map { ArtEvent.localDay($0, calendar: cal) } }

    /// Acontece naquele dia? Exposição: em temporada. Show/jogo/outro: alguma sessão (ou o início) no dia.
    func occurs(on date: Date, calendar cal: Calendar) -> Bool {
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return false }
        return overlaps(start..<end, calendar: cal)
    }

    /// Exposição com fim (ou sem sessões): vale a temporada inteira. O resto: alguma sessão (ou o início) na janela.
    private var isSeason: Bool { kind == .exhibition && (runsUntil != nil || sessions.isEmpty) }

    func overlaps(_ window: Range<Date>, calendar cal: Calendar) -> Bool {
        if isSeason {
            let from = startsAt.map { cal.startOfDay(for: $0) } ?? .distantPast
            let until = lastDay(cal).flatMap { cal.date(byAdding: .day, value: 1, to: $0) } ?? .distantFuture
            return from < window.upperBound && until > window.lowerBound
        }
        if sessions.isEmpty {
            guard let startsAt else { return false }
            return window.contains(startsAt)
        }
        return sessions.contains { window.contains($0.at) }
    }

    /// Já passou (a exposição acabou ou a última sessão foi antes de hoje)?
    func isExpired(at date: Date, calendar cal: Calendar) -> Bool {
        let today = cal.startOfDay(for: date)
        if let last = lastDay(cal) { return last < today }
        if let latest = sessions.map(\.at).max() { return latest < today }
        if let startsAt { return startsAt < today }
        return false
    }
}

// MARK: Construção a partir do board

enum ShowEventBuilder {
    static func order(_ a: ShowEvent, _ b: ShowEvent) -> Bool {
        (a.startsAt ?? .distantFuture, a.title, a.id) < (b.startsAt ?? .distantFuture, b.title, b.id)
    }

    static func events(from places: [SolverPlace], region: Region, now: Date) -> [ShowEvent] {
        let cal = region.calendar
        let today = cal.startOfDay(for: now)
        var out: [ShowEvent] = []
        for place in places where !place.done || hasUpcomingTicket(place, today: today) {
            out += events(for: place, region: region, calendar: cal, today: today)
        }
        return out.filter { !$0.isExpired(at: now, calendar: cal) }
    }

    private static func hasUpcomingTicket(_ p: SolverPlace, today: Date) -> Bool {
        p.tickets.contains { $0.at >= today }
    }

    static func events(for place: SolverPlace, region: Region, calendar cal: Calendar, today: Date) -> [ShowEvent] {
        let extra = place.extra
        let boughtIds = Set(place.tickets.compactMap(\.sessionId))
        var out: [ShowEvent] = []
        var covered = Set<Date>()

        func upcoming(_ sessions: [EventSession]) -> [EventSession] {
            sessions.filter { $0.at >= today }.map { s in
                var s = s
                if boughtIds.contains(s.id) { s.bought = true }
                covered.insert(s.at)
                return s
            }.sorted { ($0.at, $0.title) < ($1.at, $1.title) }
        }
        func make(_ id: String, _ kind: ShowKind, _ title: String, sessions: [EventSession], start: Date?, until: Date? = nil,
                  price: String? = nil, url: URL? = nil, source: ShowSource = .board, checked: Date? = nil) -> ShowEvent {
            let located = place.lat != 0 || place.lng != 0
            return ShowEvent(id: "board-\(place.id)-\(id)", placeId: place.id, kind: kind, title: title, venue: place.name,
                             lat: located ? place.lat : nil, lng: located ? place.lng : nil, startsAt: start, runsUntil: until,
                             sessions: sessions, priceText: price, url: url, source: source, checkedAt: checked)
        }
        func each(_ sessions: [EventSession], _ kind: ShowKind, source: ShowSource = .board, checked: Date? = nil) {
            for s in sessions {
                out.append(make(s.id, kind, s.title, sessions: [s], start: s.at, price: price(s.price, region: region, freeNote: nil),
                                url: s.url, source: source, checked: checked))
            }
        }

        if let art = extra?.art {
            let sessions = upcoming(art.sessions)
            if art.runsFrom != nil || art.runsUntil != nil {
                out.append(make("exposicao", .exhibition, place.name, sessions: sessions,
                                start: art.runsFrom.map { ArtEvent.localDay($0, calendar: cal) } ?? sessions.first?.at,
                                until: art.runsUntil.map { ArtEvent.localDay($0, calendar: cal) },
                                price: price(art.priceAdult, region: region, freeNote: art.freeNote), url: art.ticketURL))
            } else {
                each(sessions, .show)
            }
        }
        if let sport = extra?.sport { each(upcoming(sport.sessions), .match) }
        if let experience = extra?.experience { each(upcoming(experience.sessions), .other) }
        if let program = extra?.program, !program.isEmpty {
            each(upcoming(program), place.kind == .sport ? .match : .show, source: extra?.programSource ?? .link, checked: extra?.programCheckedAt)
        }
        // Ingresso que não casa com nenhuma sessão do lugar vira um evento só dele.
        let known = Set(((extra?.sessions ?? []) + (extra?.program ?? [])).map(\.id))
        for ticket in place.tickets where ticket.at >= today {
            if let sid = ticket.sessionId, known.contains(sid) { continue }
            if covered.contains(ticket.at) { continue }
            let kind: ShowKind = place.kind == .sport ? .match : place.kind == .art ? .exhibition : .other
            let s = EventSession(at: ticket.at, title: place.name, price: ticket.paid, bought: true)
            out.append(make("t-\(ticket.id)", kind, place.name, sessions: [s], start: ticket.at))
        }
        return out
    }

    static func price(_ value: Double?, region: Region, freeNote: String?) -> String? {
        guard let value else { return freeNote }
        if value == 0 { return "grátis" }
        return value.formatted(.currency(code: region.currency).locale(region.locale).precision(.fractionLength(value.rounded() == value ? 0 : 2)))
    }

    // MARK: Junção com externos

    /// Quem já está no board ganha de um externo com o mesmo título, no mesmo dia e lugar.
    static func merge(board: [ShowEvent], external: [ShowEvent], calendar cal: Calendar) -> [ShowEvent] {
        var seen = Set(board.map { key($0, cal) })
        var ids = Set(board.map(\.id))
        var out = board
        for e in external.sorted(by: order) {
            guard ids.insert(e.id).inserted, seen.insert(key(e, cal)).inserted else { continue }
            out.append(e)
        }
        return out
    }

    static func key(_ e: ShowEvent, _ cal: Calendar) -> String {
        let day = (e.startsAt ?? e.sessions.first?.at).map { cal.startOfDay(for: $0).timeIntervalSince1970 } ?? 0
        return "\(norm(e.title))|\(Int(day))|\(norm(e.venue ?? ""))"
    }

    static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }
}
