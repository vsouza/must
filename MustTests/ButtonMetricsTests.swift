import Foundation
import Testing
@testable import Must

@Suite("ButtonMetrics (prompt 27 §3)")
struct ButtonMetricsTests {
    @Test("uma linha nunca desce de 14 pt e a altura é ≥ 3,1 × fonte")
    func singleLine() {
        for width in stride(from: 120.0, through: 420.0, by: 10.0) {
            for text in ["Só guardar", "Mandar cartaz", "Ir agora · 9 min", "Encaixar hoje"] {
                for scale in [1.0, 1.12, 1.3] {
                    let s = ButtonMetrics.size(forWidth: width, text: text, dynamicType: scale)
                    #expect(s.font >= 14)
                    #expect(s.height >= 3.1 * s.font * scale - 0.01)
                    if s.lines == 1 { #expect([16, 15, 14].contains(s.font)) } else { #expect(s.font == 15) }
                }
            }
        }
    }

    @Test("degraus 16 → 15 → 14 → 2 linhas")
    func steps() {
        #expect(ButtonMetrics.size(forWidth: 300, text: "Só guardar").font == 16)
        #expect(ButtonMetrics.size(forWidth: 300, text: "Mandar cartaz pelo WhatsApp").lines == 1)
        let narrow = ButtonMetrics.size(forWidth: 140, text: "Mandar cartaz pelo WhatsApp")
        #expect(narrow.lines >= 2)
        #expect(narrow.height >= 56)
    }

    @Test("pílula ≥ 2,6 × fonte; botão 3,1 ×; redondo")
    func ratios() {
        #expect(ButtonMetrics.pillHeight >= 2.6 * 13)
        #expect(ButtonMetrics.smallPillHeight >= 2.6 * 12)
        #expect(ButtonMetrics.compactHeight >= 3.1 * 14)
        #expect(ButtonMetrics.buttonHeight >= 3.1 * 16)
        #expect(ButtonMetrics.horizontalPadding(height: 56) == 20)
        #expect(ButtonMetrics.horizontalPadding(height: 44) == 15 || ButtonMetrics.horizontalPadding(height: 44) == 16)
        #expect(ButtonMetrics.roundGlyph(diameter: 44) == 18)
        #expect(ButtonMetrics.roundGlyph(diameter: 36) == 16)
        #expect(ButtonMetrics.roundGlyph(diameter: 52) == 20)
        #expect(ButtonMetrics.fontSize(height: 56, kind: .button) == 16)
        #expect(ButtonMetrics.fontSize(height: 44, kind: .button) == 14)
    }
}
