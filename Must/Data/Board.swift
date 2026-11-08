import Foundation

/// Espelho Codable de `data/board.schema.json` (versão 2, prompt 28).
/// Datas "date" ficam como String "yyyy-MM-dd"; "date-time" viram `Date`
/// (ISO 8601 com fuso; exportadas no fuso da viagem).
///
/// v2: a viagem vem em `tripId` + `countryCode` (viagens criadas no app). Arquivo v1 com `region: bh|jp|it` (os seeds,
/// exports antigos) continua sendo lido. `region` é a viagem do arquivo; id que este aparelho não conhece vira uma
/// viagem só com id e país, pra mensagem de "board de outra viagem".
struct Board: Codable, Equatable, Sendable {
    /// Versão que o app grava.
    static let currentVersion = 3
    /// Versões que o importador aceita.
    static let readableVersions = 1...3

    var version: Int
    var region: Region
    var trip: BoardTrip?
    var budget: BoardBudget?
    var lists: [BoardList]
    var places: [BoardPlace]
    var expenses: [BoardExpense]?
    var days: [BoardDay]?
    /// Extensão do schema: eventos sem lugar (Shinkansen, dia inteiro). Voo `kind: flight` aqui é lido como `flights`.
    var events: [BoardEvent]?
    /// Reservas de voo (PNR, pernas, franquia, checklist). Prompt 15 · C.
    var flights: [BoardFlight]?
    /// Lista de presentes (v3, prompt 31). Aditivo: arquivo sem `gifts` continua abrindo.
    var gifts: [BoardGift]?

    private enum CodingKeys: String, CodingKey {
        case version, region, tripId, countryCode, trip, budget, lists, places, expenses, days, events, flights, gifts
    }

    init(version: Int, region: Region, trip: BoardTrip? = nil, budget: BoardBudget? = nil, lists: [BoardList], places: [BoardPlace],
         expenses: [BoardExpense]? = nil, days: [BoardDay]? = nil, events: [BoardEvent]? = nil, flights: [BoardFlight]? = nil, gifts: [BoardGift]? = nil) {
        self.version = version
        self.region = region
        self.trip = trip
        self.budget = budget
        self.lists = lists
        self.places = places
        self.expenses = expenses
        self.days = days
        self.events = events
        self.flights = flights
        self.gifts = gifts
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        let id = try c.decodeIfPresent(String.self, forKey: .tripId) ?? c.decodeIfPresent(String.self, forKey: .region)
        guard let id, !id.isEmpty else {
            throw DecodingError.keyNotFound(CodingKeys.tripId, .init(codingPath: c.codingPath, debugDescription: "falta tripId (ou region)"))
        }
        let country = try c.decodeIfPresent(String.self, forKey: .countryCode)
        region = Region(rawValue: id) ?? Region(trip: Self.unknownTrip(id: id, countryCode: country))
        trip = try c.decodeIfPresent(BoardTrip.self, forKey: .trip)
        budget = try c.decodeIfPresent(BoardBudget.self, forKey: .budget)
        lists = try c.decode([BoardList].self, forKey: .lists)
        places = try c.decode([BoardPlace].self, forKey: .places)
        expenses = try c.decodeIfPresent([BoardExpense].self, forKey: .expenses)
        days = try c.decodeIfPresent([BoardDay].self, forKey: .days)
        events = try c.decodeIfPresent([BoardEvent].self, forKey: .events)
        flights = try c.decodeIfPresent([BoardFlight].self, forKey: .flights)
        gifts = try c.decodeIfPresent([BoardGift].self, forKey: .gifts)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        if version >= 2 {
            try c.encode(region.rawValue, forKey: .tripId)
            try c.encode(region.country, forKey: .countryCode)
        } else {
            try c.encode(region.rawValue, forKey: .region)
        }
        try c.encodeIfPresent(trip, forKey: .trip)
        try c.encodeIfPresent(budget, forKey: .budget)
        try c.encode(lists, forKey: .lists)
        try c.encode(places, forKey: .places)
        try c.encodeIfPresent(expenses, forKey: .expenses)
        try c.encodeIfPresent(days, forKey: .days)
        try c.encodeIfPresent(events, forKey: .events)
        try c.encodeIfPresent(flights, forKey: .flights)
        try c.encodeIfPresent(gifts, forKey: .gifts)
    }

    /// Viagem que este aparelho não tem (board exportado de outra): só id e país, nunca vai pro registro.
    static func unknownTrip(id: String, countryCode: String?) -> Trip {
        let profile = CountryProfile.forCountry(countryCode ?? "ZZ")
        return Trip(id: id, name: id, shortName: nil, countryCode: profile.code, currency: profile.currency,
                    timeZone: profile.timeZone, colorHex: nil, kind: .trip, start: nil, end: nil, cities: [], home: nil,
                    createdAt: Date(timeIntervalSince1970: 0), archived: false, seedId: nil)
    }
}

/// Presente da lista (v3). `person` é só o nome; `source` é name|link|video|place|photo.
struct BoardGift: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var person: String?
    var quantity: Int?
    var estimatedPrice: Double?
    var paidPrice: Double?
    var boughtAt: Date?
    var source: String?
    var sourceURL: String?
    var sourceLabel: String?
    var videoClip: String?
    var placeId: String?
    var storeName: String?
    var storeLat: Double?
    var storeLng: Double?
    var chain: Bool?
    var note: String?
    var order: Int?
}

/// Reserva de voo. As pernas são os trechos; o checklist guarda o que já foi marcado.
struct BoardFlight: Codable, Equatable, Sendable {
    var pnr: String?
    var carrier: String?
    /// "intl-japan" ou "domestic-br".
    var template: String?
    var checkedKg: Int?
    var cabinKg: Int?
    var legs: [BoardFlightLeg]
    var checklist: [ChecklistItem]?
}

struct BoardFlightLeg: Codable, Equatable, Sendable {
    var number: String
    var from: String
    var to: String
    var departs: Date
    var arrives: Date?
    var seat: String?
    var terminal: String?
    var gate: String?
    var note: String?
}

struct BoardEvent: Codable, Equatable, Sendable {
    var at: Date
    var title: String
    var kind: TripEventKind?
    var note: String?
    var allDay: Bool?
    var weatherDependent: Bool?
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
    /// photo / art / sport / experience (ausente = place).
    var kind: ListKind?
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
    /// Dados do tipo: `{ photo | art | sport | experience }`.
    var extra: PlaceExtra?
    /// Ordem dentro da lista (Board). Ausente = 0.
    var order: Int?
    /// Ingressos anexados (âncoras do dia). Ausente = nenhum.
    var tickets: [Ticket]?
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
