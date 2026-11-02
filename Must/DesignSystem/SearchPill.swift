import SwiftUI

/// Campo de busca em cápsula (lupa, texto, ×) com um acessório opcional à direita (ordenação do Board).
struct SearchPill<Trailing: View>: View {
    @Binding var text: String
    var placeholder: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            MustIconView(.buscar, size: 16).foregroundStyle(Color.must.secondary)
            TextField(placeholder, text: $text)
                .font(.must.archivo(14))
                .foregroundStyle(Color.must.ink)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { MustIconView(.fechar, size: 14).foregroundStyle(Color.must.secondary) }
                    .accessibilityLabel("Limpar busca")
            }
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Capsule().fill(Color(hex: 0xF1F2F4, opacity: 0.9)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7)))
        .shadow(color: Color(hex: 0x121316, opacity: 0.06), radius: 12, x: 0, y: 8)
    }
}

extension SearchPill where Trailing == EmptyView {
    init(text: Binding<String>, placeholder: String) {
        self.init(text: text, placeholder: placeholder) { EmptyView() }
    }
}
