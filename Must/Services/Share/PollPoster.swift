import SwiftUI
import UIKit

/// Cartaz "A ou B?" (prompt 32): 1080×1920 (360×640 pt × 3), no corte. Foto de A em cima, régua preta grossa, foto de B embaixo;
/// cada metade tem a letra num bloco laranja, o nome, o bairro e o tempo até lá. Sem degradê, sem sombra, sem raio.
struct PollPoster: Hashable, Sendable {
    struct Side: Hashable, Sendable {
        var name: String
        var area: String
        /// "8 min" (a pé/transporte até lá) ou vazio.
        var minutes: String
        /// Foto já no disco (nunca baixa pro cartaz).
        var photoPath: String?
    }

    var a: Side
    var b: Side
    /// "Tóquio" · viagem.
    var city: String
    var coverRGB: UInt32
}

struct PollPosterView: View {
    var poster: PollPoster

    static let size = CGSize(width: 360, height: 640)
    private let rule: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            half(poster.a, tag: "A")
            Rectangle().fill(Color.black).frame(height: rule)
            half(poster.b, tag: "B")
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(hex: 0xF2F0EA))
        .clipped()
        .overlay(alignment: .trailing) {
            Text("OU")
                .font(Font(V8Fonts.bricolage(26, weight: 800, width: 78, opticalSize: 96)))
                .foregroundStyle(Color.black)
                .frame(width: 64, height: 64)
                .background(Color(hex: 0xF2F0EA))
                .overlay(Rectangle().stroke(Color.black, lineWidth: 4))
                .padding(.trailing, 14)
        }
        .environment(\.colorScheme, .light)
    }

    private func half(_ side: PollPoster.Side, tag: String) -> some View {
        let height = (Self.size.height - rule) / 2
        return ZStack(alignment: .bottomLeading) {
            photo(side).frame(width: Self.size.width, height: height).clipped()
            Rectangle().fill(Color(hex: poster.coverRGB).opacity(0.0))
            VStack(alignment: .leading, spacing: 6) {
                Text(side.name)
                    .font(Font(V8Fonts.bricolage(34, weight: 700, width: 92, opticalSize: 96)))
                    .tracking(-0.6)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black)
                Text([side.area, side.minutes].filter { !$0.isEmpty }.joined(separator: " · ").uppercased())
                    .font(Font(V8Fonts.martian(11, weight: 600)))
                    .tracking(1)
                    .lineLimit(1)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color(hex: 0xF2F0EA))
            }
            .padding(14)
        }
        .overlay(alignment: .topLeading) {
            Text(tag)
                .font(Font(V8Fonts.bricolage(44, weight: 800, width: 78, opticalSize: 96)))
                .foregroundStyle(Color.black)
                .frame(width: 64, height: 64)
                .background(Color(hex: 0xFF4A1C))
        }
        .frame(width: Self.size.width, height: height)
    }

    @ViewBuilder private func photo(_ side: PollPoster.Side) -> some View {
        if let path = side.photoPath, let image = UIImage(contentsOfFile: path) {
            // P&B contrastada: a foto vira textura, o nome é quem fala (o corte).
            Image(uiImage: image).resizable().scaledToFill().saturation(0).contrast(1.25)
        } else {
            ZStack {
                Color(hex: poster.coverRGB)
                Text(String(side.name.prefix(1)).uppercased())
                    .font(Font(V8Fonts.bricolage(220, weight: 800, width: 78, opticalSize: 96)))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
        }
    }
}

@MainActor
enum PollPosterRenderer {
    static let scale: CGFloat = 3

    static func png(_ poster: PollPoster) -> Data? {
        let renderer = ImageRenderer(content: PollPosterView(poster: poster))
        renderer.scale = scale
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(PollPosterView.size)
        return renderer.uiImage?.pngData()
    }

    static func url(_ poster: PollPoster) -> URL? {
        guard let data = png(poster) else { return nil }
        return DayPosterRenderer.write(data, name: "Must · \(poster.a.name) ou \(poster.b.name).png")
    }
}
