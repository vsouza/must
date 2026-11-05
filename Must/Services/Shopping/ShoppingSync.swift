import Foundation
import SwiftData

// Liga a lista de compras ao resto do app (prompt 17 · B, itens 7, 10 e 11):
// o checklist do voo de volta ganha os itens da volta; comprar cria o gasto e marca a loja como visitada.

/// Itens automáticos do voo de volta. Os ids começam com `shop-`: são do app, não do usuário.
enum ShoppingFlightSync {
    static let idPrefix = "shop-"

    /// Voo de volta: sai do Japão e chega ao Brasil (o último trecho pousa no Brasil).
    static func returnFlight(in flights: [Flight]) -> Flight? {
        flights.first { flight in
            guard let last = flight.legs.last else { return false }
            return Airports.isBrazil(last.to) && FlightRules.touchesJapan(flight.legs)
        }
    }

    /// Os itens que a lista pede agora (só os que se aplicam).
    static func desiredItems(for report: ShoppingReport) -> [ChecklistItem] {
        var out: [ChecklistItem] = []
        let tf = report.taxFree
        if tf.receipts > 0 {
            out.append(ChecklistItem(id: "\(idPrefix)taxfree", phase: .airport,
                                     title: "Tax-free: \(tf.receipts) \(tf.receipts == 1 ? "recibo" : "recibos") no quiosque antes do check-in",
                                     note: "reembolso de \(report.baseMoney(tf.refund)) · com o passaporte"))
        }
        if report.needsEDBV {
            out.append(ChecklistItem(id: "\(idPrefix)edbv", phase: .h72, title: "e-DBV se passar da cota",
                                     note: "cota de \(ShoppingReport.usdText(report.limits.airAllowanceUSD)) · o excedente paga 50%"))
        }
        if report.hasFood {
            out.append(ChecklistItem(id: "\(idPrefix)declare", phase: .arrival, title: "Declarar alimentos se tiver dúvida",
                                     note: "lacrado e rotulado passa · porco e leite cru não"))
        }
        return out
    }

    /// Põe os itens no voo de volta: some o que não se aplica mais, muda o texto do que mudou, mantém o marcado.
    /// Devolve `true` se o checklist mudou (o chamador grava o contexto).
    @discardableResult
    static func apply(_ report: ShoppingReport, flights: [Flight]) -> Bool {
        guard let flight = returnFlight(in: flights) else { return false }
        let before = flight.checklist
        var list = before.filter { !$0.id.hasPrefix(idPrefix) }
        for wanted in desiredItems(for: report) {
            if let index = before.firstIndex(where: { $0.id == wanted.id }) {
                var kept = before[index]
                kept.title = wanted.title
                kept.note = wanted.note
                kept.phase = wanted.phase
                list.append(kept)
            } else {
                list.append(wanted)
            }
        }
        // Mantém a ordem do checklist: os próprios primeiro, depois os de compras (na ordem de `desiredItems`).
        guard list != before else { return false }
        flight.checklist = list
        return true
    }

    /// Relê a região inteira (itens, ajustes, voos) e atualiza o voo de volta. Chamar depois de salvar um item.
    @MainActor
    static func refresh(context: ModelContext, region: Region) {
        let settings = context.settings(for: region)
        let report = ShoppingReport(items: context.shoppingItems(), fxRate: ShoppingFX.baseRate(for: region, userRate: settings.fxRate),
                                    brlPerUSD: settings.brlPerUSD, regionCurrency: region.currency,
                                    rules: ShoppingRules.pack(for: region), timeZone: region.timeZone)
        if apply(report, flights: context.flights()) { try? context.save() }
    }
}

/// Comprado: um `Expense` de compras e a loja marcada como visitada (済), sem duplicar nada.
@MainActor
enum ShoppingPurchase {
    /// Põe o gasto e a visita de acordo com o status do item. Chamar depois de mudar o item.
    /// O gasto fica na moeda da região: item em outra moeda é convertido pelo câmbio e a nota guarda o valor original.
    static func sync(_ item: ShoppingItem, store: Place?, context: ModelContext, now: Date = AppClock.now,
                     regionCurrency: String = "JPY", brlPerYen: Double = ShoppingFX.brlPerYen,
                     brlPerUSD: Double = ShoppingFX.brlPerUSD, brlPerEUR: Double = ShoppingFX.brlPerEUR) {
        if item.isBought {
            let date = item.boughtAt ?? now
            item.boughtAt = date
            let original = item.paid ?? item.estPrice
            let itemCurrency = item.currency ?? regionCurrency
            let amount = ShoppingFX.convert(original, from: itemCurrency, to: regionCurrency,
                                            brlPerYen: brlPerYen, brlPerUSD: brlPerUSD, brlPerEUR: brlPerEUR)
            let note = itemCurrency == regionCurrency ? "" : ShoppingReport.money(original, currency: itemCurrency)
            if let expense = expense(for: item, context: context) {
                expense.amount = amount
                expense.note = note
                expense.at = date
                expense.place = store
            } else {
                let expense = Expense(at: date, amount: amount, category: .shop, place: store, method: .card)
                expense.note = note
                context.insert(expense)
                item.expenseId = expense.id
            }
            if let store, store.done == nil {
                store.done = DoneMark(at: date, spent: amount)
            }
        } else {
            if let expense = expense(for: item, context: context) { context.delete(expense) }
            item.expenseId = nil
            item.boughtAt = nil
        }
    }

    /// Apaga o item e o gasto dele (a loja continua visitada: pode ter outras compras).
    static func delete(_ item: ShoppingItem, context: ModelContext) {
        if let expense = expense(for: item, context: context) { context.delete(expense) }
        context.delete(item)
    }

    private static func expense(for item: ShoppingItem, context: ModelContext) -> Expense? {
        guard let id = item.expenseId else { return nil }
        return try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first
    }
}
