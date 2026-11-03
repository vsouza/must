import SwiftUI

/// Miniatura da foto principal do lugar (prompt 19 · item 2): 240 px gerados no aparelho, cantos 14 pt.
/// Sem foto, o gradiente da cor do Must. Cache primeiro: o que está no disco aparece na hora; sem nada, uma
/// `/media` só (com rede boa e cota), e nunca Details pra miniatura.
struct PlaceThumb: View {
    var placeId: String?
    var refs: [PlacePhotoRef]
    var color: MustColor
    var size: CGFloat = 44

    @Environment(Services.self) private var services: Services?
    @State private var url: URL?

    var body: some View {
        TintedPhoto(url: url, color: color, tintOpacity: 0, saturation: 1)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .task(id: refs.first?.name ?? "") {
                guard let services, let first = refs.first else { url = nil; return }
                if let cached = PlacePhotoStore.existingThumb(first) { url = cached; return }
                url = await services.photoResolver.thumb(placeId: placeId, refs: refs)
            }
            .accessibilityHidden(true)
    }
}
