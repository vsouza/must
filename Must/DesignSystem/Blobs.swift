import SwiftUI

/// Uma elipse com gradiente, em coordenadas da tela de referência (390 × 844 pt).
struct Blob: Sendable, Hashable {
    enum Fill: Sendable, Hashable {
        case green, blue, sky, white

        /// v8: sem formas 3D — o preenchimento é transparente (as telas antigas que ainda desenham elipses somem com elas).
        var gradient: LinearGradient {
            LinearGradient(colors: [.clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var cx: CGFloat
    var cy: CGFloat
    var rx: CGFloat
    var ry: CGFloat
    var rotation: Double
    var fill: Fill
    var opacity: Double = 0.9
    var blur: CGFloat = 0
}

/// Fundo de formas 3D da v5 (elipses com gradiente). Desligado na v8 (ver `body`); fica pra compilar as telas antigas.
struct BlobBackground: View {
    enum Style: Sendable {
        case home, musts, hoje, lugar, assistente
        case custom([Blob])

        var blobs: [Blob] {
            switch self {
            case .home: [
                Blob(cx: 330, cy: 560, rx: 90, ry: 70, rotation: -18, fill: .green),
                Blob(cx: 300, cy: 700, rx: 110, ry: 80, rotation: 20, fill: .blue),
                Blob(cx: 110, cy: 790, rx: 120, ry: 60, rotation: -10, fill: .sky),
                Blob(cx: 350, cy: 640, rx: 40, ry: 26, rotation: 0, fill: .white, opacity: 0.35, blur: 6),
            ]
            case .musts: [
                Blob(cx: 360, cy: 130, rx: 80, ry: 55, rotation: -20, fill: .blue, opacity: 0.85),
                Blob(cx: 20, cy: 760, rx: 90, ry: 55, rotation: 15, fill: .green, opacity: 0.8),
            ]
            case .hoje: [
                Blob(cx: 392, cy: 245, rx: 62, ry: 56, rotation: -15, fill: .blue, opacity: 0.85),
                Blob(cx: 8, cy: 330, rx: 72, ry: 54, rotation: 12, fill: .green, opacity: 0.8),
            ]
            case .lugar: [
                Blob(cx: 320, cy: 150, rx: 140, ry: 95, rotation: -12, fill: .blue, opacity: 0.9),
                Blob(cx: 80, cy: 250, rx: 120, ry: 75, rotation: 8, fill: .green, opacity: 0.85),
            ]
            case .assistente: [
                Blob(cx: 170, cy: 300, rx: 110, ry: 90, rotation: -20, fill: .blue),
                Blob(cx: 230, cy: 340, rx: 100, ry: 80, rotation: 25, fill: .green),
            ]
            case .custom(let blobs): blobs
            }
        }
    }

    var style: Style

    /// v8: a única textura são os arcos (`Rings`). O fundo de blobs da v5 não desenha nada.
    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#Preview {
    BlobBackground(style: .home)
}
