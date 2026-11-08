import Foundation
import Testing
@testable import Must

/// Barra nativa do iOS 26: a lupa é o Quero…, a faixa "agora" lê o DayClock.
@MainActor
struct BarraNativaTests {
    @Test func openQueroSelecionaALupaComOTexto() {
        let router = AppRouter()
        router.sheet = .assistant
        router.openQuero(text: "café")
        #expect(router.queroSelected && router.queroText == "café" && router.sheet == nil)
        let token = router.queroToken
        router.openQuero(text: "ramen")
        #expect(router.queroToken == token + 1)
    }

    @Test func sairDaLupaVoltaPraAbaSemLimparAPilha() {
        let router = AppRouter()
        router.push(.agora, on: .hoje)
        router.openQuero()
        router.select(.hoje)
        #expect(!router.queroSelected)
        #expect(router.paths[.hoje] == [.agora])
        router.openQuero()
        router.push(.sos, on: .hoje)
        #expect(!router.queroSelected)
    }

    @Test func faixaAgoraSemDiaMandaMontar() {
        let clock = DayClock.make(plan: nil, doneIds: [], at: Date(), region: .bh)
        #expect(NowAccessoryLine.make(clock: clock, region: .bh) == "Montar o dia de hoje")
    }
}
