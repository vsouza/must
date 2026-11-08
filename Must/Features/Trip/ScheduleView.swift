import SwiftUI

/// Abas da agenda da viagem (prompt 15 · C): Voos e Reservas. Abre do calendário da Viagem.
enum ScheduleTab: String, Hashable, Sendable {
    case voos, reservas
}

/// Viagem → calendário (`design/screens/Viagem.png`): Voos (`FlightsView`) e Reservas (`ReservationsView`, sem o cabeçalho próprio).
struct ScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(\.tripTheme) private var theme

    @State private var tab: ScheduleTab

    init(tab: ScheduleTab = .voos) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            CutScreenHeader(title: "Agenda", corner: ["Viagem · voos e reservas"], height: 190, onBack: { dismiss() }) {
                CutCornerButton(systemName: "plus", label: "Trazer ingresso", tint: theme.coverInk) {
                    router.sheet = .ticketImport(inboxId: nil)
                }
            }
            switcher
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { IndexRule() }

            switch tab {
            case .voos:
                FlightsView()
            case .reservas:
                ReservationsView(embedded: true, onFlight: { tab = .voos })
            }
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var switcher: some View {
        HStack(spacing: 8) {
            ForEach([ScheduleTab.voos, .reservas], id: \.self) { option in
                Button { tab = option } label: {
                    Text((option == .voos ? "Voos" : "Reservas").uppercased())
                        .font(V8Font.mono(12, weight: .semibold)).tracking(1)
                        .foregroundStyle(tab == option ? V8.paper : V8.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(tab == option ? V8.ink : Color.clear)
                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                        .contentShape(Rectangle())
                        .accessibilityAddTraits(tab == option ? .isSelected : [])
                }
                .buttonStyle(.plain)
            }
        }
    }
}
