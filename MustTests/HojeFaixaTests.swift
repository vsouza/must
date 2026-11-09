import Foundation
import Testing
@testable import Must

/// Relatório v9, item 7: sobre a Hoje a faixa "agora" não repete o cartão da tela.
@MainActor
struct HojeFaixaTests {
    private let region = Region.jp
    private func at(_ h: Int, _ m: Int) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: h, minute: m))!
    }

    @Test func comDiaDizOQueVemDepois() {
        let c = DayClock.make(plan: DayEngineStub.qaDay, doneIds: [], at: at(14, 20), region: region)
        let elsewhere = NowAccessoryLine.make(clock: c, region: region)
        let onHoje = NowAccessoryLine.make(clock: c, region: region, onHoje: true)
        #expect(elsewhere.hasPrefix("Agora:"))
        #expect(onHoje.hasPrefix("Depois:"))
        #expect(onHoje != elsewhere)
    }

    @Test func semDiaPedeAlgoEmVezDeMontarOutraVez() {
        let c = DayClock.make(plan: nil, doneIds: [], at: at(14, 20), region: region)
        #expect(NowAccessoryLine.make(clock: c, region: region) == "Montar o dia de hoje")
        #expect(NowAccessoryLine.make(clock: c, region: region, onHoje: true) == "Pedir algo… · o que fazer agora")
    }
}
