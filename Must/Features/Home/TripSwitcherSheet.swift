import CoreLocation
import SwiftData
import SwiftUI

/// Minhas viagens (`TrocarViagem.png`), aberta pelo botão no canto superior esquerdo da capa: as viagens do registro
/// (`trips.json`, prompt 28), a ativa marcada, e a linha Nova viagem. Tocar troca pelo `TripStore` (fade de 0,4 s) e
/// não apaga nada. Deslizar uma linha: Arquivar (some, os dados ficam) e Apagar (confirma; apaga só o `.store` dela).
/// A de casa não arquiva nem apaga.
struct TripSwitcherSheet: View {
    /// Prompt 28: a linha tracejada Nova viagem abre o fluxo (`router.cover = .novaViagem()`).
    static let newTripEnabled = true

    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(AppRouter.self) private var router
    @Query private var places: [Place]
    @State private var confirmDelete: TripRow?
    /// Linha com Arquivar/Apagar à mostra (uma por vez).
    @State private var openSwipe: String?

    private var rows: [TripRow] {
        // "GPS": a viagem que o automático abriria aqui (só com posição).
        let gps = services.location.current.flatMap { store.autoPick(near: $0.coordinate) }
        return TripSwitcherModel.rows(trips: store.trips, active: store.region, now: AppClock.now, gps: gps,
                                      doneCount: places.filter(\.isDone).count)
    }

    var body: some View {
        let rows = rows
        // Rola quando não cabe (4 viagens + Nova viagem na altura menor da folha): nada encolhe nem trunca.
        ScrollView { VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Minhas viagens").font(V8Font.display(34)).foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("\(rows.count)").font(V8Font.mono(13)).foregroundStyle(V8.mute)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)
            Rectangle().fill(V8.ink).frame(height: 2)
            ForEach(rows) { row in
                SwipeToActRow(enabled: row.region.trip.kind != .home, openRow: $openSwipe, id: row.id,
                              onArchive: { store.archive(row.region.rawValue) }, onDelete: { confirmDelete = row }) {
                    Button { select(row) } label: { TripRowView(row: row) }
                        .buttonStyle(MustPressStyle())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.title). \(row.subtitle). Moeda \(TripSwitcherModel.currencyLabel(row.region)). \(row.tag.rawValue)\(row.isActive ? ". Ativa" : "")")
                .accessibilityAddTraits(row.isActive ? [.isSelected, .isButton] : .isButton)
                .accessibilityAction { select(row) }
                .accessibilityActions {
                    if row.region.trip.kind != .home {
                        Button("Arquivar") { store.archive(row.region.rawValue) }
                        Button("Apagar") { confirmDelete = row }
                    }
                }
                Rectangle().fill(V8.ink).frame(height: 2)
            }
            if Self.newTripEnabled {
                Button { newTrip() } label: { newTripRow }
                    .buttonStyle(MustPressStyle())
                    .accessibilityLabel("Nova viagem. Destino, datas, cidades, voos, Musts")
                    .padding(.top, 14)
            }
            Text("Trocar não apaga nada · cada viagem tem o próprio board, gastos e mapas\nDeslize pra arquivar ou apagar · automático: datas de hoje, depois o GPS (Ajustes › Região)")
                .font(V8Font.mono(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(V8.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(V8.paper.ignoresSafeArea())
        .presentationDetents([.fraction(rows.count > 3 ? 0.8 : 0.72), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
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

    private var newTripRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(V8.ink)
                .frame(width: 56, height: 56).background(V8.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nova viagem").font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
                Text("destino, datas, cidades, voos, Musts").font(V8Font.text(14)).foregroundStyle(V8.mute)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .overlay(Rectangle().strokeBorder(V8.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
    }
}

private struct TripRowView: View {
    var row: TripRow

    var body: some View {
        HStack(spacing: 16) {
            // Bloco quadrado na cor do lugar com a bandeira; a ativa leva a régua de 2 pt em volta.
            ZStack {
                Rectangle().fill(TripTheme.forRegion(row.region).cover)
                TripFlag(country: row.region.trip.countryCode, size: 30)
            }
            .frame(width: 52, height: 52)
            .overlay(Rectangle().strokeBorder(V8.ink, lineWidth: row.isActive ? 3 : 0).padding(-4))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(V8Font.text(19, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                Text(row.subtitle).font(V8Font.text(14)).foregroundStyle(V8.mute).lineLimit(2)
                Text(TripSwitcherModel.currencyLabel(row.region)).font(V8Font.mono(11, weight: .semibold)).tracking(1)
                    .foregroundStyle(V8.ink).lineLimit(1)
            }
            Spacer(minLength: 8)
            tag
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var tag: some View {
        let text = Text(row.tag.rawValue.uppercased()).font(V8Font.mono(11)).tracking(1.2)
        switch row.tag {
        case .agora:
            text.foregroundStyle(V8.ink).padding(.horizontal, 10).padding(.vertical, 6).background(V8.orange)
        case .gps, .plano:
            text.foregroundStyle(V8.mute)
        }
    }
}

/// Deslizar pra esquerda mostra Arquivar e Apagar atrás da linha (a folha não é `List`, então o swipe é nosso).
/// Toque na linha aberta fecha. VoiceOver usa as ações da linha.
private struct SwipeToActRow<Content: View>: View {
    var enabled: Bool
    @Binding var openRow: String?
    var id: String
    var onArchive: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var drag: CGFloat = 0
    private let width: CGFloat = 176

    private var isOpen: Bool { openRow == id }
    private var offset: CGFloat { min(0, max(-width - 24, (isOpen ? -width : 0) + drag)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            if enabled && offset < 0 {
                HStack(spacing: 8) {
                    action("Arquivar", "archivebox", fill: V8.ink, ink: V8.white) { close(); onArchive() }
                    action("Apagar", "trash", fill: V8.orange, ink: V8.ink) { close(); onDelete() }
                }
                .padding(.vertical, 12)
                .transition(.opacity)
            }
            content
                .background(V8.paper)
                .offset(x: offset)
                .allowsHitTesting(!isOpen)
                .overlay { if isOpen { Color.clear.contentShape(Rectangle()).onTapGesture { close() } } }
        }
        // Corta o que sai pela direita ao deslizar, sem cortar o anel da ativa (4 pt pra fora da miniatura).
        .mask(Rectangle().padding(-6))
        .gesture(DragGesture(minimumDistance: 18)
            .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { drag = v.translation.width } }
            .onEnded { v in
                let shouldOpen = (isOpen ? -width : 0) + v.translation.width < -width / 2
                withAnimation(.snappy(duration: 0.22)) {
                    openRow = shouldOpen ? id : (isOpen ? nil : openRow)
                    drag = 0
                }
            }, including: enabled ? .all : .subviews)
        .animation(.snappy(duration: 0.22), value: isOpen)
    }

    private func close() { withAnimation(.snappy(duration: 0.22)) { openRow = nil } }

    private func action(_ title: String, _ symbol: String, fill: Color, ink: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                Text(title).font(V8Font.text(12, weight: .bold))
            }
            .foregroundStyle(ink)
            .frame(width: 80)
            .frame(maxHeight: .infinity)
            .background(fill)
        }
        .buttonStyle(MustPressStyle())
    }
}
