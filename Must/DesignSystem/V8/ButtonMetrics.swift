import SwiftUI

/// Regra da fonte nos botões (prompt 27 §3, `BotoesFontes.png`): altura ≥ 3,1 × fonte no botão e ≥ 2,6 × na pílula;
/// degraus 16/15/14; nunca abaixo de 14 pt em linha única. Contrato da RODADA-23; o agente D completa e aplica.
enum ButtonMetrics {
    enum Kind: Sendable { case button, pill, round }

    static func fontSize(height: CGFloat, kind: Kind) -> CGFloat {
        let ratio: CGFloat = kind == .pill ? 2.6 : 3.1
        let raw = (height / ratio).rounded(.down)
        return min(16, max(14, raw))
    }
}
