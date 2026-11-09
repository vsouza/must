import SwiftUI

// Adaptadores V9 com a mesma forma das peças V8 que as telas da aba Viagem e da entrada de dados usavam
// (prompt 32 · Fase 2 · J). Ficam aqui até o orquestrador promover o que for útil ao `V9.swift`.

enum J9 {
    /// Tamanho de projeto do V8 → estilo de texto do sistema (cresce com o Dynamic Type).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let style: Font.TextStyle
        switch size {
        case 34...: style = .largeTitle
        case 26..<34: style = .title
        case 21..<26: style = .title2
        case 18.5..<21: style = .title3
        case 16..<18.5: style = .body
        case 14..<16: style = .subheadline
        case 12..<14: style = .footnote
        default: style = .caption
        }
        return .system(style, weight: weight)
    }
}

/// Rótulo pequeno (substitui `MonoLabel`/`SpecLabel`/`Micro`): texto secundário, sem caixa alta.
struct J9Label: View {
    var text: String
    var color: Color = .secondary

    init(_ text: String, size: CGFloat? = nil, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).font(.footnote).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
    }
}

/// Marcador curto ao lado de uma linha ("hoje", "ingresso"). `filled` = acento.
struct J9Tag: View {
    var text: String
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? Color.white : Color.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(filled ? V9.accent : V9.fill, in: Capsule())
    }
}

/// Botão com texto: principal (acento cheio) ou secundário.
struct J9Button: View {
    var title: String
    var prominent = true
    var systemImage: String?
    var action: () -> Void

    init(_ title: String, prominent: Bool = true, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        let label = Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
                Text(title).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        if prominent { label.v9Primary() } else { label.v9Secondary() }
    }
}

/// Botão redondo de 44 pt (− / +): cheio com o acento ou cinza de sistema.
struct J9RoundButton<Glyph: View>: View {
    var diameter: CGFloat = 44
    var filled = false
    var label: String
    var action: () -> Void
    @ViewBuilder var glyph: (CGFloat) -> Glyph

    var body: some View {
        Button(action: action) {
            glyph(diameter)
                .foregroundStyle(filled ? Color.white : Color.primary)
                .frame(width: diameter, height: diameter)
                .background(filled ? V9.accent : V9.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Botão só com ícone, 44 pt, com nome para o VoiceOver.
struct J9IconButton: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.body.weight(.semibold)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

/// Campo de texto com rótulo em cima (substitui `CutField`).
struct J9TextField: View {
    var label: String?
    @Binding var text: String
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        J9Field(label: label) {
            TextField(placeholder, text: $text, axis: axis)
                .keyboardType(keyboard)
                .lineLimit(axis == .vertical ? 1...6 : 1...1)
                .padding(.vertical, 10)
        }
    }
}

/// Campo de busca (substitui `CutSearchField`).
struct J9SearchField<Trailing: View>: View {
    @Binding var text: String
    var placeholder: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Limpar busca")
            }
            trailing
        }
        .padding(.leading, 12)
        .frame(minHeight: 44)
        .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    /// Botão principal fixo no pé (substitui `.cutFooter`): material do sistema, acento só no botão.
    func j9Footer(_ title: String, enabled: Bool = true, arrow: Bool = false, id: String? = nil, action: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: action) { Text(title).frame(maxWidth: .infinity) }
                .v9Primary()
                .disabled(!enabled)
                .padding(V9.gutter)
                .background(.bar)
                .accessibilityIdentifier(id ?? "footer")
        }
    }
}
