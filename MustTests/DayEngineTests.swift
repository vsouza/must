import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Fixtures do motor do dia v8: o seed JP (Udatsu reservada às 19:00 do dom 15/11) + a aula de sushi com ingresso às 10:00,
/// saindo de Naka-Meguro (o hotel) às 08:30.
enum DayFixtures {
    final class Token {}

    static let region = Region.jp
    static let dates = BoardDates(timeZone: Region.jp.timeZone)
    static let day = dates.day(from: "2026-11-15")!
    static let naka = CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)

    static func time(_ hhmm: String, on date: Date = day) -> Date { dates.time(hhmm, on: date)! }

    static func seed(_ region: Region = .jp) -> [SolverPlace] {
        let board = try! BoardCodec.decode(Data(contentsOf: region.seedURL(in: Bundle(for: Token.self))!))
        let lists = Dictionary(uniqueKeysWithValues: board.lists.map { ($0.id, $0) })
        return board.places.map { SolverPlace($0, color: lists[$0.listId]?.color ?? .eat, kind: lists[$0.listId]?.kind ?? .place) }
    }

    static func sushiClass() -> SolverPlace {
        SolverPlace(id: "x-sushi", name: "Aula de sushi · Tsukiji", nameLocal: nil, listId: "do", listColor: .night, sub: nil,
                    cityId: "tokyo1", area: "Tsukiji", lat: 35.6654, lng: 139.7707, price: 12_000, windows: [], hours: nil,
                    reservation: nil, saveForEnd: false, allowBudgetException: false, queueMinutes: nil, notes: "",
                    sourceKind: nil, done: false, kind: .experience,
                    extra: PlaceExtra(experience: ExperienceInfo(supplier: .viator, durationMinutes: 120)),
                    tickets: [Ticket(at: time("10:00"), confirmation: "BR-7K2M-9931")])
    }

    static func catalog() -> [SolverPlace] { seed() + [sushiClass()] }

    static func request(pace: Pace = .normal, startAt: String = "08:30", until: String? = nil, golden: Bool = true,
                        travel: TravelMatrix? = nil, focus: String? = nil) -> DayRequest {
        DayRequest(date: day, timeZone: region.timeZone, kind: .free, budget: 15_000, startAt: time(startAt), origin: naka,
                   cityId: "tokyo1", daysLeftInCity: 2, weather: nil, cityCenter: naka, travel: travel,
                   focus: focus.map { .area(id: $0, includeNeighbors: true, maxHopMinutes: 15) },
                   region: region, pace: pace, goldenPhoto: golden, endAt: until.map { time($0) })
    }

    static func source(pace: Pace = .normal, includes: Set<DayInclude> = [.micro, .goldenPhoto], startAt: String = "08:30",
                       travel: TravelMatrix? = nil, catalog: [SolverPlace] = catalog()) -> DaySource {
        DaySource(region: region, request: request(pace: pace, startAt: startAt, golden: includes.contains(.goldenPhoto), travel: travel),
                  catalog: catalog, hotel: naka, cityName: "Tóquio", dayNumber: 5, spent: 0, walkMaxKm: 1.5,
                  canFetchTravel: false, includes: includes, focusArea: nil)
    }

    static let lastTrain = DayLastTrain(line: "Hibiya Ginza → Naka-Meguro", at: time("00:12", on: dates.day(from: "2026-11-16")!))

    /// Motor real com a fonte fixa (sem SwiftData, sem rede).
    static func engine(pace: Pace = .normal, includes: Set<DayInclude> = [.micro, .goldenPhoto], startAt: String = "08:30",
                       catalog: [SolverPlace] = catalog()) -> DayEngineV8 {
        let src = source(pace: pace, includes: includes, startAt: startAt, catalog: catalog)
        return DayEngineV8(source: { _ in src }, lastTrain: { _, _, _ in DayFixtures.lastTrain })
    }

    static func build(pace: Pace = .normal, includes: Set<DayInclude> = [.micro, .goldenPhoto], startAt: String = "08:30",
                      catalog: [SolverPlace] = catalog()) async -> DayPlan {
        await engine(pace: pace, includes: includes, startAt: startAt, catalog: catalog)
            .build(area: nil, pace: pace, budget: 15_000, until: time("23:30"), includes: includes)
    }

    static func dump(_ plan: DayPlan) -> String {
        plan.stops.map { s in
            let leg = plan.leg(before: s).map { "   ↳ \($0.mode.rawValue) \($0.minutes) · \($0.detail)\n" } ?? ""
            return leg + "\(Region.jp.timeString(s.start))–\(Region.jp.timeString(s.end)) \(s.kind.rawValue) \(s.label) · \(s.note)"
        }.joined(separator: "\n")
    }
}

/// Motor do dia v8 (prompt 23 §3): ritmo 6/9/12, micro-paradas, deslocamentos, último trem, determinismo, offline.
struct DayEngineTests {
    private func micros(_ plan: DayPlan) -> [DayStop] { plan.stops.filter { $0.kind == .micro } }
    private func musts(_ plan: DayPlan) -> [DayStop] { plan.stops.filter { $0.kind == .must } }

    @Test func normalPaceIsNineStopsWithAnchorsMustsAndMicros() async {
        let plan = await DayFixtures.build(pace: .normal)
        #expect(plan.stops.count == 9, "\(DayFixtures.dump(plan))")
        #expect((3...4).contains(plan.anchors.count))
        #expect((2...3).contains(musts(plan).count))
        #expect((3...4).contains(micros(plan).count))
        #expect(plan.pace == .normal)
        // Âncoras: o ingresso das 10:00, a Udatsu às 19:00 e a foto no golden.
        #expect(plan.anchors.contains { $0.anchor == .ticket && $0.start == DayFixtures.time("10:00") && $0.tag == "QR" })
        #expect(plan.anchors.contains { $0.anchor == .reservation && $0.placeId == "j01" && $0.tag == "RES" })
        #expect(plan.anchors.contains { $0.anchor == .golden && $0.tag == "SOL" })
    }

    @Test func calmIsSixAndIntenseIsTwelve() async {
        let calm = await DayFixtures.build(pace: .calm)
        let intense = await DayFixtures.build(pace: .intense)
        #expect(calm.stops.count == 6, "\(DayFixtures.dump(calm))")
        #expect(intense.stops.count == 12, "\(DayFixtures.dump(intense))")
        #expect(calm.pace == .calm && intense.pace == .intense)
    }

    @Test func microStopsAreNeverAnchorsLastTenToFortyMinutesAndFitTheGap() async {
        for pace in Pace.allCases {
            let plan = await DayFixtures.build(pace: pace)
            #expect(!micros(plan).isEmpty)
            for (i, stop) in plan.stops.enumerated() where stop.kind == .micro {
                #expect(stop.anchor == nil)
                #expect(stop.micro != nil)
                #expect((10...40).contains(stop.minutes), "\(stop.label) \(stop.minutes) min")
                // Cabe no buraco: chega depois da anterior (com o deslocamento) e sai a tempo da seguinte.
                if i > 0 {
                    let prev = plan.stops[i - 1]
                    #expect(stop.start >= prev.end.addingTimeInterval(Double(plan.leg(before: stop)?.minutes ?? 0) * 60))
                }
                if i + 1 < plan.stops.count {
                    let next = plan.stops[i + 1]
                    #expect(DayNowRules.leaveTime(to: next, in: plan) >= stop.end, "\(stop.label) → \(next.label)")
                }
            }
        }
    }

    @Test func microStopsComeAndGoWithoutMovingTheRest() async {
        let with = await DayFixtures.build(pace: .normal, includes: [.micro, .goldenPhoto])
        let without = await DayFixtures.build(pace: .normal, includes: [.goldenPhoto])
        func board(_ p: DayPlan) -> [String] { p.stops.filter { $0.kind != .micro }.map { "\($0.id)@\($0.start)-\($0.end)" } }
        #expect(micros(without).isEmpty)
        #expect(board(with) == board(without))
        // Tirar as micro-paradas de um dia pronto dá o mesmo board, com as pernas religadas.
        let stripped = DayComposer.withoutMicros(with, region: .jp)
        #expect(board(stripped) == board(without))
        #expect(stripped.legs.map(\.from) == without.legs.map(\.from))
    }

    @Test func legsLinkConsecutiveStopsWithModeMinutesAndDetail() async {
        let plan = await DayFixtures.build(pace: .normal)
        #expect(plan.legs.count >= 4)
        let ids = plan.stops.map(\.id)
        for leg in plan.legs {
            let from = ids.firstIndex(of: leg.from), to = ids.firstIndex(of: leg.to)
            #expect(from != nil && to == from.map { $0 + 1 })
            #expect(leg.minutes > 0)
            #expect(!leg.detail.isEmpty)
            #expect(leg.detail.contains("\(leg.minutes) min"))
        }
        #expect(plan.legs.contains { $0.mode == .walk && $0.detail.hasPrefix("a pé") })
        #expect(plan.legs.contains { $0.mode != .walk })
        // Tsukiji → Ginza: a linha vem da tabela de bairros (offline).
        #expect(plan.legs.contains { $0.detail.contains("Hibiya") })
    }

    @Test func lastTrainClosesTheDay() async {
        let plan = await DayFixtures.build(pace: .normal)
        #expect(plan.lastTrain == DayFixtures.lastTrain)
        #expect(plan.stops.allSatisfy { $0.start < DayFixtures.lastTrain.at })
    }

    @Test func sameInputGivesTheSameDay() async {
        for pace in Pace.allCases {
            let a = await DayFixtures.build(pace: pace)
            let b = await DayFixtures.build(pace: pace)
            #expect(a == b)
        }
        // A mesma montagem, de novo pelo composer puro, também.
        let src = DayFixtures.source()
        let proposal = DaySolver.solve(src.request, catalog: src.catalog)
        let boards = proposal.stops.map { DayComposer.BoardStop(place: $0.place, start: $0.at, end: $0.end, isAnchor: $0.isAnchor, reason: $0.reason) }
        #expect(DayEngineV8.compose(src, boards: boards, lastTrain: nil) == DayEngineV8.compose(src, boards: boards.reversed(), lastTrain: nil))
    }

    @Test func offlineLegsAreEstimatesAndRoutesTimesAreLive() async throws {
        let plan = await DayFixtures.build(pace: .normal)
        #expect(plan.legs.allSatisfy { !$0.live })
        // Com o tempo real do Routes pra um par, a perna desse par vira `live` com os minutos do Routes.
        let walk = try #require(plan.legs.first { $0.mode == .walk })
        let a = try #require(plan.stops.first { $0.id == walk.from }.flatMap(DayComposer.coordinate))
        let b = try #require(plan.stops.first { $0.id == walk.to }.flatMap(DayComposer.coordinate))
        let matrix = TravelMatrix(walk: [TravelMatrix.key(a, b): 7], transit: [:])
        let legs = DayComposer.legs(for: plan.stops, region: .jp, walkMaxKm: 1.5, travel: matrix, areas: AreaCatalog.areas(for: .jp))
        let live = try #require(legs.first { $0.from == walk.from })
        #expect(live.live)
        #expect(live.minutes == 7)
        #expect(legs.filter(\.live).count == 1)
    }

    @Test func engineNeverWaitsForTheNetworkWhenItCannotFetch() async {
        // `canFetchTravel = false` (offline / Modo de Pouco Dados): monta na hora, só com a estimativa.
        let clock = ContinuousClock()
        let start = clock.now
        let plan = await DayFixtures.build(pace: .normal)
        #expect(clock.now - start < .seconds(2))
        #expect(!plan.stops.isEmpty)
    }

    @Test func untilCutsFreeStopsButKeepsBookings() async {
        let src = DayFixtures.source(pace: .intense)
        var request = src.request
        request.endAt = DayFixtures.time("21:00")
        let proposal = DaySolver.solve(request, catalog: src.catalog)
        #expect(proposal.stops.filter { !$0.isAnchor }.allSatisfy { $0.end <= DayFixtures.time("21:15") })
        #expect(proposal.stops.contains { $0.place.id == "j01" })
    }

    @Test func emptySourceGivesAnEmptyDay() async {
        let engine = DayEngineV8(source: { _ in nil }, lastTrain: { _, _, _ in nil })
        let plan = await engine.build(area: "shinjuku", pace: .calm, budget: 8_000, until: DayFixtures.time("23:30"), includes: [.micro])
        #expect(plan.stops.isEmpty)
        #expect(plan.pace == .calm)
        #expect(plan.area == "shinjuku")
    }

    @Test func stubStillServesTheQADay() async {
        let stub = DayEngineStub()
        let plan = await stub.build(area: nil, pace: .normal, budget: 12_000, until: DayFixtures.time("23:30"), includes: [])
        #expect(plan.stops.count == 9)
        #expect(plan.anchors.count == 3)
        #expect(plan.stops.filter { $0.kind == .micro }.allSatisfy { (10...40).contains($0.minutes) })
    }
}

/// Dia aceito (SwiftData) → `DayPlan`: aceitar e reler dá a mesma Linha; sem o dia guardado, a regeração é estável.
@MainActor
struct DayEngineAcceptTests {
    private func seeded() throws -> ModelContainer {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try RegionStore.seedIfEmpty(c.mainContext, region: .jp, bundle: Bundle(for: DayFixtures.Token.self))
        return c
    }

    private func source(_ context: ModelContext, pace: Pace = .normal) -> DaySource? {
        DayEngineV8.source(context: context, region: .jp,
                           ask: DayAsk(date: DayFixtures.day, area: nil, pace: pace, budget: 15_000, until: DayFixtures.time("23:30"),
                                       includes: [.micro, .goldenPhoto]),
                           location: nil, weather: { _, _ in nil }, online: false)
    }

    @Test func acceptedDayReadsBackTheSameLine() async throws {
        let container = try seeded()
        let ctx = container.mainContext
        let key = DayPlanPrefs.key(region: .jp, date: DayFixtures.day)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let src = try #require(source(ctx))
        let engine = DayEngineV8(source: { _ in src }, lastTrain: { _, _, _ in DayFixtures.lastTrain })
        let plan = await engine.build(on: DayFixtures.day, area: nil, pace: .normal, budget: 15_000, until: DayFixtures.time("23:30"),
                                      includes: [.micro, .goldenPhoto])
        #expect(!plan.stops.isEmpty)
        #expect(engine.plan(for: DayFixtures.day, region: .jp, context: ctx) == nil)
        try engine.accept(plan, region: .jp, context: ctx)
        let read = try #require(engine.plan(for: DayFixtures.day, region: .jp, context: ctx))
        #expect(read == plan)
        // Só as paradas do board viram `Stop`; reserva e ingresso ficam âncora.
        let saved = try #require(try ctx.fetch(FetchDescriptor<PlannedDay>()).first { $0.date == DayFixtures.day })
        #expect(saved.stops.count == plan.stops.filter { $0.kind != .micro }.count)
        #expect(saved.orderedStops.first { $0.place?.id == "j01" }?.isAnchor == true)

        // Sem o dia guardado (aceito por outro caminho): as micro-paradas voltam geradas, iguais nas duas leituras.
        UserDefaults.standard.removeObject(forKey: key)
        let again = try #require(engine.plan(for: DayFixtures.day, region: .jp, context: ctx))
        let twice = try #require(engine.plan(for: DayFixtures.day, region: .jp, context: ctx))
        #expect(again == twice)
        #expect(again.stops.filter { $0.kind != .micro }.map(\.placeId) == plan.stops.filter { $0.kind != .micro }.map(\.placeId))
        #expect(!again.stops.filter { $0.kind == .micro }.isEmpty)

        // "Feito" anda sem mexer na Linha.
        try engine.accept(plan, region: .jp, context: ctx)
        let first = try #require(try ctx.fetch(FetchDescriptor<PlannedDay>()).first { $0.date == DayFixtures.day }?.orderedStops.first)
        first.done = true
        try ctx.save()
        let done = try #require(engine.plan(for: DayFixtures.day, region: .jp, context: ctx))
        #expect(done.stops.map(\.id) == plan.stops.map(\.id))
        #expect(done.stops.first { $0.placeId == first.place?.id }?.done == true)
    }

    @Test func liveActivityShowsLeaveNextAndLastTrain() throws {
        let qa = DayEngineStub.qaDay
        let state = try #require(OutsideBridge.liveState(qa, region: .jp, now: DayFixtures.time("14:20"), here: nil, eta: nil))
        // Indo pro Fuunji (parada 4 de 9): chegue às 14:15 por causa da fila; depois, o Gyoen; último trem 00:40.
        #expect(state.number == 4)
        #expect(state.total == 9)
        #expect(state.name == "Fuunji · tsukemen")
        #expect(state.arriveBy.map { Region.jp.timeString($0) } == "14:15")
        #expect(state.leaveAt.map { Region.jp.timeString($0) } == "13:46")
        #expect(state.nextName == "Shinjuku Gyoen · golden")
        #expect(state.lastTrainLine == "Yamanote")
        #expect(state.lastTrainAt == qa.lastTrain?.at)
        #expect(state.detail.contains("chegue 14:15"))
        // Depois da última parada: nada.
        #expect(OutsideBridge.liveState(qa, region: .jp, now: DayFixtures.time("23:40"), here: nil, eta: nil) == nil)
    }
}
