import SwiftUI

/// Bandeira do país da viagem: círculo de 22 pt, desenhado em vetor (sem emoji, sem rede).
/// Contorno branco de 1,5 pt. Japão: disco vermelho em branco. Brasil: versão simplificada (losango amarelo, círculo azul
/// com faixa branca). Itália: tricolor vertical verde / branco / vermelho. País fora da tabela: nada.
struct TripFlag: View {
    var country: String
    var size: CGFloat = 22

    init(country: String, size: CGFloat = 22) {
        self.country = country.uppercased()
        self.size = size
    }

    init(_ theme: TripTheme, size: CGFloat = 22) {
        self.init(country: theme.country, size: size)
    }

    /// Países com bandeira desenhada. Os outros não mostram nada (o `neutral` não tem país).
    static let countries: Set<String> = ["JP", "BR", "IT"]

    static func drawsFlag(for country: String) -> Bool {
        countries.contains(country.uppercased())
    }

    static func label(for country: String) -> String {
        switch country.uppercased() {
        case "JP": "Bandeira do Japão"
        case "BR": "Bandeira do Brasil"
        case "IT": "Bandeira da Itália"
        default: ""
        }
    }

    var body: some View {
        if Self.drawsFlag(for: country) {
            Canvas { context, canvas in
                let scale = canvas.width / 22
                switch country {
                case "JP": Self.drawJapan(&context, scale: scale)
                case "BR": Self.drawBrazil(&context, scale: scale)
                default: Self.drawItaly(&context, scale: scale)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
            .accessibilityLabel(Self.label(for: country))
        }
    }

    /// Disco vermelho (#BC002D, o da bandeira) de raio 5,2 em 22, sobre o branco do fundo.
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

    /// Três faixas verticais iguais: verde #008C45, branco, vermelho #CD212A.
    private static func drawItaly(_ context: inout GraphicsContext, scale: CGFloat) {
        let third = 22 * scale / 3
        let height = 22 * scale
        context.fill(Path(CGRect(x: 0, y: 0, width: third, height: height)), with: .color(Color(hex: 0x008C45)))
        context.fill(Path(CGRect(x: third, y: 0, width: third, height: height)), with: .color(.white))
        context.fill(Path(CGRect(x: 2 * third, y: 0, width: 22 * scale - 2 * third, height: height)),
                     with: .color(Color(hex: 0xCD212A)))
    }
}
