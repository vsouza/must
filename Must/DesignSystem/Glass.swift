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

    /// v8: cores sólidas da identidade (sem degradê, sem vidro).
    var fill: AnyShapeStyle {
        switch self {
        case .must(let c): AnyShapeStyle(c.light)
        case .sky: AnyShapeStyle(V8.bone)
        case .gray: AnyShapeStyle(V8.white)
        case .gold: AnyShapeStyle(V8.orange)
        case .slate: AnyShapeStyle(V8.bone)
        }
    }

    var text: Color { V8.ink }
}

extension View {
    /// v5 "vidro" → v8: card branco com filete, raio 22.
    func glass(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassModifier(cornerRadius: cornerRadius))
    }

    /// Card branco (`surface2`), raio 22.
    func card(cornerRadius: CGFloat = 22) -> some View {
        overlay(Rectangle().strokeBorder(V8.ink, lineWidth: 2))
    }

    /// v5: card de vidro colorido e girado. v8: card sólido, sem giro.
    func stackCard(color: MustColor, rotation: Double = 0) -> some View {
        stackCard(tint: .must(color), rotation: rotation)
    }

    func stackCard(tint: StackTint, rotation: Double = 0) -> some View {
        modifier(StackCardModifier(tint: tint, rotation: rotation))
    }
}

/// v8: card branco sólido com filete (o "vidro" da v5 saiu: sem material, sem sombra).
private struct GlassModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        // Corte: papel com borda de 2 pt, sem raio (o parâmetro fica por compatibilidade).
        content
            .overlay(Rectangle().strokeBorder(V8.ink, lineWidth: 2))
    }
}

/// v8: card sólido na cor do papel do token, sem rotação (os cards "empilhados e girados" eram da v5).
private struct StackCardModifier: ViewModifier {
    var tint: StackTint
    var rotation: Double

    func body(content: Content) -> some View {
        content
            .foregroundStyle(tint.text)
            .background(Rectangle().fill(tint.fill))
            .overlay(Rectangle().strokeBorder(V8.ink, lineWidth: 2))
    }
}
