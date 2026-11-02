import SwiftUI

/// Abas da agenda da viagem (prompt 15 · C): Voos e Reservas. Abre do calendário da Viagem.
enum ScheduleTab: String, Hashable, Sendable {
    case voos, reservas
}

/// Viagem → calendário (`design/screens/Viagem.png`): Voos (`FlightsView`) e Reservas (`ReservationsView`, sem o cabeçalho próprio).
struct ScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    @State private var tab: ScheduleTab

    init(tab: ScheduleTab = .voos) {
        _tab = State(initialValue: tab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(.voltar, style: .glass, label: "Voltar") { dismiss() }
                Spacer()
                Micro("agenda da viagem")
                Spacer()
                IconButton(.adicionar, style: .dark, label: "Trazer ingresso") { router.sheet = .ticketImport(inboxId: nil) }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)

            switcher
                .padding(.horizontal, 22)
                .padding(.top, 14)

            switch tab {
            case .voos:
                FlightsView()
            case .reservas:
                ReservationsView(embedded: true, onFlight: { tab = .voos })
            }
        }
        .background(Color.must.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var switcher: some View {
        HStack(spacing: 6) {
            ForEach([ScheduleTab.voos, .reservas], id: \.self) { option in
                Button { tab = option } label: {
                    Text(option == .voos ? "Voos" : "Reservas")
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(tab == option ? Color.white : Color.must.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(tab == option ? Color.must.ink : Color.must.surface))
                }
                .buttonStyle(MustPressStyle())
                .accessibilityAddTraits(tab == option ? .isSelected : [])
            }
        }
    }
}
