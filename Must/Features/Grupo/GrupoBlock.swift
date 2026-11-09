import SwiftData
import SwiftUI

/// Bloco "Grupo" (V9): Pessoas · Votar · Acertar contas · Mandar o dia, como `Section` de uma `List`; a meta de cada
/// linha diz o estado (quantos, quanto, qual dia).
struct GrupoBlock: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query private var people: [Companion]
    @Query private var polls: [PlacePoll]
    @Query private var expenses: [Expense]
    @Query private var days: [PlannedDay]
    @Query private var settingsList: [Settings]

    private var region: Region { store.region }

    var body: some View {
        let split = expenses.filter { !$0.splitWith.isEmpty }
        let result = Settlement.settle(Settlement.entries(split), people: people.map(\.name), decimals: Settlement.decimals(currency: region.currency))
        let today = region.calendar.startOfDay(for: AppClock.now)
        let hasDay = days.contains { $0.date == today && $0.accepted }
        let open = polls.filter { $0.winner == nil }.count
        Section {
            row("Pessoas", people.isEmpty ? "quem viaja com você" : people.prefix(3).map(\.name).joined(separator: ", ") + (people.count > 3 ? " +\(people.count - 3)" : "")) {
                router.push(.pessoas, on: router.tab)
            }
            row("Votar", polls.isEmpty ? "A ou B? entre dois lugares" : open == 0 ? "\(polls.count) \(polls.count == 1 ? "votação" : "votações")" : "\(open) sem vencedor") {
                router.push(.votar, on: router.tab)
            }
            row("Acertar contas", split.isEmpty ? "divida gastos no Gasto"
                : result.transfers.isEmpty ? "tudo certo" : "\(result.transfers.count) \(result.transfers.count == 1 ? "acerto" : "acertos") · \(region.money(result.sharedTotal)) divididos") {
                router.push(.acertar, on: router.tab)
            }
            row("Mandar o dia", hasDay ? "cartaz, link e PDF de hoje" : "monte o dia de hoje pra mandar") {
                router.sheet = .mandar(date: today)
            }
        } header: {
            Text("Grupo · \(people.isEmpty ? "só você" : "você + \(people.count)")")
        }
    }

    private func row(_ title: String, _ meta: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(meta).font(.footnote).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
    }
}
