import Foundation
import Testing
@testable import Must

/// Montar o dia v8 (prompt 23 §2 · 05): opções da tela.
struct MontarTests {
    @Test func vizinhosAteQuinzeMinutos() {
        let areas = AreaCatalog.jp
        let shinjuku = areas.first { $0.id == "shinjuku" }
        let line = MontarOptions.neighborLine(shinjuku, areas: areas)
        #expect(line?.hasPrefix("+ ") == true)
        #expect(line?.contains(", a ") == true)
        #expect(MontarOptions.neighborLine(nil, areas: areas) == nil)
    }

    @Test func chipsPorContagemEEscolhidoPrimeiro() {
        let chips = [MontarOptions.AreaChip(id: "a", name: "A", count: 9), .init(id: "b", name: "B", count: 3), .init(id: "c", name: "C", count: 1)]
        #expect(MontarOptions.leading("c", in: chips).map(\.id) == ["c", "a", "b"])
        #expect(MontarOptions.leading("x", in: chips).map(\.id) == ["a", "b", "c"])
    }

    @Test func orcamentoPorRegiao() {
        #expect(MontarOptions.budgets(.jp) == [8_000, 12_000, 20_000])
        #expect(MontarOptions.budgets(.bh) == [100, 200, 400])
        #expect(MontarOptions.budgets(.it) == [60, 120, 200])
    }

    @Test func ateQueHorasDaAVolta() {
        #expect(MontarOptions.nextUntil(after: 23 * 60 + 30) == 25 * 60)
        #expect(MontarOptions.nextUntil(after: 25 * 60) == 21 * 60)
    }

    @Test func ritmoTemTresNiveis() {
        #expect(Pace.allCases.map(\.rawValue) == [6, 9, 12])
        #expect(MontarOptions.paceLine(.normal) == "normal · com pausas")
    }
}
