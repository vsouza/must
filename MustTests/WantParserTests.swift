import Foundation
import Testing
@testable import Must

/// Quero… (prompt 25 · A.1): vontade em texto → `{verb, object, brand?, category?, when?}` sem modelo (regex).
struct WantParserTests {
    private func parse(_ text: String) -> WantIntent { WantParser.parseLocal(text)! }

    @Test func comprarUmSeiko() {
        let w = parse("quero comprar um Seiko")
        #expect(w.verb == .comprar)
        #expect(w.object == "Seiko")
        #expect(w.brand == "Seiko")
        #expect(w.category == "relógio")
        #expect(w.when == nil)
        #expect(w.display == "relógio Seiko")
        #expect(WantCategory.of(w)?.types.contains("electronics_store") == true)
    }

    @Test func comerUmTonkatsuBomPerto() {
        let w = parse("comer um tonkatsu bom perto")
        #expect(w.verb == .comer)
        #expect(w.object == "tonkatsu")
        #expect(w.near)
        #expect(w.good)
        #expect(w.brand == nil)
        // Prato: um tipo só, vai no pedido com strictTypeFiltering.
        #expect(WantCategory.of(w)?.includedType == "restaurant")
    }

    @Test func verOFujiAmanha() {
        let w = parse("ver o Fuji amanhã")
        #expect(w.verb == .ver)
        #expect(w.object == "Fuji")
        #expect(w.when == .amanha)
        #expect(w.category == "vista")
    }

    @Test func bhPaoDeQueijo() {
        let w = parse("quero comer um pão de queijo")
        #expect(w.verb == .comer)
        #expect(w.object == "pão de queijo")
        #expect(w.category == "pão de queijo")
        #expect(WantCategory.of(w)?.types.contains("bakery") == true)
        #expect(WantCategory.of(w)?.listId == "eat")
    }

    @Test func bhCachaca() {
        let w = parse("comprar uma cachaça")
        #expect(w.verb == .comprar)
        #expect(w.object == "cachaça")
        #expect(w.category == "cachaça")
        #expect(WantCategory.of(w)?.types.contains("liquor_store") == true)
    }

    @Test func semVerboValeODaCategoria() {
        #expect(parse("um pão de queijo agora").verb == .comer)
        #expect(parse("um pão de queijo agora").when == .hoje)
        #expect(parse("tomar um café").verb == .beber)
    }

    @Test func vazioNaoEntende() {
        #expect(WantParser.parseLocal("  ") == nil)
        #expect(WantParser.parseLocal("quero") == nil)
    }

    @Test func textoDaBuscaJuntaCategoriaEMarca() {
        let w = parse("quero comprar um Seiko")
        #expect(WantSearch.text(for: w, category: WantCategory.of(w)) == "relógio Seiko")
        let t = parse("comer um tonkatsu bom perto")
        #expect(WantSearch.text(for: t, category: WantCategory.of(t)) == "tonkatsu")
    }
}
