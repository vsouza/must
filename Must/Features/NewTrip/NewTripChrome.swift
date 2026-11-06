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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            NewTripProgress(current: model.step).padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(V8Font.display(40)).tracking(-1.8)
                        .foregroundStyle(V8.ink)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 22).padding(.bottom, 26)
                        .accessibilityAddTraits(.isHeader)
                    content
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 18)
                }
            }
            footer.padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8).padding(.bottom, 12)
        .background(V8.paper.ignoresSafeArea())
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var header: some View {
        HStack(alignment: .top) {
            V8RoundButton(diameter: 44, label: model.step == 1 ? "Fechar" : "Voltar", action: model.step == 1 ? onClose : onBack) { size in
                V8Glyph(model.step == 1 ? .close : .back).frame(width: size, height: size)
            }
            .foregroundStyle(V8.ink)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 0) {
                SpecLabel("Nova viagem · \(model.step) de \(NewTripModel.questionSteps)")
                SpecLabel(model.contextLine)
            }
            .multilineTextAlignment(.trailing)
            .accessibilityElement(children: .combine)
        }
    }

    private var backButton: some View {
        V8Button("Voltar", .line) { model.step == 1 ? onClose() : onBack() }.foregroundStyle(V8.ink)
    }

    private var nextButton: some View {
        V8Button(primaryTitle, .orange, icon: .avancar, action: onNext)
            .opacity(primaryEnabled ? 1 : 0.4)
            .disabled(!primaryEnabled)
    }

    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { backButton.frame(maxWidth: 140); nextButton }
            VStack(spacing: 10) { nextButton; backButton }
        }
    }
}

/// Barra de progresso: 8 segmentos, os do passo e anteriores em laranja.
struct NewTripProgress: View {
    var current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...NewTripModel.questionSteps, id: \.self) { i in
                Capsule().fill(i <= current ? V8.orange : V8.rule).frame(height: 4)
            }
        }
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
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(dashed ? Color.clear : V8.white))
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(V8.ruleStrongColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                } else {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(V8.bone, lineWidth: 1)
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
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(filled ? V8.orange : V8.bone))
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
                Capsule().fill(.foreground).frame(width: 12, height: 2).frame(width: size, height: size)
            }
            V8RoundButton(diameter: 44, filled: filledPlus, label: plusLabel, action: onPlus) { size in
                V8Glyph(.plus).frame(width: size, height: size).foregroundStyle(filledPlus ? V8.white : V8.ink)
            }
        }
        .foregroundStyle(V8.ink)
    }
}
