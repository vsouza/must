import Foundation
import SwiftData
import Testing
@testable import Must

@MainActor
struct BoardCodecTests {
    // MARK: Helpers

    private final class Token {}
    private static var bundle: Bundle { Bundle(for: Token.self) }

    private static func seed(_ region: Region) throws -> Board {
        let url = try #require(region.seedURL(in: bundle), "seed-\(region.rawValue).json fora do bundle de testes")
        return try BoardCodec.decode(Data(contentsOf: url))
    }

    /// Container em memória que segura o `ModelContainer` vivo (o contexto não o retém).
    @MainActor final class TestBoard {
        let container: ModelContainer
        let region: Region
        init(_ region: Region) throws {
            self.region = region
            container = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        var context: ModelContext { container.mainContext }
        private var codec: BoardCodec { BoardCodec(context: context, region: region) }
        @discardableResult func `import`(board: Board, merge: Bool = true) throws -> ImportSummary {
            try codec.import(board: board, merge: merge)
        }
        func export() throws -> Board { try codec.export() }
    }

    private static func makeCodec(_ region: Region) throws -> TestBoard { try TestBoard(region) }

    private static func count<T: PersistentModel>(_ type: T.Type, in board: TestBoard) throws -> Int {
        try board.context.fetchCount(FetchDescriptor<T>())
    }

    /// Preenche os padrões do schema pra comparar o seed (campos omitidos) com o export (campos explícitos).
    private static func canon(_ p: BoardPlace) -> BoardPlace {
        var p = p
        p.approx = p.approx ?? false
        p.saveForEnd = p.saveForEnd ?? false
        p.allowBudgetException = p.allowBudgetException ?? false
        p.notes = p.notes ?? ""
        p.window = p.window ?? []
        p.order = p.order ?? 0
        return p
    }

    // MARK: Decodificação

    @Test(arguments: [(Region.bh, 50, 8), (Region.jp, 105, 8), (Region.it, 63, 9)])
    func decodesSeeds(region: Region, places: Int, lists: Int) throws {
        let board = try Self.seed(region)
        #expect(board.version == 1)
        #expect(board.region == region)
        #expect(board.places.count == places)
        #expect(board.lists.count == lists)
    }

    @Test func decodesReservationWithOffset() throws {
        let board = try Self.seed(.jp)
        let udatsu = try #require(board.places.first { $0.id == "j01" })
        let at = try #require(udatsu.reservation?.at)
        // 2026-11-15T19:00:00+09:00 == 10:00 UTC
        #expect(at == ISO8601DateFormatter().date(from: "2026-11-15T10:00:00Z"))
        #expect(udatsu.reservation?.party == 2)
        #expect(udatsu.source?.kind == .instagram)
    }

    @Test func unreadableJSONGivesReadableError() {
        #expect(throws: BoardError.self) {
            try BoardCodec.decode(Data(#"{"version": 1, "region": "bh"}"#.utf8))
        }
    }

    // MARK: Import

    @Test(arguments: [(Region.bh, 50, 8), (Region.jp, 105, 8), (Region.it, 63, 9)])
    func importsSeed(region: Region, places: Int, lists: Int) throws {
        let codec = try Self.makeCodec(region)
        let summary = try codec.import(board: Self.seed(region))
        #expect(summary.placesInserted == places)
        #expect(summary.listsInserted == lists)
        #expect(summary.citiesCreated.isEmpty)
        #expect(try Self.count(Place.self, in: codec) == places)
        #expect(try Self.count(MustList.self, in: codec) == lists)
        // Todo lugar ficou ligado a uma lista.
        let orphans = try codec.context.fetch(FetchDescriptor<Place>()).filter { $0.list == nil }
        #expect(orphans.isEmpty)
    }

    @Test func importsTripAndBudget() throws {
        let codec = try Self.makeCodec(.jp)
        try codec.import(board: Self.seed(.jp))
        let trip = codec.context.tripInfo()
        let d = BoardDates(timeZone: Region.jp.timeZone)
        #expect(trip.start.map(d.dayString) == "2026-11-11")
        #expect(trip.end.map(d.dayString) == "2026-11-24")
        #expect(trip.home == "Naka-Meguro")
        #expect(trip.cities.map(\.id) == ["tokyo1", "kyoto", "tokyo2"])
        #expect(trip.city(id: "kyoto")?.from.map(d.dayString) == "2026-11-17")
        let settings = codec.context.settings(for: .jp)
        #expect(settings.perDayBudget == 15_000)
        #expect(settings.dayStart == "09:30")
    }

    @Test func bhHasNoTripDates() throws {
        let codec = try Self.makeCodec(.bh)
        try codec.import(board: Self.seed(.bh))
        let trip = codec.context.tripInfo()
        #expect(trip.hasTrip == false)
        #expect(trip.cities.map(\.id) == ["bh"])
        #expect(codec.context.settings(for: .bh).perDayBudget == 200)
    }

    @Test(arguments: Region.allCases)
    func importIsIdempotent(region: Region) throws {
        let codec = try Self.makeCodec(region)
        let board = try Self.seed(region)
        try codec.import(board: board)
        let second = try codec.import(board: board)
        #expect(second.placesInserted == 0)
        #expect(second.listsInserted == 0)
        #expect(second.placesUpdated == board.places.count)
        #expect(try Self.count(Place.self, in: codec) == board.places.count)
        #expect(try Self.count(MustList.self, in: codec) == board.lists.count)
        #expect(try Self.count(TripInfo.self, in: codec) == 1)
        #expect(try Self.count(Settings.self, in: codec) == 1)
    }

    @Test func unknownListIsAReadableError() throws {
        let codec = try Self.makeCodec(.bh)
        var board = try Self.seed(.bh)
        board.places[0].listId = "kissaten"
        #expect(throws: BoardError.unknownList(place: board.places[0].name, list: "kissaten")) {
            try codec.import(board: board)
        }
        // Nada foi gravado.
        #expect(try Self.count(Place.self, in: codec) == 0)
    }

    @Test func unknownCityIsCreated() throws {
        let codec = try Self.makeCodec(.bh)
        var board = try Self.seed(.bh)
        board.places[0].cityId = "ouropreto"
        let summary = try codec.import(board: board)
        #expect(summary.citiesCreated == ["ouropreto"])
        let city = try #require(codec.context.tripInfo().city(id: "ouropreto"))
        #expect(city.name == "Ouropreto")
        #expect(city.currency == "BRL")
    }

    @Test func wrongRegionIsRejected() throws {
        let codec = try Self.makeCodec(.bh)
        #expect(throws: BoardError.wrongRegion(file: .jp, current: .bh)) {
            try codec.import(board: Self.seed(.jp))
        }
    }

    @Test func mergeKeepsLocalCache() throws {
        let codec = try Self.makeCodec(.bh)
        let board = try Self.seed(.bh)
        try codec.import(board: board)
        let place = try #require(try codec.context.fetch(FetchDescriptor<Place>()).first { $0.id == "p01" })
        place.placeId = "ChIJ-mercado"
        place.approx = false
        place.hours = PlaceHours(weekdayText: ["seg: 07:00–18:00"], periods: [
            .init(open: .init(day: 1, hour: 7, minute: 0), close: .init(day: 1, hour: 18, minute: 0)),
        ], fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
        place.done = DoneMark(at: Date(timeIntervalSince1970: 1_800_000_000), spent: 55)

        try codec.import(board: board, merge: true)
        #expect(place.placeId == "ChIJ-mercado")
        #expect(place.hours?.periods?.count == 1)
        #expect(place.done?.spent == 55)
        #expect(place.approx == false, "coordenada resolvida não volta a ser chute")

        try codec.import(board: board, merge: false)
        #expect(place.placeId == nil)
        #expect(place.hours == nil)
        #expect(place.done == nil)
    }

    // MARK: Export / round-trip

    @Test(arguments: Region.allCases)
    func exportMatchesSeed(region: Region) throws {
        let codec = try Self.makeCodec(region)
        let seed = try Self.seed(region)
        try codec.import(board: seed)
        let exported = try codec.export()

        #expect(exported.region == region)
        #expect(exported.lists.map(\.id) == seed.lists.map(\.id))
        #expect(exported.lists.map(\.color) == seed.lists.map(\.color))
        #expect(exported.lists.map { $0.sub ?? [] } == seed.lists.map { $0.sub ?? [] })
        #expect(exported.trip?.start == seed.trip?.start)
        #expect(exported.trip?.end == seed.trip?.end)
        #expect(exported.trip?.cities?.map(\.id) == seed.trip?.cities?.map(\.id))
        #expect(exported.trip?.cities?.map(\.from) == seed.trip?.cities?.map(\.from))
        #expect(exported.budget?.perDay == seed.budget?.perDay)

        let seedPlaces = seed.places.map(Self.canon).sorted { $0.id < $1.id }
        let exportedPlaces = exported.places.map(Self.canon).sorted { $0.id < $1.id }
        #expect(exportedPlaces.count == seedPlaces.count)
        for (a, b) in zip(exportedPlaces, seedPlaces) {
            #expect(a == b, "lugar \(b.id) mudou no round-trip")
        }
    }

    @Test(arguments: Region.allCases)
    func exportReimportDoesNotDuplicate(region: Region) throws {
        let codec = try Self.makeCodec(region)
        try codec.import(board: Self.seed(region))
        let first = try codec.export()
        let json = try BoardCodec.encode(first)
        let summary = try codec.import(board: BoardCodec.decode(json))
        #expect(summary.placesInserted == 0)
        #expect(summary.expensesInserted == 0)
        #expect(try codec.export() == first)
    }

    @Test(arguments: Region.allCases)
    func roundTripIntoFreshContainer(region: Region) throws {
        let codec = try Self.makeCodec(region)
        try codec.import(board: Self.seed(region))
        let first = try codec.export()

        let fresh = try Self.makeCodec(region)
        try fresh.import(board: BoardCodec.decode(BoardCodec.encode(first)))
        #expect(try fresh.export() == first)
    }

    @Test func expensesAndDaysRoundTrip() throws {
        let codec = try Self.makeCodec(.bh)
        try codec.import(board: Self.seed(.bh))
        let ctx = codec.context
        let places = try ctx.fetch(FetchDescriptor<Place>(sortBy: [SortDescriptor(\.id)]))
        let d = BoardDates(timeZone: Region.bh.timeZone)
        let saturday = try #require(d.day(from: "2026-10-31"))

        let day = PlannedDay(date: saturday, kind: .free, budget: 200, walk: .normal, accepted: true)
        ctx.insert(day)
        for (i, p) in places.prefix(3).enumerated() {
            let stop = Stop(place: p, at: try #require(d.time(String(format: "%02d:00", 10 + i * 3), on: saturday)), order: i, done: i == 0)
            ctx.insert(stop)
            day.stops.append(stop)
        }
        ctx.insert(Expense(at: saturday.addingTimeInterval(11 * 3600), amount: 62.5, category: .food, place: places[0], method: .card))
        ctx.insert(Expense(at: saturday.addingTimeInterval(15 * 3600), amount: 18, category: .coffee, method: .cash))
        try ctx.save()

        let exported = try codec.export()
        #expect(exported.expenses?.count == 2)
        #expect(exported.days?.first?.stops?.map(\.at) == ["10:00", "13:00", "16:00"])
        #expect(exported.days?.first?.stops?.map(\.done) == [true, false, false])

        let fresh = try Self.makeCodec(.bh)
        try fresh.import(board: BoardCodec.decode(BoardCodec.encode(exported)))
        #expect(try Self.count(Expense.self, in: fresh) == 2)
        #expect(try Self.count(Stop.self, in: fresh) == 3)
        #expect(try fresh.export() == exported)

        // Reimportar o mesmo arquivo não duplica gastos nem paradas.
        try fresh.import(board: BoardCodec.decode(BoardCodec.encode(exported)))
        #expect(try Self.count(Expense.self, in: fresh) == 2)
        #expect(try Self.count(Stop.self, in: fresh) == 3)
    }

    @Test func exportedJSONUsesRegionOffset() throws {
        let codec = try Self.makeCodec(.jp)
        try codec.import(board: Self.seed(.jp))
        let json = try #require(String(data: BoardCodec.encode(codec.export()), encoding: .utf8))
        #expect(json.contains("2026-11-15T19:00:00+09:00"))
    }
}

// MARK: - RegionStore

@MainActor
struct RegionStoreTests {
    private final class Token {}

    @Test func switchingRegionKeepsEachBoard() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "must-tests-\(UUID().uuidString)")
        let suite = "must-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        }

        let store = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        #expect(store.region == .bh)
        #expect(store.lastError == nil)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Place>()) == 50)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<MustList>()) == 8)

        // Um gasto em BH.
        store.container.mainContext.insert(Expense(at: .now, amount: 42, category: .coffee))
        try store.container.mainContext.save()

        store.switchTo(.jp)
        #expect(store.region == .jp)
        #expect(defaults.string(forKey: RegionStore.regionKey) == "jp")
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Place>()) == 105)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Expense>()) == 0)

        store.switchTo(.bh)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Place>()) == 50)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Expense>()) == 1)

        // Uma nova instância lembra da região e lê o mesmo arquivo.
        store.switchTo(.jp)
        let reopened = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        #expect(reopened.region == .jp)
        #expect(try reopened.container.mainContext.fetchCount(FetchDescriptor<Place>()) == 105)
    }

    @Test func resetBoardReseedsOnlyThatRegion() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "must-tests-\(UUID().uuidString)")
        let suite = "must-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suite)
        }

        let store = RegionStore(directory: dir, defaults: defaults, seedBundle: Bundle(for: Token.self))
        let ctx = store.container.mainContext
        ctx.insert(Expense(at: .now, amount: 10))
        let extra = Place(id: "x1", name: "Extra", cityId: "bh")
        ctx.insert(extra)
        try ctx.save()
        #expect(try ctx.fetchCount(FetchDescriptor<Place>()) == 51)

        store.switchTo(.jp)
        store.container.mainContext.insert(Expense(at: .now, amount: 1000))
        try store.container.mainContext.save()
        store.switchTo(.bh)

        store.resetBoard()
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Place>()) == 50)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Expense>()) == 0)

        store.switchTo(.jp)
        #expect(try store.container.mainContext.fetchCount(FetchDescriptor<Expense>()) == 1)
    }
}

@MainActor
struct TripEventCodecTests {
    @Test func eventsRoundTripWithoutDuplicates() throws {
        let container = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let codec = BoardCodec(context: ctx, region: .jp)
        final class T {}
        let seed = try BoardCodec.decode(Data(contentsOf: Region.jp.seedURL(in: Bundle(for: T.self))!))
        try codec.import(board: seed)
        // Voos do seed viram reservas (Flight), não eventos: só os outros eventos contam aqui.
        let seedEvents = seed.events?.filter { $0.kind != .flight }.count ?? 0
        let at = BoardDates.parseDateTime("2026-11-17T09:12:00+09:00")!
        ctx.insert(TripEvent(at: at, title: "Shinkansen → Kyoto", kind: .train, note: "Nozomi 215 · vagão 8"))
        try ctx.save()
        let exported = try codec.export()
        #expect(exported.events?.contains { $0.title == "Shinkansen → Kyoto" } == true)
        let json = String(data: try BoardCodec.encode(exported), encoding: .utf8)!
        #expect(json.contains("2026-11-17T09:12:00+09:00"))
        try codec.import(board: BoardCodec.decode(BoardCodec.encode(exported)))
        #expect(try ctx.fetchCount(FetchDescriptor<TripEvent>()) == seedEvents + 1)
    }
}
