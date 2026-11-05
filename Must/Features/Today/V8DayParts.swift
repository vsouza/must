import SwiftUI

// Peças das telas do dia v8 (agente C). Montadas sobre os componentes do contrato (`SpecLabel`, `V8Font`, `V8`).

/// Ficha técnica de duas linhas (um canto da tela).
struct SpecStack: View {
    var lines: [String]
    var color: Color
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                SpecLabel(line, color: color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rótulo mono em caixa alta, maior que a ficha ("SAIA ÀS", "HOJE É", "BAIRRO DE HOJE").
struct MonoLabel: View {
    var text: String
    var size: CGFloat = 10
    var color: Color

    init(_ text: String, size: CGFloat = 10, color: Color) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(V8Font.mono(size))
            .tracking(size * 0.1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Botão redondo de 44 pt (fechar, voltar, trocar, feito, ↗).
struct RoundButton: View {
    enum Style { case line, paper, white, ink }
    var systemImage: String
    var label: String
    var style: Style = .line
    var tint: Color = V8.white
    var size: CGFloat = 44
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(style == .line ? tint.opacity(0.6) : .clear, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(label)
    }

    private var foreground: Color {
        switch style {
        case .line: tint
        case .paper, .white: V8.ink
        case .ink: V8.white
        }
    }

    private var fill: Color {
        switch style {
        case .line: .clear
        case .paper: V8.paper
        case .white: V8.white
        case .ink: V8.ink
        }
    }
}

/// Botão grande v8 (56 pt) com texto e ícone opcional à direita; mais flexível que o `V8Button` (cor de texto e borda
/// sobre fundos escuros e coloridos).
struct BigButton: View {
    enum Style { case orange, ink, line }
    var title: String
    var style: Style = .orange
    var systemImage: String?
    /// Cor do contorno e do texto no estilo `.line`.
    var lineColor: Color = V8.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(V8Font.text(16, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
                if let systemImage { Image(systemName: systemImage).font(.system(size: 15, weight: .bold)) }
            }
            .foregroundStyle(style == .ink ? V8.white : style == .line ? lineColor : V8.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(style == .orange ? V8.orange : style == .ink ? V8.ink : .clear))
            .overlay(Capsule().strokeBorder(style == .line ? lineColor : .clear, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(MustPressStyle())
    }
}

/// Fade no fim da tela: o que rola passa por trás antes da barra ou dos botões.
struct BottomFade: View {
    var color: Color
    var height: CGFloat = 120

    var body: some View {
        LinearGradient(stops: [.init(color: color.opacity(0), location: 0), .init(color: color.opacity(0.98), location: 0.6),
                               .init(color: color, location: 1)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
    }
}

/// Título de seção v8 ("Hoje você já tem" · "3 âncoras").
struct SectionHead: View {
    var title: String
    var trailing: String?
    var ink: Color = V8.ink
    var mute: Color = V8.mute

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(V8Font.display(22)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let trailing { MonoLabel(trailing, color: mute) }
        }
    }
}

// MARK: - Linha do dia: cards e deslocamentos

/// Uma parada da Linha (âncora = tinta, must = branco, micro = tracejada; feito 50 %, agora laranja).
struct DayStopRow: View {
    var stop: DayStop
    var index: Int
    var state: LinhaStopState
    var region: Region
    var onTap: (() -> Void)?

    private var isMicro: Bool { stop.kind == .micro }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(region.timeString(stop.start))
                    .font(V8Font.mono(13))
                    .fontWeight(.semibold)
                    .foregroundStyle(state == .now ? V8.orangeDeep : V8.ink)
                Text(DayText.caption(for: stop, isNow: state == .now).uppercased())
                    .font(V8Font.mono(8))
                    .tracking(0.8)
                    .foregroundStyle(V8.mute)
            }
            .lineLimit(1)
            .frame(width: 56, alignment: .leading)
            .padding(.top, isMicro ? 10 : 16)
            .opacity(state == .done ? 0.5 : 1)

            card
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.timeString(stop.start)), \(stop.label), \(stop.note)\(state == .done ? ", feito" : state == .now ? ", agora" : "")")
    }

    @ViewBuilder private var card: some View {
        let content = HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                Text(stop.label)
                    .font(V8Font.text(isMicro ? 14 : 16, weight: isMicro ? .semibold : .bold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Text(state == .done && !stop.note.contains("feito") ? stop.note + " · feito ✓" : stop.note)
                    .font(V8Font.text(isMicro ? 12.5 : 13))
                    .foregroundStyle(titleColor.opacity(0.72))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if state == .now {
                Image(systemName: "arrow.up.right").font(.system(size: 15, weight: .bold)).foregroundStyle(V8.ink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, isMicro ? 9 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
        .overlay {
            if isMicro && state != .now {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(V8.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else if stop.kind == .must && state == .upcoming {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(V8.ink.opacity(0.08), lineWidth: 1)
            }
        }
        .opacity(state == .done ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

        if let onTap {
            Button(action: onTap) { content }.buttonStyle(MustPressStyle())
        } else {
            content
        }
    }

    private var fill: Color {
        if state == .now { return V8.orange }
        switch stop.kind {
        case .anchor: return V8.ink
        case .must: return V8.white
        case .micro: return .clear
        }
    }

    private var titleColor: Color {
        if state == .now { return V8.ink }
        return stop.kind == .anchor ? V8.white : V8.ink
    }

    /// Quadradinho da esquerda: selo da âncora (laranja), índice (must, agora), selo curto da micro.
    private var badge: some View {
        let text: String = {
            if stop.kind == .micro { return state == .done ? "✓" : (stop.tag ?? "·") }
            if stop.kind == .anchor && state != .now { return stop.tag ?? "\(index)" }
            return "\(index)"
        }()
        let (bg, fg): (Color, Color) = {
            if state == .now { return (V8.ink, V8.white) }
            if stop.kind == .anchor { return (V8.orange, V8.ink) }
            return (V8.ink.opacity(0.07), V8.ink)
        }()
        return Text(text)
            .font(V8Font.mono(text.count > 2 ? 10 : 12))
            .fontWeight(.bold)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(fg)
            .frame(width: isMicro ? 34 : 40, height: isMicro ? 34 : 40)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(bg))
            .accessibilityHidden(true)
    }
}

/// Deslocamento entre duas paradas: traço + modo + minutos ("JY Yamanote 09:12 · 34 min · plat. 14").
struct DayLegRow: View {
    var leg: DayLeg
    var color: Color = V8.mute

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.5)).frame(width: 3, height: 18)
            Text(Self.text(leg).uppercased())
                .font(V8Font.mono(9.5))
                .tracking(0.6)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.leading, 68)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    static func text(_ leg: DayLeg) -> String {
        if !leg.detail.isEmpty { return leg.detail }
        return "\(modeLabel(leg.mode)) \(leg.minutes) min"
    }

    static func modeLabel(_ mode: DayLegMode) -> String {
        switch mode {
        case .walk: "a pé"
        case .train: "trem"
        case .metro: "metrô"
        case .bus: "ônibus"
        case .taxi: "táxi"
        }
    }
}
