import Foundation
import Testing
@testable import Must

/// Compras › Regras da volta (IT) (prompt 24 §2): `Must/Data/rules/it-br.json`.
struct ShoppingITTests {
    @Test func pacoteDaItaliaCarregaDoBundle() {
        let pack = ShoppingRules.itBR
        #expect(pack.pair == "IT-BR")
        #expect(pack.from == "IT")
        #expect(pack.to == "BR")
        #expect(pack.limits.taxFreeMinYen == 70, "mínimo do tax-free da UE em €, por loja")
        #expect(pack.limits.liquorLitres == 12)
        #expect(pack.limits.airAllowanceUSD == 1_000)
        #expect(ShoppingRules.load(named: "it-br", bundle: nil) != nil)
        for section in ShoppingRuleSection.allCases {
            #expect(!pack.rules(in: section).isEmpty, "seção \(section) vazia")
        }
        for rule in pack.rules {
            #expect(rule.sourceURL.hasPrefix("https://"))
            #expect(rule.checkedAt.count == 10)
        }
        #expect(Set(pack.rules.map(\.id)).count == pack.rules.count)
    }

    @Test func regrasDeRoma() throws {
        let pack = ShoppingRules.itBR
        let cheese = try #require(pack.rule("food-cheese"))
        #expect(cheese.tone == .ok)
        #expect(cheese.text.contains("vácuo"))
        let meat = try #require(pack.rule("food-cured-meat"))
        #expect(meat.tone == .no)
        #expect(meat.text.localizedCaseInsensitiveContains("salame"))
        #expect(meat.text.localizedCaseInsensitiveContains("presunto"))
        #expect(meat.sourceURL.contains("agricultura"), "Vigiagro (MAPA)")
        #expect(try #require(pack.rule("entering-liquor")).text.contains("12 L"))
        let min = try #require(pack.rule("taxfree-eu-min"))
        #expect(min.text.contains("€ 70"))
        #expect(min.text.contains("Global Blue"))
        #expect(try #require(pack.rule("taxfree-eu-passport")).text.contains("passaporte"))
        #expect(try #require(pack.rule("taxfree-eu-stamp")).text.localizedCaseInsensitiveContains("carimbo"))
        // Nada do Japão no pacote da Itália.
        #expect(pack.rules.allSatisfy { !$0.text.contains("¥") && !$0.sourceURL.contains("mof.go.jp") })
    }

    @Test func pacotePorRegiao() {
        #expect(ShoppingRules.pack(for: .it).pair == "IT-BR")
        #expect(ShoppingRules.pack(for: .jp).pair == "JP-BR")
        #expect(ShoppingRuleSection.taxFree.title(from: "IT") == "Tax-free na UE · Global Blue")
        #expect(ShoppingRuleSection.taxFree.title(from: "JP") == ShoppingRuleSection.taxFree.title)
        #expect(ShoppingRuleSection.food.title(from: "IT") == ShoppingRuleSection.food.title)
    }
}
