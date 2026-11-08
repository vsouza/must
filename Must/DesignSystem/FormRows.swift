import SwiftUI

/// Seção em card cinza com rótulo micro (Ajustes, Região, Importar).
struct FormSection<Content: View>: View {
    var title: String?
    var background: AnyShapeStyle = AnyShapeStyle(Color.must.surface2)
    @ViewBuilder var content: Content

    init(_ title: String? = nil, background: AnyShapeStyle = AnyShapeStyle(Color.must.surface2), @ViewBuilder content: () -> Content) {
        self.title = title
        self.background = background
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Micro(title).padding(.top, 16).padding(.bottom, 4)
            }
            content
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
    }
}

/// Linha título + subtítulo + acessório à direita.
struct FormRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var titleColor: Color = Color.must.ink
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, titleColor: Color = Color.must.ink, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.must.archivo(16, .semibold))
                    .foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.must.meta)
                        .foregroundStyle(Color.must.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

extension FormRow where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleColor: Color = Color.must.ink) {
        self.init(title, subtitle: subtitle, titleColor: titleColor) { EmptyView() }
    }
}

/// Divisor 1pt `line`.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(V8.ink).frame(height: 2)
    }
}

/// Valor em mono à direita, com chevron opcional.
struct MonoValue: View {
    var text: String
    var chevron = false
    var color: Color = Color.must.ink

    init(_ text: String, chevron: Bool = false, color: Color = Color.must.ink) {
        self.text = text
        self.chevron = chevron
        self.color = color
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(.must.mono(15)).foregroundStyle(color).lineLimit(1)
            if chevron {
                MustIconView(.avancar, size: 14).foregroundStyle(Color.must.secondary)
            }
        }
    }
}

/// Status com ponto: "● ligado".
struct StatusChip: View {
    var text: String
    var on: Bool

    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(on ? V8.orange : V8.mute).frame(width: 8, height: 8)
            Text(text.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(0.8).foregroundStyle(V8.ink)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 1.5))
    }
}
