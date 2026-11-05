import SwiftUI

/// Cores dos selos (v8): o **anel** é a cor do lugar (`TripTheme.cover`; sem viagem, tinta). O miolo é papel com tinta
/// por cima — sobre foto também (disco de papel sólido, nada de foto lavada atrás de texto).
enum StampPalette {
    /// Texto do selo sobre a foto quando o selo não tem fundo (`filled: false`).
    static let onPhoto = Color.white

    /// Anel do selo: a cor do lugar.
    static func ink(_ theme: TripTheme) -> Color { theme.stampInkColor }

    /// Fundo do selo sobre foto: papel sólido (a opacidade da v5 fica na assinatura, mas não lava mais a foto).
    static func photoFill(_ theme: TripTheme, opacity: Double) -> Color { V8.paper }
}

/// Selo de estação/bairro (eki stamp): anel duplo na **cor do lugar** e, no meio, a **sigla latina** (código JR quando
/// existe — Shinjuku SJK, Shibuya SBY — senão 3 letras do nome; BH: SAV) com uma linha pequena embaixo (o nome do bairro,
/// ou "BH · 1897"). Nunca kanji (CLAUDE.md › "Selos sem japonês"). Selo pequeno: só a sigla. Rotação leve.
///
/// `surface`: `.photo` (disco de papel sobre a foto; `filled: false` deixa sem disco, texto branco) ou `.paper`.
struct StationStamp: View {
    enum Surface: Sendable {
        case photo
        case paper
    }

    var text: String
    var sub: String?
    var size: CGFloat = 74
    var surface: Surface = .photo
    /// Sobre foto: `true` põe o disco de papel; `false` deixa o selo sem fundo (texto branco).
    var filled: Bool = true
    /// v5 (opacidade do fundo do país). Ignorado na v8: o disco é sólido.
    var fillOpacity: Double = 0.55
    var rotation: Double = -8
    /// v5 (borda do país na coleção). Ignorado na v8: o anel é sempre a cor do lugar.
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

    /// Texto com escrita japonesa/chinesa/coreana (kanji, kana, hangul, largura cheia). Selo nunca mostra isso.
    static func usesKanji(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x9FFF, 0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF, 0x20000...0x2FFFF: true
            default: false
            }
        }
    }

    /// Sigla que o selo mostra: o texto, se for latino; senão a sigla do `sub` (3 letras); senão "MUST".
    static func code(_ text: String, sub: String?) -> String {
        if !text.isEmpty, !usesKanji(text) { return text }
        if let sub, !usesKanji(sub), let derived = AreaCode.derive(sub) { return derived }
        return "MUST"
    }

    /// Selo pequeno (< 50 pt) mostra só a sigla.
    private var showsSub: Bool { size >= 50 && sub.map { !$0.isEmpty && !Self.usesKanji($0) } == true }

    private var ring: Color { StampPalette.ink(theme) }

    private var fill: Color? {
        switch surface {
        case .paper: nil
        case .photo: filled ? StampPalette.photoFill(theme, opacity: fillOpacity) : nil
        }
    }

    private var label: Color {
        surface == .photo && !filled ? StampPalette.onPhoto : V8.ink
    }

    var body: some View {
        let code = Self.code(text, sub: sub)
        ZStack {
            if let fill { Circle().fill(fill) }
            Circle().strokeBorder(ring, lineWidth: max(1.5, size * 0.04))
            Circle()
                .inset(by: size * 0.075)
                .strokeBorder(ring.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            VStack(spacing: size * 0.02) {
                Text(code)
                    .font(V8Font.numeral(size * (showsSub ? 0.3 : 0.36)))
                    .tracking(size * 0.004)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if showsSub, let sub {
                    Text(sub.uppercased())
                        .font(Font(V8Fonts.martian(max(6, size * 0.085), weight: 600)))
                        .tracking(size * 0.008)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(label)
            .padding(size * 0.17)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(rotation))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(showsSub ? "\(code), \(sub ?? "")" : code)
    }
}

/// Sigla de bairro (3 letras latinas). A tabela curada (`stampCode` em `Must/Data/areas/*.json`) manda; isto é o
/// fallback: primeira letra + as próximas consoantes (Ginza → GNZ, Asakusa → ASK), em caixa alta, sem acento.
enum AreaCode {
    static func derive(_ name: String) -> String? {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        let letters = folded.unicodeScalars.filter { ("a"..."z").contains(Character($0)) }.map(Character.init)
        guard let first = letters.first else { return nil }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var code = [first]
        for c in letters.dropFirst() where !vowels.contains(c) && c != code.last {
            code.append(c)
            if code.count == 3 { break }
        }
        if code.count < 3 {
            for c in letters.dropFirst() where code.count < 3 && !code.contains(c) { code.append(c) }
        }
        return String(code.prefix(3)).uppercased()
    }
}

/// Chip de linha de transporte (v8): **badge preto com a sigla** (JY, JC, H, BUS…) e o nome. Sem cor oficial de linha
/// (a identidade v8 tem três cores); `color` fica na assinatura e é ignorado.
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

    /// Texto da sigla: branco sobre o badge preto, qualquer que seja a linha.
    static func codeColor(for rgb: UInt32) -> Color { V8.white }

    var body: some View {
        HStack(spacing: 6) {
            LineBadge(code)
            Text(name)
                .font(V8Font.text(12, weight: .semibold))
                .foregroundStyle(V8.ink)
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(V8.white))
        .overlay(Capsule().strokeBorder(V8.rule))
        .accessibilityElement(children: .combine)
    }
}

/// Badge da linha: sigla em Martian Mono branco sobre tinta, cantos de 5 pt.
struct LineBadge: View {
    var code: String

    init(_ code: String) { self.code = code }

    var body: some View {
        Text(code.uppercased())
            .font(Font(V8Fonts.martian(9, weight: 700)))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(V8.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(V8.ink))
    }
}
