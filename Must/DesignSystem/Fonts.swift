import SwiftUI

/// Famílias empacotadas no bundle (OFL, ver `Must/Resources/Fonts/README.md`). Identidade v8: Bricolage Grotesque,
/// Schibsted Grotesk e Martian Mono. Os nomes antigos (`archivo`, `geistMono`, `instrumentSerif…`, `zenKaku…`) ficam
/// como apelidos pras telas que ainda não foram redesenhadas: apontam pras fontes v8 equivalentes.
enum MustFontFamily {
    static let bricolage = V8Fonts.Family.bricolage
    static let schibsted = V8Fonts.Family.schibsted
    static let martianMono = V8Fonts.Family.martian

    /// v5 → v8: texto da interface.
    static let archivo = schibsted
    /// v5 → v8: sem serifa na identidade v8; a "voz do usuário" vira texto.
    static let instrumentSerifItalic = schibsted
    static let instrumentSerif = schibsted
    /// v5 → v8: ficha técnica.
    static let geistMono = martianMono
    /// v5 → v8: nada de kanji na interface; o que ainda pede essa fonte sai em Schibsted (nome PostScript, pro UIKit).
    static let zenKakuMedium = "SchibstedGrotesk-Medium"
    static let zenKakuBold = "SchibstedGrotesk-Bold"

    /// PostScript names usados pra checar se a fonte foi registrada.
    static let postScriptNames = V8Fonts.PostScript.all
}

/// Escala do Must (v5, mantida pra telas antigas): título 30/600, nome de lista 20, lugar 17/600, corpo 15, meta 13,
/// serif 18–20, mono 13, micro 11 mono caixa alta — agora nas fontes v8 (título e nome de lista em Bricolage display,
/// texto em Schibsted, mono em Martian Mono).
///
/// Texto até 30 pt acompanha o Dynamic Type (`relativeTo:` pelo tamanho); o app limita em `.xxxLarge`
/// (`DynamicTypeSize.mustCap`), sem os tamanhos de acessibilidade. Números de vitrine (> 30 pt) ficam fixos.
struct MustFonts: Sendable {
    let title = MustFonts.scaled(MustFontFamily.bricolage, 30).weight(.bold)
    let listName = MustFonts.scaled(MustFontFamily.bricolage, 20).weight(.bold)
    let place = MustFonts.scaled(MustFontFamily.schibsted, 17).weight(.semibold)
    let body = MustFonts.scaled(MustFontFamily.schibsted, 15)
    let meta = MustFonts.scaled(MustFontFamily.schibsted, 13)
    let serif = MustFonts.scaled(MustFontFamily.schibsted, 19)
    let mono = MustFonts.scaled(MustFontFamily.martianMono, 13).weight(.medium).monospacedDigit()
    /// Use com `.textCase(.uppercase)` e `.tracking(1.1)` (≈ .1em em 11pt) — ver `Typography.swift`.
    let micro = MustFonts.scaled(MustFontFamily.martianMono, 11).weight(.medium)
    /// v5 → v8: sem kanji; sobra o tamanho fixo em Schibsted.
    let kanji = Font.custom(MustFontFamily.schibsted, fixedSize: 17).weight(.bold)

    /// Fonte de interface (v5 "Archivo"): Schibsted Grotesk; acima de 30 pt e em negrito, Bricolage display.
    func archivo(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if size > 30, weight == .bold || weight == .heavy || weight == .black || weight == .semibold {
            return V8Font.display(size)
        }
        return Self.scaled(MustFontFamily.schibsted, size).weight(weight)
    }

    func serif(_ size: CGFloat) -> Font {
        Self.scaled(MustFontFamily.schibsted, size)
    }

    func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        V8Font.mono(size, weight: weight == .regular ? .medium : weight)
    }

    func kanji(_ size: CGFloat, bold: Bool = true) -> Font {
        Font.custom(MustFontFamily.schibsted, fixedSize: size).weight(bold ? .bold : .medium)
    }

    /// Fonte que cresce com o Dynamic Type a partir do estilo mais perto do tamanho; acima de 30 pt, fixa.
    static func scaled(_ name: String, _ size: CGFloat) -> Font {
        guard let style = textStyle(for: size) else { return .custom(name, fixedSize: size) }
        return .custom(name, size: size, relativeTo: style)
    }

    static func textStyle(for size: CGFloat) -> Font.TextStyle? {
        switch size {
        case ...11: .caption2
        case ...12: .caption
        case ...13: .footnote
        case ...15: .subheadline
        case ...17: .body
        case ...20: .title3
        case ...22: .title2
        case ...30: .title
        default: nil
        }
    }
}

extension DynamicTypeSize {
    /// Teto do texto no app: cresce até XXXL; tamanhos de acessibilidade quebrariam os cards e selos.
    static let mustCap: DynamicTypeSize = .xxxLarge
}

extension Font {
    static let must = MustFonts()
}

#if canImport(UIKit)
import UIKit

extension MustFontFamily {
    /// Fontes que não carregaram (deveria ser vazio). Útil pra validar o bundle.
    static var missing: [String] {
        postScriptNames.filter { UIFont(name: $0, size: 12) == nil }
    }
}
#endif
