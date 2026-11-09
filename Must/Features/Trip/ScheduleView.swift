import SwiftUI

/// Abas da agenda da viagem (prompt 15 · C): Voos e Reservas. Abre do calendário da Viagem.
enum ScheduleTab: String, Hashable, Sendable {
    case voos, reservas
}

/// Viagem → calendário (`design/screens/Viagem.png`): Voos (`FlightsView`) e Reservas (`ReservationsView`, sem o cabeçalho próprio).
struct ScheduleView: View {
    @Environment(AppRouter.self) private var router

    @State private var tab: ScheduleTab

    init(tab: ScheduleTab = .voos) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Agenda", selection: $tab) {
                Text("Voos").tag(ScheduleTab.voos)
                Text("Reservas").tag(ScheduleTab.reservas)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, V9.gutter)
            .padding(.vertical, 8)

            switch tab {
            case .voos:
                FlightsView()
            case .reservas:
                ReservationsView(embedded: true, onFlight: { tab = .voos })
            }
        }
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Trazer ingresso", systemImage: "ticket") { router.sheet = .ticketImport(inboxId: nil) }
            }
        }
        .v9Screen(grouped: true)
    }
}
