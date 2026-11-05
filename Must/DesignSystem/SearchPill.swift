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
                .font(V8Font.text(14))
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
        .background(Capsule().fill(V8.white))
        .overlay(Capsule().strokeBorder(V8.rule, lineWidth: 1))
    }
}

extension SearchPill where Trailing == EmptyView {
    init(text: Binding<String>, placeholder: String) {
        self.init(text: text, placeholder: placeholder) { EmptyView() }
    }
}
