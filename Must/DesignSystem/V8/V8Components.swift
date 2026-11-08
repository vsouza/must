import SwiftUI

// Componentes v8 (prompt 23 §1), fiéis a `design/v8/screens/*.png` e ao `v8.css`. Assinaturas do contrato da rodada 22
// (fase 0): C e D programam contra elas; o miolo é do agente A.

// MARK: - Texturas

/// Arcos de 1 pt (`.ring` do `v8.css`): 2–3 círculos do mesmo tamanho (420–560 pt), opacidade 25–55 %, sobrepostos e
/// sangrando a tela. Decorativo (não recebe toque, some do VoiceOver).
///
/// Use como fundo (`.background { Rings(...) }` ou primeira camada de um `ZStack`): ocupa o espaço proposto e desenha os
/// círculos a partir do canto superior esquerdo. `offset` é onde fica o canto do **primeiro** círculo; os outros descem
/// em diagonal como na capa (`CapaJP.png`: 420 pt em (−60,−150), (70,120), (−170,360)).
struct Rings: View {
    var color: Color = V8.ink
    var count: Int = 3
    var diameter: CGFloat = 480
    var opacity: Double = 0.4
    var offset: CGSize = CGSize(width: 140, height: -120)

    init(color: Color = V8.ink, count: Int = 3, diameter: CGFloat = 480, opacity: Double = 0.4,
         offset: CGSize = CGSize(width: 140, height: -120)) {
        self.color = color
        self.count = count
        self.diameter = diameter
        self.opacity = opacity
        self.offset = offset
    }

    /// Posição de cada círculo em relação ao primeiro, em diâmetros (tirada da capa do design).
    static let pattern: [CGPoint] = [CGPoint(x: 0, y: 0), CGPoint(x: 0.31, y: 0.64), CGPoint(x: -0.26, y: 1.21)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(max(count, 1), Self.pattern.count), id: \.self) { i in
                Circle()
                    .stroke(color.opacity(opacity), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                    .offset(x: offset.width + Self.pattern[i].x * diameter, y: offset.height + Self.pattern[i].y * diameter)
            }
        }
        // `minWidth/minHeight: 0`: o quadro fica do tamanho proposto mesmo com os círculos maiores que a tela (sangram).
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Numeral gigante (`.num`: Bricolage wdth 78 / 800, tracking −.06em, entrelinha .78). Um por tela, sempre com
/// significado (dia, hora, minutos, quantidade). **Sangra**: não encolhe pra caber — ocupa a largura proposta e passa da
/// borda do lado oposto a `alignment`. Decorativo: `accessibilityHidden` — o valor tem que aparecer em texto na tela.
struct BigNumeral: View {
    var text: String
    var size: CGFloat = 220
    var color: Color = V8.ink
    var alignment: Alignment = .leading

    init(_ text: String, size: CGFloat = 220, color: Color = V8.ink, alignment: Alignment = .leading) {
        self.text = text
        self.size = size
        self.color = color
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .font(V8Font.numeral(size))
            .tracking(-0.06 * size)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            // Entrelinha .78: a caixa abraça os algarismos (da linha de base à altura das maiúsculas).
            .frame(height: size * 0.78)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: alignment)
            .accessibilityHidden(true)
    }
}

/// Micro-rótulo de ficha técnica (`.spec`: Martian Mono 8,5 pt 500, caixa alta, tracking .1em, entrelinha 1,55),
/// nos cantos das telas. Aceita quebra com `\n` (duas linhas, como no design).
struct SpecLabel: View {
    var text: String
    var color: Color = V8.mute

    init(_ text: String, color: Color = V8.mute) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(V8Font.mono(8.5))
            .tracking(0.85)
            .lineSpacing(4)
            .foregroundStyle(color)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Navegação

/// Barra v8 (`Nav.png`, `.nav` do `v8.css`): cápsula preta de 66 pt; aba ativa = pílula laranja com ícone e rótulo
/// (mais larga); inativas = só o ícone branco; `+` = círculo papel à direita (toque: Montar o dia).
struct V8NavBar: View {
    var active: MustTab
    var onSelect: (MustTab) -> Void
    var onPlus: () -> Void
    /// Toque longo no `+` (prompt 25: o toque abre o Quero…, o longo monta o dia). `nil` = sem toque longo.
    var onPlusHold: (() -> Void)?
    /// O toque longo já disparou: o "soltar" que vem depois não abre o toque simples.
    @State private var held = false

    init(active: MustTab, onSelect: @escaping (MustTab) -> Void = { _ in }, onPlus: @escaping () -> Void = {},
         onPlusHold: (() -> Void)? = nil) {
        self.active = active
        self.onSelect = onSelect
        self.onPlus = onPlus
        self.onPlusHold = onPlusHold
    }

    var body: some View {
        NavRow(activeIndex: MustTab.allCases.firstIndex(of: active) ?? 0) {
            ForEach(MustTab.allCases) { tab in
                let on = tab == active
                Button { onSelect(tab) } label: {
                    HStack(spacing: 9) {
                        V8Glyph(tab.glyph).frame(width: 20, height: 20)
                        if on {
                            Text(tab.title)
                                .font(V8Font.text(14, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .foregroundStyle(on ? V8.ink : V8.white)
                    .padding(.horizontal, on ? 14 : 0)
                    .frame(maxWidth: .infinity, minHeight: 54, maxHeight: 54)
                    .background(Capsule().fill(on ? V8.orange : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Button {
                if held { held = false } else { onPlus() }
            } label: {
                V8Glyph(.plus)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(V8.ink)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(V8.paper))
                    .contentShape(Circle())
            }
            .buttonStyle(MustPressStyle())
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                held = true
                onPlusHold?()
                // Se o soltar não chegar como toque (arrastou pra fora), o próximo toque vale normal.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    held = false
                }
            }, isEnabled: onPlusHold != nil)
            .accessibilityLabel(onPlusHold == nil ? "Adicionar" : "Quero…")
            .accessibilityHint(onPlusHold == nil ? "Montar o dia" : "o que você quer agora; toque longo monta o dia")
            .accessibilityAction(named: "Montar o dia") { onPlusHold?() }
        }
        .padding(6)
        .frame(height: 66)
        .background(Capsule().fill(V8.ink))
        .shadow(color: V8.ink.opacity(0.28), radius: 22, x: 0, y: 18)
        .padding(.horizontal, 18)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Distribui a barra como o `flex` do CSS: aba ativa 2,2, as outras 1, o `+` fixo em 54 pt, 4 pt entre elas.
private struct NavRow: Layout {
    var activeIndex: Int
    var gap: CGFloat = 4
    var plus: CGFloat = 54
    var activeFlex: CGFloat = 2.2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 360, height: 54)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let tabs = subviews.count - 1
        let free = max(0, bounds.width - plus - gap * CGFloat(subviews.count - 1))
        let unit = free / (activeFlex + CGFloat(max(tabs - 1, 0)))
        var x = bounds.minX
        for (i, view) in subviews.enumerated() {
            let w = i == tabs ? plus : (i == activeIndex ? unit * activeFlex : unit)
            view.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: w, height: 54))
            x += w + gap
        }
    }
}

extension MustTab {
    /// Desenho da aba na barra v8 (`Nav.png`): relógio, mapa dobrado, linhas, maleta.
    var glyph: V8Glyph.Kind {
        switch self {
        case .hoje: .clock
        case .guia: .map
        case .musts: .lines
        case .viagem: .briefcase
        }
    }
}

/// Ícones de traço da v8 desenhados em vetor (viewBox 24, os `<svg>` do design). Herdam a cor do `foregroundStyle`.
struct V8Glyph: View {
    enum Kind: Sendable { case clock, map, lines, briefcase, plus, arrow, check, close, back, wallet, sparkle }

    var kind: Kind
    var lineWidth: CGFloat?

    init(_ kind: Kind, lineWidth: CGFloat? = nil) {
        self.kind = kind
        self.lineWidth = lineWidth
    }

    private var defaultWidth: CGFloat {
        switch kind {
        case .clock: 2
        case .plus, .arrow: 2.4
        default: 1.8
        }
    }

    var body: some View {
        GlyphShape(kind: kind)
            .stroke(style: StrokeStyle(lineWidth: lineWidth ?? defaultWidth, lineCap: .round, lineJoin: .round))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    struct GlyphShape: Shape {
        var kind: Kind

        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 24
            let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
            func poly(_ points: [(CGFloat, CGFloat)], closed: Bool = false) -> Path {
                var path = Path()
                path.addLines(points.map { p($0.0, $0.1) })
                if closed { path.closeSubpath() }
                return path
            }
            var path = Path()
            switch kind {
            case .clock:
                path.addEllipse(in: CGRect(x: o.x + 3.5 * s, y: o.y + 3.5 * s, width: 17 * s, height: 17 * s))
                path.addPath(poly([(12, 7.5), (12, 12), (15, 14)]))
            case .map:
                path.addPath(poly([(3, 6), (9, 4), (15, 6), (21, 4), (21, 18), (15, 20), (9, 18), (3, 20)], closed: true))
                path.addPath(poly([(9, 4), (9, 18)]))
                path.addPath(poly([(15, 6), (15, 20)]))
            case .lines:
                path.addPath(poly([(5, 6), (19, 6)]))
                path.addPath(poly([(5, 12), (19, 12)]))
                path.addPath(poly([(5, 18), (14, 18)]))
            case .briefcase:
                path.addPath(poly([(4, 8), (20, 8), (20, 18), (4, 18)], closed: true))
                path.addPath(poly([(8, 8), (8, 5), (16, 5), (16, 8)]))
            case .plus:
                path.addPath(poly([(12, 5), (12, 19)]))
                path.addPath(poly([(5, 12), (19, 12)]))
            case .arrow:
                path.addPath(poly([(7, 17), (17, 7)]))
                path.addPath(poly([(9, 7), (17, 7), (17, 15)]))
            case .check:
                path.addPath(poly([(5, 12.5), (10, 17.5), (19, 7)]))
            case .close:
                path.addPath(poly([(6, 6), (18, 18)]))
                path.addPath(poly([(18, 6), (6, 18)]))
            case .back:
                path.addPath(poly([(15, 5), (8, 12), (15, 19)]))
            case .wallet:
                path.addRoundedRect(in: CGRect(x: o.x + 3.5 * s, y: o.y + 6 * s, width: 17 * s, height: 12 * s),
                                    cornerSize: CGSize(width: 2 * s, height: 2 * s))
                path.addPath(poly([(3.5, 10), (20.5, 10)]))
                path.addPath(poly([(15, 14), (17, 14)]))
            case .sparkle:
                path.addPath(poly([(12, 3), (13.8, 7.6), (18, 9), (13.8, 10.4), (12, 15), (10.2, 10.4), (6, 9), (10.2, 7.6)],
                                  closed: true))
            }
            return path
        }
    }
}

// MARK: - Cards e linhas

/// Cartão de bilhete (`Proximos.png`): picote em meia-lua nas duas laterais e linha tracejada entre as metades.
/// `top` costuma ter a etiqueta (tinta, Martian Mono) e o horário; `bottom`, o nome e a meta.
/// Tons: `.orange` (reserva de hoje), `.paper` (ingresso, trem, voo), `.ink` (grafite, sobre fundo tinta ou papel).
struct TicketCard<Top: View, Bottom: View>: View {
    enum Tone: Sendable { case orange, paper, ink }

    var tone: Tone
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom

    init(tone: Tone = .paper, @ViewBuilder top: () -> Top, @ViewBuilder bottom: () -> Bottom) {
        self.tone = tone
        self.top = top()
        self.bottom = bottom()
    }

    /// Raio do picote e dos cantos.
    static var notch: CGFloat { 11 }
    static var corner: CGFloat { 24 }

    private var fill: Color {
        switch tone {
        case .orange: V8.orange
        case .paper: V8.paper
        case .ink: V8.graphite
        }
    }

    private var ink: Color { tone == .ink ? V8.white : V8.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            DashedLine()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(ink.opacity(0.35))
                .frame(height: 1)
                .padding(.horizontal, Self.notch + 4)
                .anchorPreference(key: NotchAnchorKey.self, value: .bounds) { $0 }
            bottom
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(ink)
        .backgroundPreferenceValue(NotchAnchorKey.self) { anchor in
            GeometryReader { geo in
                TicketShape(notchY: anchor.map { geo[$0].midY } ?? geo.size.height / 2,
                            notch: Self.notch, corner: Self.corner)
                    .fill(fill)
            }
        }
        .contentShape(TicketContentShape(corner: Self.corner))
    }
}

private struct NotchAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Retângulo arredondado com duas meias-luas cortadas nas laterais, na altura `notchY`.
struct TicketShape: Shape {
    var notchY: CGFloat
    var notch: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let card = Path(roundedRect: rect, cornerRadius: corner, style: .continuous)
        var holes = Path()
        holes.addEllipse(in: CGRect(x: rect.minX - notch, y: notchY - notch, width: 2 * notch, height: 2 * notch))
        holes.addEllipse(in: CGRect(x: rect.maxX - notch, y: notchY - notch, width: 2 * notch, height: 2 * notch))
        return card.subtracting(holes)
    }
}

private struct TicketContentShape: Shape {
    var corner: CGFloat
    func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: corner, style: .continuous) }
}

private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Estado à direita de um `IndexRow` (agora / aberto / abre 17h / fechado / feito / reserva).
enum IndexRowState: Hashable, Sendable {
    case now
    case open
    case opensAt(String)
    case closed
    case done
    case reservation(String)
    case none

    var label: String {
        switch self {
        case .now: "agora"
        case .open: "aberto"
        case .opensAt(let h): "abre \(h)"
        case .closed: "fechado"
        case .done: "feito"
        case .reservation(let h): "reserva \(h)"
        case .none: ""
        }
    }

    /// Agora, aberto e reserva chamam atenção (laranja escuro); o resto é cinza.
    var isLive: Bool {
        switch self {
        case .now, .open, .reservation: true
        default: false
        }
    }
}

/// Linha de índice (`Lista.png`, `.li` do `v8.css`): índice grande em laranja escuro (Bricolage wdth 80 / 800), nome
/// 16/700, uma linha de meta, e à direita o estado (ponto + Martian Mono caixa alta) e a distância/hora. Filete em cima.
/// Feito = a linha inteira a 50 %.
struct IndexRow: View {
    var index: String
    var title: String
    var meta: String
    var state: IndexRowState
    var trailing: String?

    init(index: String, title: String, meta: String, state: IndexRowState = .none, trailing: String? = nil) {
        self.index = index
        self.title = title
        self.meta = meta
        self.state = state
        self.trailing = trailing
    }

    private var stateColor: Color { state.isLive ? V8.orangeDeep : V8.mute }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(index)
                .font(Font(V8Fonts.bricolage(30, weight: 800, width: 80, opticalSize: 96)))
                .tracking(-1.2)
                .foregroundStyle(V8.orangeDeep)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 38, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(V8Font.text(16, weight: .bold))
                    .tracking(-0.16)
                    .foregroundStyle(V8.ink)
                    .lineLimit(2)
                if !meta.isEmpty {
                    Text(meta).font(V8Font.text(12)).foregroundStyle(V8.mute).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if state != .none || trailing != nil {
                VStack(alignment: .trailing, spacing: 3) {
                    if state != .none {
                        HStack(spacing: 5) {
                            Circle().fill(state.isLive ? V8.orange : V8.mute).frame(width: 6, height: 6)
                            Text(state.label.uppercased())
                                .font(V8Font.mono(10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(stateColor)
                        }
                    }
                    if let trailing {
                        Text(trailing).font(V8Font.mono(10, weight: .semibold)).foregroundStyle(V8.ink)
                    }
                }
                .lineLimit(1)
                .fixedSize()
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(V8.ink.opacity(0.14)).frame(height: 1) }
        .opacity(state == .done ? 0.5 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Faixa preta sólida por baixo do texto das telas de foto (Lugar, capa com foto). Sem degradê, sem foto lavada.
struct InkBand<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .foregroundStyle(V8.white)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.ink)
    }
}

// MARK: - Botões e pílulas

/// Botão v8 (`.btn`): mínimo 56 pt (compacto 44), cápsula, Schibsted 16/700 que desce 16 → 15 → 14 em uma linha
/// (`ViewThatFits`, sem `minimumScaleFactor`); se não couber em 14, quebra em 2 linhas a 15 e a altura cresce. Altura
/// ≥ 3,1 × fonte (cresce com o Dynamic Type); padding H = máx(14, 0,36 × altura). `.orange` = ação principal (texto
/// tinta), `.ink` = tinta (texto branco), `.line` = só contorno de 1,5 pt na cor do texto em volta.
/// Regra completa: `ButtonMetrics` e `BotoesFontes.png`.
struct V8Button: View {
    typealias Style = V8ButtonFace.Style

    var title: String
    var style: Style
    var icon: MustIcon?
    var compact: Bool
    var action: () -> Void

    init(_ title: String, _ style: Style = .orange, icon: MustIcon? = nil, compact: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.icon = icon
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            V8ButtonFace(title, style, icon: icon, compact: compact)
        }
        .buttonStyle(MustPressStyle())
    }
}

/// O desenho do `V8Button` sem o `Button` (pra usar de rótulo de `ShareLink`, `Menu`, `NavigationLink`).
struct V8ButtonFace: View {
    enum Style: Sendable { case orange, ink, line }

    var title: String
    var style: Style
    var icon: MustIcon?
    var compact: Bool

    @ScaledMetric(relativeTo: .body) private var scaled: CGFloat = 16

    init(_ title: String, _ style: Style = .orange, icon: MustIcon? = nil, compact: Bool = false) {
        self.title = title
        self.style = style
        self.icon = icon
        self.compact = compact
    }

    private var base: CGFloat { compact ? ButtonMetrics.compactHeight : ButtonMetrics.buttonHeight }
    private var steps: [CGFloat] { compact ? [14] : ButtonMetrics.steps }

    private func line(_ size: CGFloat, lines: Int) -> some View {
        HStack(spacing: 9) {
            Text(title)
                .font(V8Font.text(size, weight: .bold))
                .lineLimit(lines)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: lines > 1)
            if let icon { MustIconView(icon, size: size + 2) }
        }
    }

    var body: some View {
        let pad = ButtonMetrics.horizontalPadding(height: base)
        let minH = ButtonMetrics.height(base: base, font: compact ? scaled * 14 / 16 : scaled, kind: .button)
        let content = ViewThatFits(in: .horizontal) {
            ForEach(steps, id: \.self) { size in line(size, lines: 1) }
            line(compact ? 14 : 15, lines: 2).padding(.vertical, 12)
        }
        .padding(.horizontal, pad)
        .frame(maxWidth: .infinity, minHeight: minH)
        .contentShape(Capsule())
        switch style {
        case .orange: content.foregroundStyle(V8.ink).background(Capsule().fill(V8.orange))
        case .ink: content.foregroundStyle(V8.white).background(Capsule().fill(V8.ink))
        case .line: content.overlay(Capsule().strokeBorder(.foreground, lineWidth: 1.5))
        }
    }
}

/// Pílula v8 (`.pill`): 34 pt / 13·600 (pequena 32 / 12·600), contorno de 1 pt na cor do texto, padding H 14 — chips de
/// contexto e filtros. Altura ≥ 2,6 × fonte (cresce com o Dynamic Type); linhas de pílulas rolam na horizontal.
/// `active`: sobre papel vira **tinta** (filtros de Lista/Musts/Dicas); sobre tinta (`onInk`) vira **laranja**
/// (modos do Ir). Assim a pílula ativa nunca some no fundo.
struct V8Pill: View {
    var text: String
    var active: Bool
    var onInk: Bool
    var small: Bool

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    init(_ text: String, active: Bool = false, onInk: Bool = false, small: Bool = false) {
        self.text = text
        self.active = active
        self.onInk = onInk
        self.small = small
    }

    private var fill: Color {
        guard active else { return .clear }
        return onInk ? V8.orange : V8.ink
    }

    private var ink: Color {
        if active { return onInk ? V8.ink : V8.white }
        return onInk ? V8.white : V8.ink
    }

    var body: some View {
        let font: CGFloat = small ? 12 : 13
        let base = small ? ButtonMetrics.smallPillHeight : ButtonMetrics.pillHeight
        Text(text)
            .font(V8Font.text(font, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .frame(minHeight: max(base, ButtonMetrics.pillRatio * font * scale))
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(active ? Color.clear : ink, lineWidth: 1))
            .contentShape(Capsule())
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// Botão redondo v8 (`BotoesFontes.png`): 44 (glifo 18), 36 (glifo 16) ou 52 (glifo 20), contorno de 1,8 pt.
struct V8RoundButton<Glyph: View>: View {
    var diameter: CGFloat
    var filled: Bool
    var label: String
    var action: () -> Void
    @ViewBuilder var glyph: (CGFloat) -> Glyph

    init(diameter: CGFloat = 44, filled: Bool = false, label: String, action: @escaping () -> Void,
         @ViewBuilder glyph: @escaping (CGFloat) -> Glyph) {
        self.diameter = diameter
        self.filled = filled
        self.label = label
        self.action = action
        self.glyph = glyph
    }

    var body: some View {
        Button(action: action) {
            glyph(ButtonMetrics.roundGlyph(diameter: diameter))
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(filled ? V8.ink : .clear))
                .overlay(Circle().strokeBorder(.foreground, lineWidth: 1.8))
                .contentShape(Circle())
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(label)
    }
}
