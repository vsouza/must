import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Montar → aceitar → registrar gasto, sobre o seed de BH em memória.
@MainActor
struct DayFlowTests {
    private final class Token {}

    private func container() throws -> ModelContainer {
        let c = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try RegionStore.seedIfEmpty(c.mainContext, region: .bh, bundle: Bundle(for: Token.self))
        return c
    }

    private func saturday() -> Date { BoardDates(timeZone: Region.bh.timeZone).time("09:30", on: BoardDates(timeZone: Region.bh.timeZone).day(from: "2026-10-31")!)! }

    @Test func acceptPersistsDayAndReplacesPrevious() throws {
        let c = try container()
        let ctx = c.mainContext
        let places = try ctx.fetch(FetchDescriptor<Place>())
        let planner = DayPlanner(date: saturday(), region: .bh, settings: ctx.settings(for: .bh), existing: nil)
        planner.startAt = saturday()
        let here = CLLocation(latitude: -19.9385, longitude: -43.9343)
        planner.build(catalog: places.solverCatalog, trip: ctx.tripInfo(), settings: ctx.settings(for: .bh), location: here)
        let proposal = try #require(planner.proposal)
        try planner.accept(context: ctx)
        try planner.accept(context: ctx) // aceitar de novo substitui, não duplica

        let days = try ctx.fetch(FetchDescriptor<PlannedDay>())
        #expect(days.count == 1)
        let day = try #require(days.first)
        #expect(day.accepted)
        #expect(day.orderedStops.map { $0.place?.id } == proposal.stops.map(\.place.id))
        #expect(try ctx.fetchCount(FetchDescriptor<Stop>()) == proposal.stops.count)
    }

    @Test func recordingExpenseMarksDone() throws {
        let c = try container()
        let ctx = c.mainContext
        let place = try #require(try ctx.fetch(FetchDescriptor<Place>()).first { $0.id == "p07" })
        let day = PlannedDay(date: BoardDates(timeZone: Region.bh.timeZone).day(from: "2026-10-31")!, budget: 200, accepted: true)
        ctx.insert(day)
        let stop = Stop(place: place, at: saturday(), order: 0)
        ctx.insert(stop)
        day.stops.append(stop)

        PlaceActions.record(amount: 18, place: place, category: .coffee, method: .cash, day: day, at: saturday(), context: ctx)
        #expect(place.done?.spent == 18)
        #expect(stop.done)
        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1)
        #expect(expenses.first?.place?.id == "p07")
        #expect(expenses.first?.category == .coffee)

        // Sem lugar: só o gasto. Zero sem lugar: nada.
        PlaceActions.record(amount: 6, place: nil, category: .transit, method: .card, day: day, context: ctx)
        PlaceActions.record(amount: 0, place: nil, category: nil, method: .card, day: day, context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<Expense>()) == 2)

        PlaceActions.undoDone(place, context: ctx)
        #expect(place.done == nil)
        #expect(try ctx.fetchCount(FetchDescriptor<Expense>()) == 1)
    }
}
