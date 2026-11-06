import Foundation

// Conta da lista de compras (prompt 17 · B, itens 7–8): previsto, já gasto, cota do Brasil, tax-free a receber,
// álcool e a regra dos iguais, alertas e o impacto de cada regra na lista do usuário. Puro: testável sem SwiftData.
struct ShoppingAlert: Identifiable, Hashable, Sendable {
    var id: String
    /// Regra que o alerta contraria (`ShoppingRule.id`).
    var ruleId: String
    var text: String
}

/// Linha "sua lista: …" de uma regra, com o tom (verde, âmbar, vermelho).
struct ShoppingImpact: Hashable, Sendable {
    var text: String
    var tone: ShoppingTone
}

/// Câmbio da lista, num lugar só. Tudo que é conta passa por aqui: cada item converte da própria moeda pra moeda das
/// regras da volta (¥ no pacote do Japão, € no da Itália) e pra R$ e US$ com estes valores. `Settings.fxRate` é o
/// câmbio que o usuário editou pra moeda da região (R$ por ¥1 no Japão, por €1 na Itália); no Brasil ele é 1.
enum ShoppingFX {
    /// R$ por ¥1 quando não há cotação do usuário.
    static let brlPerYen = 0.036
    /// R$ por €1 quando não há cotação do usuário (o mesmo valor de referência de `Region.it`).
    static let brlPerEUR = Region.it.defaultFXRate
    /// R$ por US$ 1 (`Settings.brlPerUSD` começa aqui).
    static let brlPerUSD = 5.5

    /// R$ por ¥1 da região: o câmbio do usuário (Ajustes) só vale no Japão; fora dele usa o padrão.
    static func rate(for region: Region, userRate: Double?) -> Double {
        guard region.currency == "JPY", let rate = userRate, rate > 0 else { return brlPerYen }
        return rate
    }

    /// R$ por €1 da região: o câmbio do usuário só vale na Itália; fora dela usa o padrão.
    static func eurRate(for region: Region, userRate: Double?) -> Double {
        guard region.currency == "EUR", let rate = userRate, rate > 0 else { return brlPerEUR }
        return rate
    }

    /// R$ por 1 unidade da moeda das regras da volta da região (o `fxRate` do `ShoppingReport`): € em Roma, ¥ no resto.
    static func baseRate(for region: Region, userRate: Double?) -> Double {
        region.currency == "EUR" ? eurRate(for: region, userRate: userRate) : rate(for: region, userRate: userRate)
    }

    /// Converte um valor de uma moeda pra outra pelo câmbio (passa por R$).
    static func convert(_ value: Double, from: String, to: String, brlPerYen: Double, brlPerUSD: Double,
                        brlPerEUR: Double = ShoppingFX.brlPerEUR) -> Double {
        let brl = value * brlPerUnit(from, brlPerYen: brlPerYen, brlPerUSD: brlPerUSD, brlPerEUR: brlPerEUR)
        return brl / brlPerUnit(to, brlPerYen: brlPerYen, brlPerUSD: brlPerUSD, brlPerEUR: brlPerEUR)
    }

    /// Quanto vale 1 unidade da moeda em R$. Moeda desconhecida conta como R$ (não some).
    static func brlPerUnit(_ currency: String, brlPerYen: Double, brlPerUSD: Double, brlPerEUR: Double = ShoppingFX.brlPerEUR) -> Double {
        switch currency {
        case "JPY": brlPerYen
        case "USD": brlPerUSD
        case "EUR": brlPerEUR
        default: 1
        }
    }
}

struct ShoppingReport {
    /// Reembolso da saída: recibos que entram (loja/dia com pelo menos ¥ 5.000) e o total.
    struct TaxFree: Equatable, Sendable {
        var receipts: Int = 0
        var refund: Double = 0
        /// Lojas/dia com recibo mas abaixo do mínimo: sem reembolso.
        var belowMinStores: Int = 0
        /// O mesmo, contando também o que ainda não foi comprado (a "volta ~" do topo).
        var plannedRefund: Double = 0
    }

    /// Unidades iguais (mesmo nome) somadas.
    struct Identical: Equatable, Sendable {
        var name: String
        var units: Int
        var unitUSD: Double
    }

    let items: [ShoppingItem]
    /// R$ por 1 unidade de `baseCurrency` (¥ no Japão, € na Itália: o câmbio de Ajustes, ou `ShoppingFX.baseRate`).
    let fxRate: Double
    /// Moeda das regras da volta (a base das contas, dos mínimos do tax-free e do reembolso): ¥ ou €.
    /// O nome "yen" nas funções ficou do pacote do Japão; com o pacote da Itália, é em euro.
    let baseCurrency: String
    /// R$ por US$ 1 (`Settings.brlPerUSD`).
    let brlPerUSD: Double
    /// Moeda da região: a que aparece nos totais. Item sem moeda própria usa esta.
    let regionCurrency: String
    let rules: ShoppingRulePack
    let timeZone: TimeZone

    init(items: [ShoppingItem], fxRate: Double, brlPerUSD: Double, regionCurrency: String = "JPY",
         rules: ShoppingRulePack = ShoppingRules.jpBR, timeZone: TimeZone = Region.jp.timeZone) {
        self.items = items
        self.baseCurrency = rules.from == "IT" ? "EUR" : "JPY"
        self.fxRate = fxRate > 0 ? fxRate : (baseCurrency == "EUR" ? ShoppingFX.brlPerEUR : ShoppingFX.brlPerYen)
        self.brlPerUSD = brlPerUSD > 0 ? brlPerUSD : ShoppingFX.brlPerUSD
        self.regionCurrency = regionCurrency
        self.rules = rules
        self.timeZone = timeZone
    }

    var limits: ShoppingLimits { rules.limits }

    // MARK: Conversão

    /// Moeda do item: a própria, ou a da região.
    func currency(of item: ShoppingItem) -> String { item.currency ?? regionCurrency }

    /// R$ por 1 unidade da moeda: a base usa `fxRate`; as outras, o padrão de `ShoppingFX`.
    func brlPerUnit(_ currency: String) -> Double {
        currency == baseCurrency ? fxRate : ShoppingFX.brlPerUnit(currency, brlPerYen: ShoppingFX.brlPerYen, brlPerUSD: brlPerUSD)
    }

    /// Valor do item (o pago ou o estimado) convertido pra moeda base (¥/€): a base das regras da volta.
    func yen(of item: ShoppingItem) -> Double {
        item.committedAmount * brlPerUnit(currency(of: item)) / fxRate
    }

    /// Um valor na moeda base convertido pra outra moeda (R$, US$, ¥ ou €).
    func amount(yen: Double, in currency: String) -> Double {
        yen * fxRate / brlPerUnit(currency)
    }

    /// Valor na moeda base com símbolo ("¥ 5.000", "€ 70").
    func baseMoney(_ value: Double) -> String { Self.money(value, currency: baseCurrency) }

    /// Um valor em ¥ na moeda da região (o que os totais mostram).
    func regionAmount(yen: Double) -> Double { amount(yen: yen, in: regionCurrency) }

    // MARK: Totais

    /// Previsto em ¥: estimado dos não comprados + pago dos comprados.
    var planned: Double { items.reduce(0) { $0 + yen(of: $1) } }

    /// Já gasto em ¥ (só dos comprados).
    var spent: Double { items.filter(\.isBought).reduce(0) { $0 + yen(of: $1) } }

    var plannedBRL: Double { amount(yen: planned, in: "BRL") }

    /// Quanto da cota do Brasil a lista usa, em US$ (previsto convertido).
    var usedUSD: Double { usd(planned) }

    /// Parte da cota que já é compra feita, em US$.
    var boughtUSD: Double { usd(spent) }

    /// Cota passou da parte do aéreo: vale a e-DBV pelo excedente.
    var needsEDBV: Bool { usedUSD > limits.airAllowanceUSD }

    /// US$ a partir de ¥: ¥ → R$ (× fxRate) → US$ (÷ R$ por US$).
    func usd(_ yen: Double) -> Double { yen * fxRate / brlPerUSD }

    // MARK: Tax-free

    /// Reembolso em ¥ (as regras são em iene).
    var taxFree: TaxFree {
        let bought = items.filter { $0.taxFreeReceipt && $0.isBought }
        let real = refundable(bought)
        let all = refundable(items.filter(\.taxFreeReceipt))
        return TaxFree(receipts: real.receipts, refund: real.refund, belowMinStores: real.belowMin, plannedRefund: all.refund)
    }

    /// Recibos que entram no reembolso: agrupa por loja e dia; cada grupo precisa de ¥ 5.000 (sem imposto e sem o mínimo, o recibo perde).
    func refundable(_ list: [ShoppingItem]) -> (receipts: Int, refund: Double, belowMin: Int) {
        let groups = Dictionary(grouping: list) { item in
            "\(item.storeId ?? item.storeName)|\(FlightRules.dayKey(item.boughtAt ?? item.createdAt, zone: timeZone))"
        }
        var receipts = 0
        var refund = 0.0
        var belowMin = 0
        for group in groups.values {
            let total = group.reduce(0) { $0 + yen(of: $1) }
            guard total >= limits.taxFreeMinYen else {
                belowMin += 1
                continue
            }
            receipts += group.count
            refund += group.reduce(0) { $0 + Self.refundOf(yen: yen(of: $1), category: $1.category, limits: limits) }
        }
        return (receipts, refund.rounded(), belowMin)
    }

    /// Imposto de volta de um item (em ¥): o preço tem a taxa embutida (preço × taxa / (1 + taxa)).
    static func refundOf(yen: Double, category: ShoppingCategory, limits: ShoppingLimits) -> Double {
        let rate = category == .food ? limits.taxFreeRateFood : limits.taxFreeRate
        return yen * rate / (1 + rate)
    }

    // MARK: Álcool e iguais

    /// Litros de bebida alcoólica na lista (unidades × volume do nome/notas). Sem volume, conta zero.
    var liquorLitres: Double {
        items.filter { $0.flags.contains(.alcohol) }.reduce(0) { $0 + Double($1.qty) * (volume(of: $1) ?? 0) }
    }

    func volume(of item: ShoppingItem) -> Double? {
        ShoppingChecks.volumeLitres(in: [item.name, item.notes, item.ingredients].joined(separator: " "))
    }

    /// Itens iguais (mesmo nome), com unidades e preço unitário em US$.
    var identicals: [Identical] {
        let groups = Dictionary(grouping: items) { ShoppingChecks.identityKey($0.name) }
        return groups.values.map { group in
            let units = group.reduce(0) { $0 + $1.qty }
            let total = group.reduce(0) { $0 + yen(of: $1) }
            return Identical(name: group[0].name, units: units, unitUSD: usd(total / Double(max(units, 1))))
        }
        .sorted { ($0.name.lowercased(), $0.units) < ($1.name.lowercased(), $1.units) }
    }

    /// Passa da regra dos iguais: acima de US$ 10 no máximo 3; abaixo, até 10.
    func exceedsIdentical(_ identical: Identical) -> Bool {
        let cap = identical.unitUSD > limits.identicalAboveUSD ? limits.identicalAboveMax : limits.identicalBelowMax
        return identical.units > cap
    }

    // MARK: Alertas

    var alerts: [ShoppingAlert] {
        var out: [ShoppingAlert] = []
        for item in items {
            if item.flags.contains(.pork) {
                out.append(ShoppingAlert(id: "pork-\(item.id)", ruleId: "food-pork", text: "\(item.name): porco"))
            }
            if item.flags.contains(.rawMilk) || item.flags.contains(.fruitOrSeed) {
                let what = item.flags.contains(.rawMilk) ? "leite cru" : "fruta/semente"
                out.append(ShoppingAlert(id: "raw-\(item.id)", ruleId: "food-raw", text: "\(item.name): \(what)"))
            }
            if item.flags.contains(.alcohol), volume(of: item) == nil {
                out.append(ShoppingAlert(id: "volume-\(item.id)", ruleId: "entering-liquor", text: "\(item.name): sem volume"))
            }
        }
        if liquorLitres > limits.liquorLitres {
            out.append(ShoppingAlert(id: "liquor", ruleId: "entering-liquor",
                                     text: "álcool \(Self.litres(liquorLitres)) L · passa de \(Self.litres(limits.liquorLitres)) L"))
        }
        for identical in identicals where exceedsIdentical(identical) {
            out.append(ShoppingAlert(id: "identical-\(identical.name)", ruleId: "entering-liquor",
                                     text: "\(identical.name) × \(identical.units): passa do limite de iguais"))
        }
        if needsEDBV {
            out.append(ShoppingAlert(id: "allowance", ruleId: "entering-allowance",
                                     text: "cota \(Self.usdText(usedUSD)) de \(Self.usdText(limits.airAllowanceUSD)) · e-DBV"))
        }
        if taxFree.belowMinStores > 0 {
            out.append(ShoppingAlert(id: "taxfree-min", ruleId: "taxfree-min",
                                     text: "\(taxFree.belowMinStores) loja(s) abaixo de \(baseMoney(limits.taxFreeMinYen)) · sem reembolso"))
        }
        return out
    }

    var hasFood: Bool { items.contains { $0.category == .food } }

    /// Impacto de uma regra na lista do usuário (nil = a lista não toca nessa regra).
    func impact(for ruleId: String) -> ShoppingImpact? {
        switch ruleId {
        case "taxfree-refund":
            let tf = taxFree
            return ShoppingImpact(text: "ainda falta: \(tf.receipts) \(tf.receipts == 1 ? "recibo" : "recibos") · \(baseMoney(tf.refund)) de volta",
                                  tone: tf.receipts > 0 ? .ok : .warn)
        case "taxfree-min", "taxfree-eu-min":
            let below = taxFree.belowMinStores
            return below > 0 ? ShoppingImpact(text: "\(below) loja(s) abaixo de \(baseMoney(limits.taxFreeMinYen)) · sem reembolso", tone: .no) : nil
        case "carry-powerbank":
            return named(["power bank", "powerbank", "bateria externa"]).map { ShoppingImpact(text: "sua lista: \($0) · na mão", tone: .ok) }
        case "carry-knife":
            return named(["faca", "包丁", "knife"]).map { ShoppingImpact(text: "sua lista: \($0) · despachar", tone: .warn) }
        case "carry-film":
            let rolls = items.filter { Self.matchesAny($0.name, ["filme", "film", "portra", "ektar", "kodak", "ilford", "fuji "]) }
            let count = rolls.reduce(0) { $0 + $1.qty }
            return rolls.isEmpty ? nil : ShoppingImpact(text: "sua lista: \(count) \(count == 1 ? "rolo" : "rolos") · na mão", tone: .ok)
        case "entering-allowance":
            let over = needsEDBV
            return ShoppingImpact(text: "sua lista: \(Self.usdText(usedUSD))\(over ? " · excedente: e-DBV" : "")", tone: over ? .warn : .ok)
        case "entering-camera":
            let cameras = items.filter { $0.category == .cameras && Self.matchesAny($0.name, Self.cameraWords) && !$0.name.lowercased().contains("bolsa") }
                .reduce(0) { $0 + $1.qty }
            guard cameras > 0 else { return nil }
            let fine = cameras <= limits.personalCameras
            return ShoppingImpact(text: fine ? "sua lista: \(cameras) câmera" : "sua lista: \(cameras) câmeras · só \(limits.personalCameras) de uso pessoal",
                                  tone: fine ? .ok : .warn)
        case "entering-liquor":
            var parts: [String] = []
            if liquorLitres > 0 {
                parts.append("\(liquorLitres > limits.liquorLitres ? "passa" : "álcool") \(Self.litres(liquorLitres)) de \(Self.litres(limits.liquorLitres)) L")
            }
            for identical in identicals where identical.units > 1 && !items.contains(where: { $0.flags.contains(.alcohol) && ShoppingChecks.identityKey($0.name) == ShoppingChecks.identityKey(identical.name) }) {
                let ok = !exceedsIdentical(identical)
                parts.append("\(identical.name) × \(identical.units): \(ok ? "ok" : "acima do limite") (\(identical.unitUSD > limits.identicalAboveUSD ? "acima de US$ 10, até \(limits.identicalAboveMax)" : "abaixo de US$ 10, até \(limits.identicalBelowMax)"))")
            }
            guard !parts.isEmpty else { return nil }
            return ShoppingImpact(text: parts.joined(separator: " · "), tone: alerts.contains { $0.ruleId == "entering-liquor" } ? .no : .ok)
        case "food-pork":
            let pork = items.filter { $0.flags.contains(.pork) }.map(\.name)
            if pork.isEmpty { return ShoppingImpact(text: "nada suíno na sua lista", tone: .ok) }
            return ShoppingImpact(text: "na sua lista: \(pork.joined(separator: ", ")) · trocar por shoyu?", tone: .no)
        case "food-raw":
            let flagged = items.filter { $0.flags.contains(.rawMilk) || $0.flags.contains(.fruitOrSeed) }.map(\.name)
            return flagged.isEmpty ? nil : ShoppingImpact(text: "na sua lista: \(flagged.joined(separator: ", "))", tone: .no)
        case "food-packaged":
            let packaged = items.filter { $0.category == .food && $0.flags.isEmpty }.count
            return packaged > 0 ? ShoppingImpact(text: "ok na sua lista: \(packaged) \(packaged == 1 ? "item" : "itens") lacrado", tone: .ok) : nil
        default:
            return nil
        }
    }

    // MARK: Texto

    /// "¥ 15.400" (pt-BR, sem símbolo no número).
    static func yen(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0)).grouping(.automatic))
    }

    /// "US$ 740".
    static func usdText(_ value: Double) -> String {
        "US$ " + value.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0)).grouping(.automatic))
    }

    /// Valor com símbolo da moeda, pt-BR ("¥ 15.400", "R$ 6.700").
    static func money(_ value: Double, currency: String) -> String {
        value.formatted(.money(currency))
    }

    /// Curto pra linha de cima do total: "15k" pra 15.400, "740" abaixo de mil.
    static func compact(_ value: Double) -> String {
        if abs(value) >= 1_000 {
            return "\(Int((value / 1_000).rounded()))k"
        }
        return yen(value)
    }

    /// "1,4" (uma casa, pt-BR).
    static func litres(_ value: Double) -> String {
        value.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0...1)))
    }

    private static let cameraWords = ["câmera", "camera", "contax", "leica", "nikon", "canon", "fuji", "olympus", "ricoh", "pentax", "minolta", "sony"]

    static func matchesAny(_ name: String, _ words: [String]) -> Bool {
        let lowered = name.lowercased()
        return words.contains { lowered.contains($0) }
    }

    /// Primeiro item cujo nome casa com uma das palavras (pra "sua lista: faca · despachar").
    private func named(_ words: [String]) -> String? {
        items.first { Self.matchesAny($0.name, words) }?.name
    }
}
