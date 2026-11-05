import SwiftUI

// Os ícones de design/icons/ estão no Asset Catalog como image sets SVG
// (template + vetor preservado), não como custom SF Symbols: os SVGs são de
// traço e o template de símbolo exige contornos expandidos. Regenerar com
// `python3 scripts/gen-icons.py`.

extension Image {
    /// Ícone do set do Must, como template (pega `foregroundStyle`).
    /// `feito` não tem asset (é um kanji) — use `MustIconView` pra ele.
    init(mustIcon icon: MustIcon) {
        if icon.isTextGlyph {
            self.init(systemName: icon.fallbackSymbol)
        } else {
            self.init(icon.rawValue)
        }
    }
}

/// Ícone dimensionado (padrão 24pt, como o viewBox). O `feito` (era 済 na v5) é um ✓ em vetor: nada de japonês na interface.
struct MustIconView: View {
    var icon: MustIcon
    var size: CGFloat = 24

    init(_ icon: MustIcon, size: CGFloat = 24) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Group {
            if icon.isTextGlyph {
                CheckGlyph()
                    .stroke(style: StrokeStyle(lineWidth: max(1.2, size * 1.8 / 24), lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)
            } else {
                Image(mustIcon: icon)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)
            }
        }
        .accessibilityLabel(icon.label)
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
        ForEach(MustIcon.allCases) { MustIconView($0) }
    }
    .padding()
}
