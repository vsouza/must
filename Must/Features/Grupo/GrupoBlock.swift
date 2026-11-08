import SwiftData
import SwiftUI

/// Bloco "Grupo" da aba Viagem (prompt 32): Pessoas · Votar · Acertar contas · Mandar o dia. Quatro linhas num quadro de
/// borda de 2 pt, régua entre elas; a meta de cada uma diz o estado (quantos, quanto, qual dia).
struct GrupoBlock: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query private var people: [Companion]
    @Query private var polls: [PlacePoll]
    @Query private var expenses: [Expense]
    @Query private var days: [PlannedDay]
    @Query private var settingsList: [Settings]

    /// Na aba Viagem (fundo tinta) as réguas e o texto viram brancos.
    var onInk: Bool = false
    private var fg: Color { onInk ? V8.white : V8.ink }
    private var sub: Color { onInk ? V8.muteDark : V8.mute }

    private var region: Region { store.region }

    var body: some View {
        let split = expenses.filter { !$0.splitWith.isEmpty }
        let result = Settlement.settle(Settlement.entries(split), people: people.map(\.name), decimals: Settlement.decimals(currency: region.currency))
        let today = region.calendar.startOfDay(for: AppClock.now)
        let hasDay = days.contains { $0.date == today && $0.accepted }
        let open = polls.filter { $0.winner == nil }.count
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("grupo · \(people.isEmpty ? "só você" : "você + \(people.count)")", size: 10, color: sub)
            VStack(spacing: 0) {
                row("Pessoas", people.isEmpty ? "quem viaja com você" : people.prefix(3).map(\.name).joined(separator: ", ") + (people.count > 3 ? " +\(people.count - 3)" : "")) {
                    router.push(.pessoas, on: router.tab)
                }
                rule
                row("Votar", polls.isEmpty ? "A ou B? entre dois lugares" : open == 0 ? "\(polls.count) \(polls.count == 1 ? "votação" : "votações")" : "\(open) sem vencedor") {
                    router.push(.votar, on: router.tab)
                }
                rule
                row("Acertar contas", split.isEmpty ? "divida gastos no Gasto"
                    : result.transfers.isEmpty ? "tudo certo" : "\(result.transfers.count) \(result.transfers.count == 1 ? "acerto" : "acertos") · \(region.money(result.sharedTotal)) divididos") {
                    router.push(.acertar, on: router.tab)
                }
                rule
                row("Mandar o dia", hasDay ? "cartaz, link e PDF de hoje" : "monte o dia de hoje pra mandar") {
                    router.sheet = .mandar(date: today)
                }
            }
            .overlay(Rectangle().stroke(fg, lineWidth: 2))
        }
    }

    private var rule: some View { Rectangle().fill(fg).frame(height: 2) }

    private func row(_ title: String, _ meta: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(V8Font.text(17, weight: .bold)).foregroundStyle(fg).lineLimit(2)
                    Text(meta).font(V8Font.text(13)).foregroundStyle(sub).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .bold)).foregroundStyle(fg)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
