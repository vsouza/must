import SwiftUI

/// Moldura de um passo (prompt 28 · F3): botão redondo + ficha no canto, barra de 8 segmentos, título display,
/// conteúdo rolável com fade antes dos botões, Voltar/Continuar no pé. Layout em stacks: o texto que quebra empurra.
struct NewTripStepFrame<Content: View>: View {
    var model: NewTripModel
    var title: String
    var primaryTitle = "Continuar"
    var primaryEnabled = true
    var onClose: () -> Void
    var onBack: () -> Void
    var onNext: () -> Void
    @ViewBuilder var content: Content

    @Environment(\.tripTheme) private var theme
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            NewTripProgress(current: model.step)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .background(V8.paper.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// Bloco do corte: cor do lugar (a da viagem em criação, se já escolheu), numeral do passo gigante e o título.
    private var header: some View {
        CutBand(photo: nil, tint: model.draft.colorHex.isEmpty ? nil : UInt32(model.draft.colorHex.dropFirst(), radix: 16)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    CutCornerButton(systemName: model.step == 1 ? "xmark" : "chevron.left", label: model.step == 1 ? "Fechar" : "Voltar",
                                    tint: V8.white, action: model.step == 1 ? onClose : onBack)
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 3) {
                        SpecLabel("Nova viagem · \(model.step) de \(NewTripModel.questionSteps)", color: V8.white.opacity(0.9))
                        SpecLabel(model.contextLine, color: V8.white.opacity(0.9))
                    }
                    .multilineTextAlignment(.trailing)
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: 8)
                HStack(alignment: .bottom, spacing: 12) {
                    Text(title)
                        .font(V8Font.display(38)).tracking(-1.6)
                        .foregroundStyle(V8.white)
                        .lineLimit(3).minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    Text("\(model.step)")
                        .font(V8Font.numeral(72)).tracking(-4)
                        .foregroundStyle(V8.white.opacity(0.9))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(height: 220 * min(scale, 1.3))
    }

    private var backButton: some View {
        Button { model.step == 1 ? onClose() : onBack() } label: {
            Text("VOLTAR").font(V8Font.mono(12, weight: .semibold)).tracking(1).foregroundStyle(V8.paper)
                .frame(minWidth: 96, maxHeight: .infinity)
                .padding(.horizontal, 14)
                .background(V8.ink)
        }
        .buttonStyle(.plain)
    }

    private var nextButton: some View {
        Button(action: onNext) {
            HStack(spacing: 10) {
                Text(primaryTitle.uppercased()).font(V8Font.mono(14, weight: .semibold)).tracking(1.2)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(V8.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(V8.orange)
            .opacity(primaryEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!primaryEnabled)
    }

    /// Voltar (tinta) e Continuar (laranja) de ponta a ponta no pé, régua de tinta em cima.
    private var footer: some View {
        HStack(spacing: 0) { backButton; nextButton }
            .frame(minHeight: 64)
            .fixedSize(horizontal: false, vertical: true)
            .background(V8.orange.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
    }
}

/// Barra de progresso: 8 segmentos, os do passo e anteriores em laranja.
struct NewTripProgress: View {
    var current: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...NewTripModel.questionSteps, id: \.self) { i in
                Rectangle().fill(i <= current ? V8.orange : V8.paper).frame(height: 8)
                    .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            }
        }
        .background(V8.ink)
        .accessibilityElement()
        .accessibilityLabel("Passo \(min(current, NewTripModel.questionSteps)) de \(NewTripModel.questionSteps)")
    }
}

/// Rótulo de seção (`.spec`): mono caixa alta.
struct NewTripSection: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(V8Font.mono(12, weight: .semibold)).tracking(1.4)
            .foregroundStyle(V8.mute)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Linha de nota (texto secundário de 15).
struct NewTripNote: View {
    var text: String
    var body: some View {
        Text(text).font(V8Font.text(15)).foregroundStyle(V8.mute)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Cartão branco de 1 pt de borda (`.card` do design) e o pontilhado das faltas.
struct NewTripCard<Content: View>: View {
    var dashed = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if dashed {
                    Rectangle().strokeBorder(V8.ink.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                } else {
                    Rectangle().strokeBorder(V8.ink, lineWidth: 2)
                }
            }
    }
}

extension V8 {
    static var ruleStrongColor: Color { Color(hex: Hex.ruleStrong) }
}

/// Etiqueta mono (LIDO, LIDO DO E-MAIL).
struct NewTripTag: View {
    var text: String
    var filled = false
    var body: some View {
        Text(text.uppercased())
            .font(V8Font.mono(11, weight: .bold)).tracking(1)
            .foregroundStyle(V8.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Rectangle().fill(filled ? V8.orange : Color.clear))
            .overlay(Rectangle().strokeBorder(V8.ink, lineWidth: filled ? 0 : 1.5))
            .fixedSize()
    }
}

/// Botão − / + redondo do passo 3 e 7.
struct NewTripStepper: View {
    var minusLabel: String
    var plusLabel: String
    var filledPlus = false
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            V8RoundButton(diameter: 44, label: minusLabel, action: onMinus) { size in
                Rectangle().fill(.foreground).frame(width: 12, height: 2).frame(width: size, height: size)
            }
            V8RoundButton(diameter: 44, filled: filledPlus, label: plusLabel, action: onPlus) { size in
                V8Glyph(.plus).frame(width: size, height: size).foregroundStyle(filledPlus ? V8.white : V8.ink)
            }
        }
        .foregroundStyle(V8.ink)
    }
}
