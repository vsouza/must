import CoreLocation
import Observation
import SwiftData
import SwiftUI

/// Estado de Montar → Proposta → Trocar → Aceitar. O solver decide; aqui só se juntam os parâmetros.
@MainActor
@Observable
final class DayPlanner {
    let region: Region
    /// Meia-noite do dia.
    let date: Date

    var kind: DayKind = .free
    var budget: Double
    var walk: WalkLevel = .normal
    /// "Acordou 9:04" — hora de sair.
    var startAt: Date
    var lists: [String: ListMode] = [:]
    var text = ""
    var intent = DayIntent()
    var seed = 0
    var proposal: DayProposal?

    init(date: Date, region: Region, settings: Settings?, existing: PlannedDay?) {
        self.region = region
        self.date = region.calendar.startOfDay(for: date)
        budget = existing?.budget ?? settings?.perDayBudget ?? region.defaultBudget
        kind = existing?.kind ?? .free
        walk = existing?.walk ?? .normal
        let dayStart = settings?.dayStartMinutes ?? 570
        let start = region.calendar.date(byAdding: .minute, value: dayStart, to: self.date) ?? self.date
        // Hoje depois da hora padrão: sai agora (arredondado pros próximos 5 min).
        let now = AppClock.now
        if region.calendar.isDate(now, inSameDayAs: self.date), now > start {
            let minutes = Int(now.timeIntervalSince(self.date) / 60)
            startAt = region.calendar.date(byAdding: .minute, value: ((minutes + 4) / 5) * 5, to: self.date) ?? now
        } else {
            startAt = start
        }
    }

    var isToday: Bool { region.calendar.isDate(date, inSameDayAs: AppClock.now) }

    // MARK: Pedido

    /// Previsão do dia (do `SyncCoordinator`), usada no subtítulo e na regra de tempo do solver.
    var weather: DayWeather?

    func request(trip: TripInfo?, settings: Settings?, location: CLLocation?, flights: [DayFlight] = []) -> DayRequest {
        let cal = region.calendar
        let city = trip?.city(on: date, calendar: cal)
        let center = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude,
                                            longitude: city?.lng ?? region.defaultCenter.longitude)
        // Hoje sai de onde está; outro dia, do centro da cidade (ou da posição atual se estiver nela).
        var origin = center
        if let here = location, here.distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < 40_000 {
            origin = here.coordinate
        }
        return DayRequest(date: date, timeZone: region.timeZone, kind: kind, budget: budget, walk: walk, lists: lists,
                          intent: intent, startAt: startAt, origin: origin, cityId: city?.id ?? region.rawValue,
                          sameCityIds: Set((trip?.cities ?? []).filter { $0.name == city?.name && $0.id != city?.id }.map(\.id)),
                          daysLeftInCity: city.flatMap { trip?.daysLeft(in: $0, after: date, calendar: cal) },
                          weather: weather, walkMaxKm: settings?.walkMaxKm ?? 1.5,
                          oneMealPerWindow: settings?.oneMealPerWindow ?? true, cityCenter: center, seed: seed,
                          flights: flights)
    }

    func solve(catalog: [SolverPlace], trip: TripInfo?, settings: Settings?, location: CLLocation?, flights: [DayFlight] = []) -> DayProposal {
        DaySolver.solve(request(trip: trip, settings: settings, location: location, flights: flights), catalog: catalog)
    }

    func build(catalog: [SolverPlace], trip: TripInfo?, settings: Settings?, location: CLLocation?, flights: [DayFlight] = []) {
        proposal = solve(catalog: catalog, trip: trip, settings: settings, location: location, flights: flights)
        if let proposal { Log.solver.info("dia \(proposal.stops.count) paradas · \(proposal.predictedSpend) · \(proposal.explanation, privacy: .public)") }
    }

    func reshuffle(catalog: [SolverPlace], trip: TripInfo?, settings: Settings?, location: CLLocation?, flights: [DayFlight] = []) {
        seed += 1
        build(catalog: catalog, trip: trip, settings: settings, location: location, flights: flights)
    }

    /// "ou diga: …" → intenção; reflete na tela (tipo, andar, orçamento, listas) antes de montar.
    /// Texto já virou intenção (Foundation Models ou palavras-chave): reflete na tela.
    func apply(_ parsed: DayIntent) {
        intent = parsed
        if let k = parsed.kind { kind = k }
        if let w = parsed.walk { walk = w }
        if let b = parsed.budget { budget = b }
        // O texto liga/desliga listas só pela intenção (o solver lê `intent.roles` nas listas em auto).
        // Não vira toque explícito: "fica pro fim" em BH continua pedindo o toggle de verdade.
    }

    // MARK: Trocar

    func swap(_ stopId: String, with place: SolverPlace) {
        guard let proposal else { return }
        self.proposal = DaySolver.swap(stopId, with: place, in: proposal)
    }

    func skip(_ stopId: String) {
        guard let proposal else { return }
        self.proposal = DaySolver.skip(stopId, in: proposal)
    }

    // MARK: Aceitar

    /// Grava o `PlannedDay` aceito (substitui o que houver nesse dia).
    func accept(context: ModelContext) throws {
        guard let proposal else { return }
        let start = date
        let existing = try context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == start }))
        for day in existing { context.delete(day) }
        let places = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Place>()).map { ($0.id, $0) })
        let day = PlannedDay(date: date, kind: intent.kind ?? kind, budget: intent.budget ?? budget, walk: walk, accepted: true)
        context.insert(day)
        for (i, s) in proposal.stops.enumerated() {
            let stop = Stop(place: places[s.place.id], at: s.at, order: i, isAnchor: s.isAnchor, isException: s.isException)
            context.insert(stop)
            day.stops.append(stop)
        }
        try context.save()
        Log.solver.info("dia aceito \(BoardDates(timeZone: self.region.timeZone).dayString(self.date), privacy: .public)")
    }
}

extension Array where Element == Place {
    @MainActor var solverCatalog: [SolverPlace] { map(SolverPlace.init) }
}
