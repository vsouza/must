import Foundation
import Testing
@testable import Must

/// Boa noite (prompt 23 §2 · 14): o resumo do dia.
struct BoaNoiteTests {
    private let plan = DayEngineStub.qaDay

    @Test func resumoContaFeitasEKm() {
        let s = NightSummary.build(plan: plan, doneIds: [], spent: 4_250)
        #expect(s.done == 2 && s.total == 9)
        // a pé 14 min × 75 m + 3 pernas de trem/metrô × 400 m = 2,25 km
        #expect(abs(s.walkKm - 2.25) < 0.001)
        #expect(s.percent == 35)
        #expect(s.sentence.hasPrefix("2 das 9 paradas."))
    }

    @Test func umaDeForaGanhaONome() {
        let all = Set(plan.stops.map(\.id)).subtracting(["s6"])
        let s = NightSummary.build(plan: plan, doneIds: all, spent: 11_300)
        #expect(s.done == 8)
        #expect(s.sentence == "8 das 9 paradas. Ficou de fora: descanso.")
    }

    @Test func todasFeitas() {
        let s = NightSummary.build(plan: plan, doneIds: Set(plan.stops.map(\.id)), spent: 0)
        #expect(s.sentence == "Todas as 9 paradas.")
    }

    @Test func semOrcamentoSemPercentual() {
        var day = plan
        day.budget = 0
        #expect(NightSummary.build(plan: day, doneIds: [], spent: 100).percent == nil)
    }

    @Test func gastoCompacto() {
        #expect(DayText.compactMoney(11_300, region: .jp) == ("¥11,3", "k"))
        #expect(DayText.compactMoney(86, region: .bh) == ("R$86", ""))
    }

    @Test func feitoGuardadoPorDia() {
        let defaults = UserDefaults(suiteName: "BoaNoiteTests")!
        defaults.removePersistentDomain(forName: "BoaNoiteTests")
        let store = DayDoneStore(defaults: defaults)
        store.mark("s3", day: "2026-11-15")
        #expect(store.ids(day: "2026-11-15") == ["s3"])
        #expect(store.ids(day: "2026-11-16").isEmpty)
        #expect(store.isDone(plan.stops[2], day: "2026-11-15"))
        store.mark("s3", day: "2026-11-15", done: false)
        #expect(!store.isDone(plan.stops[2], day: "2026-11-15"))
    }
}
