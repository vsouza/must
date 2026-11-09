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
        NavigationStack {
            VStack(spacing: 0) {
                NewTripProgress(current: model.step)
                    .padding(.horizontal, V9.gutter)
                    .padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.largeTitle.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.bottom, 4)
                        Text(model.contextLine).font(.subheadline).foregroundStyle(.secondary)
                            .padding(.bottom, 16)
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, V9.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Nova viagem · \(model.step) de \(NewTripModel.questionSteps)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.step == 1 {
                        Button("Fechar", action: onClose)
                    } else {
                        Button("Voltar", systemImage: "chevron.left", action: onBack)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .v9Screen()
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// Continuar de ponta a ponta no pé (o Voltar fica na barra de cima).
    private var footer: some View {
        Button(action: onNext) {
            HStack(spacing: 8) {
                Text(primaryTitle).multilineTextAlignment(.center)
                Image(systemName: "arrow.right").accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .v9Primary()
        .disabled(!primaryEnabled)
        .padding(V9.gutter)
        .background(.bar)
    }
}

/// Barra de progresso do passo (nativa).
struct NewTripProgress: View {
    var current: Int

    var body: some View {
        ProgressView(value: Double(min(current, NewTripModel.questionSteps)), total: Double(NewTripModel.questionSteps))
            .tint(V9.accent)
            .accessibilityElement()
            .accessibilityLabel("Passo \(min(current, NewTripModel.questionSteps)) de \(NewTripModel.questionSteps)")
    }
}

/// Rótulo de seção.
struct NewTripSection: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Linha de nota (texto secundário de 15).
struct NewTripNote: View {
    var text: String
    var body: some View {
        Text(text).font(J9.font(15)).foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Cartão do sistema (ou pontilhado, pras faltas).
struct NewTripCard<Content: View>: View {
    var dashed = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dashed ? Color.clear : V9.card, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
            .overlay {
                if dashed {
                    RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                }
            }
    }
}

/// Etiqueta ("lido", "lido do e-mail").
struct NewTripTag: View {
    var text: String
    var filled = false
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? Color.white : Color.secondary)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(filled ? V9.accent : V9.fill, in: Capsule())
            .fixedSize()
    }
}

/// Botão − / + do passo 3 e 7.
struct NewTripStepper: View {
    var minusLabel: String
    var plusLabel: String
    var filledPlus = false
    var onMinus: () -> Void
    var onPlus: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            J9RoundButton(label: minusLabel, action: onMinus) { _ in Image(systemName: "minus").font(.body.weight(.bold)) }
            J9RoundButton(filled: filledPlus, label: plusLabel, action: onPlus) { _ in Image(systemName: "plus").font(.body.weight(.bold)) }
        }
    }
}
