import SwiftUI

/// Bandeira do país da viagem (prompt 20 · item 4): círculo de 22 pt, desenhado em vetor (sem emoji, sem rede).
/// Contorno branco de 1,5 pt e sombra leve. Japão: disco vermelho em branco. Brasil: versão simplificada
/// (losango amarelo, círculo azul com faixa branca). País fora da tabela: nada.
struct TripFlag: View {
    var country: String
    var size: CGFloat = 22

    init(country: String, size: CGFloat = 22) {
        self.country = country
        self.size = size
    }

    init(_ theme: TripTheme, size: CGFloat = 22) {
        self.init(country: theme.country, size: size)
    }

    /// Países com bandeira desenhada. Os outros não mostram nada (o `neutral` não tem país).
    static func drawsFlag(for country: String) -> Bool {
        country == "JP" || country == "BR"
    }

    var body: some View {
        if Self.drawsFlag(for: country) {
            Canvas { context, canvas in
                let scale = canvas.width / 22
                if country == "JP" {
                    Self.drawJapan(&context, scale: scale)
                } else {
                    Self.drawBrazil(&context, scale: scale)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .shadow(color: Color.must.ink.opacity(0.18), radius: 3, x: 0, y: 1)
            .accessibilityLabel(country == "JP" ? "Bandeira do Japão" : "Bandeira do Brasil")
        }
    }

    /// Disco vermelho (#BC002D) de raio 5,2 em 22, sobre o branco do fundo.
    private static func drawJapan(_ context: inout GraphicsContext, scale: CGFloat) {
        context.fill(Path(CGRect(x: 0, y: 0, width: 22 * scale, height: 22 * scale)), with: .color(.white))
        let r = 5.2 * scale
        let center = CGPoint(x: 11 * scale, y: 11 * scale)
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        context.fill(disc, with: .color(Color(hex: 0xBC002D)))
    }

    /// Verde (#009C3B), losango amarelo (#FFDF00), círculo azul (#002776) e a faixa branca.
    private static func drawBrazil(_ context: inout GraphicsContext, scale: CGFloat) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale, y: y * scale) }
        context.fill(Path(CGRect(x: 0, y: 0, width: 22 * scale, height: 22 * scale)), with: .color(Color(hex: 0x009C3B)))

        var diamond = Path()
        diamond.move(to: p(11, 3.5))
        diamond.addLine(to: p(19.5, 11))
        diamond.addLine(to: p(11, 18.5))
        diamond.addLine(to: p(2.5, 11))
        diamond.closeSubpath()
        context.fill(diamond, with: .color(Color(hex: 0xFFDF00)))

        let r = 4.4 * scale
        let center = p(11, 11)
        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                     with: .color(Color(hex: 0x002776)))

        var band = Path()
        band.move(to: p(6.8, 10.2))
        band.addCurve(to: p(15.2, 11.6), control1: p(9.5, 9.4), control2: p(12.8, 9.8))
        context.stroke(band, with: .color(.white), style: StrokeStyle(lineWidth: 0.9 * scale, lineCap: .round))
    }
}
