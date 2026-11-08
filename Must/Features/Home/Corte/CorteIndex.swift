import CoreGraphics
import Foundation

// O papel da capa do corte (prompt 30 §2) e as alturas do bloco: pura, sem SwiftUI.

/// Uma linha do índice da capa, vinda do ranker (`Suggestion`): distância ou hora grande, nome e o motivo.
struct CorteIndexLine: Identifiable, Hashable, Sendable {
    /// Cor da linha inteira: laranja = Must seu, tinta = o mundo lá fora (fora do board, evento), papel = o plano e o resto.
    enum Tone: Sendable { case orange, ink, paper }

    var id: String
    var tone: Tone
    var big: String
    var unit: String
    var title: String
    var reason: String
    var card: Suggestion

    static func == (a: CorteIndexLine, b: CorteIndexLine) -> Bool { a.id == b.id && a.big == b.big && a.reason == b.reason }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    init(_ card: Suggestion) {
        self.card = card
        id = card.id
        title = card.title
        switch card.kind {
        case .must, .closing: tone = .orange
        case .event, .indicated: tone = .ink
        case .plan, .light, .rain: tone = .paper
        }
        if let trailing = card.trailing {
            let parts = Self.parts(trailing)
            big = parts.value
            unit = parts.unit
        } else if card.kind == .plan, let time = Self.time(in: card.meta) {
            big = time
            unit = "agora"
        } else {
            big = "·"
            unit = card.kind == .rain ? "chuva" : "agora"
        }
        let first = card.reasons.first ?? ""
        reason = card.meta.isEmpty ? card.reasonLine : (first.isEmpty ? card.meta : "\(card.meta) · \(first)")
    }

    /// "240 m" → ("240", "metros"); "1,2 km" → ("1,2", "km").
    static func parts(_ text: String) -> (value: String, unit: String) {
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (text, "") }
        return (parts[0], parts[1] == "m" ? "metros" : parts[1])
    }

    /// "saia 19:30 · desde 18:10" → "19:30".
    static func time(in text: String) -> String? {
        guard let range = text.range(of: #"\d{1,2}[:h]\d{2}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

/// As alturas do corte (pt): o bloco da foto encolhe e a fenda laranja abre, conforme a régua desce.
enum CorteLayout {
    enum Stage: Equatable, Sendable { case rest, asking, result }

    static let askingBand: CGFloat = 118
    static let askingSlit: CGFloat = 124
    static let resultBand: CGFloat = 120

    /// `pull` = quanto a régua desceu (0…110), `rest` = altura do bloco com a capa em repouso.
    static func heights(stage: Stage, pull: CGFloat, rest: CGFloat) -> (band: CGFloat, slit: CGFloat) {
        switch stage {
        case .rest:
            let p = min(max(pull, 0), 110)
            return (rest - 0.4 * p, 1.4 * p)
        case .asking: return (askingBand, askingSlit)
        case .result: return (resultBand, 0)
        }
    }
}
