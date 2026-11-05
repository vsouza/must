import CoreText
import SwiftUI
import Testing
import UIKit
@testable import Must

/// Tipografia v8 (prompt 23 §1): as três famílias estão no bundle, as antigas saíram, e o eixo `wdth` da Bricolage
/// muda a largura de verdade (display wdth 92, numeral wdth 78).
@MainActor
struct V8TypeTests {
    private func width(_ font: CTFont, _ text: String = "Hoje é Shinjuku 14:35") -> CGFloat {
        let string = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(string)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func axisValue(_ font: CTFont, _ tag: UInt32) -> Double? {
        let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
        return variation?[NSNumber(value: tag)]?.doubleValue
    }

    @Test func asTresFamiliasEstaoRegistradas() {
        #expect(MustFontFamily.missing.isEmpty, "faltando: \(MustFontFamily.missing)")
        for name in V8Fonts.PostScript.all {
            #expect(UIFont(name: name, size: 12) != nil, "\(name) não registrada")
        }
    }

    @Test func fontesAntigasSairamDoBundle() {
        for old in ["Archivo-SemiBold", "GeistMono-Regular", "InstrumentSerif-Italic", "ZenKakuGothicNew-Bold"] {
            #expect(UIFont(name: old, size: 12) == nil, "\(old) ainda está no bundle")
        }
        for file in ["Archivo", "GeistMono", "InstrumentSerif-Italic", "ZenKakuGothicNew-Bold"] {
            #expect(Bundle.main.url(forResource: file, withExtension: "ttf") == nil)
        }
    }

    @Test func eixoDeLarguraDaBricolageEstreitaOTexto() {
        let wide = V8Fonts.bricolage(40, weight: 700, width: 100, opticalSize: 40)
        let display = V8Fonts.bricolage(40, weight: 700, width: 92, opticalSize: 40)
        let numeral = V8Fonts.bricolage(40, weight: 700, width: 78, opticalSize: 40)
        #expect(width(display) < width(wide) * 0.97, "wdth 92 não estreitou")
        #expect(width(numeral) < width(display) * 0.92, "wdth 78 não estreitou")
        #expect(axisValue(display, V8Fonts.Axis.width).map { abs($0 - 92) < 0.5 } == true)
        #expect(axisValue(numeral, V8Fonts.Axis.width).map { abs($0 - 78) < 0.5 } == true)
    }

    @Test func pesoDaBricolageVemDoEixo() {
        let bold = V8Fonts.bricolage(40, weight: 700, width: 92, opticalSize: 40)
        let heavy = V8Fonts.bricolage(40, weight: 800, width: 92, opticalSize: 40)
        #expect(axisValue(bold, V8Fonts.Axis.weight).map { abs($0 - 700) < 0.5 } == true)
        // 800 é o padrão do arquivo: o CoreText omite o eixo quando ele está no valor padrão.
        #expect(abs((axisValue(heavy, V8Fonts.Axis.weight) ?? 800) - 800) < 0.5)
        #expect(width(heavy) > width(bold))
        #expect(CTFontCopyPostScriptName(bold) as String == V8Fonts.PostScript.bricolage || CTFontCopyFamilyName(bold) as String == "Bricolage Grotesque")
    }

    @Test func martianMonoSaiNaLarguraNormalNaoNaExpandida() {
        let normal = V8Fonts.martian(13, weight: 500)
        let expanded = V8Fonts.martian(13, weight: 500, width: 112.5)
        #expect(width(normal) < width(expanded) * 0.95)
        #expect(axisValue(normal, V8Fonts.Axis.width).map { abs($0 - 100) < 0.5 } == true)
        #expect((CTFontCopyFamilyName(normal) as String).hasPrefix("Martian Mono"))
    }

    @Test func numeralTemTamanhoFixo() {
        // Decorativo: não cresce com o Dynamic Type (o valor aparece também em texto normal na tela).
        #expect(V8Fonts.scaled(220) == 220)
        #expect(V8Fonts.scaled(54) == 54)
    }

    @Test func pesoDoSwiftUIViraEixoWght() {
        #expect(V8Fonts.wght(.regular) == 400)
        #expect(V8Fonts.wght(.medium) == 500)
        #expect(V8Fonts.wght(.semibold) == 600)
        #expect(V8Fonts.wght(.bold) == 700)
        #expect(V8Fonts.wght(.heavy) == 800)
    }
}
