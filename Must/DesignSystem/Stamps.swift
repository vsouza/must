import SwiftUI

/// Cores dos selos (prompt 20): ponto único. Sobre papel a tinta é a do país (`stampInk`); sobre foto o selo
/// é branco com fundo `stampInk` a 55% (card do dia) ou 50% (cartões de bairro). Sem tema (`neutral`), a tinta
/// é a tinta do app, como antes.
enum StampPalette {
    /// Selo sobre foto escurecida: anel e texto.
    static let onPhoto = Color.white

    /// Tinta do selo sobre papel.
    static func ink(_ theme: TripTheme) -> Color { theme.stampInkColor }

    /// Fundo do selo sobre foto: a tinta do país na opacidade pedida.
    static func photoFill(_ theme: TripTheme, opacity: Double) -> Color {
        theme.stampInkColor.opacity(opacity)
    }
}

/// Selo de estação/bairro (eki stamp, D.18): círculo de borda dupla com linha tracejada por dentro, kanji
/// (ou sigla no BH) e uma linha pequena. Rotação leve (−6° a −10°). Ver `.stamp` em `design/screens/must-light.css`.
///
/// `surface`: `.photo` (branco sobre foto, com fundo do país se `filled`) ou `.paper` (tinta do país).
struct StationStamp: View {
    enum Surface: Sendable {
        case photo
        case paper
    }

    var text: String
    var sub: String?
    var size: CGFloat = 74
    var surface: Surface = .photo
    /// Sobre foto: `true` põe o fundo do país (`fillOpacity`); `false` deixa o selo sem fundo.
    var filled: Bool = true
    var fillOpacity: Double = 0.55
    var rotation: Double = -8
    /// Cor do anel quando a coleção pede a borda do país (Viagem: `trip`). `nil` = a tinta do selo.
    var border: Color?

    @Environment(\.tripTheme) private var theme

    init(_ text: String, sub: String? = nil, size: CGFloat = 74, surface: Surface = .photo, filled: Bool = true,
         fillOpacity: Double = 0.55, rotation: Double = -8, border: Color? = nil) {
        self.text = text
        self.sub = sub
        self.size = size
        self.surface = surface
        self.filled = filled
        self.fillOpacity = fillOpacity
        self.rotation = rotation
        self.border = border
    }

    /// Kanji (Zen Kaku Gothic New) quando o texto não é sigla ASCII (BH: SAV, LOU…).
    static func usesKanji(_ text: String) -> Bool {
        !text.unicodeScalars.allSatisfy { $0.isASCII }
    }

    private var ring: Color { border ?? (surface == .photo ? StampPalette.onPhoto : StampPalette.ink(theme)) }

    private var fill: Color? {
        guard surface == .photo, filled else { return nil }
        return StampPalette.photoFill(theme, opacity: fillOpacity)
    }

    var body: some View {
        let kanji = Self.usesKanji(text)
        ZStack {
            if let fill { Circle().fill(fill) }
            Circle().strokeBorder(ring, lineWidth: max(1.5, size * 0.034))
            Circle()
                .inset(by: size * 0.054)
                .strokeBorder(ring.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            VStack(spacing: size * 0.03) {
                Text(text)
                    .font(kanji ? .must.kanji(size * 0.3) : .must.archivo(size * 0.23, .heavy))
                    .tracking(kanji ? 0 : size * 0.008)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let sub {
                    Text(sub)
                        .font(.must.archivo(max(7, size * 0.11), .bold))
                        .tracking(size * 0.02)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(ring)
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sub.map { "\(text), \($0)" } ?? text)
    }
}

/// Chip de linha de transporte (D.19): bolinha com o código (JY, JC, H, BUS…) na cor oficial e o nome.
/// Ver `.line-chip` em `design/screens/must-light.css`.
struct LineChip: View {
    var code: String
    var name: String
    var color: UInt32

    init(code: String, name: String, color: UInt32) {
        self.code = code
        self.name = name
        self.color = color
    }

    init(_ line: LineRef) {
        self.init(code: line.code, name: line.name, color: line.rgb)
    }

    /// Texto escuro sobre cor clara (linha H, cinza), branco sobre o resto.
    static func codeColor(for rgb: UInt32) -> Color {
        let r = Double((rgb >> 16) & 0xFF) / 255, g = Double((rgb >> 8) & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.62 ? Color.must.ink : .white
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(code)
                .font(.must.mono(9, .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Self.codeColor(for: color))
                .frame(width: code.count > 2 ? 26 : 20, height: 20)
                .background(Circle().fill(Color(hex: color)))
            Text(name)
                .font(.must.archivo(12, .semibold))
                .foregroundStyle(Color.must.ink)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white))
        .overlay(Capsule().strokeBorder(Color.must.line))
        .accessibilityElement(children: .combine)
    }
}
