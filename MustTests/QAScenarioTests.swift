import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Cenários do QA.md que dá pra rodar sem o iPhone.
@MainActor
struct QAScenarioTests {
    private final class Token {}

    private func container(_ region: Region) throws -> ModelContainer {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try RegionStore.seedIfEmpty(c.mainContext, region: region, bundle: Bundle(for: Token.self))
        return c
    }

    /// "Domingo: Montar compras → Feira Hippie entra de manhã."
    @Test func sundayShoppingPullsFeiraHippieInTheMorning() throws {
        let c = try container(.bh)
        let ctx = c.mainContext
        let places = try ctx.fetch(FetchDescriptor<Place>())
        let sunday = BoardDates(timeZone: Region.bh.timeZone).day(from: "2026-11-01")!
        let planner = DayPlanner(date: sunday, region: .bh, settings: ctx.settings(for: .bh), existing: nil)
        planner.kind = .shopping
        planner.startAt = BoardDates(timeZone: Region.bh.timeZone).time("09:30", on: sunday)!
        planner.build(catalog: places.solverCatalog, trip: ctx.tripInfo(), settings: ctx.settings(for: .bh),
                      location: CLLocation(latitude: -19.9385, longitude: -43.9343))
        let feira = try #require(planner.proposal?.stops.first { $0.place.id == "p22" })
        #expect(feira.window == .morning)
        #expect(planner.proposal?.stops.contains { $0.place.role == .listen } == false)
    }

    /// "Simular 2026-11-15 10:00 e GPS Naka-Meguro → Início do Japão mostra a reserva do Udatsu como Próxima."
    @Test func japanHomeShowsUdatsuAsNext() throws {
        let c = try container(.jp)
        let ctx = c.mainContext
        let now = BoardDates.parseDateTime("2026-11-15T10:00:00+09:00")!
        let model = HomeModel(places: try ctx.fetch(FetchDescriptor<Place>()), expenses: [], days: [], trip: ctx.tripInfo(),
                              region: .jp, now: now, location: CLLocation(latitude: 35.6442, longitude: 139.6985))
        let next = try #require(model.next)
        #expect(next.place.id == "j01")
        #expect(next.isReservation)
        #expect(Region.jp.timeString(next.at) == "19:00")
    }

    /// "Primeira abertura: seed BH carregado."
    @Test func firstOpenLoadsBHSeed() throws {
        let c = try container(.bh)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<Place>()) == 50)
        #expect(try c.mainContext.fetchCount(FetchDescriptor<MustList>()) == 8)
        #expect(c.mainContext.settings(for: .bh).perDayBudget == 200)
    }

    /// "Orçamento R$ 100: Glouton/Trindade não entram; com 'vale a exceção' e 'jantar bom', entra fora da meta."
    @Test func budget100WithSplurge() throws {
        let c = try container(.bh)
        let ctx = c.mainContext
        let places = try ctx.fetch(FetchDescriptor<Place>())
        let saturday = BoardDates(timeZone: Region.bh.timeZone).day(from: "2026-10-31")!
        let planner = DayPlanner(date: saturday, region: .bh, settings: ctx.settings(for: .bh), existing: nil)
        planner.budget = 100
        planner.startAt = BoardDates(timeZone: Region.bh.timeZone).time("09:30", on: saturday)!
        let here = CLLocation(latitude: -19.9385, longitude: -43.9343)
        planner.build(catalog: places.solverCatalog, trip: ctx.tripInfo(), settings: ctx.settings(for: .bh), location: here)
        #expect(planner.proposal?.stops.contains { ["p04", "p05"].contains($0.place.id) } == false)
        planner.apply(RegexIntentParser.parse("quero um jantar bom"))
        planner.build(catalog: places.solverCatalog, trip: ctx.tripInfo(), settings: ctx.settings(for: .bh), location: here)
        let fine = try #require(planner.proposal?.stops.first { ["p04", "p05"].contains($0.place.id) })
        #expect(fine.isException)
        #expect((planner.proposal?.predictedSpend ?? 999) <= 100)
    }

    /// "Exportar → apagar app → reinstalar → Importar: tudo volta." (com gasto, dia aceito e 済)
    @Test func exportWipeImportRestoresEverything() throws {
        let c = try container(.bh)
        let ctx = c.mainContext
        let place = try #require(try ctx.fetch(FetchDescriptor<Place>()).first { $0.id == "p07" })
        PlaceActions.markDone(place, spent: 15, method: .cash, at: BoardDates.parseDateTime("2026-10-31T10:00:00-03:00")!, context: ctx)
        let board = try BoardCodec(context: ctx, region: .bh).export()
        let json = try BoardCodec.encode(board)

        let fresh = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try BoardCodec(context: fresh.mainContext, region: .bh).import(board: BoardCodec.decode(json))
        let restored = try #require(try fresh.mainContext.fetch(FetchDescriptor<Place>()).first { $0.id == "p07" })
        #expect(restored.done?.spent == 15)
        #expect(try fresh.mainContext.fetchCount(FetchDescriptor<Expense>()) == 1)
        #expect(try BoardCodec(context: fresh.mainContext, region: .bh).export() == board)
    }
}
