import SwiftUI

// Peças da capa do corte: a fenda laranja, a linha do índice e a linha do resultado. Réguas de 2 pt, sem cartão arredondado.

/// A fenda laranja do "quero…": o campo grande (Bricolage), o microfone e a dica.
struct CorteSlit: View {
    @Bindable var model: QueroModel
    var focused: FocusState<Bool>.Binding
    var speech: SpeechInput
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $model.text, prompt: Text("café").foregroundStyle(V8.ink.opacity(0.35)))
                .font(Font(V8Fonts.bricolage(52, weight: 800, width: 85, opticalSize: 96)))
                .tracking(-1.6)
                .foregroundStyle(V8.ink)
                .tint(V8.ink)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(onSubmit)
                .accessibilityLabel("O que você quer")
            HStack(alignment: .center, spacing: 10) {
                MonoLabel("digite ou fale · só lugares físicos", size: 9, color: V8.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button { Task { await speech.toggle() } } label: {
                    Text(speech.isListening ? "OUVINDO…" : "OU FALE")
                        .font(V8Font.mono(10, weight: .semibold)).tracking(1)
                        .foregroundStyle(speech.isListening ? V8.paper : V8.ink)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(speech.isListening ? V8.ink : Color.clear)
                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isListening ? "Parar de ouvir" : "Falar")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(V8.orange)
    }
}

/// Linha do índice duro da capa: número grande (distância ou hora), nome e motivo. Laranja = Must seu, tinta = fora do board
/// ou evento, papel = o plano. Réguas de 2 pt entre as linhas.
struct CorteIndexRow: View {
    var line: CorteIndexLine
    var open: () -> Void

    private var background: Color {
        switch line.tone {
        case .orange: V8.orange
        case .ink: V8.ink
        case .paper: V8.paper
        }
    }
    private var main: Color { line.tone == .ink ? V8.white : V8.ink }
    private var sub: Color { line.tone == .ink ? V8.muteDark : (line.tone == .orange ? V8.ink.opacity(0.75) : V8.mute) }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.big)
                        .font(V8Font.numeral(30))
                        .tracking(-0.6)
                        .foregroundStyle(main)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(line.unit.uppercased())
                        .font(V8Font.mono(9)).tracking(0.9).foregroundStyle(sub).lineLimit(1)
                }
                .frame(width: 84, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.title)
                        .font(V8Font.text(17, weight: .bold))
                        .foregroundStyle(main)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let trust = line.trust {
                            Text(trust.uppercased())
                                .font(V8Font.mono(8)).tracking(0.7).foregroundStyle(sub)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .overlay(Rectangle().stroke(sub.opacity(0.7), lineWidth: 0.8))
                        }
                        Text(line.reason)
                            .font(V8Font.text(12))
                            .foregroundStyle(sub)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(background)
            .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(line.title). \(line.big) \(line.unit). \(line.reason)\(line.trust.map { ". \($0)" } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// Linha do resultado: distância grande (mono), nome, motivo e a ação ("ir", "amanhã" ou "+ board"). Toque longo = encaixar hoje.
struct CorteResultRow: View {
    var line: CorteRow
    /// Na faixa tinta (fora do board).
    var dark: Bool
    var added: Bool
    var onTap: () -> Void
    var onAction: () -> Void
    var onFit: (() -> Void)?

    private var main: Color { dark ? V8.white : V8.ink }
    private var sub: Color { dark ? V8.muteDark : V8.mute }

    private var actionText: String {
        switch line.action {
        case .go: "ir"
        case .later(let day): day
        case .addToBoard: added ? "no board" : "+ board"
        }
    }
    private var actionDim: Bool {
        if case .later = line.action { return true }
        return added
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.distance.value)
                    .font(V8Font.mono(24, weight: .semibold)).foregroundStyle(main)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text((line.isBoard ? "\(line.distance.unit)\n\(line.travel)" : line.distance.unit).uppercased())
                    .font(V8Font.mono(8.5)).tracking(0.6).foregroundStyle(sub)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 84, alignment: .leading)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(line.row.result.name).font(V8Font.text(16, weight: .bold)).foregroundStyle(main).lineLimit(2)
                    Text(line.reason).font(V8Font.text(12)).foregroundStyle(sub).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onAction) {
                Text(actionText.uppercased())
                    .font(V8Font.mono(10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(actionDim ? sub : main)
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 9)
                    .overlay(Rectangle().stroke(actionDim ? sub.opacity(0.6) : main, lineWidth: 2))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(added)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { Rectangle().fill(dark ? V8.white.opacity(0.18) : V8.ink).frame(height: dark ? 1 : 2) }
        .contextMenu {
            if let onFit { Button("Encaixar hoje", systemImage: "arrow.up.right", action: onFit) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: actionText, onAction)
    }
}
