import SwiftUI

/// Regra da fonte nos botões (prompt 27 §3, `BotoesFontes.png`): altura ≥ 3,1 × fonte no botão e ≥ 2,6 × na pílula;
/// degraus 16/15/14; nunca abaixo de 14 pt em linha única. Quando o rótulo não cabe em 14, quebra em 2 linhas a 15 e a
/// altura cresce. Função pura (testável); `V8Button`/`V8Pill` aplicam com `ViewThatFits`.
enum ButtonMetrics {
    enum Kind: Sendable { case button, pill, round }

    /// Degraus de fonte do rótulo em uma linha.
    static let steps: [CGFloat] = [16, 15, 14]
    static let buttonRatio: CGFloat = 3.1
    static let pillRatio: CGFloat = 2.6
    /// Fonte mínima em linha única.
    static let minSingleLine: CGFloat = 14
    /// Altura padrão (botão 56, compacto 44, pílula 34, pílula pequena 32).
    static let buttonHeight: CGFloat = 56
    static let compactHeight: CGFloat = 44
    static let pillHeight: CGFloat = 34
    static let smallPillHeight: CGFloat = 32

    static func fontSize(height: CGFloat, kind: Kind) -> CGFloat {
        let ratio: CGFloat = kind == .pill ? pillRatio : buttonRatio
        let raw = (height / ratio).rounded(.down)
        return min(16, max(14, raw))
    }

    /// Padding horizontal = máx(14, 0,36 × altura) (20 em 56, 16 em 44).
    static func horizontalPadding(height: CGFloat) -> CGFloat { max(14, (0.36 * height).rounded(.down)) }

    /// Altura mínima pra uma fonte: `max(base, razão × fonte)`.
    static func height(base: CGFloat, font: CGFloat, kind: Kind) -> CGFloat {
        max(base, (kind == .pill ? pillRatio : buttonRatio) * font)
    }

    /// Tamanho do glifo do botão redondo (44 → 18, 36 → 16, 52 → 20).
    static func roundGlyph(diameter: CGFloat) -> CGFloat {
        switch diameter {
        case ..<40: 16
        case ..<48: 18
        default: 20
        }
    }

    struct Size: Equatable, Sendable {
        var font: CGFloat
        var lines: Int
        var height: CGFloat
    }

    /// Escolhe a fonte e as linhas pra um rótulo na largura disponível (`forWidth`, já sem padding). A largura do
    /// texto é estimada (0,56 × fonte por caractere, Schibsted bold) e cresce com `dynamicType` (1 = padrão).
    static func size(forWidth width: CGFloat, text: String, dynamicType scale: CGFloat = 1, base: CGFloat = buttonHeight) -> Size {
        let count = CGFloat(max(text.count, 1))
        for step in steps {
            let font = step * scale
            if count * 0.56 * font <= width {
                return Size(font: step, lines: 1, height: height(base: base, font: font, kind: .button))
            }
        }
        let font = 15 * scale
        let lines = max(2, Int((count * 0.56 * font / max(width, 1)).rounded(.up)))
        return Size(font: 15, lines: lines, height: max(base, buttonRatio * font, CGFloat(lines) * font * 1.25 + 24))
    }
}
