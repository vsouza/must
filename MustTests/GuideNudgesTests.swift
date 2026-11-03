import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Avisos do guia (prompt 18 · C.17): geração, espaçamento de 45 min, prioridade, só futuro e reagendar só os `guide.*`.
@MainActor
struct GuideNudgesTests {
    private final class Token {}

    static let bh = Region.bh.timeZone
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let savassi = CLLocationCoordinate2D(latitude: -19.9385, longitude: -43.9343)
    static let centro = CLLocationCoordinate2D(latitude: -19.9191, longitude: -43.9386)

    /// Dia de BH (terça 03/11/2026) à hora dada.
    func bhTime(_ hhmm: String) -> Date {
        let boards = BoardDates(timeZone: Self.bh)
        return boards.time(hhmm, on: boards.day(from: "2026-11-03")!)!
    }

    func stop(_ id: String, _ name: String, at start: Date, _ c: CLLocationCoordinate2D = centro, photo: Bool = false,
              done: Bool = false, hours: PlaceHours? = nil) -> GuideStop {
        GuideStop(placeId: id, name: name, lat: c.latitude, lng: c.longitude, start: start, end: start.addingTimeInterval(75 * 60),
                  isPhoto: photo, isDone: done, hours: hours)
    }

    func day(_ stops: [GuideStop], origin: CLLocationCoordinate2D = savassi) -> GuideDay {
        let boards = BoardDates(timeZone: Self.bh)
        let date = boards.day(from: "2026-11-03")!
        return GuideDay(date: date, dayStart: boards.time("09:30", on: date)!, timeZone: Self.bh, origin: origin, walkMaxKm: 1.5, stops: stops)
    }

    /// Minutos do solver entre dois pontos (o que o aviso usa).
    func legMinutes(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Int {
        DaySolver.leg(a, b, walkMax: 1.5).minutes
    }

    // MARK: Saída

    @Test func leaveNudgeIsFiveMinutesBeforeTravelTime() {
        let start = bhTime("10:00")
        let plan = GuideNudges.plan(day([stop("p1", "Mercado Central", at: start)]), now: bhTime("09:00"))
        let leave = plan.first { $0.kind == .leave }
        let minutes = legMinutes(Self.savassi, Self.centro)
        #expect(leave?.fireAt == start.addingTimeInterval(-TimeInterval(minutes * 60) - 300))
        #expect(leave?.title == "Saia em 5 min pro Mercado Central")
        #expect(leave?.placeId == "p1")
    }

    @Test func doneStopsAreNotNudged() {
        let plan = GuideNudges.plan(day([stop("p1", "Mercado Central", at: bhTime("10:00"), done: true)]), now: bhTime("09:00"))
        #expect(plan.isEmpty)
    }

    // MARK: Golden

    @Test func goldenNudgeComesFromAPhotoStopNearTheWindow() {
        let tz = Self.tokyo
        let gyoen = (lat: 35.6852, lng: 139.7600)
        let c = CLLocationCoordinate2D(latitude: gyoen.lat, longitude: gyoen.lng)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
        let sun = SunService.day(noon, latitude: gyoen.lat, longitude: gyoen.lng, timeZone: tz)
        let golden = try! #require(sun.goldenPM)
        // Parada de foto depois do pôr (dentro de 1 h da janela): o aviso de golden entra, longe da saída.
        let start = golden.end.addingTimeInterval(30 * 60)
        let tokyoDay = GuideDay(date: cal.startOfDay(for: noon), dayStart: cal.date(byAdding: .hour, value: 9, to: cal.startOfDay(for: noon))!,
                                timeZone: tz, origin: c, walkMaxKm: 1.5,
                                stops: [stop("j18", "Gyoen", at: start, c, photo: true)])
        let plan = GuideNudges.plan(tokyoDay, now: cal.date(byAdding: .hour, value: 9, to: cal.startOfDay(for: noon))!)
        let nudge = plan.first { $0.kind == .golden }
        // Segundos inteiros, como o trigger de calendário grava.
        #expect(nudge?.fireAt == Date(timeIntervalSince1970: floor(golden.start.addingTimeInterval(-20 * 60).timeIntervalSince1970)))
        #expect(nudge?.title == "Golden em 20 min")
        #expect(nudge?.body == "Você está a 0 min do Gyoen")
    }

    @Test func noGoldenNudgeWithoutPhotoStopOrFarFromWindow() {
        let tz = Self.tokyo
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let noon = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
        let c = CLLocationCoordinate2D(latitude: 35.6852, longitude: 139.7600)
        let sun = SunService.day(noon, latitude: c.latitude, longitude: c.longitude, timeZone: tz)
        let golden = try! #require(sun.goldenPM)
        let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 9))!
        let base = GuideDay(date: cal.startOfDay(for: noon), dayStart: cal.date(byAdding: .hour, value: 9, to: cal.startOfDay(for: noon))!,
                            timeZone: tz, origin: c, walkMaxKm: 1.5, stops: [])
        // Mesma hora de golden, mas a lista não é photo.
        var notPhoto = base
        notPhoto.stops = [stop("j18", "Gyoen", at: golden.end.addingTimeInterval(30 * 60), c, photo: false)]
        #expect(GuideNudges.plan(notPhoto, now: morning).allSatisfy { $0.kind != .golden })
        // Foto de manhã, longe da janela de golden: nada.
        var farPhoto = base
        farPhoto.stops = [stop("j18", "Gyoen", at: morning, c, photo: true)]
        #expect(GuideNudges.plan(farPhoto, now: morning).allSatisfy { $0.kind != .golden })
    }

    // MARK: Abre agora

    @Test func opensNudgeWhenPlaceOpensLaterInTheDay() {
        // Terça (2): abre 11:00, fecha 22:00.
        let hours = PlaceHours(periods: [.init(open: .init(day: 2, hour: 11, minute: 0), close: .init(day: 2, hour: 22, minute: 0))])
        let plan = GuideNudges.plan(day([stop("p2", "Bar do Ponto", at: bhTime("14:00"), hours: hours)], origin: Self.centro),
                                    now: bhTime("09:00"))
        let opens = plan.first { $0.kind == .opens }
        #expect(opens?.fireAt == bhTime("11:00"))
        #expect(opens?.title == "Bar do Ponto abre agora")
    }

    @Test func noOpensNudgeWhenAlreadyOpenAtDayStart() {
        let hours = PlaceHours(periods: [.init(open: .init(day: 2, hour: 8, minute: 0), close: .init(day: 2, hour: 22, minute: 0))])
        let plan = GuideNudges.plan(day([stop("p2", "Padaria", at: bhTime("14:00"), hours: hours)]), now: bhTime("09:00"))
        #expect(plan.allSatisfy { $0.kind != .opens })
    }

    // MARK: Prioridade e espaçamento

    @Test func leaveWinsOverOpensWhenTheyAreTooClose() {
        // Abre 11:00; a parada é 11:20 com a origem nela: a saída cai 11:15, a menos de 45 min da abertura.
        let hours = PlaceHours(periods: [.init(open: .init(day: 2, hour: 11, minute: 0), close: .init(day: 2, hour: 22, minute: 0))])
        let plan = GuideNudges.plan(day([stop("p2", "Bar", at: bhTime("11:20"), hours: hours)], origin: Self.centro), now: bhTime("09:00"))
        #expect(plan.map(\.kind) == [.leave])
    }

    @Test func onlyOneNudgePerFortyFiveMinutes() {
        // Duas saídas 30 min apart: fica a primeira.
        let plan = GuideNudges.plan(day([stop("p1", "A", at: bhTime("10:00"), Self.centro),
                                         stop("p2", "B", at: bhTime("10:30"), Self.centro)], origin: Self.centro), now: bhTime("09:00"))
        #expect(plan.count == 1)
        #expect(plan.first?.placeId == "p1")
    }

    @Test func gapOfExactlyFortyFiveMinutesIsAllowed() {
        let plan = GuideNudges.plan(day([stop("p1", "A", at: bhTime("10:00"), Self.centro),
                                         stop("p2", "B", at: bhTime("10:45"), Self.centro)], origin: Self.centro), now: bhTime("09:00"))
        #expect(plan.count == 2)
        #expect(plan.map(\.placeId) == ["p1", "p2"])
    }

    @Test func takenNotificationsCountForTheGap() {
        let start = bhTime("10:00")
        let plan = GuideNudges.plan(day([stop("p1", "A", at: start, Self.centro)], origin: Self.centro), now: bhTime("09:00"),
                                    taken: [start.addingTimeInterval(-10 * 60)])
        #expect(plan.isEmpty)
    }

    // MARK: Só o que vem

    @Test func onlyFutureNudgesAreKept() {
        let plan = GuideNudges.plan(day([stop("p1", "A", at: bhTime("10:00"), Self.centro),
                                         stop("p2", "B", at: bhTime("10:30"), Self.centro)], origin: Self.centro), now: bhTime("10:20"))
        // A saída de A (09:55) já passou; a de B (10:25) ainda cabe.
        #expect(plan.map(\.placeId) == ["p2"])
        #expect(plan.allSatisfy { $0.fireAt > bhTime("10:20") })
    }

    @Test func idsCarryTheDayAndAreNumbered() {
        let plan = GuideNudges.plan(day([stop("p1", "A", at: bhTime("10:00"), Self.centro),
                                         stop("p2", "B", at: bhTime("12:00"), Self.centro)], origin: Self.centro), now: bhTime("09:00"))
        #expect(plan.count == 2)
        #expect(plan[0].id.hasPrefix(GuideNudges.idPrefix))
        #expect(plan[0].id.hasSuffix(".1"))
        #expect(plan[1].id.hasSuffix(".2"))
        #expect(plan[0].id.contains("2026-11-03"))
    }
}

/// Agendador de mentira: guarda o que foi pedido e simula a central (pendentes de outros lembretes ficam lá).
@MainActor
final class FakeNudgeCenter: NudgeScheduling {
    var pending: [PendingNudge]
    var delivered: [Date] = []
    var grant = true
    private(set) var asked: [Bool] = []
    private(set) var removed: [String] = []
    private(set) var added: [GuideNudge] = []

    init(pending: [PendingNudge] = []) { self.pending = pending }

    func allowed(askIfNeeded: Bool) async -> Bool {
        asked.append(askIfNeeded)
        return grant
    }

    func pendingGuide() async -> [PendingNudge] { pending.filter { $0.id.hasPrefix(GuideNudges.idPrefix) } }

    func deliveredGuideDates() async -> [Date] { delivered }

    func remove(ids: [String]) {
        removed += ids
        pending.removeAll { ids.contains($0.id) }
    }

    func add(_ nudge: GuideNudge, calendar: Calendar) async {
        added.append(nudge)
        pending.append(PendingNudge(id: nudge.id, fireAt: nudge.fireAt, title: nudge.title, body: nudge.body))
    }
}

/// Dia aceito de hoje no banco de BH (seed em memória), pra testar o agendador de ponta a ponta.
@MainActor
struct GuideSchedulerTests {
    private final class Token {}

    private let now = BoardDates(timeZone: Region.bh.timeZone).time("09:00", on: BoardDates(timeZone: Region.bh.timeZone).day(from: "2026-11-03")!)!

    /// O contêiner volta junto: o `ModelContext` não o segura, e sem ele o próximo fetch encerra o processo.
    private func makeContainer(acceptToday: Bool) throws -> ModelContainer {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = c.mainContext
        try RegionStore.seedIfEmpty(ctx, region: .bh, bundle: Bundle(for: Token.self))
        guard acceptToday else { return c }
        let boards = BoardDates(timeZone: Region.bh.timeZone)
        let date = boards.day(from: "2026-11-03")!
        let places = try ctx.fetch(FetchDescriptor<Place>()).filter { $0.lat != 0 }.sorted { $0.id < $1.id }.prefix(2)
        let day = PlannedDay(date: date, kind: .free, budget: 200, walk: .normal, accepted: true)
        ctx.insert(day)
        for (i, place) in places.enumerated() {
            let stop = Stop(place: place, at: boards.time(i == 0 ? "10:00" : "13:00", on: date)!, order: i)
            ctx.insert(stop)
            day.stops.append(stop)
        }
        return c
    }

    private let others = [PendingNudge(id: "ticket.leave.1700000000", fireAt: nil, title: "Saia pro Tsukiji", body: ""),
                          PendingNudge(id: "flight.a.b", fireAt: nil, title: "Passaporte", body: "Voo"),
                          PendingNudge(id: "guide.2026-11-02.1", fireAt: nil, title: "velho", body: "velho")]

    @Test func refreshReplacesOnlyGuideIds() async throws {
        let container = try makeContainer(acceptToday: true)
        let center = FakeNudgeCenter(pending: others)
        await GuideNudgeScheduler.refresh(context: container.mainContext, region: .bh, origin: nil, askPermission: true, enabled: true, now: now, center: center)

        #expect(!center.added.isEmpty)
        #expect(center.added.allSatisfy { $0.id.hasPrefix(GuideNudges.idPrefix) })
        #expect(center.removed == ["guide.2026-11-02.1"])
        // Os lembretes de ingresso e voo continuam lá, intactos.
        #expect(center.pending.contains { $0.id == "ticket.leave.1700000000" })
        #expect(center.pending.contains { $0.id == "flight.a.b" })
        #expect(center.asked == [true])
    }

    @Test func unchangedPlanIsNotRescheduled() async throws {
        let container = try makeContainer(acceptToday: true)
        let center = FakeNudgeCenter(pending: others)
        await GuideNudgeScheduler.refresh(context: container.mainContext, region: .bh, origin: nil, askPermission: false, enabled: true, now: now, center: center)
        let removedBefore = center.removed.count, addedBefore = center.added.count
        await GuideNudgeScheduler.refresh(context: container.mainContext, region: .bh, origin: nil, askPermission: false, enabled: true, now: now, center: center)
        #expect(center.removed.count == removedBefore)
        #expect(center.added.count == addedBefore)
        #expect(center.asked == [false, false])
    }

    @Test func noAcceptedDayClearsOnlyGuideIds() async throws {
        let container = try makeContainer(acceptToday: false)
        let center = FakeNudgeCenter(pending: others)
        await GuideNudgeScheduler.refresh(context: container.mainContext, region: .bh, origin: nil, askPermission: true, enabled: true, now: now, center: center)
        #expect(center.added.isEmpty)
        #expect(center.removed == ["guide.2026-11-02.1"])
        #expect(center.pending.count == 2)
    }

    @Test func disabledClearsGuideIdsAndAddsNothing() async throws {
        let container = try makeContainer(acceptToday: true)
        let center = FakeNudgeCenter(pending: others)
        await GuideNudgeScheduler.refresh(context: container.mainContext, region: .bh, origin: nil, askPermission: true, enabled: false, now: now, center: center)
        #expect(center.added.isEmpty)
        #expect(center.removed == ["guide.2026-11-02.1"])
        #expect(center.asked.isEmpty)
    }

    @Test func deniedPermissionSchedulesNothing() async throws {
        let container = try makeContainer(acceptToday: true)
        let center = FakeNudgeCenter(pending: others)
        center.grant = false
        await GuideNudgeScheduler.refresh(context: container.mainContext, region: .bh, origin: nil, askPermission: false, enabled: true, now: now, center: center)
        #expect(center.added.isEmpty)
        #expect(center.pending.contains { $0.id == "ticket.leave.1700000000" })
    }

    @Test func disableRemovesOnlyGuideIds() async {
        let center = FakeNudgeCenter(pending: others)
        await GuideNudgeScheduler.disable(center: center)
        #expect(center.removed == ["guide.2026-11-02.1"])
        #expect(center.pending.count == 2)
    }
}
