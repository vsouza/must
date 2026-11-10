import SwiftUI

// Sobras do V8 que telas vivas ainda usam: etiqueta (Em cartaz) e foto com placeholder de cor.

/// Etiqueta pequena em caixa (mono, caixa alta): "AGORA · PARADA 2", "FILA ~20 MIN", "RESERVA · HOJE".
struct V8Tag: View {
    enum Style { case orange, ink, glass, graphite, paper }

    var text: String
    var style: Style = .ink

    var body: some View {
        Text(text.uppercased())
            .font(V8Font.mono(11))
            .tracking(1.1)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background))
    }

    private var foreground: Color {
        switch style {
        case .orange: V8.ink
        case .ink: V8.white
        case .glass: V8.white
        case .graphite: V8.white
        case .paper: V8.mute
        }
    }

    private var background: Color {
        switch style {
        case .orange: V8.orange
        case .ink: V8.ink
        case .glass: V8.ink.opacity(0.45)
        case .graphite: V8.graphite
        case .paper: V8.ink.opacity(0.07)
        }
    }
}

/// Foto do disco (ou da URL que o resolvedor deu), em cor cheia, sem tinta por cima e sem zoom (v8). Enquanto não
/// carrega, ou sem foto, o placeholder de cor (grafite) — nunca spinner, nunca espera a rede.
struct V8Photo: View {
    var url: URL?
    var placeholder: Color = V8.graphite

    @State private var image: UIImage?

    var body: some View {
        placeholder
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                guard let url else { image = nil; return }
                image = await PhotoLoader.load(url)
            }
            .accessibilityHidden(true)
    }
}

