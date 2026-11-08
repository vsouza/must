import SwiftUI

// Peças do corte pras telas de topo e folhas que ainda eram do visual antigo (prompt 31 · item 10).
// Bloco da foto/cor em cima, régua estática, papel embaixo com faixas de régua de 2 pt, campos quadrados de borda 2 pt,
// botão principal laranja de ponta a ponta no pé. Sem cápsula, raio, degradê ou sombra.

/// Cabeçalho de tela de topo: `CutBand` (foto que já está no disco, senão a cor do lugar com trama e arcos) com a ficha técnica
/// no canto, o título grande e uma linha de apoio; embaixo a régua estática de 12 pt.
struct CutScreenHeader<Trailing: View>: View {
    var title: String
    var corner: [String] = []
    var subtitle: String?
    var photo: URL?
    var height: CGFloat = 220
    var onBack: (() -> Void)?
    var backIcon = "chevron.left"
    @ViewBuilder var trailing: Trailing

    @Environment(\.tripTheme) private var theme
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            CutBand(photo: photo) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        if let onBack {
                            CutCornerButton(systemName: backIcon, label: backIcon == "xmark" ? "Fechar" : "Voltar", tint: theme.coverInk, action: onBack)
                        }
                        Spacer(minLength: 8)
                        if !corner.isEmpty {
                            SpecStack(lines: corner, color: theme.coverInk.opacity(0.9), alignment: .trailing)
                        }
                        trailing
                    }
                    Spacer(minLength: 8)
                    Text(title)
                        .font(V8Font.display(52))
                        .tracking(-1.6)
                        .foregroundStyle(theme.coverInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                    if let subtitle {
                        Text(subtitle)
                            .font(V8Font.text(14))
                            .foregroundStyle(theme.coverInk.opacity(0.9))
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .frame(height: height * min(scale, 1.4))
            CutRule()
        }
    }
}

extension CutScreenHeader where Trailing == EmptyView {
    init(title: String, corner: [String] = [], subtitle: String? = nil, photo: URL? = nil, height: CGFloat = 220,
         onBack: (() -> Void)? = nil, backIcon: String = "chevron.left") {
        self.init(title: title, corner: corner, subtitle: subtitle, photo: photo, height: height, onBack: onBack,
                  backIcon: backIcon) { EmptyView() }
    }
}

/// Faixa de papel: micro-rótulo mono (e um complemento à direita), o conteúdo e a régua de 2 pt embaixo.
struct CutSection<Content: View>: View {
    var label: String
    var trailing: String?
    var inset = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(label, size: 10, color: V8.mute)
                Spacer(minLength: 8)
                if let trailing { MonoLabel(trailing, size: 10, color: V8.ink) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)
            content
                .padding(.horizontal, inset ? 20 : 0)
                .padding(.bottom, 16)
            IndexRule()
        }
    }
}

/// Linha de ajuste/lista de papel: título, apoio, valor mono e régua de 2 pt.
struct CutRow<Trailing: View>: View {
    var title: String
    var detail: String?
    var tone: DayStrip<EmptyView>.Tone = .paper
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(V8Font.text(16, weight: .bold))
                    .foregroundStyle(tone == .ink ? V8.white : V8.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(V8Font.text(13))
                        .foregroundStyle(tone == .ink ? V8.muteDark : tone == .orange ? V8.ink.opacity(0.8) : V8.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(tone == .ink ? V8.ink : tone == .orange ? V8.orange : Color.clear)
        .overlay(alignment: .bottom) { IndexRule() }
        .contentShape(Rectangle())
    }
}

/// Valor mono à direita de uma `CutRow` (com seta opcional).
struct CutValue: View {
    var text: String
    var chevron = false
    var color: Color = V8.ink

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(V8Font.mono(13, weight: .semibold)).foregroundStyle(color).multilineTextAlignment(.trailing)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(color) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Etiqueta quadrada (mono, caixa alta): borda de 2 pt, ou cheia quando `filled`.
struct CutTag: View {
    var text: String
    var filled = false
    var orange = false

    var body: some View {
        Text(text.uppercased())
            .font(V8Font.mono(10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(filled ? (orange ? V8.ink : V8.paper) : V8.ink)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(filled ? (orange ? V8.orange : V8.ink) : Color.clear)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: filled ? 0 : 1.5))
    }
}

/// Botão quadrado de borda 2 pt (ação secundária).
struct CutButton: View {
    var title: String
    var filled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(V8Font.mono(12, weight: .semibold))
                .tracking(1)
                .foregroundStyle(filled ? V8.paper : V8.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(filled ? V8.ink : Color.clear)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Campo de texto quadrado: borda de 2 pt, texto Schibsted, micro-rótulo em cima.
struct CutField: View {
    var label: String?
    @Binding var text: String
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label { MonoLabel(label, size: 10, color: V8.mute) }
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(V8.mute), axis: axis)
                .font(V8Font.text(16))
                .foregroundStyle(V8.ink)
                .tint(V8.orange)
                .keyboardType(keyboard)
                .padding(.horizontal, 12)
                .frame(minHeight: 48, alignment: .leading)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
        }
    }
}

extension View {
    /// Botão principal da folha/tela: laranja de ponta a ponta no pé, régua de tinta em cima, mono caixa alta.
    func cutFooter(_ title: String, enabled: Bool = true, arrow: Bool = true, action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Text(title.uppercased())
                        .font(V8Font.mono(14, weight: .semibold)).tracking(1.2)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if arrow { Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold)) }
                }
                .foregroundStyle(V8.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(V8.orange.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
    }
}

/// Botão quadrado de canto (voltar, fechar, adicionar): 44 pt, borda de 2 pt.
struct CutCornerButton: View {
    var systemName: String
    var label: String
    var tint: Color = V8.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .overlay(Rectangle().stroke(tint, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Tela de topo no corte: cabeçalho (`CutScreenHeader`) + papel que rola, com folga pra barra. Uma linha troca o
/// "ZStack { fundo; ScrollView { voltar + título } }" das telas antigas.
struct CutPage<Content: View, Trailing: View>: View {
    var title: String
    var corner: [String] = []
    var subtitle: String?
    var height: CGFloat = 200
    var photo: URL?
    var onBack: (() -> Void)?
    var backIcon = "chevron.left"
    var spacer = true
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            CutScreenHeader(title: title, corner: corner, subtitle: subtitle, photo: photo, height: height, onBack: onBack,
                            backIcon: backIcon) { trailing }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                    if spacer { V8BarSpacer() }
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension CutPage where Trailing == EmptyView {
    init(title: String, corner: [String] = [], subtitle: String? = nil, height: CGFloat = 200, photo: URL? = nil,
         onBack: (() -> Void)? = nil, backIcon: String = "chevron.left", spacer: Bool = true, @ViewBuilder content: () -> Content) {
        self.init(title: title, corner: corner, subtitle: subtitle, height: height, photo: photo, onBack: onBack,
                  backIcon: backIcon, spacer: spacer, trailing: { EmptyView() }, content: content)
    }
}
