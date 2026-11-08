import Foundation

/// Acertar contas (prompt 32): saldo por pessoa e o mínimo de transferências. Puro: valores em unidades menores da moeda
/// (centavos; iene = 0 casas) pra a soma fechar sempre, sem erro de ponto flutuante; o resto da divisão vai pros primeiros
/// da lista, de forma determinística.
enum Settlement {
    /// "Você" nos dados (nunca um nome digitado).
    static let me = "__eu__"
    /// `splitWith` de "dividido com todos".
    static let everyone = "*"

    struct Entry: Hashable, Sendable {
        var amount: Double
        /// Vazio ou `me` = você.
        var paidBy: String = ""
        /// Vazio = não dividido; `everyone` = todos; senão nomes separados por `|`.
        var splitWith: String = ""
    }

    struct Transfer: Hashable, Sendable {
        var from: String
        var to: String
        var amount: Double
    }

    struct Result: Hashable, Sendable {
        /// Positivo = tem a receber; negativo = deve. Só quem aparece.
        var balances: [String: Double]
        var transfers: [Transfer]
        /// Soma dos gastos que entraram na divisão.
        var sharedTotal: Double
    }

    static func members(_ raw: String) -> [String] {
        raw.split(separator: "|").map { String($0) }.filter { !$0.isEmpty }
    }

    static func join(_ names: [String]) -> String { names.joined(separator: "|") }

    /// `people`: os companheiros (sem você). `decimals`: casas da moeda (0 pra iene, 2 pra real).
    static func settle(_ entries: [Entry], people: [String], decimals: Int = 2) -> Result {
        let scale = pow(10.0, Double(decimals))
        var order = [me] + people.filter { $0 != me }
        var balance: [String: Int] = [:]
        var shared = 0

        for entry in entries {
            guard entry.amount > 0, !entry.splitWith.isEmpty else { continue }
            let units = Int((entry.amount * scale).rounded())
            guard units > 0 else { continue }
            let payer = entry.paidBy.isEmpty ? me : entry.paidBy
            var list = entry.splitWith == everyone ? order : members(entry.splitWith)
            // Quem foi apagado da lista de pessoas ainda entra na conta (a dívida existe).
            for name in list + [payer] where !order.contains(name) { order.append(name) }
            list = order.filter { list.contains($0) }
            guard !list.isEmpty else { continue }

            shared += units
            balance[payer, default: 0] += units
            let base = units / list.count
            let extra = units % list.count
            for (index, name) in list.enumerated() {
                balance[name, default: 0] -= base + (index < extra ? 1 : 0)
            }
        }

        var debtors = balance.filter { $0.value < 0 }.map { (name: $0.key, units: -$0.value) }
            .sorted { ($1.units, $0.name) < ($0.units, $1.name) }
        var creditors = balance.filter { $0.value > 0 }.map { (name: $0.key, units: $0.value) }
            .sorted { ($1.units, $0.name) < ($0.units, $1.name) }
        var transfers: [Transfer] = []
        var d = 0, c = 0
        while d < debtors.count, c < creditors.count {
            let pay = min(debtors[d].units, creditors[c].units)
            if pay > 0 { transfers.append(Transfer(from: debtors[d].name, to: creditors[c].name, amount: Double(pay) / scale)) }
            debtors[d].units -= pay
            creditors[c].units -= pay
            if debtors[d].units == 0 { d += 1 }
            if creditors[c].units == 0 { c += 1 }
        }
        return Result(balances: balance.filter { $0.value != 0 }.mapValues { Double($0) / scale }, transfers: transfers,
                      sharedTotal: Double(shared) / scale)
    }

    static func entries(_ expenses: [Expense]) -> [Entry] {
        expenses.map { Entry(amount: $0.amount, paidBy: $0.paidBy, splitWith: $0.splitWith) }
    }

    /// Casas decimais da moeda.
    static func decimals(currency: String) -> Int {
        ["JPY", "KRW", "VND", "CLP", "ISK", "HUF"].contains(currency) ? 0 : 2
    }
}
