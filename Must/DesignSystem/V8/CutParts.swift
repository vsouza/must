import SwiftUI

// Peças do corte que a limpeza da Fase 2 tinha levado junto (rodada 33: o corte volta nas telas principais).

/// Régua de 2 pt entre as linhas do índice.
struct IndexRule: View {
    var color: Color = V8.ink
    var body: some View { Rectangle().fill(color).frame(height: 2).accessibilityHidden(true) }
}

/// Uma faixa do índice que não é parada (em cartaz, aviso, texto): bloco inteiro, régua embaixo.
struct DayStrip<Content: View>: View {
    enum Tone { case paper, ink, orange }
    var tone: Tone = .paper
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone == .ink ? V8.ink : tone == .orange ? V8.orange : Color.clear)
            .overlay(alignment: .bottom) { IndexRule() }
    }
}

/// Ficha técnica de duas linhas (um canto da tela).
struct SpecStack: View {
    var lines: [String]
    var color: Color
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                SpecLabel(line, color: color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Respiro no fim das telas roláveis (a barra nativa e a faixa "agora" já entram na safe area).
struct V8BarSpacer: View {
    var body: some View { Color.clear.frame(height: 24) }
}
