import Foundation

/// Horas e dias de voo no fuso do aeroporto (a partida é local de quem embarca). Português fixo, sem depender do locale.
enum FlightFormat {
    private static let weekdays = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
    private static let months = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

    /// Fuso do aeroporto; sem ele, o da região.
    static func zone(_ iata: String, fallback: TimeZone) -> TimeZone {
        Airports.airport(iata)?.timeZone ?? fallback
    }

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal
    }

    /// "22:10"
    static func time(_ date: Date, zone: TimeZone) -> String {
        let c = calendar(zone).dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// "ter 11 nov"
    static func day(_ date: Date, zone: TimeZone) -> String {
        let c = calendar(zone).dateComponents([.weekday, .day, .month], from: date)
        return "\(weekdays[(c.weekday ?? 1) - 1]) \(c.day ?? 0) \(months[(c.month ?? 1) - 1])"
    }

    /// "TER 11 NOV" (a linha de cima do card).
    static func dayUpper(_ date: Date, zone: TimeZone) -> String { day(date, zone: zone).uppercased() }

    /// "hoje" · "amanhã" · "em 8 dias" · "ontem" (dias inteiros no fuso da região).
    static func daysAway(_ date: Date, now: Date, region: Region) -> String {
        let days = WalletRules.daysBetween(now, date, region: region)
        switch days {
        case 0: return "hoje"
        case 1: return "amanhã"
        case -1: return "ontem"
        case 2...: return "em \(days) dias"
        default: return "há \(-days) dias"
        }
    }
}
