import SwiftData
import SwiftUI

/// Viagem › Grupo › Acertar contas (prompt 32): saldo por pessoa e o mínimo de transferências dos gastos divididos, na moeda
/// da viagem (e em R$ quando o app tem câmbio). O resumo sai em texto pelo compartilhar do iOS.
struct AcertarView: View {
    @Environment(RegionStore.self) private var store
    @Environment(AppRouter.self) private var router

    @Query private var expenses: [Expense]
    @Query(sort: [SortDescriptor(\Companion.order), SortDescriptor(\Companion.createdAt)]) private var people: [Companion]
    @Query private var settingsList: [Settings]

    private var region: Region { store.region }
    private var money: GiftMoney { GiftMoney(region: region, userRate: settingsList.first?.fxRate) }

    private var result: Settlement.Result {
        Settlement.settle(Settlement.entries(expenses), people: people.map(\.name), decimals: Settlement.decimals(currency: region.currency))
    }

    private func label(_ name: String) -> String { name == Settlement.me ? "Você" : name }

    var body: some View {
        let result = result
        let splitCount = expenses.filter { !$0.splitWith.isEmpty }.count
        List {
            if splitCount == 0 {
                empty
            } else {
                Section {
                    totalBlock(result)
                }
                if result.transfers.isEmpty {
                    Section { Label("Tudo certo: ninguém deve nada.", systemImage: "checkmark.circle").font(.body.weight(.semibold)) }
                } else {
                    Section("Quem acerta com quem") {
                        ForEach(Array(result.transfers.enumerated()), id: \.offset) { _, t in transferRow(t) }
                    }
                }
                balances(result)
                Section {
                    ShareLink(item: summaryText(result)) { Label("Mandar o resumo", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle("Acertar contas")
        .navigationBarTitleDisplayMode(.inline)
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
    }

    private var empty: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nenhum gasto dividido ainda.").font(.headline)
                Text(people.isEmpty
                     ? "Adicione as pessoas do grupo; no Gasto, marque quem pagou e com quem dividiu."
                     : "No Gasto, marque quem pagou e com quem dividiu. As contas aparecem aqui.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if people.isEmpty {
                    Button("Adicionar pessoas") { router.push(.pessoas, on: router.tab) }.v9Primary()
                }
            }
        }
    }

    private func totalBlock(_ result: Settlement.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Total dividido").font(.subheadline).foregroundStyle(.secondary)
            Text(money.text(result.sharedTotal)).font(.largeTitle.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            if let brl = money.brl(result.sharedTotal) { Text(brl).font(.subheadline).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    /// `group`: a frase pro grupo (quem lê não é o dono do app).
    private func sentence(_ t: Settlement.Transfer, group: Bool = false) -> String {
        if t.to == Settlement.me { return group ? "\(label(t.from)) deve a mim" : "\(label(t.from)) te deve" }
        if t.from == Settlement.me { return group ? "Eu devo a \(label(t.to))" : "Você deve a \(label(t.to))" }
        return "\(label(t.from)) deve a \(label(t.to))"
    }

    private func transferRow(_ t: Settlement.Transfer) -> some View {
        let toMe = t.to == Settlement.me
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sentence(t)).font(.body).lineLimit(2)
                if let brl = money.brl(t.amount) { Text(brl).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Text(money.text(t.amount)).font(.body.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(toMe ? V9.accent : Color.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func balances(_ result: Settlement.Result) -> some View {
        let names = ([Settlement.me] + people.map(\.name)).filter { result.balances[$0] != nil }
        return Section("Saldo de cada um") {
            ForEach(names, id: \.self) { name in
                let value = result.balances[name] ?? 0
                LabeledContent(label(name)) {
                    Text((value > 0 ? "recebe " : "deve ") + money.text(abs(value))).monospacedDigit()
                        .foregroundStyle(value > 0 ? V9.accent : Color.secondary)
                }
            }
        }
    }

    private func summaryText(_ result: Settlement.Result) -> String {
        var lines = ["Acertando as contas da viagem (\(region.displayName)):"]
        if result.transfers.isEmpty { lines.append("Tudo certo, ninguém deve nada.") }
        for t in result.transfers {
            lines.append("• \(sentence(t, group: true)) \(money.text(t.amount))" + (money.brl(t.amount).map { " (\($0))" } ?? ""))
        }
        lines.append("Total dividido: \(money.text(result.sharedTotal))")
        return lines.joined(separator: "\n")
    }
}
