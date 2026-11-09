import Foundation
import Testing
@testable import Must

/// Problema 2 do relatório do viajante: atrasou → o dia se refaz, a âncora fica e o que saiu tem motivo (sem culpa).
@MainActor
struct ReplanSummaryTests {
    private let region = Region.jp

    private func t(_ h: Int, _ m: Int) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: h, minute: m))!
    }

    private func stop(_ id: String, _ kind: StopKind, _ s: (Int, Int), _ e: (Int, Int), _ label: String,
                      anchor: DayAnchorReason? = nil) -> DayStop {
        DayStop(id: id, placeId: nil, kind: kind, start: t(s.0, s.1), end: t(e.0, e.1), label: label, note: "", anchor: anchor)
    }

    /// Almoço 12:00–13:00, café 14:00–14:40, museu 15:00–16:00, reserva 17:00–19:00.
    private var day: DayPlan {
        DayPlan(date: t(0, 0), title: "Teste", dayNumber: 3, area: nil, stops: [
            stop("a", .must, (12, 0), (13, 0), "Ramen"),
            stop("b", .must, (14, 0), (14, 40), "Café"),
            stop("c", .must, (15, 0), (16, 0), "Museu"),
            stop("r", .anchor, (17, 0), (19, 0), "Jantar", anchor: .reservation),
        ], legs: [], lastTrain: nil, pace: .normal, budget: 10_000)
    }

    @Test func atraso40MinRefazEMantemAAncora() throws {
        let c = DayClock.make(plan: day, doneIds: ["a"], at: t(15, 50), region: region)
        let anchor = try #require(c.plan?.stops.first { $0.id == "r" })
        #expect(anchor.start == t(17, 0) && anchor.end == t(19, 0))
        #expect(c.active?.stops.contains { $0.id == "r" } == true)
        #expect(c.adjusted)
        #expect(c.skipReasons["b"] == .passed)
    }

    @Test func naoCabeMaisSaiComMotivoDaAncora() throws {
        var plan = day
        plan.stops.append(stop("d", .must, (16, 30), (17, 15), "Doces"))
        plan.stops.sort { $0.start < $1.start }
        let c = DayClock.make(plan: plan, doneIds: ["a", "b"], at: t(16, 20), region: region)
        let summary = try #require(ReplanSummary.make(clock: c, region: region))
        #expect(!summary.removed.isEmpty)
        #expect(summary.removed.allSatisfy { !$0.lowercased().contains("deveria") })
        #expect(summary.removed.contains("Tirei Doces pra caber a reserva das 17:00."))
        #expect(c.active?.stops.first { $0.id == "r" }?.start == t(17, 0))
    }

    @Test func semAtrasoSemResumo() {
        let c = DayClock.make(plan: day, doneIds: [], at: t(11, 0), region: region)
        #expect(ReplanSummary.make(clock: c, region: region) == nil)
    }
}
