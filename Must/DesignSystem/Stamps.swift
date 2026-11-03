import SwiftUI

/// Cores dos selos e linhas. Ponto único: o prompt 20 (tema da viagem) troca a cor do selo por país aqui,
/// sem mexer nas telas. Por enquanto o selo é branco (sobre foto) ou tinta (sobre papel).
enum StampPalette {
    /// Selo sobre foto escurecida.
    static let onPhoto = Color.white
    /// Preenchimento atrás do texto do selo sobre foto.
    static let onPhotoFill = Color.black.opacity(0.28)
    /// Selo sobre papel (fundo claro).
    static let onPaper = Color.must.ink
}

/// Selo de estação/bairro (eki stamp, D.18): círculo de borda dupla com linha tracejada por dentro, kanji
/// (ou sigla no BH) e uma linha pequena. Rotação leve (−6° a −10°). Ver `.stamp` em `design/screens/must-light.css`.
struct StationStamp: View {
    var text: String
    var sub: String?
    var size: CGFloat = 74
    var ring: Color = StampPalette.onPhoto
    var fill: Color? = StampPalette.onPhotoFill
    var rotation: Double = -8

    init(_ text: String, sub: String? = nil, size: CGFloat = 74, ring: Color = StampPalette.onPhoto,
         fill: Color? = StampPalette.onPhotoFill, rotation: Double = -8) {
        self.text = text
        self.sub = sub
        self.size = size
        self.ring = ring
        self.fill = fill
        self.rotation = rotation
    }

    /// Kanji (Zen Kaku Gothic New) quando o texto não é sigla ASCII (BH: SAV, LOU…).
    static func usesKanji(_ text: String) -> Bool {
        !text.unicodeScalars.allSatisfy { $0.isASCII }
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
