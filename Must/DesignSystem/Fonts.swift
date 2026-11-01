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
struct MustFonts: Sendable {
    let title = Font.custom(MustFontFamily.archivo, fixedSize: 30).weight(.semibold)
    let listName = Font.custom(MustFontFamily.archivo, fixedSize: 20).weight(.semibold)
    let place = Font.custom(MustFontFamily.archivo, fixedSize: 17).weight(.semibold)
    let body = Font.custom(MustFontFamily.archivo, fixedSize: 15)
    let meta = Font.custom(MustFontFamily.archivo, fixedSize: 13)
    let serif = Font.custom(MustFontFamily.instrumentSerifItalic, fixedSize: 19)
    let mono = Font.custom(MustFontFamily.geistMono, fixedSize: 13).monospacedDigit()
    /// Use com `.textCase(.uppercase)` e `.tracking(1.1)` (≈ .1em em 11pt) — ver `Typography.swift`.
    let micro = Font.custom(MustFontFamily.geistMono, fixedSize: 11)
    let kanji = Font.custom(MustFontFamily.zenKakuBold, fixedSize: 17)

    func archivo(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(MustFontFamily.archivo, fixedSize: size).weight(weight)
    }

    func serif(_ size: CGFloat) -> Font {
        .custom(MustFontFamily.instrumentSerifItalic, fixedSize: size)
    }

    func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(MustFontFamily.geistMono, fixedSize: size).weight(weight).monospacedDigit()
    }

    func kanji(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? MustFontFamily.zenKakuBold : MustFontFamily.zenKakuMedium, fixedSize: size)
    }
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
