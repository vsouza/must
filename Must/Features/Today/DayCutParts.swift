import SwiftUI

// O corte nas telas do dia (rodada 33): bloco da foto do bairro, índice de paradas e deslocamentos. Peças da Linha e do Agora.
// A foto é a que o app já tem no disco (`CapaState.diskPhoto`); nunca baixa nada por causa do corte.

/// Bloco da foto do dia: o bairro (`areaId`) com a foto já no disco, ou só a cor do lugar com a trama (estado normal).
struct DayBand<Content: View>: View {
    var areaId: String?
    var places: [Place]
    var height: CGFloat = 250
    /// Safe area de cima quando o bloco sangra (`cutBleed`).
    var topInset: CGFloat = 0
    @ViewBuilder var content: Content

    @Environment(RegionStore.self) private var store
    @State private var photo: URL?
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    var body: some View {
        CutBand(photo: photo) {
            content
                .padding(.horizontal, 20)
                .padding(.top, 10 + topInset)
                .padding(.bottom, 16)
        }
        .frame(height: height * min(scale, 1.4) + topInset)
        .task(id: "\(store.region.trip.id)|\(areaId ?? "")|\(places.count)") {
            photo = await Self.photo(region: store.region, areaId: areaId, places: places)
        }
    }

    /// Foto do bairro que já está no disco (Google de um Must dele › Commons já baixada). `nil` = só a cor.
    static func photo(region: Region, areaId: String?, places: [Place]) async -> URL? {
        guard let areaId, let (_, candidates) = CapaState.areaCandidates(region: region, areaId: areaId, places: places),
              let found = await CapaState.diskPhoto(region: region, areaId: areaId, candidates: candidates) else { return nil }
        return URL(string: found.largeURL ?? found.url)
    }
}

/// Cantos do bloco: ficha técnica à esquerda e à direita, na tinta do bloco.
struct DayBandCorners: View {
    var left: [String]
    var right: [String]
    @Environment(\.tripTheme) private var theme

    var body: some View {
        HStack(alignment: .top) {
            SpecStack(lines: left, color: theme.coverInk.opacity(0.9))
            Spacer(minLength: 12)
            SpecStack(lines: right, color: theme.coverInk.opacity(0.9), alignment: .trailing)
        }
    }
}

/// O numeral grande do bloco (na tinta do bloco) com a legenda em mono embaixo.
struct DayBandNumeral: View {
    var value: String
    var caption: String
    var size: CGFloat = 96
    @Environment(\.tripTheme) private var theme

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            BigNumeral(value, size: size, color: theme.coverInk, alignment: .trailing)
                .fixedSize()
                .padding(.bottom, -size * 0.06)
            MonoLabel(caption, size: 9.5, color: theme.coverInk.opacity(0.9))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption)")
    }
}

extension DayPlan {
    /// O bairro pra foto do bloco: o do dia, ou o da primeira parada que tem um (a próxima, quando o dia já começou).
    func bandArea(from now: Date? = nil) -> String? {
        if let area { return area }
        let upcoming = now.map { n in stops.filter { $0.end >= n } } ?? stops
        return (upcoming + stops).compactMap(\.area).first
    }
}

/// Uma parada da Linha como linha do índice, de largura total: hora em número grande, nome e motivo, régua de 2 pt embaixo.
/// Agora = laranja inteiro; âncora = tinta; must = papel; micro-parada = linha baixa com régua tracejada. Feito 50 %.
struct DayStopRow: View {
    var stop: DayStop
    var state: LinhaStopState
    var region: Region
    var onTap: (() -> Void)?

    private var isMicro: Bool { stop.kind == .micro }
    private var isShow: Bool { isMicro && stop.tag?.uppercased() == "EXP" }
    private var isInk: Bool { state != .now && stop.kind == .anchor }

    private var main: Color { state == .now ? V8.ink : isInk ? V8.white : V8.ink }
    private var sub: Color { state == .now ? V8.ink.opacity(0.75) : isInk ? V8.muteDark : V8.mute }
    private var fill: Color { state == .now ? V8.orange : isInk ? V8.ink : .clear }

    private var noteText: String {
        switch state {
        case .done: stop.note.contains("feito") ? stop.note : (stop.note.isEmpty ? "feito ✓" : stop.note + " · feito ✓")
        case .skipped: "ficou pra depois" + (stop.note.isEmpty ? "" : " · " + stop.note)
        default: stop.note
        }
    }

    var body: some View {
        if let onTap {
            Button(action: onTap) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(region.timeString(stop.start))
                    .font(isMicro ? V8Font.mono(17, weight: .semibold) : V8Font.numeral(28))
                    .tracking(isMicro ? 0 : 0.5)
                    .foregroundStyle(state == .now || isInk ? main : (isMicro ? V8.ink.opacity(0.75) : V8.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(DayText.caption(for: stop, isNow: state == .now).uppercased())
                    .font(V8Font.mono(8.5)).tracking(0.9)
                    .foregroundStyle(sub)
                    .lineLimit(1)
            }
            .frame(width: 88, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.label)
                    .font(V8Font.text(isMicro ? 15 : 17, weight: isMicro ? .semibold : .bold))
                    .foregroundStyle(main)
                    .lineLimit(2)
                if !noteText.isEmpty {
                    Text(noteText)
                        .font(V8Font.text(isMicro ? 12 : 12.5))
                        .foregroundStyle(sub)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, isMicro ? 9 : 13)
        .frame(maxWidth: .infinity, minHeight: isMicro ? 52 : 68, alignment: .leading)
        .background(fill)
        .overlay(alignment: .bottom) {
            if isMicro && state != .now {
                DayDashLine().stroke(V8.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
            } else {
                IndexRule()
            }
        }
        .opacity(state == .done || state == .skipped ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.timeString(stop.start)), \(stop.label), \(noteText)\(state == .done ? ", feito" : state == .now ? ", agora" : "")")
    }

    @ViewBuilder private var trailing: some View {
        if state == .now {
            Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold)).foregroundStyle(V8.ink)
        } else if stop.kind == .anchor || isShow {
            Text((stop.tag ?? (isShow ? "EXP" : "RES")).uppercased())
                .font(V8Font.mono(9.5, weight: .semibold)).tracking(0.8)
                .foregroundStyle(isInk ? V8.orange : V8.ink)
                .lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 5)
                .overlay(Rectangle().stroke(isInk ? V8.orange : V8.ink, lineWidth: 1.5))
        } else if state == .done {
            Text("✓").font(V8Font.mono(14, weight: .bold)).foregroundStyle(V8.ink)
        }
    }
}

struct DayDashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Deslocamento entre duas paradas: um item de índice baixo ("↓ JY Yamanote 09:12 · 34 min · plat. 14"), alinhado ao nome da
/// parada, com régua fina embaixo.
struct DayLegItem: View {
    var leg: DayLeg
    var color: Color = V8.mute

    var body: some View {
        HStack(spacing: 8) {
            Text("↓").font(V8Font.mono(10.5, weight: .bold)).foregroundStyle(color)
            Text(DayLegRow.text(leg).uppercased())
                .font(V8Font.mono(9.5))
                .tracking(0.6)
                .foregroundStyle(color)
                .lineLimit(2)
        }
        .padding(.leading, 20 + 88 + 14)
        .padding(.trailing, 20)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink.opacity(0.35)).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Deixa o bloco da foto sangrar até o topo da tela dentro de um `ScrollView` (o scroll recorta na safe area): lê o
    /// inset de cima e o entrega pra quem desenha o bloco somar à altura e ao respiro.
    func cutBleed(_ safeTop: Binding<CGFloat>) -> some View {
        ignoresSafeArea(.container, edges: .top)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { safeTop.wrappedValue = $0 }
    }
}
