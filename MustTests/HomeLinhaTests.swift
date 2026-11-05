import Foundation
import Testing
@testable import Must

/// Linha do dia e Agora (prompt 23 §2 · 03, 04): estados das paradas e o conteúdo do Agora.
struct HomeLinhaTests {
    private let plan = DayEngineStub.qaDay

    private func at(_ h: Int, _ m: Int) -> Date {
        Region.jp.calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: h, minute: m))!
    }

    @Test func estadosDaLinha() {
        let stops = plan.stops
        #expect(LinhaStopState.of(stops[0], nowId: "s4", doneIds: []) == .done)   // feito no plano
        #expect(LinhaStopState.of(stops[2], nowId: "s4", doneIds: ["s3"]) == .done) // marcado aqui
        #expect(LinhaStopState.of(stops[3], nowId: "s4", doneIds: []) == .now)
        #expect(LinhaStopState.of(stops[4], nowId: "s4", doneIds: []) == .upcoming)
    }

    @Test func rotulosDaLinha() {
        #expect(DayText.caption(for: plan.stops[0], isNow: false) == "café")
        #expect(DayText.caption(for: plan.stops[1], isNow: false) == "âncora")
        #expect(DayText.caption(for: plan.stops[2], isNow: false) == "micro")
        #expect(DayText.caption(for: plan.stops[3], isNow: false) == "eat")
        #expect(DayText.caption(for: plan.stops[3], isNow: true) == "agora")
        #expect(DayLegRow.text(plan.legs[0]) == "JY Yamanote 09:12 · 34 min · plat. 14")
    }

    @Test func contagens() {
        #expect(plan.countLine == "9 paradas")
        #expect(plan.anchorLine == "3 âncoras · 4 micro")
        #expect(plan.position(of: plan.stops[3]) == 4)
    }

    @Test func agoraDoDiaDeQA() throws {
        let now = at(14, 20)
        let dayNow = try #require(DayEngineStub().now(in: plan, at: now))
        let c = AgoraContent.build(plan: plan, now: dayNow, at: now, region: .jp, placeNotes: nil, distance: 650)
        #expect(c.title == "Fuunji")
        #expect(c.meta.hasPrefix("tsukemen · fila ~20 min · ¥ 1.250 · até "))
        #expect(c.travel == "a pé · 9 min")
        #expect(c.position == "4 de 9")
        #expect(c.next?.id == "s5")
        #expect(c.more.first?.hasSuffix("descanso") == true)
        #expect(c.verb == "Saia às")
        #expect((0...1).contains(c.progress))
    }

    @Test func chipsDoAgora() {
        let cash = DayStop(id: "x", placeId: nil, kind: .must, start: .now, end: .now, label: "Golden Gai", note: "só cash")
        let walk = DayLeg(mode: .walk, minutes: 9, from: "a", to: "x", detail: "")
        #expect(AgoraContent.chips(stop: cash, placeNotes: nil, region: .jp, legBefore: walk)
                == ["caixa 7 Bank no konbini", "konbini no caminho", "só cash"])
        let train = DayLeg(mode: .train, minutes: 9, from: "a", to: "x", detail: "")
        #expect(AgoraContent.chips(stop: cash, placeNotes: nil, region: .bh, legBefore: train) == ["saque antes", "só cash"])
    }

    @Test func diaDaViagem() {
        let cal = Region.jp.calendar
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 11))!
        let end = cal.date(from: DateComponents(year: 2026, month: 11, day: 24))!
        #expect(DayText.tripDay(start: start, end: end, on: at(14, 20), calendar: cal)! == (5, 14))
        #expect(DayText.tripDay(start: nil, end: end, on: at(14, 20), calendar: cal) == nil)
    }
}
