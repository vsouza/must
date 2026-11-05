import CoreText
import SwiftUI
import UIKit

/// Tipografia v8 (prompt 23 §1): três vozes, todas OFL no bundle (`Must/Resources/Fonts`).
/// - **Bricolage Grotesque** (variável: opsz, wght, wdth): display (títulos, wdth 92 / 700) e numeral gigante
///   (wdth 78 / 800, tamanho fixo).
/// - **Schibsted Grotesk** (variável: wght): texto 400–700. Acompanha o Dynamic Type. Sem `tnum`: no Schibsted o
///   recurso tabular também alarga vírgula, ponto e dois-pontos ("dia , numa tela só ."); número alinhado vai em mono.
/// - **Martian Mono** (variável: wght, wdth): ficha técnica, horários, códigos — wdth 100 (o arquivo vem em 112,5).
///
/// Os eixos `wdth`/`opsz` não existem em `Font.custom`: display, numeral e mono são `CTFont` com
/// `kCTFontVariationAttribute`. Até 30 pt o tamanho cresce com o Dynamic Type (limite `.xxxLarge`, como o resto do app);
/// acima de 30 pt é fixo (numeral, títulos de capa).
/// As assinaturas são do contrato da rodada 22: as telas (C, D) usam só estas funções.
enum V8Font {
    /// Display (títulos): Bricolage Grotesque wdth 92 / 700. `width` em % (78 = numeral, 92 = título).
    static func display(_ size: CGFloat, width: CGFloat = 92) -> Font {
        display(size, width: width, weight: 700)
    }

    /// Display com peso explícito (o subtítulo da capa usa 500).
    static func display(_ size: CGFloat, width: CGFloat = 92, weight: CGFloat) -> Font {
        Font(V8Fonts.bricolage(V8Fonts.scaled(size), weight: weight, width: width, opticalSize: size))
    }

    /// Numeral gigante e índices: Bricolage Grotesque wdth 78 / 800. Tamanho fixo (decorativo, `accessibilityHidden`).
    static func numeral(_ size: CGFloat) -> Font {
        Font(V8Fonts.bricolage(size, weight: 800, width: 78, opticalSize: 96))
    }

    /// Texto: Schibsted Grotesk 400–700. Acompanha o Dynamic Type. Sem `.monospacedDigit()` (ver acima).
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        MustFonts.scaled(V8Fonts.Family.schibsted, size).weight(weight)
    }

    /// Ficha técnica: Martian Mono 500, wdth 100 (micro-rótulos em caixa alta, horários, códigos).
    static func mono(_ size: CGFloat) -> Font {
        mono(size, weight: .medium)
    }

    /// Martian Mono com peso (600 nos horários da Linha e nos valores das fichas).
    static func mono(_ size: CGFloat, weight: Font.Weight) -> Font {
        Font(V8Fonts.martian(V8Fonts.scaled(size), weight: V8Fonts.wght(weight)))
    }
}

/// Fábrica de `CTFont` com eixos variáveis. Função pura: o CoreText guarda as instâncias em cache.
enum V8Fonts {
    enum Family {
        static let bricolage = "Bricolage Grotesque"
        static let schibsted = "Schibsted Grotesk"
        static let martian = "Martian Mono"
    }

    /// Nomes PostScript da instância padrão de cada arquivo (é por eles que o descritor acha a fonte).
    enum PostScript {
        static let bricolage = "BricolageGrotesque-96ptExtraBold"
        static let schibsted = "SchibstedGrotesk-Regular"
        static let martian = "MartianMono-SemiExpandedRegular"
        static let all = [bricolage, schibsted, martian]
    }

    /// Tags OpenType dos eixos (4 bytes ASCII em big-endian).
    enum Axis {
        static let weight: UInt32 = 0x7767_6874      // 'wght'
        static let width: UInt32 = 0x7764_7468       // 'wdth'
        static let opticalSize: UInt32 = 0x6F70_737A // 'opsz'
    }

    static func bricolage(_ size: CGFloat, weight: CGFloat, width: CGFloat, opticalSize: CGFloat) -> CTFont {
        variable(PostScript.bricolage, size: size, axes: [
            Axis.weight: min(max(weight, 200), 800),
            Axis.width: min(max(width, 75), 100),
            Axis.opticalSize: min(max(opticalSize, 12), 96),
        ])
    }

    static func martian(_ size: CGFloat, weight: CGFloat, width: CGFloat = 100) -> CTFont {
        variable(PostScript.martian, size: size, axes: [
            Axis.weight: min(max(weight, 100), 800),
            Axis.width: min(max(width, 75), 112.5),
        ])
    }

    static func variable(_ postScriptName: String, size: CGFloat, axes: [UInt32: CGFloat]) -> CTFont {
        let variation = Dictionary(uniqueKeysWithValues: axes.map { (NSNumber(value: $0.key), NSNumber(value: Double($0.value))) })
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: postScriptName,
            kCTFontVariationAttribute: variation,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Valor do eixo `wght` pra um `Font.Weight` do SwiftUI.
    static func wght(_ weight: Font.Weight) -> CGFloat {
        switch weight {
        case .ultraLight: 200
        case .thin: 100
        case .light: 300
        case .regular: 400
        case .medium: 500
        case .semibold: 600
        case .bold: 700
        case .heavy: 800
        case .black: 800
        default: 400
        }
    }

    /// Tamanho no Dynamic Type de agora (limite `.xxxLarge`) pra fontes `CTFont`, que o SwiftUI não escala.
    /// Até 30 pt segue o estilo de texto mais perto (como `MustFonts.scaled`); acima, fixo.
    static func scaled(_ size: CGFloat) -> CGFloat {
        guard let style = MustFonts.textStyle(for: size) else { return size }
        let traits = UITraitCollection(preferredContentSizeCategory: contentSize)
        return UIFontMetrics(forTextStyle: style.uiKit).scaledValue(for: size, compatibleWith: traits)
    }

    /// Categoria de texto do sistema, com o teto do app (`DynamicTypeSize.mustCap` = XXXL).
    private static var contentSize: UIContentSizeCategory {
        let current = UITraitCollection.current.preferredContentSizeCategory
        if current == .unspecified { return .large }
        return current > .extraExtraExtraLarge ? .extraExtraExtraLarge : current
    }
}

extension Font.TextStyle {
    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}
