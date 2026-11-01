import Foundation

/// Moeda no estilo do Must: "R$ 200", "R$ 12,50", "¥ 15.000" (sempre separadores pt-BR).
struct MoneyFormatStyle: FormatStyle, Sendable {
    var currency: String
    var showsSymbol = true

    func format(_ value: Double) -> String {
        let decimals = currency == "JPY" ? 0 : (value.rounded() == value ? 0 : 2)
        let number = value.formatted(
            .number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(decimals)).grouping(.automatic)
        )
        guard showsSymbol else { return number }
        return "\(Self.symbol(for: currency)) \(number)"
    }

    static func symbol(for currency: String) -> String {
        switch currency {
        case "BRL": "R$"
        case "JPY": "¥"
        default: currency
        }
    }
}

extension FormatStyle where Self == MoneyFormatStyle {
    static func money(_ currency: String, symbol: Bool = true) -> MoneyFormatStyle {
        MoneyFormatStyle(currency: currency, showsSymbol: symbol)
    }
}

extension Region {
    func money(_ value: Double, symbol: Bool = true) -> String {
        value.formatted(.money(currency, symbol: symbol))
    }

    /// Datas no fuso e locale da região.
    func dateStyle(_ date: Date.FormatStyle.DateStyle = .abbreviated, time: Date.FormatStyle.TimeStyle = .omitted) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: date, time: time, locale: locale, calendar: calendar)
        style.timeZone = timeZone
        return style
    }

    /// "19:00"
    func timeString(_ date: Date) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// "13" (dia do mês)
    func dayNumber(_ date: Date) -> String { "\(calendar.component(.day, from: date))" }

    /// "nov"
    func monthShort(_ date: Date) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar).month(.abbreviated)
        style.timeZone = timeZone
        return date.formatted(style).replacingOccurrences(of: ".", with: "")
    }
}
