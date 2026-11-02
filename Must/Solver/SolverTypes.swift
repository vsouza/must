import CoreLocation
import Foundation

// Tipos do solver: valores imutáveis, sem SwiftData, pra ser puro e testável.

/// Papel de um lugar no dia (derivado da cor da lista).
enum StopRole: String, Sendable, Hashable, CaseIterable {
    case eat, drink, see, listen, shop, photo, sport

    init(color: MustColor) {
        switch color {
        case .eat: self = .eat
        case .drink, .coffee: self = .drink
        case .see, .temple, .art: self = .see
        case .listen, .night: self = .listen
        case .shop: self = .shop
        case .photo: self = .photo
        case .sport: self = .sport
        }
    }

    /// O tipo da lista manda (art é um "see" com regras próprias); senão, a cor.
    init(kind: ListKind, color: MustColor) {
        switch kind {
        case .photo: self = .photo
        case .sport: self = .sport
        case .art: self = .see
        // Experiência entra no dia só com ingresso ou pedido: papel de "ver" (a atividade).
        case .experience: self = .see
        case .place: self.init(color: color)
        }
    }

    /// Minutos padrão de uma parada.
    var duration: Int {
        switch self {
        case .eat: 75
        case .drink: 50
        case .see: 90
        case .listen: 90
        case .shop: 75
        case .photo: 50
        case .sport: 60
        }
    }
}

/// Lista no Montar: o solver decide (`auto`), ou o usuário ligou/desligou.
enum ListMode: String, Sendable, Hashable, CaseIterable {
    case auto, on, off
}

/// Previsão de um dia (preenchida pelo WeatherService no prompt 07).
struct DayWeather: Sendable, Hashable, Codable {
    var tempMin: Double
    var tempMax: Double
    /// Código WMO (Open-Meteo).
    var code: Int
    var precipProb: Int
    var sunrise: Date?
    var sunset: Date?
    /// Previsão hora a hora (Open-Meteo `hourly` + qualidade do ar). Vazio = sem detalhe.
    var hours: [HourWeather] = []

    /// A hora que contém `date` (ou a mais próxima, até 90 min).
    func hour(at date: Date) -> HourWeather? {
        hours.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
            .flatMap { abs($0.time.timeIntervalSince(date)) <= 90 * 60 ? $0 : nil }
    }

    /// Céu limpo ou quase (WMO 0–2) e pouca chance de chuva.
    var isClear: Bool { code <= 2 && precipProb < 30 }
    /// Chuva forte: WMO 63/65/81/82/95+ ou probabilidade alta.
    var isHeavyRain: Bool { [63, 65, 67, 81, 82, 95, 96, 99].contains(code) || precipProb >= 70 }
}

/// Lugar do board visto pelo solver.
struct SolverPlace: Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var nameLocal: String? = nil
    var listId: String
    var listColor: MustColor
    var sub: String?
    var cityId: String
    var area: String?
    var lat: Double
    var lng: Double
    var price: Double?
    var windows: [DayWindow]
    var hours: PlaceHours?
    var reservation: Reservation?
    var saveForEnd: Bool
    var allowBudgetException: Bool
    var queueMinutes: Int?
    var notes: String
    var sourceKind: SourceKind?
    var done: Bool
    var kind: ListKind = .place
    var extra: PlaceExtra?
    /// Ingressos anexados: âncoras do dia (como a reserva).
    var tickets: [Ticket] = []

    var role: StopRole { StopRole(kind: kind, color: listColor) }
    var rules: NotesRules { NotesRules(notes: notes) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lng) }
    var cost: Double { price ?? 0 }
}

extension SolverPlace {
    @MainActor
    init(_ place: Place) {
        self.init(id: place.id, name: place.name, nameLocal: place.nameLocal, listId: place.list?.id ?? "", listColor: place.list?.color ?? .eat,
                  sub: place.sub, cityId: place.cityId, area: place.area, lat: place.lat, lng: place.lng, price: place.price,
                  windows: place.windows, hours: place.hours, reservation: place.reservation, saveForEnd: place.saveForEnd,
                  allowBudgetException: place.allowBudgetException, queueMinutes: place.queueMinutes, notes: place.notes,
                  sourceKind: place.source?.kind, done: place.isDone, kind: place.kind, extra: place.extra, tickets: place.tickets)
    }

    init(_ p: BoardPlace, color: MustColor, kind: ListKind = .place) {
        self.init(id: p.id, name: p.name, nameLocal: p.nameLocal, listId: p.listId, listColor: color, sub: p.sub, cityId: p.cityId, area: p.area,
                  lat: p.lat ?? 0, lng: p.lng ?? 0, price: p.price, windows: p.window ?? [], hours: p.hours,
                  reservation: p.reservation, saveForEnd: p.saveForEnd ?? false, allowBudgetException: p.allowBudgetException ?? false,
                  queueMinutes: p.queueMinutes, notes: p.notes ?? "", sourceKind: p.source?.kind, done: p.done != nil,
                  kind: kind, extra: p.extra, tickets: p.tickets ?? [])
    }
}

/// O que o texto/voz pediu (regex agora; Foundation Models no prompt 08).
struct DayIntent: Sendable, Hashable {
    var kind: DayKind?
    /// Papéis ligados/desligados pelo texto ("sem compras", "café").
    var roles: [StopRole: ListMode] = [:]
    var budget: Double?
    var walk: WalkLevel?
    /// Trechos de nome a incluir/excluir ("Fuunji", "Nakano").
    var mustInclude: [String] = []
    var mustExclude: [String] = []
    /// Sub-listas preferidas ("Ramen", "Café").
    var preferSubs: [String] = []
    var startEarly: Bool?
    /// "dois almoços", "sushi e ramen": libera duas refeições na mesma janela.
    var mealsException = false
    /// "jantar bom", "caprichar": libera um lugar com "vale a exceção".
    var splurge = false
    /// Janela da exceção pedida ("jantar bom" → jantar). `nil` = qualquer.
    var splurgeWindow: DayWindow?

    var isEmpty: Bool { self == DayIntent() }
}

/// Pedido de dia.
struct DayRequest: Sendable {
    /// Meia-noite do dia, no fuso.
    var date: Date
    var timeZone: TimeZone
    var kind: DayKind = .free
    var budget: Double
    var walk: WalkLevel = .normal
    /// Modo por `listId` (lista ausente = `auto`).
    var lists: [String: ListMode] = [:]
    var intent = DayIntent()
    /// Hora de sair (acordou + preparo).
    var startAt: Date
    var origin: CLLocationCoordinate2D
    var cityId: String
    /// Outros trechos da mesma cidade (Tóquio 13–17 e 20–24): os lugares de um valem no outro.
    var sameCityIds: Set<String> = []
    /// Dias que ainda restam na cidade depois de hoje (0 = último dia). `nil` = sem viagem (BH).
    var daysLeftInCity: Int?
    var weather: DayWeather?
    var walkMaxKm: Double = 1.5
    var oneMealPerWindow = true
    /// Centro da cidade do dia (posição do sol). `nil` = usa a origem.
    var cityCenter: CLLocationCoordinate2D?
    /// Desempate (↻ "outra proposta").
    var seed = 0

    /// Lugar da cidade do dia (ou de outro trecho dela).
    func isInCity(_ id: String) -> Bool { id == cityId || sameCityIds.contains(id) }

    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// 0 = domingo … 6 = sábado.
    var weekday: Int { calendar.component(.weekday, from: date) - 1 }
}

enum LegMode: String, Sendable, Hashable { case walk, metro }

struct Leg: Sendable, Hashable {
    var km: Double
    var mode: LegMode
    var minutes: Int
}

struct ProposedStop: Sendable, Hashable, Identifiable {
    var place: SolverPlace
    var at: Date
    var end: Date
    var window: DayWindow
    /// Frase curta: "antes da multidão", "horário não confirmado".
    var reason: String
    var isAnchor: Bool
    /// Fora da meta do dia ("vale a exceção").
    var isException: Bool
    var legFromPrevious: Leg?

    var id: String { place.id }
}

struct LeftOut: Sendable, Hashable {
    var place: SolverPlace
    var reason: String
}

struct DayProposal: Sendable {
    var request: DayRequest
    var stops: [ProposedStop]
    /// Gasto previsto dentro da meta (sem exceções).
    var predictedSpend: Double
    /// Gasto das exceções (fora da meta).
    var exceptionSpend: Double
    var walkKm: Double
    var transitLegs: Int
    var leftOut: [LeftOut]
    var explanation: String
    /// Avisos do dia: âncoras que se sobrepõem ("Udatsu 19:00 e … 19:00 se sobrepõem").
    var warnings: [String] = []

    func reason(for placeId: String) -> String? { leftOut.first { $0.place.id == placeId }?.reason }
}

/// Filtros da sheet Trocar.
enum SwapFilter: String, Sendable, CaseIterable, Identifiable {
    case sameSub, sameRole, cheaper, noQueue

    var id: String { rawValue }

    func label(sub: String?, role: StopRole) -> String {
        switch self {
        case .sameSub: sub ?? "Mesma lista"
        case .sameRole: "Qualquer \(role.rawValue)"
        case .cheaper: "Mais barato"
        case .noQueue: "Sem fila"
        }
    }
}

struct SwapAlternative: Sendable, Hashable, Identifiable {
    var place: SolverPlace
    var priceDelta: Double
    /// Minutos a mais (+) ou a menos (−) de deslocamento no trajeto.
    var detourMinutes: Int
    var note: String

    var id: String { place.id }
}
