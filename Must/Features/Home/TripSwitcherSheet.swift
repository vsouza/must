import CoreLocation
import SwiftData
import SwiftUI

/// Minhas viagens (`TrocarViagem.png`), aberta pelo botão no canto superior esquerdo da capa: as viagens do registro
/// (`trips.json`, prompt 28), a ativa marcada, e a linha Nova viagem. Tocar troca pelo `TripStore` (fade de 0,4 s) e
/// não apaga nada. Arquivar (some, os dados ficam) e Apagar (confirma; apaga só o `.store` dela) pelo ⋯ da linha; o
/// deslize do sistema é atalho. A de casa não arquiva nem apaga. Visual V9 (prompt 32 Fase 2).
struct TripSwitcherSheet: View {
    /// Prompt 28: a linha tracejada Nova viagem abre o fluxo (`router.cover = .novaViagem()`).
    static let newTripEnabled = true

    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(AppRouter.self) private var router
    @Query private var places: [Place]
    @State private var confirmDelete: TripRow?

    private var rows: [TripRow] {
        // "GPS": a viagem que o automático abriria aqui (só com posição).
        let gps = services.location.current.flatMap { store.autoPick(near: $0.coordinate) }
        return TripSwitcherModel.rows(trips: store.trips, active: store.region, now: AppClock.now, gps: gps,
                                      doneCount: places.filter(\.isDone).count)
    }

    var body: some View {
        let rows = rows
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        let canEdit = row.region.trip.kind != .home
                        HStack(spacing: 4) {
                            Button { select(row) } label: { TripRowView(row: row) }
                                .buttonStyle(.plain)
                            // Prompt 32 §1: Arquivar/Apagar com controle visível (o deslize do sistema fica como atalho).
                            if canEdit {
                                Menu {
                                    Button("Arquivar", systemImage: "archivebox") { store.archive(row.region.rawValue) }
                                    Button("Apagar", systemImage: "trash", role: .destructive) { confirmDelete = row }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Mais ações de \(row.title)")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canEdit {
                                Button("Apagar", systemImage: "trash", role: .destructive) { confirmDelete = row }
                                Button("Arquivar", systemImage: "archivebox") { store.archive(row.region.rawValue) }
                                    .tint(.gray)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.title). \(row.subtitle). Moeda \(TripSwitcherModel.currencyLabel(row.region)). \(row.tag.rawValue)\(row.isActive ? ". Ativa" : "")")
                        .accessibilityAddTraits(row.isActive ? [.isSelected, .isButton] : .isButton)
                        .accessibilityAction { select(row) }
                        .accessibilityActions {
                            if canEdit {
                                Button("Arquivar") { store.archive(row.region.rawValue) }
                                Button("Apagar") { confirmDelete = row }
                            }
                        }
                    }
                } footer: {
                    Text("Trocar não apaga nada: cada viagem tem o próprio board, gastos e mapas. Use ⋯ pra arquivar ou apagar. No automático vale a viagem com hoje nas datas, depois o GPS (Ajustes › Região).")
                }
                if Self.newTripEnabled {
                    Section {
                        Button { newTrip() } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nova viagem").font(.body.weight(.semibold))
                                    Text("destino, datas, cidades, voos, Musts").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(V9.accent)
                            }
                        }
                        .accessibilityLabel("Nova viagem. Destino, datas, cidades, voos, Musts")
                    }
                }
            }
            .navigationTitle("Minhas viagens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
            }
        }
        .presentationDetents([.fraction(rows.count > 3 ? 0.8 : 0.72), .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog(confirmDelete.map { "Apagar \($0.title)?" } ?? "", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Apagar viagem", role: .destructive) {
                if let row = confirmDelete { store.delete(row.region.rawValue) }
                confirmDelete = nil
            }
            Button("Cancelar", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Apaga o board, os gastos e os ingressos desta viagem neste iPhone. As outras viagens ficam como estão.")
        }
    }

    /// Fecha a folha e abre o fluxo Nova viagem (prompt 28), depois da animação da folha.
    private func newTrip() {
        dismiss()
        let router = router
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            router.cover = .novaViagem()
        }
    }

    private func select(_ row: TripRow) {
        guard row.region != store.region else { dismiss(); return }
        dismiss()
        RegionSwitch.afterDismiss(row.region, store: store)
    }
}

private struct TripRowView: View {
    var row: TripRow

    var body: some View {
        HStack(spacing: 14) {
            // A cor do país fica só na bandeira (prompt 32 §5).
            TripFlag(country: row.region.trip.countryCode, size: 30)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text(row.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                Text(TripSwitcherModel.currencyLabel(row.region)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            tag
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var tag: some View {
        switch row.tag {
        case .agora:
            Label(row.tag.rawValue, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(V9.accent)
        case .gps, .plano:
            Text(row.tag.rawValue).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
