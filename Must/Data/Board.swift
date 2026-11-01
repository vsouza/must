import Foundation

/// Espelho Codable de `data/board.schema.json` (versão 1).
/// Datas "date" ficam como String "yyyy-MM-dd"; "date-time" viram `Date`
/// (ISO 8601 com fuso; exportadas no fuso da região).
struct Board: Codable, Equatable, Sendable {
    var version: Int
    var region: Region
    var trip: BoardTrip?
    var budget: BoardBudget?
    var lists: [BoardList]
    var places: [BoardPlace]
    var expenses: [BoardExpense]?
    var days: [BoardDay]?
}

struct BoardTrip: Codable, Equatable, Sendable {
    var start: String?
    var end: String?
    var home: String?
    var cities: [BoardCity]?
}

struct BoardCity: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var from: String?
    var to: String?
    var tz: String?
    var currency: String?
    var lat: Double?
    var lng: Double?
}

struct BoardBudget: Codable, Equatable, Sendable {
    var perDay: Double?
    var currency: String?
    var walkMaxKm: Double?
    var dayStart: String?
}

struct BoardList: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var kanji: String?
    var icon: String?
    var color: MustColor
    var photo: ListPhoto?
    var sub: [String]?
}

struct BoardPlace: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var nameLocal: String?
    var listId: String
    var sub: String?
    var cityId: String
    var area: String?
    var lat: Double?
    var lng: Double?
    var approx: Bool?
    var placeId: String?
    var price: Double?
    var priceLevel: Int?
    var hours: PlaceHours?
    var window: [DayWindow]?
    var reservation: Reservation?
    var saveForEnd: Bool?
    var allowBudgetException: Bool?
    var queueMinutes: Int?
    var notes: String?
    var source: Source?
    var done: DoneMark?
}

struct BoardExpense: Codable, Equatable, Sendable {
    var at: Date
    var amount: Double
    var category: ExpenseCategory?
    var placeId: String?
    var method: PaymentMethod?
}

struct BoardDay: Codable, Equatable, Sendable {
    var date: String
    var kind: DayKind?
    var budget: Double?
    var walk: WalkLevel?
    var stops: [BoardStop]?
    /// Extensão do schema: o dia foi aceito (virou Hoje).
    var accepted: Bool?
}

struct BoardStop: Codable, Equatable, Sendable {
    var placeId: String
    /// "HH:mm" no fuso da região.
    var at: String?
    var done: Bool?
}

// MARK: - JSON

extension JSONDecoder {
    /// Aceita ISO 8601 com fuso (com ou sem fração de segundo) e "yyyy-MM-dd".
    static var board: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = BoardDates.parseDateTime(string) { return date }
            if let date = BoardDates(timeZone: .gmt).day(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "data inválida: \(string)")
        }
        return decoder
    }
}

extension JSONEncoder {
    /// Datas em ISO 8601 no fuso dado ("2026-11-15T19:00:00+09:00"), chaves ordenadas.
    static func board(timeZone: TimeZone) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(BoardDates(timeZone: timeZone).dateTimeString(date))
        }
        return encoder
    }
}

/// Conversões de data do board num fuso.
struct BoardDates: Sendable {
    var timeZone: TimeZone

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    static func parseDateTime(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string)
    }

    func dateTimeString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = timeZone
        return f.string(from: date)
    }

    /// "2026-11-13" → meia-noite no fuso.
    func day(from string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, string.count == 10 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    func dayString(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    /// Dia + "HH:mm" (ou um date-time completo).
    func time(_ hhmm: String, on day: Date) -> Date? {
        if let full = Self.parseDateTime(hhmm) { return full }
        guard let minutes = Settings.minutes(from: hhmm) else { return nil }
        return calendar.date(byAdding: .minute, value: minutes, to: startOfDay(day))
    }

    func timeString(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
