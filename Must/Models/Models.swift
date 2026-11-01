import Foundation
import SwiftData

// Modelos SwiftData. Cada região tem o próprio container (must-<região>.store).
// Enums ficam como raw value (String) com acessores tipados: mais simples de
// filtrar em `#Predicate` e à prova de mudanças no enum.

@Model
final class MustList {
    @Attribute(.unique) var id: String
    /// Sem o prefixo "Must".
    var name: String
    var kanji: String?
    var iconRaw: String
    var colorRaw: String
    var photo: ListPhoto?
    var subs: [String]
    var order: Int

    @Relationship(deleteRule: .cascade, inverse: \Place.list)
    var places: [Place] = []

    init(id: String, name: String, kanji: String? = nil, icon: MustIcon, color: MustColor,
         photo: ListPhoto? = nil, subs: [String] = [], order: Int = 0) {
        self.id = id
        self.name = name
        self.kanji = kanji
        self.iconRaw = icon.rawValue
        self.colorRaw = color.rawValue
        self.photo = photo
        self.subs = subs
        self.order = order
    }

    var icon: MustIcon {
        get { MustIcon(rawValue: iconRaw) ?? .mustsLista }
        set { iconRaw = newValue.rawValue }
    }

    var color: MustColor {
        get { MustColor(rawValue: colorRaw) ?? .eat }
        set { colorRaw = newValue.rawValue }
    }

    /// "Must eat"
    var displayName: String { "Must \(name)" }
}

@Model
final class Place {
    @Attribute(.unique) var id: String
    var name: String
    var nameLocal: String?
    var list: MustList?
    var sub: String?
    var cityId: String
    var area: String?
    var lat: Double
    var lng: Double
    /// Coordenada chutada — resolver no Places.
    var approx: Bool
    var placeId: String?
    /// Gasto esperado por pessoa, na moeda da região.
    var price: Double?
    var priceLevel: Int?
    /// JSON de `PlaceHours` (cache do Places).
    var hoursData: Data?
    var windowsRaw: [String]
    var reservation: Reservation?
    var saveForEnd: Bool
    var allowBudgetException: Bool
    var queueMinutes: Int?
    var notes: String
    var source: Source?
    var done: DoneMark?

    @Relationship(deleteRule: .nullify, inverse: \Expense.place)
    var expenses: [Expense] = []

    @Relationship(deleteRule: .nullify, inverse: \Stop.place)
    var stops: [Stop] = []

    init(id: String, name: String, cityId: String, lat: Double = 0, lng: Double = 0) {
        self.id = id
        self.name = name
        self.cityId = cityId
        self.lat = lat
        self.lng = lng
        self.approx = false
        self.windowsRaw = []
        self.saveForEnd = false
        self.allowBudgetException = false
        self.notes = ""
    }

    var hours: PlaceHours? {
        get { hoursData.flatMap { try? JSONDecoder.board.decode(PlaceHours.self, from: $0) } }
        set { hoursData = newValue.flatMap { try? JSONEncoder.board(timeZone: .gmt).encode($0) } }
    }

    var windows: [DayWindow] {
        get { windowsRaw.compactMap(DayWindow.init(rawValue:)) }
        set { windowsRaw = newValue.map(\.rawValue) }
    }

    var isDone: Bool { done != nil }
}

@Model
final class Expense {
    @Attribute(.unique) var id: UUID
    var at: Date
    var amount: Double
    var categoryRaw: String
    var place: Place?
    var methodRaw: String

    init(at: Date, amount: Double, category: ExpenseCategory = .other, place: Place? = nil, method: PaymentMethod = .card) {
        self.id = UUID()
        self.at = at
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.place = place
        self.methodRaw = method.rawValue
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var method: PaymentMethod {
        get { PaymentMethod(rawValue: methodRaw) ?? .card }
        set { methodRaw = newValue.rawValue }
    }
}

@Model
final class PlannedDay {
    /// Meia-noite do dia, no fuso da região.
    @Attribute(.unique) var date: Date
    var kindRaw: String
    var budget: Double
    var walkRaw: String
    var accepted: Bool

    @Relationship(deleteRule: .cascade, inverse: \Stop.day)
    var stops: [Stop] = []

    init(date: Date, kind: DayKind = .free, budget: Double, walk: WalkLevel = .normal, accepted: Bool = false) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.budget = budget
        self.walkRaw = walk.rawValue
        self.accepted = accepted
    }

    var kind: DayKind {
        get { DayKind(rawValue: kindRaw) ?? .free }
        set { kindRaw = newValue.rawValue }
    }

    var walk: WalkLevel {
        get { WalkLevel(rawValue: walkRaw) ?? .normal }
        set { walkRaw = newValue.rawValue }
    }

    /// Paradas na ordem do roteiro.
    var orderedStops: [Stop] { stops.sorted { ($0.order, $0.at) < ($1.order, $1.at) } }
}

@Model
final class Stop {
    @Attribute(.unique) var id: UUID
    var day: PlannedDay?
    var place: Place?
    var at: Date
    var done: Bool
    var order: Int
    /// `Place.id` da parada original, quando foi trocada.
    var swappedFrom: String?
    /// Reserva (âncora fixa do dia).
    var isAnchor: Bool = false
    /// Fora da meta do dia ("vale a exceção").
    var isException: Bool = false

    init(place: Place?, at: Date, order: Int, done: Bool = false, swappedFrom: String? = nil,
         isAnchor: Bool = false, isException: Bool = false) {
        self.id = UUID()
        self.place = place
        self.at = at
        self.order = order
        self.done = done
        self.swappedFrom = swappedFrom
        self.isAnchor = isAnchor
        self.isException = isException
    }
}

/// Viagem (singleton por região). Em BH não há start/end: só a cidade de casa.
@Model
final class TripInfo {
    var start: Date?
    var end: Date?
    /// Bairro/base onde dorme (último metrô pra casa).
    var home: String?
    /// JSON de `[City]`.
    var citiesData: Data

    init(start: Date? = nil, end: Date? = nil, home: String? = nil, cities: [City] = []) {
        self.start = start
        self.end = end
        self.home = home
        self.citiesData = (try? JSONEncoder.board(timeZone: .gmt).encode(cities)) ?? Data("[]".utf8)
    }

    var cities: [City] {
        get { (try? JSONDecoder.board.decode([City].self, from: citiesData)) ?? [] }
        set { citiesData = (try? JSONEncoder.board(timeZone: .gmt).encode(newValue)) ?? Data("[]".utf8) }
    }

    var hasTrip: Bool { start != nil && end != nil }

    func city(id: String) -> City? { cities.first { $0.id == id } }
}

/// Ajustes do dia e da inteligência (singleton por região).
@Model
final class Settings {
    var perDayBudget: Double
    var walkMaxKm: Double
    /// Minutos desde a meia-noite (09:30 = 570).
    var dayStartMinutes: Int
    var oneMealPerWindow: Bool
    var onDeviceAI: Bool
    var cloudBoost: Bool
    var transcribeVideos: Bool
    /// Fotos de fundo (Wikimedia Commons). Nome antigo mantido pra não migrar o banco.
    var flickrPhotos: Bool
    /// Quanto vale 1 unidade da moeda da região em BRL (¥1 = R$ 0,036). BH = 1.
    var fxRate: Double
    var fxDate: Date?

    init(region: Region) {
        self.perDayBudget = region.defaultBudget
        self.walkMaxKm = 1.5
        self.dayStartMinutes = 9 * 60 + 30
        self.oneMealPerWindow = true
        self.onDeviceAI = true
        self.cloudBoost = false
        self.transcribeVideos = false
        self.flickrPhotos = true
        self.fxRate = region == .jp ? 0.036 : 1
        self.fxDate = nil
    }

    /// "09:30"
    var dayStart: String {
        get { String(format: "%02d:%02d", dayStartMinutes / 60, dayStartMinutes % 60) }
        set { if let m = Self.minutes(from: newValue) { dayStartMinutes = m } }
    }

    static func minutes(from hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }
}

extension ModelContext {
    /// Singleton `Settings` da região (cria se faltar).
    func settings(for region: Region) -> Settings {
        if let existing = try? fetch(FetchDescriptor<Settings>()).first { return existing }
        let created = Settings(region: region)
        insert(created)
        return created
    }

    /// Singleton `TripInfo` (cria se faltar).
    func tripInfo() -> TripInfo {
        if let existing = try? fetch(FetchDescriptor<TripInfo>()).first { return existing }
        let created = TripInfo()
        insert(created)
        return created
    }
}

/// Todos os modelos persistidos.
enum MustSchema {
    static let models: [any PersistentModel.Type] = [
        MustList.self, Place.self, Expense.self, PlannedDay.self, Stop.self, TripInfo.self, Settings.self,
    ]
    static var schema: Schema { Schema(models) }
}
