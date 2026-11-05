import SwiftUI

// Fotos de bairro do v7 (cards da Início antiga). A capa v8 não usa; ficam até a fase 3 conferir que ninguém mais usa.

/// Foto do bairro com a escurecida de baixo pra cima (cards grandes da Início). Sem foto: a cor da categoria.
struct HeroBackdrop: View {
    var photo: CCPhoto?
    var fallback: MustColor

    private var vivid: Bool { PhotoStyle.current == .vivid }

    var body: some View {
        ZStack {
            AreaPhotoView(photo: photo, fallback: fallback, motion: true)
            if vivid {
                // Foto viva: escurece só onde tem texto (nome do bairro no topo, "agora" e botões embaixo).
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: 0x15171C).opacity(0.5), location: 0),
                        .init(color: Color(hex: 0x15171C).opacity(0.08), location: 0.3),
                        .init(color: Color(hex: 0x15171C).opacity(0.15), location: 0.48),
                        .init(color: Color(hex: 0x15171C).opacity(0.86), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                LinearGradient(
                    stops: [
                        // Topo também escuro: o nome do bairro fica legível em foto clara.
                        .init(color: Color(hex: 0x15171C).opacity(0.62), location: 0),
                        .init(color: Color(hex: 0x15171C).opacity(0.45), location: 0.35),
                        .init(color: Color(hex: 0x15171C).opacity(0.6), location: 0.55),
                        .init(color: Color(hex: 0x15171C).opacity(0.96), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .background(Color(hex: 0x15171C))
    }
}

/// Foto de um bairro ou lugar: cache primeiro (`PhotoLoader`), sem spinner. Sem foto, o gradiente da cor.
struct AreaPhotoView: View {
    var photo: CCPhoto?
    var fallback: MustColor
    /// Zoom lento (hero grande da Início).
    var motion = false
    @State private var image: UIImage?

    private var url: URL? { photo.flatMap { URL(string: $0.largeURL ?? $0.url) } }

    var body: some View {
        fallback.gradient
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .saturation(PhotoStyle.current == .vivid ? 1.08 : 0.8)
                        .modifier(MaybeKenBurns(on: motion))
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; return }
                image = await PhotoLoader.load(url)
            }
    }
}

