import Foundation

// Tipos de Must com painel próprio no Lugar (prompt 13): photo, art, sport; e experiência (prompt 14 · C).
// Os dados ficam num `PlaceExtra` (JSON no `Place`), espelhado no board como `extra: { photo | art | sport | experience }`.

/// Tipo da lista. `.place` é o padrão (comer, beber, ver…).
enum ListKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case place, photo, art, sport
    /// "Must do": aula, tour, ingresso com hora (Viator, Klook, Airbnb…). Cor `night`.
    case experience

    var id: String { rawValue }

    var label: String {
        switch self {
        case .place: "lugar"
        case .photo: "photo"
        case .art: "art"
        case .sport: "sport"
        case .experience: "experiência"
        }
    }
}

/// Luz boa pra um spot de foto.
enum LightKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case goldenAM = "golden-am"
    case goldenPM = "golden-pm"
    case blue
    case hard
    case night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .goldenAM: "golden da manhã"
        case .goldenPM: "golden da tarde"
        case .blue: "hora azul"
        case .hard: "luz dura"
        case .night: "noite"
        }
    }
}

struct PhotoSpot: Codable, Hashable, Sendable {
    /// Azimute do eixo/vista (graus, 0 = norte, sentido horário) — pra onde a câmera aponta.
    var facing: Double?
    var bestLight: [LightKind] = []
    var gear: String?
    var tripodAllowed: Bool?
    var crowdNote: String?

    init(facing: Double? = nil, bestLight: [LightKind] = [], gear: String? = nil, tripodAllowed: Bool? = nil, crowdNote: String? = nil) {
        self.facing = facing
        self.bestLight = bestLight
        self.gear = gear
        self.tripodAllowed = tripodAllowed
        self.crowdNote = crowdNote
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        facing = try c.decodeIfPresent(Double.self, forKey: .facing)
        bestLight = try c.decodeIfPresent([LightKind].self, forKey: .bestLight) ?? []
        gear = try c.decodeIfPresent(String.self, forKey: .gear)
        tripodAllowed = try c.decodeIfPresent(Bool.self, forKey: .tripodAllowed)
        crowdNote = try c.decodeIfPresent(String.self, forKey: .crowdNote)
    }
}

/// Sessão com ingresso: show, palestra, jogo.
struct EventSession: Codable, Hashable, Sendable, Identifiable {
    var at: Date
    var title: String
    var price: Double?
    var soldOut: Bool = false
    var url: URL?
    /// Ingresso já comprado: vira âncora do dia.
    var bought: Bool = false
    /// "em japonês · 40 lugares"
    var note: String?

    var id: String { "\(at.timeIntervalSince1970)-\(title)" }

    init(at: Date, title: String, price: Double? = nil, soldOut: Bool = false, url: URL? = nil, bought: Bool = false, note: String? = nil) {
        self.at = at
        self.title = title
        self.price = price
        self.soldOut = soldOut
        self.url = url
        self.bought = bought
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(Date.self, forKey: .at)
        title = try c.decode(String.self, forKey: .title)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        soldOut = try c.decodeIfPresent(Bool.self, forKey: .soldOut) ?? false
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        bought = try c.decodeIfPresent(Bool.self, forKey: .bought) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

struct ArtEvent: Codable, Hashable, Sendable {
    var style: [String] = []
    var priceAdult: Double?
    var priceStudent: Double?
    /// "1ª quinta do mês"
    var freeNote: String?
    /// Dia (meia-noite no fuso) em que a temporada começa/termina.
    var runsFrom: Date?
    var runsUntil: Date?
    /// Última entrada: minutos antes de fechar.
    var lastEntryMinutes: Int?
    var needsBooking: Bool = false
    var ticketURL: URL?
    var durationMinutes: Int?
    var photographyAllowed: Bool?
    var sessions: [EventSession] = []
    var floors: Int?
    /// "Fotografar: proibido nas salas, liberado no hall. Catálogo ¥4.200."
    var note: String?

    init(style: [String] = [], priceAdult: Double? = nil, priceStudent: Double? = nil, freeNote: String? = nil,
         runsFrom: Date? = nil, runsUntil: Date? = nil, lastEntryMinutes: Int? = nil, needsBooking: Bool = false,
         ticketURL: URL? = nil, durationMinutes: Int? = nil, photographyAllowed: Bool? = nil, sessions: [EventSession] = [],
         floors: Int? = nil, note: String? = nil) {
        self.style = style
        self.priceAdult = priceAdult
        self.priceStudent = priceStudent
        self.freeNote = freeNote
        self.runsFrom = runsFrom
        self.runsUntil = runsUntil
        self.lastEntryMinutes = lastEntryMinutes
        self.needsBooking = needsBooking
        self.ticketURL = ticketURL
        self.durationMinutes = durationMinutes
        self.photographyAllowed = photographyAllowed
        self.sessions = sessions
        self.floors = floors
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        style = try c.decodeIfPresent([String].self, forKey: .style) ?? []
        priceAdult = try c.decodeIfPresent(Double.self, forKey: .priceAdult)
        priceStudent = try c.decodeIfPresent(Double.self, forKey: .priceStudent)
        freeNote = try c.decodeIfPresent(String.self, forKey: .freeNote)
        runsFrom = try c.decodeIfPresent(Date.self, forKey: .runsFrom)
        runsUntil = try c.decodeIfPresent(Date.self, forKey: .runsUntil)
        lastEntryMinutes = try c.decodeIfPresent(Int.self, forKey: .lastEntryMinutes)
        needsBooking = try c.decodeIfPresent(Bool.self, forKey: .needsBooking) ?? false
        ticketURL = try c.decodeIfPresent(URL.self, forKey: .ticketURL)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        photographyAllowed = try c.decodeIfPresent(Bool.self, forKey: .photographyAllowed)
        sessions = try c.decodeIfPresent([EventSession].self, forKey: .sessions) ?? []
        floors = try c.decodeIfPresent(Int.self, forKey: .floors)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    /// Dias inteiros até o fim da temporada (0 = termina hoje). `nil` sem data.
    func daysLeft(from now: Date, calendar: Calendar) -> Int? {
        guard let runsUntil else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: Self.localDay(runsUntil, calendar: calendar)).day
    }

    /// A temporada cobre o dia?
    func isRunning(on day: Date, calendar: Calendar) -> Bool {
        let d = calendar.startOfDay(for: day)
        if let runsFrom, d < Self.localDay(runsFrom, calendar: calendar) { return false }
        if let runsUntil, d > Self.localDay(runsUntil, calendar: calendar) { return false }
        return true
    }

    /// "2026-11-30" vira meia-noite UTC no JSON: lê o dia do calendário, não o instante.
    static func localDay(_ date: Date, calendar: Calendar) -> Date {
        if Int(date.timeIntervalSince1970) % 86_400 == 0 {
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = .gmt
            let c = utc.dateComponents([.year, .month, .day], from: date)
            return calendar.date(from: c) ?? calendar.startOfDay(for: date)
        }
        return calendar.startOfDay(for: date)
    }
}

enum SportActivity: String, Codable, CaseIterable, Sendable, Identifiable {
    case run, bike, hike, swim, climb, walk, watch

    var id: String { rawValue }

    var label: String {
        switch self {
        case .run: "Corrida"
        case .bike: "Bike"
        case .hike: "Trilha"
        case .swim: "Natação"
        case .climb: "Escalada"
        case .walk: "Caminhada"
        case .watch: "Jogo"
        }
    }

    /// Minutos por km (estimativa do "~42 min").
    var minutesPerKm: Double {
        switch self {
        case .run: 6
        case .bike: 2.5
        case .hike: 15
        case .swim: 25
        case .climb, .watch: 0
        case .walk: 12
        }
    }

    /// Verbo da frase de janela ("corra até as 9h").
    var imperative: String {
        switch self {
        case .run: "corra"
        case .bike: "pedale"
        case .hike: "suba"
        case .swim: "nade"
        case .climb: "escale"
        case .walk: "caminhe"
        case .watch: "vá"
        }
    }
}

struct SportSpot: Codable, Hashable, Sendable {
    var activity: SportActivity = .run
    var distanceKm: Double?
    var elevationM: Int?
    var surface: String?
    var loop: Bool = false
    var routeNote: String?
    var facilities: [String] = []
    var preferredTempMax: Int?
    var preferredUVMax: Int?
    /// `watch`: jogos com ingresso.
    var sessions: [EventSession] = []

    static let defaultTempMax = 28
    static let defaultUVMax = 6

    var tempMax: Int { preferredTempMax ?? Self.defaultTempMax }
    var uvMax: Int { preferredUVMax ?? Self.defaultUVMax }

    /// Minutos estimados do percurso.
    var estimatedMinutes: Int? {
        guard let km = distanceKm, activity.minutesPerKm > 0 else { return nil }
        return Int((km * activity.minutesPerKm).rounded())
    }

    init(activity: SportActivity = .run, distanceKm: Double? = nil, elevationM: Int? = nil, surface: String? = nil, loop: Bool = false,
         routeNote: String? = nil, facilities: [String] = [], preferredTempMax: Int? = nil, preferredUVMax: Int? = nil,
         sessions: [EventSession] = []) {
        self.activity = activity
        self.distanceKm = distanceKm
        self.elevationM = elevationM
        self.surface = surface
        self.loop = loop
        self.routeNote = routeNote
        self.facilities = facilities
        self.preferredTempMax = preferredTempMax
        self.preferredUVMax = preferredUVMax
        self.sessions = sessions
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activity = try c.decodeIfPresent(SportActivity.self, forKey: .activity) ?? .run
        distanceKm = try c.decodeIfPresent(Double.self, forKey: .distanceKm)
        elevationM = try c.decodeIfPresent(Int.self, forKey: .elevationM)
        surface = try c.decodeIfPresent(String.self, forKey: .surface)
        loop = try c.decodeIfPresent(Bool.self, forKey: .loop) ?? false
        routeNote = try c.decodeIfPresent(String.self, forKey: .routeNote)
        facilities = try c.decodeIfPresent([String].self, forKey: .facilities) ?? []
        preferredTempMax = try c.decodeIfPresent(Int.self, forKey: .preferredTempMax)
        preferredUVMax = try c.decodeIfPresent(Int.self, forKey: .preferredUVMax)
        sessions = try c.decodeIfPresent([EventSession].self, forKey: .sessions) ?? []
    }
}

/// Fornecedor de uma experiência. A integração por API (fatia 4, `ExperienceSource`) não existe ainda:
/// hoje a experiência entra por link colado ou à mão.
enum ExperienceSupplier: String, Codable, CaseIterable, Sendable, Identifiable {
    case viator, getYourGuide, klook, airbnb, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .viator: "Viator"
        case .getYourGuide: "GetYourGuide"
        case .klook: "Klook"
        case .airbnb: "Airbnb"
        case .other: "outro"
        }
    }
}

/// Experiência com hora marcada (aula, tour, show com ingresso). As sessões são `EventSession`
/// (mesmo formato de art e jogos: `bought` vira âncora do dia).
struct ExperienceInfo: Codable, Hashable, Sendable {
    var supplier: ExperienceSupplier
    var productCode: String?
    /// Página do produto no fornecedor ("Ver no Viator").
    var url: URL?
    var durationMinutes: Int?
    var priceFrom: Double?
    /// Moeda do preço (ISO). `nil` = a da região.
    var currency: String?
    var rating: Double?
    var reviewCount: Int?
    var meetingPoint: String?
    var meetingLat: Double?
    var meetingLng: Double?
    var languages: [String]
    var groupMax: Int?
    /// Cancelamento grátis até N horas antes.
    var freeCancellationHours: Int?
    var sessions: [EventSession]

    init(supplier: ExperienceSupplier = .other, productCode: String? = nil, url: URL? = nil, durationMinutes: Int? = nil,
         priceFrom: Double? = nil, currency: String? = nil, rating: Double? = nil, reviewCount: Int? = nil,
         meetingPoint: String? = nil, meetingLat: Double? = nil, meetingLng: Double? = nil, languages: [String] = [],
         groupMax: Int? = nil, freeCancellationHours: Int? = nil, sessions: [EventSession] = []) {
        self.supplier = supplier
        self.productCode = productCode
        self.url = url
        self.durationMinutes = durationMinutes
        self.priceFrom = priceFrom
        self.currency = currency
        self.rating = rating
        self.reviewCount = reviewCount
        self.meetingPoint = meetingPoint
        self.meetingLat = meetingLat
        self.meetingLng = meetingLng
        self.languages = languages
        self.groupMax = groupMax
        self.freeCancellationHours = freeCancellationHours
        self.sessions = sessions
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        supplier = try c.decodeIfPresent(ExperienceSupplier.self, forKey: .supplier) ?? .other
        productCode = try c.decodeIfPresent(String.self, forKey: .productCode)
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
        priceFrom = try c.decodeIfPresent(Double.self, forKey: .priceFrom)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        rating = try c.decodeIfPresent(Double.self, forKey: .rating)
        reviewCount = try c.decodeIfPresent(Int.self, forKey: .reviewCount)
        meetingPoint = try c.decodeIfPresent(String.self, forKey: .meetingPoint)
        meetingLat = try c.decodeIfPresent(Double.self, forKey: .meetingLat)
        meetingLng = try c.decodeIfPresent(Double.self, forKey: .meetingLng)
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? []
        groupMax = try c.decodeIfPresent(Int.self, forKey: .groupMax)
        freeCancellationHours = try c.decodeIfPresent(Int.self, forKey: .freeCancellationHours)
        sessions = try c.decodeIfPresent([EventSession].self, forKey: .sessions) ?? []
    }

    /// Coordenada do ponto de encontro, se houver.
    var meetingCoordinate: (lat: Double, lng: Double)? {
        guard let meetingLat, let meetingLng else { return nil }
        return (meetingLat, meetingLng)
    }
}

/// `extra` do lugar: no máximo um por tipo (o da lista manda).
struct PlaceExtra: Codable, Hashable, Sendable {
    var photo: PhotoSpot?
    var art: ArtEvent?
    var sport: SportSpot?
    var experience: ExperienceInfo?

    var isEmpty: Bool { photo == nil && art == nil && sport == nil && experience == nil }

    /// Sessões com ingresso (art, jogo ou experiência).
    var sessions: [EventSession] { (art?.sessions ?? []) + (sport?.sessions ?? []) + (experience?.sessions ?? []) }

    /// Marca como comprada cada sessão cujo id está em `ids` (ingresso anexado a uma sessão).
    mutating func markBought(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        func mark(_ list: inout [EventSession]) {
            for i in list.indices where ids.contains(list[i].id) { list[i].bought = true }
        }
        if var a = art { mark(&a.sessions); art = a }
        if var s = sport { mark(&s.sessions); sport = s }
        if var e = experience { mark(&e.sessions); experience = e }
    }
}
