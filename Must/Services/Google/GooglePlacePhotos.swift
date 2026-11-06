import Foundation
#if DEBUG
import UIKit
#endif

/// Fotos do Google Places (prompt 19). Dois pedidos, ambos pela `GoogleAPI` (orçamento por SKU):
/// - `photoRefs`: Details só com `id,photos` (Essentials). Usado quando o lugar não tem refs ou a ref expirou.
///   No dia a dia as refs já vêm no Details de sincronização (`PlacesService.detailsMask` pede `photos`).
/// - `photo`: `/media?maxWidthPx=800&skipHttpRedirect=true` (uma por foto) e o JPEG do `photoUri`, gravado em disco.
/// A foto já no disco não gasta nada: a conferência é a primeira coisa.
protocol PlacePhotosProviding: Sendable {
    var isConfigured: Bool { get }
    func photoRefs(placeId: String) async throws -> [PlacePhotoRef]
    /// `hero`: foto principal do Lugar aberto (fica liberada acima de 80% do mês). `prefetch`: pré-download (Modo de Pouco Dados não deixa).
    func photo(_ ref: PlacePhotoRef, placeId: String, hero: Bool, prefetch: Bool) async throws -> URL
}

struct GooglePlacePhotos: PlacePhotosProviding {
    var http = HTTP()
    var apiKey: String? = Secrets.googlePlacesKey

    var isConfigured: Bool { apiKey != nil }

    static let maxWidthPx = 800
    /// Até 5 fotos por lugar guardadas (hero + galeria do Lugar).
    static let maxRefs = 5

    func photoRefs(placeId: String) async throws -> [PlacePhotoRef] {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        var comps = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")!
        comps.queryItems = [URLQueryItem(name: "languageCode", value: "pt-BR")]
        let data = try await GoogleAPI.run(.placesEssentials) {
            try await http.get(comps.url!, headers: GoogleAPI.headers(key: apiKey, mask: "id,photos"), service: "places.photos")
        }
        return try Self.parseRefs(data)
    }

    func photo(_ ref: PlacePhotoRef, placeId: String, hero: Bool = false, prefetch: Bool = false) async throws -> URL {
        if let existing = PlacePhotoStore.existing(ref) { return existing }
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        var client = http
        client.kind = prefetch ? .prefetch : .interactive
        var media = URLComponents(string: "https://places.googleapis.com/v1/\(ref.name)/media")!
        media.queryItems = [URLQueryItem(name: "maxWidthPx", value: "\(Self.maxWidthPx)"), URLQueryItem(name: "skipHttpRedirect", value: "true")]
        let json = try await GoogleAPI.run(.placePhotos, hero: hero) {
            try await client.get(media.url!, headers: GoogleAPI.headers(key: apiKey), service: "places.media")
        }
        guard let uri = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["photoUri"] as? String,
              let imageURL = URL(string: uri) else { throw ServiceError.decoding("places.media") }
        let image = try await client.get(imageURL, service: "places.photo.file")
        // Resposta cortada (metrô, rede caindo) gravada aqui ficava quebrada 30 dias: a foto é baixada uma vez só.
        guard PlacePhotoStore.isCompleteImage(image) else { throw ServiceError.decoding("places.photo.file incompleta") }
        return try PlacePhotoStore.save(image, for: ref)
    }

    /// `photos[]` de um Details (ou de um `id,photos`): `name` + o primeiro autor e o link dele. No máximo 5.
    static func parseRefs(_ data: Data) throws -> [PlacePhotoRef] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("places.photos") }
        return refs(from: json)
    }

    static func refs(from json: [String: Any]) -> [PlacePhotoRef] {
        let photos = json["photos"] as? [[String: Any]] ?? []
        return photos.prefix(maxRefs).compactMap { p in
            guard let name = p["name"] as? String else { return nil }
            let author = (p["authorAttributions"] as? [[String: Any]])?.first
            return PlacePhotoRef(name: name, author: author?["displayName"] as? String, authorURI: author?["uri"] as? String)
        }
    }
}

#if DEBUG
/// `-debugPhotos fake` (prints e simulador): refs de mentira e uma imagem gerada no aparelho, sem cota.
struct FakePlacePhotos: PlacePhotosProviding {
    var isConfigured = true
    var refs: [PlacePhotoRef] = [
        PlacePhotoRef(name: "places/fake/photos/one", author: "Maria Viaja", authorURI: "https://maps.google.com/?cid=1"),
        PlacePhotoRef(name: "places/fake/photos/two", author: "Tomás Lima", authorURI: nil),
        PlacePhotoRef(name: "places/fake/photos/three", author: "Ana Souza", authorURI: nil),
    ]

    func photoRefs(placeId: String) async throws -> [PlacePhotoRef] { refs }

    func photo(_ ref: PlacePhotoRef, placeId: String, hero: Bool, prefetch: Bool) async throws -> URL {
        if let existing = PlacePhotoStore.existing(ref) { return existing }
        let image = await MainActor.run { Self.drawn(ref) }
        guard let data = image.jpegData(compressionQuality: 0.7) else { throw ServiceError.decoding("fake") }
        return try PlacePhotoStore.save(data, for: ref)
    }

    @MainActor
    private static func drawn(_ ref: PlacePhotoRef) -> UIImage {
        let size = CGSize(width: 800, height: 1067)
        let renderer = UIGraphicsImageRenderer(size: size)
        let hue = Double(abs(ref.name.hashValue) % 360) / 360
        return renderer.image { ctx in
            UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let text = "FOTO DE MENTIRA\n\(ref.author ?? "")" as NSString
            text.draw(in: CGRect(x: 40, y: 480, width: 720, height: 200),
                      withAttributes: [.font: UIFont.systemFont(ofSize: 56, weight: .bold), .foregroundColor: UIColor.white])
        }
    }
}
#endif
