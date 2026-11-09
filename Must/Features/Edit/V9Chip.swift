import SwiftUI

/// Chip de escolha dentro de formulário (V9): cápsula de preenchimento do sistema; ligado = contorno e texto no acento.
/// Use dentro de `FlowLayout` com `.buttonStyle(.borderless)` (em `Form` o botão não pode tomar a linha inteira).
struct V9Chip: View {
    var title: String
    var isOn = false
    var systemImage: String?

    init(_ title: String, isOn: Bool = false, systemImage: String? = nil) {
        self.title = title
        self.isOn = isOn
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.footnote) }
            Text(title).lineLimit(1)
        }
        .font(.subheadline.weight(isOn ? .semibold : .regular))
        .foregroundStyle(isOn ? V9.accent : Color.primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(isOn ? V9.accent.opacity(0.14) : V9.fill, in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? V9.accent : Color.clear, lineWidth: 1))
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Campo com rótulo pequeno em cima (o "nome", "bairro" do formulário).
struct V9Field<Content: View>: View {
    var label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
