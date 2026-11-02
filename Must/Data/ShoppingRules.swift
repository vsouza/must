import Foundation

// Regras da volta por par de países (`Must/Data/rules/<par>.json`, no bundle). Cada regra tem `checkedAt` e `sourceURL`.
// Os números (limites, taxas) ficam no mesmo arquivo; o código só faz a conta.

enum ShoppingRuleSection: String, Codable, CaseIterable, Sendable {
    case taxFree, carry, entering, food
}

enum ShoppingTone: String, Codable, CaseIterable, Sendable {
    case ok, warn, no
}

struct ShoppingRule: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var section: ShoppingRuleSection
    var tone: ShoppingTone
    /// Texto da regra; `**negrito**` é o único marcador.
    var text: String
    /// Data da conferência ("2026-11-02").
    var checkedAt: String
    /// Página oficial da regra.
    var sourceURL: String
}

struct ShoppingLimits: Codable, Hashable, Sendable {
    /// Compra mínima por loja/dia pra ter reembolso (¥).
    var taxFreeMinYen: Double
    /// Taxa de consumo embutida no preço (reembolsada na volta): geral e alimentos.
    var taxFreeRate: Double
    var taxFreeRateFood: Double
    /// Cota de compras no aéreo (US$ por pessoa) e no free shop da chegada.
    var airAllowanceUSD: Double
    var freeShopUSD: Double
    /// Parte do excedente que paga pela e-DBV.
    var excessRate: Double
    /// Bebida alcoólica total (litros) e a regra dos iguais.
    var liquorLitres: Double
    var identicalAboveUSD: Double
    var identicalAboveMax: Int
    var identicalBelowMax: Int
    var personalCameras: Int

    /// Os números de `jp-br.json` (usado só se o arquivo não estiver no bundle).
    static let standard = ShoppingLimits(
        taxFreeMinYen: 5_000, taxFreeRate: 0.10, taxFreeRateFood: 0.08, airAllowanceUSD: 1_000, freeShopUSD: 1_000,
        excessRate: 0.5, liquorLitres: 12, identicalAboveUSD: 10, identicalAboveMax: 3, identicalBelowMax: 10, personalCameras: 1)
}

struct ShoppingRulePack: Codable, Sendable {
    var pair: String
    var from: String
    var to: String
    var limits: ShoppingLimits
    var rules: [ShoppingRule]

    /// Regras de uma seção, na ordem do arquivo.
    func rules(in section: ShoppingRuleSection) -> [ShoppingRule] {
        rules.filter { $0.section == section }
    }

    func rule(_ id: String) -> ShoppingRule? { rules.first { $0.id == id } }
}

enum ShoppingRules {
    /// Pacote Japão → Brasil (a volta). Carregado uma vez.
    static let jpBR: ShoppingRulePack = load(named: "jp-br", bundle: nil)
        ?? ShoppingRulePack(pair: "JP-BR", from: "JP", to: "BR", limits: .standard, rules: [])

    private final class BundleAnchor {}

    /// Lê `<nome>.json` do bundle (o app, ou o bundle de testes como plano B). Nil se não achar ou não decodificar.
    static func load(named name: String, bundle: Bundle?) -> ShoppingRulePack? {
        for candidate in [bundle ?? .main, Bundle(for: BundleAnchor.self)] {
            guard let url = candidate.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let pack = try? JSONDecoder().decode(ShoppingRulePack.self, from: data) else { continue }
            return pack
        }
        Log.app.error("regras \(name, privacy: .public) não estão no bundle")
        return nil
    }
}
