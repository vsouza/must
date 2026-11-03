import Foundation

/// Foto do Google Places guardada no `Place` (prompt 19 · item 1): o `name` do `photos[]` (ref do `/media`),
/// e o autor (`authorAttributions[0]`) pro crédito. Os nomes expiram: `/media` com 400/404 → refaz Details só com `photos`.
struct PlacePhotoRef: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var author: String?
    /// `authorAttributions[0].uri`: o toque no crédito abre.
    var authorURI: String?

    var id: String { name }
}
