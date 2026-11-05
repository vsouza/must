import SwiftUI

// Componentes v8 (prompt 23 §1). Contrato da fase 0: assinaturas públicas estáveis e uma versão simples que já desenha
// algo parecido com o design. O agente A é dono deste arquivo e troca o miolo; C e D programam contra as assinaturas.
// `Pill` já existe (v5): a pílula v8 se chama `V8Pill` até o A apagar a antiga.

// MARK: - Texturas

/// Arcos de 1 pt (2–3 círculos sobrepostos, 420–560 pt, opacidade 25–55 %, sangrando a tela). Decorativo.
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

    var body: some View {
        ZStack {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Circle()
                    .stroke(color.opacity(opacity), lineWidth: 1)
                    .frame(width: diameter + CGFloat(i) * 40, height: diameter + CGFloat(i) * 40)
                    .offset(x: CGFloat(i) * 36, y: CGFloat(i) * 24)
            }
        }
        .offset(offset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Numeral gigante (um por tela, sempre com significado: dia, hora, minutos, quantidade). Sangra a borda.
/// Decorativo: `accessibilityHidden` — o valor tem que aparecer também em texto normal na tela.
struct BigNumeral: View {
    var text: String
    var size: CGFloat = 220
    var color: Color = V8.ink

    init(_ text: String, size: CGFloat = 220, color: Color = V8.ink) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(V8Font.numeral(size))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityHidden(true)
    }
}

/// Micro-rótulo de ficha técnica (Martian Mono 8,5 pt, caixa alta, tracking .1em), nos cantos das telas.
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
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

// MARK: - Navegação

/// Barra v8: cápsula preta 66 pt; aba ativa = pílula laranja com rótulo; inativas = ícone; `+` = círculo papel.
struct V8NavBar: View {
    var active: MustTab
    var onSelect: (MustTab) -> Void
    var onPlus: () -> Void

    init(active: MustTab, onSelect: @escaping (MustTab) -> Void = { _ in }, onPlus: @escaping () -> Void = {}) {
        self.active = active
        self.onSelect = onSelect
        self.onPlus = onPlus
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MustTab.allCases) { tab in
                Button { onSelect(tab) } label: {
                    HStack(spacing: 6) {
                        MustIconView(tab.icon, size: 20)
                        if tab == active { Text(tab.title).font(V8Font.text(13, weight: .semibold)).lineLimit(1) }
                    }
                    .foregroundStyle(tab == active ? V8.ink : V8.white)
                    .padding(.horizontal, tab == active ? 14 : 10)
                    .frame(height: 46)
                    .background(Capsule().fill(tab == active ? V8.orange : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(tab == active ? .isSelected : [])
                if tab != MustTab.allCases.last { Spacer(minLength: 0) }
            }
            Button(action: onPlus) {
                MustIconView(.adicionar, size: 20)
                    .foregroundStyle(V8.ink)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(V8.paper))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Adicionar")
        }
        .padding(.horizontal, 10)
        .frame(height: 66)
        .background(Capsule().fill(V8.ink))
        .padding(.horizontal, 16)
    }
}

// MARK: - Cards e linhas

/// Cartão de bilhete (Próximos): picote nas laterais e linha tracejada entre as duas metades.
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

    private var fill: Color {
        switch tone {
        case .orange: V8.orange
        case .paper: V8.paper
        case .ink: V8.graphite
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            top.padding(16)
            Line().stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(V8.ink.opacity(0.3))
                .frame(height: 1)
                .padding(.horizontal, 14)
            bottom.padding(16)
        }
        .foregroundStyle(tone == .ink ? V8.white : V8.ink)
        .background(RoundedRectangle(cornerRadius: 18).fill(fill))
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
}

/// Linha de índice (Musts, Lista): índice grande em laranja escuro, nome, uma linha de meta, estado à direita.
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

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(index)
                .font(V8Font.numeral(34))
                .foregroundStyle(V8.orangeDeep)
                .frame(minWidth: 44, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(V8Font.text(17, weight: .semibold)).foregroundStyle(V8.ink).lineLimit(2)
                Text(meta).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if state != .none {
                    Text(state.label.uppercased()).font(V8Font.mono(10))
                        .foregroundStyle(state == .now ? V8.orangeDeep : V8.mute)
                }
                if let trailing { Text(trailing).font(V8Font.mono(10)).foregroundStyle(V8.mute) }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Faixa preta sólida por baixo do texto das telas de foto (Lugar, capa com foto). Sem degradê, sem foto lavada.
struct CutBand<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .foregroundStyle(V8.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(V8.ink)
    }
}

// MARK: - Botões e pílulas

/// Botão v8: laranja (ação principal), tinta, ou só contorno.
struct V8Button: View {
    enum Style: Sendable { case orange, ink, line }

    var title: String
    var style: Style
    var icon: MustIcon?
    var action: () -> Void

    init(_ title: String, _ style: Style = .orange, icon: MustIcon? = nil, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title).font(V8Font.text(15, weight: .semibold)).lineLimit(1)
                if let icon { MustIconView(icon, size: 16) }
            }
            .foregroundStyle(style == .ink ? V8.white : V8.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(style == .orange ? V8.orange : style == .ink ? V8.ink : Color.clear))
            .overlay(Capsule().strokeBorder(style == .line ? V8.ink.opacity(0.4) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(MustPressStyle())
    }
}

/// Pílula v8 (chips de contexto, filtros). `active` = laranja.
struct V8Pill: View {
    var text: String
    var active: Bool
    var onInk: Bool

    init(_ text: String, active: Bool = false, onInk: Bool = false) {
        self.text = text
        self.active = active
        self.onInk = onInk
    }

    var body: some View {
        Text(text)
            .font(V8Font.text(13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(active ? V8.ink : onInk ? V8.white : V8.ink)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(active ? V8.orange : Color.clear))
            .overlay(Capsule().strokeBorder(active ? Color.clear : (onInk ? V8.white : V8.ink).opacity(0.3), lineWidth: 1))
    }
}
