import SwiftUI

/// Tintas possíveis de um card empilhado (Home, Lugar).
enum StackTint: Sendable, Hashable {
    case must(MustColor)
    /// Céu do card "Perto de você".
    case sky
    /// Vidro cinza (card de Horário/Distância/Preço no Lugar).
    case gray
    /// Golden hour (card "Sol hoje").
    case gold
    /// Cinza mais fechado (terceiro card dos painéis photo/sport).
    case slate

    var fill: AnyShapeStyle {
        switch self {
        case .must(let c): AnyShapeStyle(c.gradient(opacity: 0.9))
        case .sky: AnyShapeStyle(MustGradient.sky(opacity: (0.96, 0.9)))
        case .gray: AnyShapeStyle(Color(hex: 0xF6F7F9, opacity: 0.96))
        case .gold: AnyShapeStyle(LinearGradient(colors: [MustGradient.goldLight.opacity(0.96), MustGradient.goldStrong.opacity(0.9)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
        case .slate: AnyShapeStyle(Color(hex: 0xE9EBEF, opacity: 0.96))
        }
    }

    var text: Color {
        switch self {
        case .must(let c): c.text
        case .sky: Color.must.blueText
        case .gray, .slate: Color.must.ink
        case .gold: MustGradient.goldText
        }
    }
}

extension View {
    /// Vidro: branco 75% sobre `.ultraThinMaterial`, borda branca 70%, sombra suave, raio 22.
    func glass(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius))
    }

    /// Card cinza claro (`surface2`), raio 22.
    func card(cornerRadius: CGFloat = 22) -> some View {
        background(Color.must.surface2, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Card de vidro colorido e girado — os cards empilhados da Home.
    func stackCard(color: MustColor, rotation: Double = 0) -> some View {
        stackCard(tint: .must(color), rotation: rotation)
    }

    func stackCard(tint: StackTint, rotation: Double = 0) -> some View {
        modifier(StackCardModifier(tint: tint, rotation: rotation))
    }
}

private struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.white.opacity(0.75)))
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Color(hex: 0x121316, opacity: 0.08), radius: 15, x: 0, y: 10)
    }
}

private struct StackCardModifier: ViewModifier {
    var tint: StackTint
    var rotation: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        content
            .foregroundStyle(tint.text)
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(tint.fill))
            }
            .overlay(shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Color(hex: 0x121316, opacity: 0.12), radius: 25, x: 0, y: 20)
            .rotationEffect(.degrees(rotation))
    }
}
