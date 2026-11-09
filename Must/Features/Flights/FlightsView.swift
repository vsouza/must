import SwiftData
import SwiftUI

/// Voos (`design/screens/Voos.png`): o próximo voo num card, o checklist por fase e os lembretes.
/// O status ao vivo só é consultado quando a tela abre ou o usuário puxa pra atualizar (`FlightStatusUpdater`).
struct FlightsView: View {
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(AppRouter.self) private var router

    @Query(sort: \Flight.order) private var flights: [Flight]
    @Query private var wallet: [WalletItem]

    @State private var selectedId: String?
    @State private var reminders = FlightReminders.enabled
    @State private var checkedAt: Date?

    private var region: Region { store.region }
    private var now: Date { AppClock.now }

    /// Reservas que ainda não pousaram, na ordem da viagem.
    private var upcoming: [Flight] {
        flights.filter { !$0.isOver(now: now) }.sorted { ($0.departs ?? .distantFuture) < ($1.departs ?? .distantFuture) }
    }

    /// O que a tela mostra: o escolhido, o próximo, ou o último (quando já não há voo pela frente).
    private var current: Flight? {
        if let selectedId, let chosen = flights.first(where: { $0.id == selectedId }) { return chosen }
        return upcoming.first ?? flights.max { ($0.departs ?? .distantPast) < ($1.departs ?? .distantPast) }
    }

    var body: some View {
        List {
            if let flight = current {
                Section {
                    FlightCardView(flight: flight, region: region, now: now)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text(subtitle).textCase(nil).font(.subheadline)
                }
                FlightChecklistView(flight: flight, region: region, now: now) { item in toggle(item, in: flight) }
                Section { remindersRow } footer: { statusLine }
                otherFlights(except: flight)
            } else {
                emptyState
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await refreshAll() }
        .task { await refreshAll() }
    }

    private var subtitle: String {
        guard let next = upcoming.first, let departs = next.departs else { return "nenhum voo pela frente" }
        return "Próximo \(FlightFormat.daysAway(departs, now: now, region: region)) · tudo pronto antes de cada perna"
    }

    // MARK: Status e checklist

    /// Aplica a Carteira (Visit Japan Web, eSIM) e consulta o status dos voos que a política manda. Sem rede ou cota, só o programado.
    private func refreshAll() async {
        applyWallet()
        for flight in upcoming {
            await FlightStatusUpdater.refresh(flight, context: context, now: AppClock.now, region: region)
        }
        checkedAt = AppClock.now
        await FlightReminders.sync(upcoming, now: AppClock.now)
    }

    private func applyWallet() {
        var changed = false
        for flight in flights {
            let marked = ChecklistRules.applyWallet(flight.checklist, wallet: wallet)
            if marked != flight.checklist {
                flight.checklist = marked
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    private func toggle(_ item: ChecklistItem, in flight: Flight) {
        var items = flight.checklist
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].done.toggle()
        flight.checklist = items
        try? context.save()
        Task { await FlightReminders.sync(upcoming, now: AppClock.now) }
    }

    private var statusLine: some View {
        let live = FlightStatusUpdater.activeSource() != nil
        let stamp = checkedAt.map { " · \(FlightFormat.time($0, zone: region.timeZone))" } ?? ""
        return Text(live ? "Status ao vivo · AeroDataBox\(stamp)" : "Só o horário programado · sem chave de status ao vivo")
    }

    // MARK: Lembretes

    private var remindersRow: some View {
        Toggle(isOn: Binding(get: { reminders }, set: { setReminders($0) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lembrar no horário")
                Text("check-in, malas e portão · só o que tem hora marcada").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// Ligar pede a permissão agora (nunca antes). Desligar tira o que estava agendado.
    private func setReminders(_ on: Bool) {
        Task {
            if on {
                reminders = await FlightReminders.enable(upcoming, now: AppClock.now)
            } else {
                await FlightReminders.disable()
                reminders = false
            }
        }
    }

    // MARK: Outros trechos e vazio

    @ViewBuilder
    private func otherFlights(except flight: Flight) -> some View {
        let others = upcoming.filter { $0.id != flight.id }
        if !others.isEmpty {
            Section("Outros voos · \(others.count)") {
                ForEach(others) { other in
                    Button { selectedId = other.id } label: {
                        LabeledContent {
                            Text(other.routeLabel).monospacedDigit()
                        } label: {
                            Text(other.legs.map(\.number).joined(separator: " · "))
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nenhum voo ainda.").font(.headline)
                Text("Traga o e-mail ou o PDF da companhia: o localizador e os trechos entram sozinhos.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Trazer ingresso ou e-mail") { router.sheet = .ticketImport(inboxId: nil) }.v9Secondary()
            }
        }
    }
}
