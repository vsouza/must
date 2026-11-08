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
    /// Fundo do estilo `.line` (o fundo da tela, quando há lista rolando por trás).
    var lineFill: Color = .clear
    var action: () -> Void

    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 16

    private func line(_ size: CGFloat, lines: Int) -> some View {
        HStack(spacing: 9) {
            Text(title).font(V8Font.text(size, weight: .bold)).lineLimit(lines).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: lines > 1)
            if let systemImage { Image(systemName: systemImage).font(.system(size: size - 1, weight: .bold)) }
        }
    }

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                ForEach(ButtonMetrics.steps, id: \.self) { line($0, lines: 1) }
                line(15, lines: 2).padding(.vertical, 12)
            }
            .foregroundStyle(style == .ink ? V8.white : style == .line ? lineColor : V8.ink)
            .padding(.horizontal, ButtonMetrics.horizontalPadding(height: 56))
            .frame(maxWidth: .infinity, minHeight: ButtonMetrics.height(base: 56, font: scaled, kind: .button))
            .background(Capsule().fill(style == .orange ? V8.orange : style == .ink ? V8.ink : lineFill))
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

// MARK: - Linha do dia: o índice (prompt 30)

/// Uma parada da Linha como linha do índice, de largura total: hora em número grande, nome e motivo, régua de 2 pt embaixo.
/// Agora = laranja inteiro; âncora = tinta; must = papel; micro-parada = linha baixa com régua fina tracejada. Feito 50 %.
struct DayStopRow: View {
    var stop: DayStop
    var index: Int
    var state: LinhaStopState
    var region: Region
    var onTap: (() -> Void)?

    private var isMicro: Bool { stop.kind == .micro }
    /// Micro-parada "em cartaz" (exposição/show na janela livre): selo EXP em laranja.
    /// TODO(r23:A): o motor (`MicroStops`) deve marcar com `tag: "EXP"`; troco por um `DayMicroKind` quando existir.
    private var isShow: Bool { isMicro && stop.tag?.uppercased() == "EXP" }
    private var isInk: Bool { state != .now && stop.kind == .anchor }

    private var main: Color { state == .now ? V8.ink : isInk ? V8.white : V8.ink }
    private var sub: Color { state == .now ? V8.ink.opacity(0.75) : isInk ? V8.muteDark : V8.mute }
    private var fill: Color { state == .now ? V8.orange : isInk ? V8.ink : .clear }

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
                    .lineLimit(1)
                Text(state == .done && !stop.note.contains("feito") ? stop.note + " · feito ✓" : state == .skipped ? "ficou pra depois · " + stop.note : stop.note)
                    .font(V8Font.text(isMicro ? 12 : 12.5))
                    .foregroundStyle(sub)
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                Line().stroke(V8.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
            } else {
                IndexRule()
            }
        }
        .opacity(state == .done || state == .skipped ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.timeString(stop.start)), \(stop.label), \(stop.note)\(state == .done ? ", feito" : state == .now ? ", agora" : "")")
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

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

/// Deslocamento entre duas paradas: um item de índice baixo ("JY Yamanote 09:12 · 34 min · plat. 14"), alinhado ao nome da
/// parada, com régua fina embaixo.
struct DayLegRow: View {
    var leg: DayLeg
    var color: Color = V8.mute

    var body: some View {
        HStack(spacing: 8) {
            Text("↓")
                .font(V8Font.mono(10.5, weight: .bold))
                .foregroundStyle(color)
            Text(Self.text(leg).uppercased())
                .font(V8Font.mono(9.5))
                .tracking(0.6)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.leading, 20 + 88 + 14)
        .padding(.trailing, 20)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink.opacity(0.35)).frame(height: 1) }
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
