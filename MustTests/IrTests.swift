import Foundation
import Testing
@testable import Must

/// Ir (prompt 23 §2 · 13): passos e pílulas.
struct IrTests {
    @Test func caixaAntesDeLugarSoCash() {
        let walk = TravelOption(mode: .walk, source: .estimate, minutes: 9, meters: 650, departs: nil, arrives: nil)
        let steps = IrSteps.build(option: walk, placeName: "Fuunji", cashOnly: true, doorNote: "Placa amarela", region: .jp, arrives: nil)
        #expect(steps.map(\.id) == [1, 2, 3])
        #expect(steps[0].title == "A pé até o Fuunji")
        #expect(steps[1].onTheWay)
        #expect(steps[1].title.contains("7 Bank"))
        #expect(steps[2].title == "Fuunji: a porta")
    }

    @Test func semCashSemCaixa() {
        let taxi = TravelOption(mode: .taxi, source: .estimate, minutes: 6, meters: 2000, departs: nil, arrives: nil, fare: 900)
        let steps = IrSteps.build(option: taxi, placeName: "Fuunji", cashOnly: false, doorNote: nil, region: .jp, arrives: nil)
        #expect(steps.count == 2)
        #expect(!steps.contains { $0.onTheWay })
    }

    @Test func pilulas() {
        let walk = TravelOption(mode: .walk, source: .estimate, minutes: 9, meters: 650, departs: nil, arrives: nil)
        let taxi = TravelOption(mode: .taxi, source: .estimate, minutes: 6, meters: 2000, departs: nil, arrives: nil, fare: 900)
        #expect(IrSteps.pill(walk, region: .jp) == "A pé · 9 min")
        #expect(IrSteps.pill(taxi, region: .jp) == "Táxi · ¥ 900")
        #expect(IrView.order(.walk) < IrView.order(.transit))
    }

    @Test func soCashPeloTexto() {
        #expect(CashOnly.detect("Must drink · cover ¥ 800 · só cash"))
        #expect(CashOnly.detect(nil, "Cash only, no cards"))
        #expect(!CashOnly.detect("aceita cartão", nil))
    }
}
