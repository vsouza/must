import Foundation
import SwiftData

extension GiftLogic {
    /// Corrige o valor pago (painel "Comprado"): o gasto do dia acompanha.
    static func setPaid(_ gift: Gift, to paid: Double, context: ModelContext) {
        gift.paidPrice = paid
        if let id = gift.expenseId,
           let expense = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first {
            expense.amount = paid
        }
        try? context.save()
    }

    /// Mínimo pra valer o tax-free numa loja no mesmo dia (Japão: ¥ 5.000, com passaporte). Outras moedas: sem medidor.
    static func taxFreeMinimum(currency: String) -> Double? { currency == "JPY" ? 5_000 : nil }

    /// A loja de um presente como chave de "mesma loja" ("p12" do board, ou o nome em minúsculas).
    static func storeKey(_ gift: Gift) -> String? {
        if let id = gift.boughtPlaceId ?? gift.placeId { return "place:\(id)" }
        let name = gift.storeName.trimmingCharacters(in: .whitespaces).lowercased()
        return name.isEmpty ? nil : "name:\(name)"
    }

    /// Quanto já foi comprado (pago) nessa loja nesse dia, de todos os presentes.
    static func spentAtStore(_ gifts: [Gift], key: String, on day: Date, calendar: Calendar) -> Double {
        gifts.filter { $0.boughtAt.map { calendar.isDate($0, inSameDayAs: day) } == true && storeKey($0) == key }
            .reduce(0) { $0 + ($1.paidPrice ?? $1.estimatedTotal) }
    }

    /// Medidor do tax-free: quanto já foi, o mínimo e o que falta.
    struct TaxFree: Equatable {
        var spent: Double
        var minimum: Double
        var missing: Double { max(0, minimum - spent) }
        var reached: Bool { spent >= minimum }
        var fraction: Double { min(1, spent / minimum) }
    }

    static func taxFree(for gift: Gift, among gifts: [Gift], on day: Date, calendar: Calendar, currency: String, extra: Double = 0) -> TaxFree? {
        guard let minimum = taxFreeMinimum(currency: currency), let key = storeKey(gift) else { return nil }
        let others = gifts.filter { $0.id != gift.id }
        return TaxFree(spent: spentAtStore(others, key: key, on: day, calendar: calendar) + extra, minimum: minimum)
    }
}
