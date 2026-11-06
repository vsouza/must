import Foundation
import Testing
@testable import Must

/// "Outra" mostra o que mudou (`ProposalDiff`) e a ficha do Lugar mostra quanto custa (`PlaceFicha.cost`), 06/11/2026.
struct ProposalDiffTests {
    private func stop(_ id: String, _ place: String?, _ label: String, kind: StopKind = .must) -> DayStop {
        DayStop(id: id, placeId: place, kind: kind, start: .now, end: .now, label: label, note: "")
    }

    @Test func outraMarcaQuemEntrouESaiu() {
        let old = [stop("m-cafe", "c1", "Fuglen · café", kind: .micro), stop("p-j05", "j05", "Fuunji · tsukemen"),
                   stop("p-j10", "j10", "Gyoen")]
        let new = [stop("m-cafe", "c2", "Glitch · café", kind: .micro), stop("p-j07", "j07", "Afuri · ramen"),
                   stop("p-j10", "j10", "Gyoen")]
        let diff = ProposalDiff(old: old, new: new)
        #expect(diff.changedIds == ["m-cafe", "p-j07"])
        #expect(diff.added == ["Afuri"])
        #expect(diff.removed == ["Fuunji"])
        #expect(diff.title == "2 trocas")
        #expect(diff.detail == "entrou Afuri · saiu Fuunji")
    }

    @Test func mesmoDiaDizQueNadaMudou() {
        let day = [stop("p-j05", "j05", "Fuunji"), stop("p-j10", "j10", "Gyoen")]
        let diff = ProposalDiff(old: day, new: day)
        #expect(diff.changedIds.isEmpty)
        #expect(diff.detail == nil)
        #expect(diff.title.hasPrefix("Mesmo dia"))
    }
}

@MainActor
struct PlaceCostTests {
    private func place(_ list: String, price: Double? = nil, art: ArtEvent? = nil) -> Place {
        let p = Place(id: "x", name: "Lugar", cityId: "bh", lat: -19.93, lng: -43.93)
        p.list = MustList(id: list, name: list, icon: .cafe, color: .eat)
        p.price = price
        if let art { p.extra = PlaceExtra(art: art) }
        return p
    }

    @Test func museuGratisApareceComoGratis() {
        // O seed marca museu de graça com `price: 0`; antes a ficha escondia e só mostrava o pagamento.
        let cost = PlaceFicha.cost(place("art", price: 0), region: .bh, now: .now)
        #expect(cost == PlaceFicha.Cell(label: "entrada", value: "grátis"))
    }

    @Test func inteiraEMeia() throws {
        let art = ArtEvent(priceAdult: 2_000, priceStudent: 1_000, freeNote: nil)
        let cost = try #require(PlaceFicha.cost(place("art", art: art), region: .jp, now: .now))
        #expect(cost.label == "entrada")
        #expect(cost.value.contains("meia"))
        #expect(cost.value.hasPrefix(Region.jp.money(2_000)))
    }

    @Test func comidaEPrecoEFichaTemOCusto() {
        let p = place("eat", price: 80)
        #expect(PlaceFicha.cost(p, region: .bh, now: .now)?.label == "preço")
        let cells = PlaceFicha.cells(p, region: .bh, now: .now, here: nil, walkMaxKm: 1.5, queueFirst: false)
        #expect(cells.contains { $0.label == "preço" })
        #expect(cells.contains { $0.label == "pagamento" })
    }

    @Test func semDadoNaoInventaPreco() {
        #expect(PlaceFicha.cost(place("art"), region: .bh, now: .now) == nil)
    }
}
