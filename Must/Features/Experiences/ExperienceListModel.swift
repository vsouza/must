import Foundation

/// Tela Experiências: as salvas, em ordem de data, com busca, filtro e aviso de conflito (prompt 14 · C, item 10).
@MainActor
enum ExperienceListModel {
    enum Chip: String, CaseIterable, Identifiable {
        case any = "Qualquer dia", today = "Hoje", short = "≤ 2 h", freeCancel = "Cancela grátis"
        var id: String { rawValue }
    }

    struct Row: Identifiable {
        var place: Place
        /// Próxima sessão (de hoje em diante, a mais cedo). `nil` = sem horário.
        var session: EventSession?
        /// "conflita: Udatsu Sushi 19:00", uma por âncora que se sobrepõe à sessão.
        var conflicts: [String]

        var id: String { place.id }
    }

    /// Experiência = lugar da lista do tipo experiência, ou que tem `extra.experience`.
    static func isExperience(_ place: Place) -> Bool {
        place.kind == .experience || place.extra?.experience != nil
    }

    static func rows(places: [Place], query: String, chip: Chip, region: Region, now: Date) -> [Row] {
        let today = region.calendar.startOfDay(for: now)
        let all = places.filter(isExperience).map { place -> Row in
            let next = (place.extra?.experience?.sessions ?? []).filter { $0.at >= today }.min { $0.at < $1.at }
            let labels = next.map { conflicts(for: $0, place: place, places: places, region: region) } ?? []
            return Row(place: place, session: next, conflicts: labels)
        }
        return all
            .filter { matches($0, query: query, chip: chip, region: region, now: now) }
            .sorted { a, b in
                switch (a.session, b.session) {
                case let (x?, y?): x.at != y.at ? x.at < y.at : a.place.name < b.place.name
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): a.place.name < b.place.name
                }
            }
    }

    static func matches(_ row: Row, query: String, chip: Chip, region: Region, now: Date) -> Bool {
        let info = row.place.extra?.experience
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let supplier = ExperienceSupplier.badge(info?.supplier ?? .other, url: info?.url)
            guard row.place.matches(q) || supplier.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
                .contains(q.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)) else { return false }
        }
        switch chip {
        case .any: return true
        case .today: return row.session.map { region.calendar.isDate($0.at, inSameDayAs: now) } ?? false
        case .short: return (info?.durationMinutes).map { $0 <= 120 } ?? false
        case .freeCancel: return info?.freeCancellationHours != nil
        }
    }

    // MARK: Conflitos

    /// Âncoras que se sobrepõem à sessão. A regra é a do solver (`DaySolver.overlapWarnings`): quem é fixo no dia manda.
    static func conflicts(for session: EventSession, place: Place, places: [Place], region: Region) -> [String] {
        let cal = region.calendar
        let day = cal.startOfDay(for: session.at)
        let minutes = place.extra?.experience?.durationMinutes ?? 120
        let anchors = anchors(on: day, places: places.filter { $0 !== place }, region: region)
        guard !anchors.isEmpty else { return [] }

        let request = DayRequest(date: day, timeZone: region.timeZone, budget: 0, startAt: day, origin: region.defaultCenter, cityId: "")
        let ctx = DaySolver.Context(request, catalog: [])
        func stop(_ p: Place, at: Date, minutes: Int) -> ProposedStop {
            ProposedStop(place: SolverPlace(p), at: at, end: at.addingTimeInterval(TimeInterval(minutes * 60)),
                         window: window(at, region: region), reason: "", isAnchor: true, isException: false, legFromPrevious: nil)
        }
        let mine = stop(place, at: session.at, minutes: minutes)
        var labels: [String] = []
        for anchor in anchors {
            let warnings = DaySolver.overlapWarnings([mine, stop(anchor.place, at: anchor.at, minutes: anchor.minutes)], ctx: ctx)
            let label = "conflita: \(anchor.place.name) \(region.timeString(anchor.at))"
            if !warnings.isEmpty, !labels.contains(label) { labels.append(label) }
        }
        return labels
    }

    /// Reservas, ingressos e sessões compradas de outros lugares, no dia.
    private static func anchors(on day: Date, places: [Place], region: Region) -> [(place: Place, at: Date, minutes: Int)] {
        let cal = region.calendar
        var out: [(place: Place, at: Date, minutes: Int)] = []
        for p in places where !p.isDone {
            if let r = p.reservation, cal.isDate(r.at, inSameDayAs: day) {
                let role = SolverPlace(p).role
                out.append((p, r.at, role == .eat ? 105 : role.duration))
            }
            for t in p.tickets where cal.isDate(t.at, inSameDayAs: day) {
                out.append((p, t.at, p.extra?.experience?.durationMinutes ?? 120))
            }
            for s in p.extra?.sessions ?? [] where s.bought && cal.isDate(s.at, inSameDayAs: day) {
                out.append((p, s.at, 120))
            }
        }
        return out
    }

    private static func window(_ at: Date, region: Region) -> DayWindow {
        switch region.calendar.component(.hour, from: at) {
        case ..<11: .morning
        case 11..<14: .lunch
        case 14..<17: .afternoon
        case 17..<21: .dinner
        default: .night
        }
    }
}
