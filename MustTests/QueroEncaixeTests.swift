import CoreLocation
import Foundation
import Testing
@testable import Must

/// Relatório v9, item 6: um café às 16:00 não pode virar "Encaixa hoje depois do Bar Trench 22:05".
@MainActor
struct QueroEncaixeTests {
    private let region = Region.jp
    private var day: Date { region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))! }
    private func at(_ h: Int, _ m: Int) -> Date { region.calendar.date(bySettingHour: h, minute: m, second: 0, of: day)! }

    private let shinjuku = CLLocationCoordinate2D(latitude: 35.6909, longitude: 139.7003)
    private let tsukiji = CLLocationCoordinate2D(latitude: 35.6654, longitude: 139.7707)
    private let asakusa = CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967)

    private func stop(_ id: String, _ s: (Int, Int), _ e: (Int, Int), _ c: CLLocationCoordinate2D) -> DayStop {
        DayStop(id: id, placeId: id, kind: .must, start: at(s.0, s.1), end: at(e.0, e.1), label: id, note: "", lat: c.latitude, lng: c.longitude)
    }

    @Test func cafeDeTardeNaoVaiParaDepoisDoUltimoBarDaNoite() throws {
        // Tsukiji 14:00, Asakusa 17:00 (buraco grande no meio), e o Bar Trench colado em Shinjuku, 20:40–22:05 (sem buraco antes).
        let plan = DayPlan(date: day, title: "t", dayNumber: nil, area: nil, stops: [
            stop("tsukiji", (14, 0), (15, 0), tsukiji),
            stop("asakusa", (18, 30), (20, 0), asakusa),
            stop("trench", (20, 10), (22, 5), shinjuku),
        ], legs: [], lastTrain: nil, pace: .normal, budget: 10_000)
        let slot = try #require(DayFit.slot(at: shinjuku, plan: plan, now: at(16, 0), region: region, origin: shinjuku))
        #expect(slot.start < at(19, 0), "encaixou às \(slot.start)")
        #expect(slot.after?.id != "trench")
    }

    @Test func comTempoDeSobraDepoisDaUltimaAindaPodeEncaixarLa() throws {
        // Dia que só tem uma parada de manhã: o encaixe depois dela, agora à tarde, continua valendo.
        let plan = DayPlan(date: day, title: "t", dayNumber: nil, area: nil, stops: [
            stop("manha", (9, 0), (10, 0), shinjuku),
        ], legs: [], lastTrain: nil, pace: .normal, budget: 10_000)
        let slot = try #require(DayFit.slot(at: shinjuku, plan: plan, now: at(16, 0), region: region, origin: shinjuku))
        #expect(slot.start >= at(16, 0) && slot.start <= at(16, 40))
    }
}
