import SwiftUI

/// Controles do corte (prompt 30 §1): chip quadrado de borda 2 pt (ativo = tinta cheia com texto papel) e campo de busca em faixa
/// de papel com régua de 2 pt embaixo. Sem raio, sem cápsula.
struct CutChip: View {
    var text: String
    var isOn: Bool = false
    var minHeight: CGFloat = 40

    var body: some View {
        Text(text)
            .font(V8Font.mono(11, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(isOn ? V8.paper : V8.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: minHeight)
            .background(isOn ? V8.ink : Color.clear)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            .contentShape(Rectangle())
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Campo de busca do corte: lupa, texto, × e acessório; a régua de 2 pt fica embaixo.
struct CutSearchField<Trailing: View>: View {
    @Binding var text: String
    var placeholder: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                MustIconView(.buscar, size: 16).foregroundStyle(V8.ink)
                TextField("", text: $text, prompt: Text(placeholder.uppercased()).font(V8Font.mono(11)).foregroundStyle(V8.mute))
                    .font(V8Font.text(15))
                    .foregroundStyle(V8.ink)
                    .tint(V8.orange)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !text.isEmpty {
                    Button { text = "" } label: {
                        MustIconView(.fechar, size: 14).foregroundStyle(V8.ink).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Limpar busca")
                }
                trailing
            }
            .frame(minHeight: 46)
            Rectangle().fill(V8.ink).frame(height: 2)
        }
    }
}
