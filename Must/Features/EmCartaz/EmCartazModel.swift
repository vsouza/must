import Foundation

/// Lógica pura da tela Em cartaz (prompt 27 §1): o que entra, em que seção, em que ordem e com que texto.
/// Nada aqui lê SwiftData nem rede: a tela passa os `ShowEvent` que o provedor já tem no aparelho.
enum EmCartazFilter: String, CaseIterable, Identifiable, Sendable {
    case trip, today, museums, shows, matches

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trip: "Na viagem"
        case .today: "Hoje"
        case .museums: "Museus"
        case .shows: "Shows"
        case .matches: "Jogos"
        }
    }
}

struct EmCartazSections: Equatable, Sendable {
    var today: [ShowEvent]
    var later: [ShowEvent]

    var all: [ShowEvent] { today + later }
    var count: Int { today.count + later.count }
}

enum EmCartazModel {
    /// Junta "hoje" e "próximos" sem repetir, tira o que já venceu e separa em Hoje / Dias seguintes.
    static func sections(today: [ShowEvent], upcoming: [ShowEvent], filter: EmCartazFilter, now: Date,
                         calendar: Calendar) -> EmCartazSections {
        var seen = Set<String>()
        let merged = (today + upcoming).filter { seen.insert($0.id).inserted }
        let alive = merged.filter { !isExpired($0, now: now, calendar: calendar) }
        let kept = alive.filter { matches($0, filter: filter, now: now, calendar: calendar) }
        let now_ = kept.filter { happensToday($0, now: now, calendar: calendar) }
        let later = kept.filter { !happensToday($0, now: now, calendar: calendar) }
        return EmCartazSections(today: now_.sorted { sortKey($0, now: now) < sortKey($1, now: now) },
                                later: later.sorted { sortKey($0, now: now) < sortKey($1, now: now) })
    }

    static func matches(_ event: ShowEvent, filter: EmCartazFilter, now: Date, calendar: Calendar) -> Bool {
        switch filter {
        case .trip: true
        case .today: happensToday(event, now: now, calendar: calendar)
        case .museums: event.kind == .exhibition
        case .shows: event.kind == .show
        case .matches: event.kind == .match
        }
    }

    /// Venceu: a temporada acabou antes de hoje e não há sessão daqui pra frente.
    static func isExpired(_ event: ShowEvent, now: Date, calendar: Calendar) -> Bool {
        let today = calendar.startOfDay(for: now)
        if let until = event.runsUntil, calendar.startOfDay(for: until) < today { return event.sessions.allSatisfy { $0.at < today } }
        if event.runsUntil == nil, event.sessions.isEmpty, let start = event.startsAt { return start < today }
        return false
    }

    /// Acontece hoje: começa hoje, tem sessão hoje ou é exposição em temporada.
    static func happensToday(_ event: ShowEvent, now: Date, calendar: Calendar) -> Bool {
        if let start = event.startsAt, calendar.isDate(start, inSameDayAs: now) { return true }
        if event.sessions.contains(where: { calendar.isDate($0.at, inSameDayAs: now) }) { return true }
        if event.kind == .exhibition || event.runsUntil != nil {
            let today = calendar.startOfDay(for: now)
            let started = event.startsAt.map { calendar.startOfDay(for: $0) <= today } ?? true
            let notOver = event.runsUntil.map { calendar.startOfDay(for: $0) >= today } ?? true
            return started && notOver && event.kind == .exhibition
        }
        return false
    }

    /// A próxima data com hora (sessão de hoje em diante, ou o início). Exposição em temporada não tem.
    static func nextDate(_ event: ShowEvent, now: Date) -> Date? {
        let upcomingSession = event.sessions.map(\.at).filter { $0 >= now.addingTimeInterval(-3600) }.min()
        if let upcomingSession { return upcomingSession }
        if let start = event.startsAt, start >= now.addingTimeInterval(-3600) { return start }
        return nil
    }

    private static func sortKey(_ event: ShowEvent, now: Date) -> Date {
        nextDate(event, now: now) ?? event.runsUntil ?? .distantFuture
    }

    // MARK: Textos

    static func origin(_ source: ShowSource) -> String {
        switch source {
        case .board: "do board"
        case .link: "link colado"
        case .poster: "foto do cartaz"
        case .bandsintown: "Bandsintown"
        case .ticketmaster: "Ticketmaster"
        case .feed: "agenda pública"
        }
    }

    static func kindLabel(_ kind: ShowKind) -> String {
        switch kind {
        case .exhibition: "exposição"
        case .show: "show"
        case .match: "jogo"
        case .other: "evento"
        }
    }

    /// "Museu · Ebisu · exposição até 15 fev" (o que a segunda linha da linha diz).
    static func meta(_ event: ShowEvent, region: Region, now: Date) -> String {
        var parts: [String] = []
        if let venue = event.venue, !venue.isEmpty { parts.append(venue) }
        if let until = event.runsUntil { parts.append("até \(region.shortDay(until))") }
        else if let next = nextDate(event, now: now) {
            parts.append("\(KindLines.weekdayDay(next, region: region)) · \(region.timeString(next))")
        }
        if let price = event.priceText, !price.isEmpty { parts.append(price) }
        return parts.joined(separator: " · ")
    }

    /// Coluna da direita: ("SEG 16", "19:00"), ("HOJE", "19:00") ou ("EM CARTAZ", nil).
    static func trailing(_ event: ShowEvent, region: Region, now: Date) -> (top: String, bottom: String?) {
        let calendar = region.calendar
        guard let next = nextDate(event, now: now) else {
            return (happensToday(event, now: now, calendar: calendar) ? "aberto" : "em cartaz", nil)
        }
        let time = region.timeString(next)
        if calendar.isDate(next, inSameDayAs: now) { return ("hoje", time) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(next, inSameDayAs: tomorrow) {
            return ("amanhã", time)
        }
        return (KindLines.weekdayDay(next, region: region), time)
    }

    /// "2 museus · 1 show" / "1 jogo · 1 em breve": os dois cantos do cabeçalho.
    static func headerCounts(_ sections: EmCartazSections) -> (left: String, right: String) {
        let all = sections.all
        func n(_ kind: ShowKind, _ one: String, _ many: String) -> String? {
            let c = all.filter { $0.kind == kind }.count
            return c == 0 ? nil : "\(c) \(c == 1 ? one : many)"
        }
        let left = [n(.exhibition, "museu", "museus"), n(.show, "show", "shows")].compactMap { $0 }.joined(separator: " · ")
        let right = [n(.match, "jogo", "jogos"), sections.later.isEmpty ? nil : "\(sections.later.count) em breve"]
            .compactMap { $0 }.joined(separator: " · ")
        return (left, right)
    }
}
