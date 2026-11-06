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
    /// Datas das viagens com data (hoje só o Japão: 11–24 nov 2026, `CLAUDE.md`).
    static func tripRange(_ region: Region) -> ClosedRange<Date>? {
        guard region == .jp else { return nil }
        let cal = region.calendar
        guard let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 11)),
              let end = cal.date(from: DateComponents(year: 2026, month: 11, day: 24)) else { return nil }
        return start...end
    }

    static func title(_ region: Region) -> String {
        switch region {
        case .jp: "Japão · Tóquio e Kyoto"
        case .bh: "Belo Horizonte · casa"
        case .it: "Roma"
        }
    }

    static func rows(active: Region, now: Date, gps: Region?, doneCount: Int) -> [TripRow] {
        Region.allCases.map { region in
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
                parts.append(region == .bh ? "sempre disponível" : "sem datas")
            }
            if region == active { parts.append(doneCount == 1 ? "1 feito" : "\(doneCount) feitos") }
            let tag: TripRow.Tag = inside ? .agora : (gps == region ? .gps : .plano)
            return TripRow(region: region, title: title(region), subtitle: parts.joined(separator: " · "), tag: tag,
                           isActive: region == active)
        }
    }

    /// "11–24 nov 2026".
    static func rangeText(_ range: ClosedRange<Date>, region: Region) -> String {
        let cal = region.calendar
        let a = cal.component(.day, from: range.lowerBound), b = cal.component(.day, from: range.upperBound)
        let month = range.upperBound.formatted(Date.FormatStyle(locale: region.locale, calendar: cal).month(.abbreviated).year())
        return "\(a)–\(b) \(month.replacingOccurrences(of: ".", with: ""))".replacingOccurrences(of: " de ", with: " ")
    }
}
