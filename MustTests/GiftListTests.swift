import Foundation
import Testing
@testable import Must

/// Lista fácil de Presentes: atalho de pessoa no campo rápido, link colado, filtro, contagem e ordem (comprado desce).
@MainActor
struct GiftListTests {
    @Test func atalhoPra() {
        let e = GiftQuick.parse("Kit Kat de matcha pra Ana")
        #expect(e == GiftQuickEntry(title: "Kit Kat de matcha", person: "Ana", url: nil, personExplicit: true))
    }

    @Test func atalhoTravessaEHifen() {
        #expect(GiftQuick.parse("Furoshiki — Mãe")?.person == "Mãe")
        #expect(GiftQuick.parse("Furoshiki - mãe")?.person == "Mãe")
        #expect(GiftQuick.parse("Furoshiki para Ana Paula")?.person == "Ana Paula")
    }

    @Test func semAtalhoFicaTudoNoTitulo() {
        let e = GiftQuick.parse("Bolsa pra notebook de couro marrom")
        #expect(e?.title == "Bolsa pra notebook de couro marrom")
        #expect(e?.personExplicit == false)
        #expect(GiftQuick.parse("Camiseta - 2 unidades")?.person == "")
    }

    @Test func linhaVaziaNaoCria() {
        #expect(GiftQuick.parse("   ") == nil)
        #expect(GiftQuick.parse("") == nil)
    }

    @Test func linkColadoViraPresenteComLink() {
        let e = GiftQuick.parse("https://www.amazon.co.jp/dp/B000 pra Pedro")
        #expect(e?.url == "https://www.amazon.co.jp/dp/B000")
        #expect(e?.title == "amazon.co.jp")
        #expect(e?.person == "Pedro")
        #expect(GiftQuick.parse("Disco https://loja.jp/x")?.title == "Disco")
    }

    private func gift(_ id: String, _ person: String, bought: Bool = false, price: Double = 1_000, order: Int = 0) -> Gift {
        let g = Gift(id: id, title: id, person: person, estimatedPrice: price, order: order)
        if bought { g.boughtAt = Date(timeIntervalSince1970: 1_000); g.paidPrice = price }
        return g
    }

    @Test func filtroEContagem() {
        let all = [gift("a", "Ana"), gift("b", "Ana", bought: true), gift("c", "Mãe"), gift("d", "")]
        #expect(GiftFilter.pending.apply(all).map(\.id) == ["a", "c", "d"])
        #expect(GiftFilter.all.apply(all).count == 4)
        #expect(GiftFilter.person("Ana").apply(all).map(\.id) == ["a", "b"])
        #expect(GiftFilter.person(GiftLogic.noPerson).apply(all).map(\.id) == ["d"])
        #expect(GiftLogic.pendingOfText(all) == "3 faltam de 4")
        #expect(GiftLogic.pendingText([gift("x", "A")]) == "1 falta")
        #expect(GiftLogic.pendingOfText([]) == "lista vazia")
        #expect(GiftLogic.pendingText([gift("x", "A", bought: true)]) == "tudo comprado")
    }

    @Test func compradoDesceProFimDoGrupo() {
        let items = [gift("a", "Ana", bought: true, order: 0), gift("b", "Ana", order: 1), gift("c", "Ana", order: 2)]
        let groups = GiftLogic.groups(items)
        #expect(groups.count == 1)
        #expect(groups[0].gifts.map(\.id) == ["b", "c", "a"])
    }

    @Test func campoHerdaPessoaDoUltimoGrupo() {
        let groups = GiftLogic.groups([gift("a", "Ana"), gift("b", "Mãe"), gift("c", "")])
        #expect(GiftQuick.inheritedPerson(groups) == "")
        #expect(GiftQuick.inheritedPerson(GiftLogic.groups([gift("a", "Ana"), gift("b", "Mãe")])) == "Mãe")
        #expect(GiftQuick.inheritedPerson([]) == "")
    }
}
