import Foundation
import SwiftUI
import UIKit

/// Marca o texto colado com o que foi reconhecido (ColarTexto.png, prompt 18 · E.22): lugar por categoria em cor
/// de fundo, área sublinhada tracejada, link em bloco preto, dica sublinhada em âmbar. Puro: testável sem tela.
enum ColarTextoHighlight {
    enum Style: Equatable {
        case eat, see, drink, other, area, link, tip
    }

    struct Span: Equatable {
        var range: Range<String.Index>
        var style: Style
    }

    /// Intervalos do texto, sem sobreposição. Prioridade: link, dica, lugar, área (o que vem antes ganha).
    static func spans(in text: String, links: [Range<String.Index>], tips: [String],
                      places: [(name: String, style: Style)], areas: [String]) -> [Span] {
        var out: [Span] = []
        func add(_ range: Range<String.Index>, _ style: Style) {
            guard !range.isEmpty, !out.contains(where: { $0.range.overlaps(range) }) else { return }
            out.append(Span(range: range, style: style))
        }
        func occurrences(of needle: String) -> [Range<String.Index>] {
            guard !needle.isEmpty else { return [] }
            var found: [Range<String.Index>] = []
            var search = text.startIndex..<text.endIndex
            while let r = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: search) {
                found.append(r)
                search = r.upperBound..<text.endIndex
            }
            return found
        }
        for range in links { add(range, .link) }
        for tip in tips {
            // Dica com cláusulas unidas ("..., porque ...") não aparece inteira: marca o começo.
            if let r = occurrences(of: tip).first ?? occurrences(of: String(tip.prefix(40))).first { add(r, .tip) }
        }
        for place in places {
            for r in occurrences(of: place.name) { add(r, place.style) }
        }
        for area in areas {
            for r in occurrences(of: area) { add(r, .area) }
        }
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Texto com os trechos marcados (cores do design: comer verde, ver violeta, beber azul, link preto, dica âmbar).
    static func attributed(_ text: String, spans: [Span]) -> AttributedString {
        var out = AttributedString()
        var cursor = text.startIndex
        for span in spans where span.range.lowerBound >= cursor {
            if cursor < span.range.lowerBound {
                out += AttributedString(String(text[cursor..<span.range.lowerBound]))
            }
            var piece = AttributedString(String(text[span.range]))
            style(&piece, span.style)
            out += piece
            cursor = span.range.upperBound
        }
        if cursor < text.endIndex {
            out += AttributedString(String(text[cursor...]))
        }
        return out
    }

    private static func style(_ piece: inout AttributedString, _ style: Style) {
        switch style {
        case .eat:
            piece.backgroundColor = Color(hex: 0xB9F5CF)
            piece.foregroundColor = Color(hex: 0x0B2A18)
            piece.font = .must.archivo(15, .semibold)
        case .see:
            piece.backgroundColor = Color(hex: 0xDCCFFF)
            piece.foregroundColor = Color(hex: 0x2E1065)
            piece.font = .must.archivo(15, .semibold)
        case .drink:
            piece.backgroundColor = Color(hex: 0x9FD6FF)
            piece.foregroundColor = Color(hex: 0x0F3B8C)
            piece.font = .must.archivo(15, .semibold)
        case .other:
            piece.backgroundColor = Color(hex: 0xE9EBEF)
            piece.foregroundColor = Color(hex: 0x121316)
            piece.font = .must.archivo(15, .semibold)
        case .area:
            piece.foregroundColor = Color(hex: 0x121316)
            piece.font = .must.archivo(15, .semibold)
            piece.uiKit.underlineStyle = [.single, .patternDash]
            piece.uiKit.underlineColor = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        case .link:
            piece.backgroundColor = Color(hex: 0x121316)
            piece.foregroundColor = .white
            piece.font = .must.mono(13)
        case .tip:
            piece.uiKit.underlineStyle = .single
            piece.uiKit.underlineColor = UIColor(red: 1, green: 0.69, blue: 0.125, alpha: 1)
        }
    }
}
