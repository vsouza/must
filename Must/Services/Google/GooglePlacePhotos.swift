import Foundation

/// Fotos do Google Places (Place Photos): só quando o Wikimedia não tem foto (hero do Lugar) e pro card de Buscar por nome.
/// Cada foto vira `CCPhoto` com `source: "Google"`, pro crédito ("foto · Google · @autor") aparecer sempre.
/// Cache: a lista de fotos do lugar e os arquivos ficam 30 dias em Caches/.
protocol PlacePhotosProviding: Sendable {
    var isConfigured: Bool { get }
    func photos(placeId: String, limit: Int) async throws -> [CCPhoto]
}

struct GooglePlacePhotos: PlacePhotosProviding {
    var http = HTTP()
    var apiKey: String? = Secrets.googlePlacesKey

    var isConfigured: Bool { apiKey != nil }

    static let maxAge: TimeInterval = 30 * 86_400
    static let maxWidthPx = 800
    static let directory = URL.cachesDirectory.appending(path: "must-place-photos", directoryHint: .isDirectory)

    func photos(placeId: String, limit: Int = 3) async throws -> [CCPhoto] {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        let listKey = "gplaces-photos-\(placeId)-\(limit)"
        if let cached = await DiskCache.shared.data(for: listKey, maxAge: Self.maxAge),
           let list = try? JSONDecoder().decode([CCPhoto].self, from: cached) {
            return list.filter { FileManager.default.fileExists(atPath: URL(string: $0.url)?.path() ?? "") }
        }
        // 1) Nomes das fotos (Details só com `photos`).
        var comps = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")!
        comps.queryItems = [URLQueryItem(name: "languageCode", value: "pt-BR")]
        let details = try await GoogleAPI.run(.placePhotos) {
            try await http.get(comps.url!, headers: GoogleAPI.headers(key: apiKey, mask: "id,photos"), service: "places.photos")
        }
        let refs = Self.parseRefs(details).prefix(limit)
        // 2) Um link por foto (skipHttpRedirect devolve JSON com `photoUri`), depois o arquivo.
        var out: [CCPhoto] = []
        for ref in refs {
            let file = Self.fileURL(for: ref.name)
            if FileManager.default.fileExists(atPath: file.path()) {
                out.append(Self.photo(name: ref.name, file: file, author: ref.author, placeId: placeId))
                continue
            }
            var media = URLComponents(string: "https://places.googleapis.com/v1/\(ref.name)/media")!
            media.queryItems = [URLQueryItem(name: "maxWidthPx", value: "\(Self.maxWidthPx)"), URLQueryItem(name: "skipHttpRedirect", value: "true")]
            let json = try await GoogleAPI.run(.placePhotos) {
                try await http.get(media.url!, headers: GoogleAPI.headers(key: apiKey), service: "places.media")
            }
            guard let uri = (try? JSONSerialization.jsonObject(with: json) as? [String: Any])?["photoUri"] as? String,
                  let imageURL = URL(string: uri) else { continue }
            let image = try await http.get(imageURL, service: "places.photo.file")
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try image.write(to: file, options: .atomic)
            out.append(Self.photo(name: ref.name, file: file, author: ref.author, placeId: placeId))
        }
        if let encoded = try? JSONEncoder().encode(out) { await DiskCache.shared.store(encoded, for: listKey) }
        return out
    }

    struct Ref: Equatable {
        var name: String
        var author: String?
    }

    /// `photos[].name` + o primeiro `authorAttributions[].displayName`.
    static func parseRefs(_ data: Data) -> [Ref] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let photos = json["photos"] as? [[String: Any]] ?? []
        return photos.compactMap { p in
            guard let name = p["name"] as? String else { return nil }
            let author = (p["authorAttributions"] as? [[String: Any]])?.first?["displayName"] as? String
            return Ref(name: name, author: author)
        }
    }

    static func fileURL(for name: String) -> URL {
        let safe = name.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined().suffix(120)
        return directory.appending(path: "\(safe).jpg")
    }

    private static func photo(name: String, file: URL, author: String?, placeId: String) -> CCPhoto {
        CCPhoto(id: name, url: file.absoluteString, largeURL: file.absoluteString, owner: String((author ?? "Google").prefix(28)),
                licenseName: "Google", page: "https://www.google.com/maps/place/?q=place_id:\(placeId)", source: "Google")
    }
}

struct FakePlacePhotos: PlacePhotosProviding {
    var isConfigured = true
    var photos: [CCPhoto] = []
    func photos(placeId: String, limit: Int) async throws -> [CCPhoto] { Array(photos.prefix(limit)) }
}
