import SwiftUI

/// Rótulo mono em caixa alta, maior que a ficha ("SAIA ÀS", "HOJE É", "BAIRRO DE HOJE").
struct MonoLabel: View {
    var text: String
    var size: CGFloat = 10
    var color: Color

    init(_ text: String, size: CGFloat = 10, color: Color) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(V8Font.mono(size))
            .tracking(size * 0.1)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Textos dos deslocamentos entre paradas (a linha em si é `V9LegRow`).
enum DayLegRow {
    static func text(_ leg: DayLeg) -> String {
        if !leg.detail.isEmpty { return leg.detail }
        return "\(modeLabel(leg.mode)) \(leg.minutes) min"
    }

    static func modeLabel(_ mode: DayLegMode) -> String {
        switch mode {
        case .walk: "a pé"
        case .train: "trem"
        case .metro: "metrô"
        case .bus: "ônibus"
        case .taxi: "táxi"
        }
    }
}
