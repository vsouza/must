import Foundation

/// Minhas viagens (prompt 27 §7, `TrocarViagem.png`): uma linha por região. Tudo puro; a folha só desenha.
/// Cada região tem o próprio container, então só a ativa tem contagem de feitos; as outras mostram o que é fixo.
struct TripRow: Equatable, Identifiable, Sendable {
    enum Tag: String, Sendable { case agora, gps, plano }

    var region: Region
    var title: String
    var subtitle: String
    var tag: Tag
    var isActive: Bool
    var id: String { region.rawValue }
}

enum TripSwitcherModel {
    /// Datas da viagem (registro; Japão: 11–24 nov 2026, `CLAUDE.md`). Sem as duas datas: `nil` (em plano).
    static func tripRange(_ region: Region) -> ClosedRange<Date>? { region.trip.range }

    /// "Japão · Tóquio e Kyoto", "Belo Horizonte · casa", "Roma", "Portugal · Lisboa e Porto".
    static func title(_ region: Region) -> String {
        let trip = region.trip
        if trip.kind == .home { return "\(trip.name) · casa" }
        var names: [String] = []
        for city in trip.cities where !names.contains(city.name) { names.append(city.name) }
        names.removeAll { $0 == trip.name }
        guard !names.isEmpty else { return trip.name }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " e " + names[names.count - 1]
        return "\(trip.name) · \(list)"
    }

    /// Uma linha por viagem do registro (sem as arquivadas), na ordem dele.
    static func rows(trips: [Trip] = BuiltInTrip.all, active: Region, now: Date, gps: Region?, doneCount: Int) -> [TripRow] {
        trips.filter { !$0.archived }.map(Region.init(trip:)).map { region in
            let range = tripRange(region)
            let cal = region.calendar
            let today = cal.startOfDay(for: now)
            let inside = range.map { $0.contains(today) } ?? false
            var parts: [String] = []
            if let range {
                parts.append(rangeText(range, region: region))
                let total = (cal.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0) + 1
                if inside {
                    let day = (cal.dateComponents([.day], from: range.lowerBound, to: today).day ?? 0) + 1
                    parts.append("dia \(day) de \(total)")
                } else if today < range.lowerBound {
                    let left = cal.dateComponents([.day], from: today, to: range.lowerBound).day ?? 0
                    parts.append(left == 1 ? "começa amanhã" : "em \(left) dias")
                } else {
                    parts.append("terminou")
                }
            } else {
                parts.append(region.trip.kind == .home ? "sempre disponível" : "sem datas")
            }
            if region == active { parts.append(doneCount == 1 ? "1 feito" : "\(doneCount) feitos") }
            let tag: TripRow.Tag = inside ? .agora : (gps == region ? .gps : .plano)
            return TripRow(region: region, title: title(region), subtitle: parts.joined(separator: " · "), tag: tag,
                           isActive: region == active)
        }
    }

    /// "11–24 nov 2026"; atravessando o mês, "28 fev–3 mar 2027".
    static func rangeText(_ range: ClosedRange<Date>, region: Region) -> String {
        let cal = region.calendar
        let a = cal.component(.day, from: range.lowerBound), b = cal.component(.day, from: range.upperBound)
        let style = Date.FormatStyle(locale: region.locale, calendar: cal, timeZone: cal.timeZone)
        func clean(_ s: String) -> String { s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " de ", with: " ") }
        let month = clean(range.upperBound.formatted(style.month(.abbreviated).year()))
        if cal.component(.month, from: range.lowerBound) != cal.component(.month, from: range.upperBound) {
            let first = clean(range.lowerBound.formatted(style.month(.abbreviated)))
            return "\(a) \(first)–\(b) \(month)"
        }
        return "\(a)–\(b) \(month)"
    }
}
