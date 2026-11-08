import SwiftData
import SwiftUI

/// Viagem › Grupo › Acertar contas (prompt 32): saldo por pessoa e o mínimo de transferências dos gastos divididos, na moeda
/// da viagem (e em R$ quando o app tem câmbio). O resumo sai em texto pelo compartilhar do iOS.
struct AcertarView: View {
    @Environment(\.dismiss) private var dismiss
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
        CutPage(title: "Acertar", corner: ["Viagem · Grupo", "\(splitCount) \(splitCount == 1 ? "gasto dividido" : "gastos divididos")"],
                subtitle: nil, height: 190, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                if splitCount == 0 {
                    empty
                } else {
                    totalBlock(result)
                    if result.transfers.isEmpty {
                        Text("Tudo certo: ninguém deve nada.").font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                            .padding(.horizontal, 20).padding(.vertical, 18)
                    } else {
                        MonoLabel("quem acerta com quem", size: 10, color: V8.mute).padding(.horizontal, 20).padding(.vertical, 12)
                        ForEach(Array(result.transfers.enumerated()), id: \.offset) { _, t in transferRow(t) }
                    }
                    balances(result)
                    ShareLink(item: summaryText(result)) {
                        HStack {
                            Text("MANDAR O RESUMO").font(V8Font.mono(12, weight: .semibold)).tracking(1)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(V8.ink).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                    }
                    .padding(.horizontal, 20).padding(.top, 20)
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nenhum gasto dividido ainda.").font(V8Font.display(26)).foregroundStyle(V8.ink)
            Text(people.isEmpty
                 ? "Adicione as pessoas do grupo; no Gasto, marque quem pagou e com quem dividiu."
                 : "No Gasto, marque quem pagou e com quem dividiu. As contas aparecem aqui.")
                .font(V8Font.text(15)).foregroundStyle(V8.mute)
            if people.isEmpty {
                BigButton(title: "Adicionar pessoas", style: .orange, systemImage: "arrow.up.right") { router.push(.pessoas, on: router.tab) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 24)
    }

    private func totalBlock(_ result: Settlement.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel("total dividido", size: 10, color: V8.mute)
            Text(money.text(result.sharedTotal)).font(V8Font.numeral(54)).tracking(-1.5).foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.5)
            if let brl = money.brl(result.sharedTotal) { Text(brl).font(V8Font.text(14)).foregroundStyle(V8.mute) }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { IndexRule() }
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
                Text(sentence(t)).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                if let brl = money.brl(t.amount) { Text(brl).font(V8Font.text(13)).foregroundStyle(V8.mute) }
            }
            Spacer(minLength: 8)
            Text(money.text(t.amount)).font(V8Font.mono(16, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(toMe ? V8.orange : Color.clear)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .overlay(alignment: .bottom) { IndexRule() }
        .accessibilityElement(children: .combine)
    }

    private func balances(_ result: Settlement.Result) -> some View {
        let names = ([Settlement.me] + people.map(\.name)).filter { result.balances[$0] != nil }
        return VStack(alignment: .leading, spacing: 0) {
            MonoLabel("saldo de cada um", size: 10, color: V8.mute).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
            ForEach(names, id: \.self) { name in
                let value = result.balances[name] ?? 0
                HStack {
                    Text(label(name)).font(V8Font.text(15)).foregroundStyle(V8.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text((value > 0 ? "recebe " : "deve ") + money.text(abs(value))).font(V8Font.mono(13, weight: .semibold))
                        .foregroundStyle(value > 0 ? V8.orangeDeep : V8.ink).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
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
