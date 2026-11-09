import SwiftUI

// Peças repetidas das telas v8 do agente D (Guia, Dicas, Bolso, Lugar, Musts, Lista, Próximos): o botão redondo de
// contorno do canto, a pilha de micro-rótulos, a fileira de filtros e a foto com placeholder de cor.
// Usam só os tokens do contrato (`V8`, `V8Font`, `SpecLabel`, `V8Pill`); o agente A troca o miolo deles.

/// Botão de canto v9: quadrado de 44 pt, borda de 2 pt, sem raio (voltar, fechar, trocar, ✦). Cantos fixos: ⇄/←/✕ à
/// esquerda e ✦ (Assistente) à direita. `tint` força a cor do traço (bloco da foto com a cor do lugar).
struct V8CornerButton: View {
    var systemName: String
    var label: String
    var onInk = false
    /// Sobre foto: fundo tinta translúcido pra ler em qualquer foto.
    var onPhoto = false
    var filled = false
    var tint: Color?
    var action: () -> Void

    var body: some View {
        let stroke = tint ?? (onInk || onPhoto ? V8.white : V8.ink)
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? (onInk ? V8.ink : V8.white) : stroke)
                .frame(width: 44, height: 44)
                .background {
                    if filled {
                        Rectangle().fill(onInk ? V8.paper : V8.ink)
                    } else if onPhoto {
                        Rectangle().fill(V8.ink.opacity(0.28))
                    }
                }
                .overlay { if !filled { Rectangle().strokeBorder(stroke, lineWidth: 2) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(label)
    }
}

/// ✦ do canto superior direito: abre o Assistente (sempre aí, em todo bloco de foto).
struct AssistantCorner: View {
    var onInk = false
    var onPhoto = false
    var tint: Color?
    @Environment(AppRouter.self) private var router

    var body: some View {
        V8CornerButton(systemName: "sparkle", label: "Assistente", onInk: onInk, onPhoto: onPhoto, tint: tint) {
            router.sheet = .assistant
        }
    }
}

/// Duas ou três linhas de micro-rótulo (ficha técnica no canto).
struct V8SpecStack: View {
    var lines: [String]
    var color: Color = V8.mute
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                SpecLabel(line, color: color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fileira de filtros que rola na horizontal (a primeira ativa = tinta cheia, como no design).
struct V8FilterRow: View {
    struct Item: Identifiable, Hashable {
        var id: String
        var title: String
        var on: Bool
    }

    var items: [Item]
    var onInk = false
    /// Sangra 20 pt pros lados (dentro de uma tela com margem de 20); `false` quando a linha já está dentro do próprio padding.
    var bleed = true
    var onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button { onTap(item.id) } label: { V8FilterChip(title: item.title, on: item.on, onInk: onInk) }
                        .buttonStyle(MustPressStyle())
                        .accessibilityAddTraits(item.on ? .isSelected : [])
                }
            }
            .padding(.horizontal, bleed ? 20 : 0)
        }
        .padding(.horizontal, bleed ? -20 : 0)
        .scrollClipDisabled()
    }
}

/// Chip de filtro (`Agora`, `Perto`), no corte (prompt 30 §1): quadrado de borda 2 pt, mono em caixa alta; ligado = tinta cheia
/// com texto papel. Mesmo desenho do `CutChip` do Board, pra Lista, Musts, Dicas e Em cartaz falarem a mesma língua.
struct V8FilterChip: View {
    var title: String
    var on: Bool
    var onInk = false

    private var line: Color { onInk ? V8.white : V8.ink }

    var body: some View {
        Text(title)
            .font(V8Font.mono(11, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(on ? (onInk ? V8.ink : V8.paper) : line)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(Rectangle().fill(on ? (onInk ? V8.paper : V8.ink) : Color.clear))
            .overlay(Rectangle().strokeBorder(line, lineWidth: 2))
    }
}

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

/// Miniatura de lugar da Lista e do Guia (cantos 12 pt): só o que já está no disco ou o resolvedor de miniatura
/// (uma `/media` com rede boa; no Modo de Pouco Dados, nada). Sem foto, o quadrado grafite.
struct V8Thumb: View {
    var placeId: String?
    var refs: [PlacePhotoRef]
    var size: CGFloat = 44
    var dimmed = false
    /// Tocar na miniatura abre as fotos do lugar em carrossel.
    var opensViewer = false

    @Environment(Services.self) private var services: Services?
    @State private var url: URL?
    @State private var carousel: PhotoCarousel?

    var body: some View {
        V8Photo(url: url, placeholder: dimmed ? V8.mute.opacity(0.6) : Color(hex: 0x3A3A38))
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .opacity(dimmed ? 0.6 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard opensViewer else { return }
                carousel = .place(placeId: placeId, refs: refs, resolver: services?.photoResolver)
            }
            .photoCarousel($carousel)
            .task(id: refs.first?.name ?? "") {
                guard let first = refs.first else { url = nil; return }
                if let cached = PlacePhotoStore.existingThumb(first) { url = cached; return }
                guard let services else { return }
                url = await services.photoResolver.thumb(placeId: placeId, refs: refs)
            }
    }
}

/// Fundo das telas v8 claras: papel com os arcos de 1 pt sangrando.
struct V8PaperBackground: View {
    var dark = false
    var rings = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            (dark ? V8.ink : V8.paper)
            if rings {
                Rings(color: dark ? V8.white : V8.ink, count: 1, diameter: 520, opacity: dark ? 0.32 : 0.38,
                      offset: CGSize(width: 250, height: -150))
            }
        }
        .ignoresSafeArea()
    }
}

/// Respiro no fim das telas roláveis. A barra nativa e a faixa "agora" já entram na safe area (antes: 110 pt da cápsula v8).
struct V8BarSpacer: View {
    var body: some View { Color.clear.frame(height: 24) }
}
