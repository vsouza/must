import SwiftUI

/// Identidade v8 (prompt 23 §1): três cores — tinta, papel, laranja — e cinzas só pra texto secundário.
/// Contrato da rodada 22 (fase 0). O agente A é dono deste arquivo; os outros só leem.
enum V8 {
    /// Tinta #121212: texto e fundos escuros (Agora, Ir, Montar, Próximos).
    static let ink = Color(hex: 0x121212)
    /// Papel #F2F0EA: fundo claro (Linha, Dicas, Lugar).
    static let paper = Color(hex: 0xF2F0EA)
    /// Laranja #FF4A1C: a única cor — ação e "agora".
    static let orange = Color(hex: 0xFF4A1C)
    /// Laranja escuro #C8330A: laranja como texto sobre papel (índices do `IndexRow`).
    static let orangeDeep = Color(hex: 0xC8330A)
    /// Texto secundário sobre papel #6B6B66.
    static let mute = Color(hex: 0x6B6B66)
    /// Texto secundário sobre tinta #A3A39C.
    static let muteDark = Color(hex: 0xA3A39C)
    /// Card sobre tinta #2B2B2B.
    static let graphite = Color(hex: 0x2B2B2B)
    /// Branco puro (cards de Must sobre papel, tinta da capa).
    static let white = Color.white

    /// Valores exatos (0xRRGGBB), pros testes.
    enum Hex {
        static let ink: UInt32 = 0x121212
        static let paper: UInt32 = 0xF2F0EA
        static let orange: UInt32 = 0xFF4A1C
        static let orangeDeep: UInt32 = 0xC8330A
        static let mute: UInt32 = 0x6B6B66
        static let muteDark: UInt32 = 0xA3A39C
        static let graphite: UInt32 = 0x2B2B2B
    }
}
