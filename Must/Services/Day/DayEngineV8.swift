import CoreLocation
import Foundation
import SwiftData

/// Pedido do Montar v8, como o motor recebe.
struct DayAsk: Sendable, Hashable {
    /// Dia a montar; `nil` = hoje (no fuso da região).
    var date: Date?
    var area: String?
    var pace: Pace
    var budget: Double
    /// "até 23:30": só a hora vale (aplicada no dia pedido; de madrugada = dia seguinte).
    var until: Date?
    var includes: Set<DayInclude>
}

/// O que o motor lê do aparelho antes de montar: rápido, no main, sem rede. Depois disso tudo roda fora do main.
struct DaySource: Sendable {
    var region: Region
    /// Pedido do solver já com a cidade, a origem, a previsão, os voos e o ritmo (`DayPlanner.request`).
    var request: DayRequest
    var catalog: [SolverPlace]
    /// Onde dorme: café da manhã e descanso.
    var hotel: CLLocationCoordinate2D
    var cityName: String?
    var dayNumber: Int?
    var spent: Double
    var walkMaxKm: Double
    /// Online, sem Modo de Pouco Dados: pode pedir a matriz de tempos (que tem cache em disco e cota).
    var canFetchTravel: Bool
    var includes: Set<DayInclude>
    var focusArea: String?
}

/// Motor do dia v8 (prompt 23 §3) sobre o solver de sempre: o `DaySolver` escolhe âncoras e Musts (todas as regras:
/// uma refeição por janela, reservas/ingressos, fica pro fim, orçamento, cidade, tipo de dia, andar, bairro + vizinhos,
/// e as regras de Roma); o `DayComposer` gera as micro-paradas, os deslocamentos e o último trem.
/// Sem estado: mesma entrada → mesmo dia. A rede só entra pra tempos reais do Routes, com cache e 2 s de teto.
struct DayEngineV8: DayEngine {
    typealias Source = @MainActor @Sendable (DayAsk) -> DaySource?
    typealias LastTrainLookup = @MainActor @Sendable (Region, Date, CLLocationCoordinate2D?) -> DayLastTrain?

    private let source: Source
    private let lastTrain: LastTrainLookup
    private let travelTimeout: Duration

    init(source: @escaping Source, lastTrain: @escaping LastTrainLookup = { DayEngineV8.lastTrain(region: $0, date: $1, near: $2) },
         travelTimeout: Duration = .seconds(2)) {
        self.source = source
        self.lastTrain = lastTrain
        self.travelTimeout = travelTimeout
    }

    /// O motor do app: lê a região atual do `RegionStore` e o GPS, a previsão e a rede dos `Services`.
    @MainActor
    init(store: RegionStore, services: Services) {
        self.init(source: { ask in
            DayEngineV8.source(context: store.container.mainContext, region: store.region, ask: ask,
                               location: services.location.current,
                               weather: { date, trip in services.sync.weather(on: date, region: store.region, trip: trip) },
                               online: services.connectivity.status == .online)
        })
    }

    // MARK: DayEngine

    func build(area: String?, pace: Pace, budget: Double, until: Date, includes: Set<DayInclude>) async -> DayPlan {
        await build(DayAsk(date: nil, area: area, pace: pace, budget: budget, until: until, includes: includes))
    }

    func build(on date: Date, area: String?, pace: Pace, budget: Double, until: Date, includes: Set<DayInclude>) async -> DayPlan {
        await build(DayAsk(date: date, area: area, pace: pace, budget: budget, until: until, includes: includes))
    }

    @MainActor func plan(for date: Date, region: Region, context: ModelContext) -> DayPlan? {
        Self.accepted(on: date, region: region, context: context, lastTrain: lastTrain)
    }

    // MARK: Montar

    func build(_ ask: DayAsk) async -> DayPlan {
        guard var src = await source(ask) else {
            let date = ask.date ?? AppClock.now
            return DayPlan(date: date, title: "", dayNumber: nil, area: ask.area, stops: [], legs: [], lastTrain: nil,
                           pace: ask.pace, budget: ask.budget, includes: ask.includes)
        }
        if src.canFetchTravel, src.request.travel == nil {
            src.request.travel = await Self.fetchTravel(src, timeout: travelTimeout)
        }
        let proposal = DaySolver.solve(src.request, catalog: src.catalog)
        Log.solver.info("dia v8 \(proposal.stops.count) do board · ritmo \(ask.pace.rawValue) · \(proposal.explanation, privacy: .public)")
        let boards = proposal.stops.map {
            DayComposer.BoardStop(place: $0.place, start: $0.at, end: $0.end, isAnchor: $0.isAnchor, reason: $0.reason,
                                  isException: $0.isException)
        }
        let last = await lastTrain(src.region, src.request.date, boards.last.map { CLLocationCoordinate2D(latitude: $0.place.lat, longitude: $0.place.lng) })
        return Self.compose(src, boards: boards, lastTrain: last)
    }

    /// Junta a fonte e as paradas do solver no `DayPlan` (puro).
    static func compose(_ src: DaySource, boards: [DayComposer.BoardStop], lastTrain: DayLastTrain?) -> DayPlan {
        DayComposer.compose(DayComposer.Input(
            date: src.request.date, region: src.region, stops: boards, hotel: src.hotel, pace: src.request.pace ?? .normal,
            includes: src.includes, walkMaxKm: src.walkMaxKm, travel: src.request.travel, lastTrain: lastTrain,
            dayNumber: src.dayNumber, budget: src.request.budget, spent: src.spent, focusArea: src.focusArea,
            cityName: src.cityName, catalog: src.catalog))
    }

    /// Tempos reais (Routes Matrix) da origem e das 9 candidatas mais perto — o mesmo pedido do Montar v7, com o cache em
    /// disco de 24 h. Passou do teto, segue com a estimativa (nunca espera a rede).
    static func fetchTravel(_ src: DaySource, timeout: Duration) async -> TravelMatrix? {
        let req = src.request
        let candidates = src.catalog
            .filter { !$0.done && req.isInCity($0.cityId) && ($0.lat != 0 || $0.lng != 0) }
            .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            .sorted { DaySolver.streetKm(req.origin, $0) < DaySolver.streetKm(req.origin, $1) }
        let points = TravelMatrixLoader.points(origin: req.origin, candidates: candidates)
        let departAt = max(req.startAt, AppClock.now)
        let day = BoardDates(timeZone: src.region.timeZone).dayString(req.date)
        let modes = GoogleRoutes.matrixModes(for: src.region)
        return await withTaskGroup(of: TravelMatrix?.self) { group in
            group.addTask { await TravelMatrixLoader.load(points: points, departAt: departAt, day: day, modes: modes) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: Fonte (main)

    /// Lê o board, a viagem, os ajustes e os voos do dia, e monta o `DayRequest` como o Montar v7 (`DayPlanner`).
    @MainActor
    static func source(context: ModelContext, region: Region, ask: DayAsk, location: CLLocation?,
                       weather: (Date, TripInfo?) -> DayWeather?, online: Bool) -> DaySource? {
        let cal = region.calendar
        let date = cal.startOfDay(for: ask.date ?? AppClock.now)
        let settings = (try? context.fetch(FetchDescriptor<Settings>()))?.first
        let trip = (try? context.fetch(FetchDescriptor<TripInfo>()))?.first
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let flights = FlightRules.dayFlights(context.flights(), on: date, region: region)
        let planner = DayPlanner(date: date, region: region, settings: settings, existing: nil)
        planner.budget = ask.budget
        planner.pace = ask.pace
        planner.goldenPhoto = ask.includes.contains(.goldenPhoto)
        planner.until = ask.until.map { untilOn(date, $0, calendar: cal) }
        planner.focusArea = ask.area
        planner.weather = weather(date, trip)
        let request = planner.request(trip: trip, settings: settings, location: location, flights: flights)
        let city = trip?.city(on: date, calendar: cal)
        return DaySource(region: region, request: request, catalog: places.solverCatalog,
                         hotel: hotel(region: region, trip: trip, date: date), cityName: city?.name,
                         dayNumber: dayNumber(trip: trip, date: date, calendar: cal),
                         spent: spent(context: context, region: region, date: date),
                         walkMaxKm: DaySolver.effectiveWalkMax(walkMaxKm: settings?.walkMaxKm ?? 1.5, walk: request.walk),
                         canFetchTravel: online && DevOverrides.liveData, includes: ask.includes, focusArea: ask.area)
    }

    /// A hora de `until` no dia pedido (00:00–04:59 = madrugada do dia seguinte).
    static func untilOn(_ date: Date, _ until: Date, calendar: Calendar) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: until)
        let hour = c.hour ?? 23, minute = c.minute ?? 30
        let day = hour < 5 ? calendar.date(byAdding: .day, value: 1, to: date) ?? date : date
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? until
    }

    /// Onde dorme: o bairro do `TripInfo.home` (centroide da tabela), senão o centro da cidade do dia, senão o da região.
    @MainActor
    static func hotel(region: Region, trip: TripInfo?, date: Date) -> CLLocationCoordinate2D {
        if let home = trip?.home {
            let key = AreaName.key(home)
            if let area = AreaCatalog.areas(for: region).first(where: { a in ([a.name] + a.aliases).contains { AreaName.key($0) == key } }) {
                return area.centroid.clCoordinate
            }
        }
        if let city = trip?.city(on: date, calendar: region.calendar) {
            return CLLocationCoordinate2D(latitude: city.lat, longitude: city.lng)
        }
        return region.defaultCenter
    }

    /// Dia da viagem (1 = primeiro dia). `nil` fora da viagem ou sem datas (BH).
    @MainActor
    static func dayNumber(trip: TripInfo?, date: Date, calendar: Calendar) -> Int? {
        guard let trip, let start = trip.start, let end = trip.end else { return nil }
        let day = calendar.startOfDay(for: date)
        guard day >= calendar.startOfDay(for: start), day <= calendar.startOfDay(for: end) else { return nil }
        return (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: day).day ?? 0) + 1
    }

    @MainActor
    static func spent(context: ModelContext, region: Region, date: Date) -> Double {
        let range = region.dayRange(date)
        let start = range.lowerBound, end = range.upperBound
        let expenses = (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.at >= start && $0.at < end }))) ?? []
        return expenses.reduce(0) { $0 + $1.amount }
    }

    /// Último trem/metrô do dia perto da última parada: tabela do Japão (`LastTrains`), metrô de BH, metrô de Roma.
    @MainActor
    static func lastTrain(region: Region, date: Date, near: CLLocationCoordinate2D?) -> DayLastTrain? {
        let cal = region.calendar
        switch region {
        case .it:
            // TODO(v8:E): `TransitLoader.fileName(.it)` cai no bh-lines; até ter as linhas de Roma, o metrô fixo do Bolso.
            return DayComposer.romeLastMetro(on: date, calendar: cal)
        case .jp, .bh:
            guard let last = LastTrains.home(region: region, near: near, transit: TransitLoader.load(region)),
                  let at = DayComposer.clock(last.time, on: date, calendar: cal) else { return nil }
            let line = last.label.hasPrefix("Último ") ? String(last.label.dropFirst("Último ".count)) : last.label
            return DayLastTrain(line: line == "Metrô até" ? "Metrô" : line, at: at)
        }
    }

    // MARK: Dia aceito (SwiftData → v8)

    @MainActor private static var memo: [String: DayPlan] = [:]

    /// O dia aceito numa data, no formato v8: as paradas gravadas (`Stop`) com as micro-paradas geradas de novo, do mesmo
    /// jeito (ritmo e "incluir" guardados no aceite), pra Linha voltar igual. `nil` = nada aceito.
    @MainActor
    static func accepted(on day: Date, region: Region, context: ModelContext,
                         lastTrain: LastTrainLookup = { DayEngineV8.lastTrain(region: $0, date: $1, near: $2) }) -> DayPlan? {
        let cal = region.calendar
        let date = cal.startOfDay(for: day)
        guard let planned = (try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == date })))?.first,
              planned.accepted else { return nil }
        let stops = planned.orderedStops.filter { $0.place != nil }
        let prefs = DayPlanPrefs.load(region: region, date: date)
        let placeCount = (try? context.fetchCount(FetchDescriptor<Place>())) ?? 0
        let signature = ([region.rawValue, "\(date.timeIntervalSince1970)", "\(planned.budget)", planned.focusAreaId ?? "-",
                          "\(prefs.pace.rawValue)", prefs.includes.map(\.rawValue).sorted().joined(separator: ","), "\(placeCount)"]
                         + stops.map { "\($0.place!.id)@\($0.at.timeIntervalSince1970)\($0.done ? "+" : "")\($0.isAnchor ? "!" : "")" })
            .joined(separator: "|")
        let spent = spent(context: context, region: region, date: date)
        // O dia que foi aceito (com as micro-paradas e os fins exatos do solver) volta igual enquanto as paradas gravadas
        // forem as mesmas; só o "feito" e o gasto andam.
        if var stored = prefs.plan {
            let board = stored.stops.filter { $0.kind != .micro }
            if board.map(\.placeId) == stops.map({ $0.place?.id }), zip(board, stops).allSatisfy({ abs($0.start.timeIntervalSince($1.at)) < 60 }) {
                let done = Dictionary(stops.map { ($0.place!.id, $0.done) }, uniquingKeysWith: { a, b in a || b })
                for i in stored.stops.indices where stored.stops[i].kind != .micro {
                    stored.stops[i].done = stored.stops[i].placeId.flatMap { done[$0] } ?? stored.stops[i].done
                }
                for i in stored.stops.indices where stored.stops[i].kind == .micro {
                    stored.stops[i].done = stored.stops[(i + 1)...].first { $0.kind != .micro }?.done ?? false
                }
                stored.spent = spent
                return stored
            }
        }
        if var hit = memo[signature] {
            hit.spent = spent
            return hit
        }
        let trip = (try? context.fetch(FetchDescriptor<TripInfo>()))?.first
        let settings = (try? context.fetch(FetchDescriptor<Settings>()))?.first
        let catalog = ((try? context.fetch(FetchDescriptor<Place>())) ?? []).solverCatalog
        let boards = stops.map { stop -> DayComposer.BoardStop in
            let place = SolverPlace(stop.place!)
            let timing = boardTiming(place, at: stop.at, isAnchor: stop.isAnchor, region: region)
            return DayComposer.BoardStop(place: place, start: stop.at, end: timing.end, isAnchor: stop.isAnchor, reason: timing.reason,
                                         isException: stop.isException, done: stop.done)
        }
        let last = lastTrain(region, date, boards.last.map { CLLocationCoordinate2D(latitude: $0.place.lat, longitude: $0.place.lng) })
        let plan = DayComposer.compose(DayComposer.Input(
            date: date, region: region, stops: boards, hotel: hotel(region: region, trip: trip, date: date), pace: prefs.pace,
            includes: prefs.includes, walkMaxKm: DaySolver.effectiveWalkMax(walkMaxKm: settings?.walkMaxKm ?? 1.5, walk: planned.walk),
            travel: nil, lastTrain: last, dayNumber: dayNumber(trip: trip, date: date, calendar: cal), budget: planned.budget,
            spent: spent, focusArea: planned.focusAreaId, cityName: trip?.city(on: date, calendar: cal)?.name, catalog: catalog))
        if memo.count > 24 { memo.removeAll() }
        memo[signature] = plan
        return plan
    }

    /// Fim e motivo de uma parada gravada, com as mesmas contas do solver (reserva, turno de Roma, ingresso, Appia).
    static func boardTiming(_ p: SolverPlace, at: Date, isAnchor: Bool, region: Region) -> (end: Date, reason: String) {
        let cal = region.calendar
        func plus(_ minutes: Int) -> Date { at.addingTimeInterval(Double(minutes) * 60) }
        guard isAnchor else {
            let minutes = p.role == .photo ? 45 : DaySolver.duration(p) + (p.queueMinutes ?? 0)
            return (plus(minutes), "")
        }
        if let r = p.reservation, abs(r.at.timeIntervalSince(at)) < 60 {
            if region == .it, let shift = ItalyRules.shiftMinutes(p) { return (plus(shift), "reserva · turno") }
            return (plus(p.role == .eat ? 105 : p.role.duration), "reserva")
        }
        let ticketed = p.tickets.contains { abs($0.at.timeIntervalSince(at)) < 60 }
            || (p.extra?.sessions ?? []).contains { $0.bought && abs($0.at.timeIntervalSince(at)) < 60 }
        if ticketed {
            let length = p.extra?.art?.durationMinutes ?? p.extra?.experience?.durationMinutes ?? (p.kind == .sport ? 150 : 120)
            return (plus(length), "ingresso")
        }
        if region == .it, ItalyRules.isAppia(p), cal.component(.weekday, from: at) == 1 {
            return (plus(max(ItalyRules.appiaMinutes, DaySolver.duration(p))), "domingo sem carros")
        }
        return (plus(p.role == .eat ? 105 : p.role.duration), "reserva")
    }

    // MARK: Aceitar

    /// Grava o dia aceito (substitui o que houver na data): as paradas do board viram `Stop`; as micro-paradas não são
    /// gravadas, voltam geradas do mesmo jeito (o ritmo e o "incluir" ficam em `DayPlanPrefs`).
    @MainActor
    static func save(_ plan: DayPlan, region: Region, context: ModelContext) throws {
        let date = region.calendar.startOfDay(for: plan.date)
        for day in (try context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == date }))) { context.delete(day) }
        let places = Dictionary(try context.fetch(FetchDescriptor<Place>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let day = PlannedDay(date: date, kind: .free, budget: plan.budget, walk: .normal, accepted: true)
        day.focusAreaId = plan.area
        context.insert(day)
        for (i, s) in plan.stops.filter({ $0.kind != .micro }).enumerated() {
            guard let id = s.placeId, let place = places[id] else { continue }
            let stop = Stop(place: place, at: s.start, order: i, done: s.done,
                            isAnchor: s.isBooked || s.anchor == .sunday, isException: s.isException)
            context.insert(stop)
            day.stops.append(stop)
        }
        try context.save()
        DayPlanPrefs.save(DayPlanPrefs(pace: plan.pace, includes: plan.includes, plan: plan), region: region, date: date)
        Log.solver.info("dia v8 aceito \(BoardDates(timeZone: region.timeZone).dayString(date), privacy: .public) · \(plan.stops.count) paradas")
    }
}

extension DayEngine {
    /// Aceitar o dia do Montar: grava e pede a permissão dos avisos do guia (só aqui, como no Montar v7).
    @MainActor
    func accept(_ plan: DayPlan, region: Region, context: ModelContext, origin: CLLocationCoordinate2D? = nil) throws {
        try DayEngineV8.save(plan, region: region, context: context)
        guard !DebugFlags.isTestHost else { return }
        Task { await GuideNudgeScheduler.refresh(context: context, region: region, origin: origin, askPermission: true) }
    }
}

/// Ritmo e "incluir" de um dia aceito (o `PlannedDay` não tem esses campos nesta rodada): UserDefaults por região e dia.
struct DayPlanPrefs: Codable, Hashable, Sendable {
    var pace: Pace = .normal
    var includes: Set<DayInclude> = [.micro, .goldenPhoto]
    /// O dia como foi aceito (alguns KB): a Linha volta exatamente igual enquanto as paradas gravadas não mudarem.
    var plan: DayPlan? = nil

    static func key(region: Region, date: Date) -> String {
        "day.v8.\(region.rawValue).\(BoardDates(timeZone: region.timeZone).dayString(date))"
    }

    static func load(region: Region, date: Date, defaults: UserDefaults = .standard) -> DayPlanPrefs {
        guard let data = defaults.data(forKey: key(region: region, date: date)),
              let prefs = try? JSONDecoder().decode(DayPlanPrefs.self, from: data) else { return DayPlanPrefs() }
        return prefs
    }

    static func save(_ prefs: DayPlanPrefs, region: Region, date: Date, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults.set(data, forKey: key(region: region, date: date))
    }
}
