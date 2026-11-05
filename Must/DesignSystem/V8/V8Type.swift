import SwiftUI

/// Tipografia v8 (prompt 23 §1). Contrato da fase 0: por enquanto devolve as fontes atuais (Archivo, Geist Mono);
/// o agente A troca pelas novas — Bricolage Grotesque (display, numeral), Schibsted Grotesk (texto), Martian Mono (ficha).
/// As assinaturas não mudam: as telas (C, D) usam só estas quatro funções.
enum V8Font {
    /// Display (títulos): Bricolage Grotesque wdth 92 / 700. `width` em % (78 = numeral, 92 = título).
    static func display(_ size: CGFloat, width: CGFloat = 92) -> Font {
        MustFonts.scaled(MustFontFamily.archivo, size).weight(.bold)
    }

    /// Numeral gigante e índices: Bricolage Grotesque wdth 78 / 800. Tamanho fixo (decorativo, `accessibilityHidden`).
    static func numeral(_ size: CGFloat) -> Font {
        Font.custom(MustFontFamily.archivo, fixedSize: size).weight(.heavy)
    }

    /// Texto: Schibsted Grotesk 400–700, números tabulares. Acompanha o Dynamic Type.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        MustFonts.scaled(MustFontFamily.archivo, size).weight(weight).monospacedDigit()
    }

    /// Ficha técnica: Martian Mono (micro-rótulos em caixa alta, horários, códigos).
    static func mono(_ size: CGFloat) -> Font {
        MustFonts.scaled(MustFontFamily.geistMono, size).monospacedDigit()
    }
}
