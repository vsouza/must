import CoreLocation
import SwiftData
import SwiftUI

/// Minhas viagens (`TrocarViagem.png`), aberta pelo botão no canto superior esquerdo da capa: as três regiões, a ativa marcada.
/// Tocar troca pelo `RegionStore` (fade de 0,4 s) e não apaga nada. "Nova viagem" fica escondida até o prompt 28.
struct TripSwitcherSheet: View {
    /// Liga com o prompt 28 (Nova viagem). Até lá, a linha tracejada não aparece.
    static let newTripEnabled = false

    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var places: [Place]

    private var rows: [TripRow] {
        let gps = services.location.current.flatMap { Region.detect($0.coordinate) }
        return TripSwitcherModel.rows(active: store.region, now: AppClock.now, gps: gps, doneCount: places.filter(\.isDone).count)
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Minhas viagens").font(V8Font.display(34)).foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("\(rows.count)").font(V8Font.mono(13)).foregroundStyle(V8.mute)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)
            Rectangle().fill(V8.rule).frame(height: 1)
            ForEach(rows) { row in
                Button { select(row) } label: { TripRowView(row: row) }
                    .buttonStyle(MustPressStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.title). \(row.subtitle). \(row.tag.rawValue)\(row.isActive ? ". Ativa" : "")")
                    .accessibilityAddTraits(row.isActive ? .isSelected : [])
                Rectangle().fill(V8.rule).frame(height: 1)
            }
            if Self.newTripEnabled { newTripRow.padding(.top, 14) }
            Text("Trocar não apaga nada · cada viagem tem o próprio board, gastos e mapas\nModo automático: o GPS escolhe quando você pousa (Ajustes › Região)")
                .font(V8Font.mono(10))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(V8.mute)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(V8.paper.ignoresSafeArea())
        .presentationDetents([.fraction(0.62), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }

    private func select(_ row: TripRow) {
        guard row.region != store.region else { dismiss(); return }
        dismiss()
        RegionSwitch.afterDismiss(row.region, store: store)
    }

    private var newTripRow: some View {
        HStack(spacing: 16) {
            Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(V8.ink)
                .frame(width: 56, height: 56).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(V8.orange))
            VStack(alignment: .leading, spacing: 2) {
                Text("Nova viagem").font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
                Text("destino, datas, cidades, voos, Musts").font(V8Font.text(14)).foregroundStyle(V8.mute)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(V8.mute.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}

private struct TripRowView: View {
    var row: TripRow

    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(TripTheme.forRegion(row.region).cover)
                Circle().strokeBorder(V8.white.opacity(0.45), lineWidth: 1).frame(width: 38, height: 38).offset(x: 12, y: -12)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(V8.ink, lineWidth: row.isActive ? 2.5 : 0).padding(-4))
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(V8Font.text(19, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                Text(row.subtitle).font(V8Font.text(14)).foregroundStyle(V8.mute).lineLimit(2)
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
            text.foregroundStyle(V8.ink).padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(V8.orange))
        case .gps, .plano:
            text.foregroundStyle(V8.mute)
        }
    }
}
