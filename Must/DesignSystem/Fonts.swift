import SwiftUI

/// Famílias empacotadas no bundle (OFL). Archivo e Geist Mono são variáveis:
/// usamos o nome da família + `.weight(_:)`.
enum MustFontFamily {
    static let archivo = "Archivo"
    static let instrumentSerifItalic = "InstrumentSerif-Italic"
    static let instrumentSerif = "InstrumentSerif-Regular"
    static let geistMono = "Geist Mono"
    static let zenKakuMedium = "ZenKakuGothicNew-Medium"
    static let zenKakuBold = "ZenKakuGothicNew-Bold"

    /// PostScript names usados pra checar se a fonte foi registrada.
    static let postScriptNames = [
        "Archivo-SemiBold",
        "InstrumentSerif-Italic",
        "GeistMono-Regular",
        "ZenKakuGothicNew-Medium",
        "ZenKakuGothicNew-Bold",
    ]
}

/// Escala do Must (CLAUDE.md): título 30/600, nome de lista 20, lugar 17/600,
/// corpo 15, meta 13, serif 18–20, mono 13, micro 11 mono caixa alta.
///
/// Texto até 30 pt acompanha o Dynamic Type (`relativeTo:` pelo tamanho); o app limita em `.xxxLarge`
/// (`DynamicTypeSize.mustCap`), sem os tamanhos de acessibilidade. Kanji (selos de bairro, círculos) e números de vitrine
/// (> 30 pt) ficam fixos: vivem dentro de formas de tamanho fixo.
struct MustFonts: Sendable {
    let title = MustFonts.scaled(MustFontFamily.archivo, 30).weight(.semibold)
    let listName = MustFonts.scaled(MustFontFamily.archivo, 20).weight(.semibold)
    let place = MustFonts.scaled(MustFontFamily.archivo, 17).weight(.semibold)
    let body = MustFonts.scaled(MustFontFamily.archivo, 15)
    let meta = MustFonts.scaled(MustFontFamily.archivo, 13)
    let serif = MustFonts.scaled(MustFontFamily.instrumentSerifItalic, 19)
    let mono = MustFonts.scaled(MustFontFamily.geistMono, 13).monospacedDigit()
    /// Use com `.textCase(.uppercase)` e `.tracking(1.1)` (≈ .1em em 11pt) — ver `Typography.swift`.
    let micro = MustFonts.scaled(MustFontFamily.geistMono, 11)
    let kanji = Font.custom(MustFontFamily.zenKakuBold, fixedSize: 17)

    func archivo(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Self.scaled(MustFontFamily.archivo, size).weight(weight)
    }

    func serif(_ size: CGFloat) -> Font {
        Self.scaled(MustFontFamily.instrumentSerifItalic, size)
    }

    func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Self.scaled(MustFontFamily.geistMono, size).weight(weight).monospacedDigit()
    }

    func kanji(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? MustFontFamily.zenKakuBold : MustFontFamily.zenKakuMedium, fixedSize: size)
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
