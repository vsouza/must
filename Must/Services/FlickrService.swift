import CoreLocation
import Foundation

struct FlickrPhoto: Sendable, Hashable, Codable, Identifiable {
    var id: String
    var url: String
    var largeURL: String?
    var owner: String
    var ownerId: String
    var licenseName: String

    /// Página da foto (o crédito abre aqui).
    var pageURL: URL? { URL(string: "https://www.flickr.com/photos/\(ownerId)/\(id)") }
    /// "foto · Flickr CC · @owner"
    var credit: String { "foto · Flickr \(licenseName.hasPrefix("CC") ? "CC" : licenseName) · @\(owner)" }

    var listPhoto: ListPhoto {
        ListPhoto(flickrId: id, url: largeURL ?? url, credit: credit, license: licenseName, page: pageURL?.absoluteString)
    }
}

protocol FlickrProviding: Sendable {
    var isConfigured: Bool { get }
    func search(text: String) async throws -> [FlickrPhoto]
    func search(near: CLLocationCoordinate2D, radiusKm: Double) async throws -> [FlickrPhoto]
}

/// `flickr.photos.search` só com licenças CC/domínio público (4, 5, 7, 9, 10). Cache 7 dias.
struct FlickrService: FlickrProviding {
    var http = HTTP()
    var apiKey: String? = Secrets.flickrKey
    var isConfigured: Bool { apiKey != nil }

    static let licenses: [String: String] = ["4": "CC BY 2.0", "5": "CC BY-SA 2.0", "7": "sem restrição", "9": "CC0", "10": "domínio público"]

    func search(text: String) async throws -> [FlickrPhoto] {
        try await run(["text": text], cacheKey: "flickr-t-\(text.lowercased())")
    }

    func search(near c: CLLocationCoordinate2D, radiusKm: Double) async throws -> [FlickrPhoto] {
        try await run(["lat": String(format: "%.4f", c.latitude), "lon": String(format: "%.4f", c.longitude),
                       "radius": String(format: "%.1f", radiusKm), "radius_units": "km"],
                      cacheKey: String(format: "flickr-g-%.4f-%.4f-%.1f", c.latitude, c.longitude, radiusKm))
    }

    private func run(_ params: [String: String], cacheKey: String) async throws -> [FlickrPhoto] {
        if let cached = await DiskCache.shared.data(for: cacheKey, maxAge: 7 * 86_400),
           let photos = try? JSONDecoder().decode([FlickrPhoto].self, from: cached) { return photos }
        guard let apiKey else { throw ServiceError.missingKey("FLICKR_KEY") }
        var comps = URLComponents(string: "https://api.flickr.com/services/rest/")!
        comps.queryItems = [
            URLQueryItem(name: "method", value: "flickr.photos.search"), URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "nojsoncallback", value: "1"),
            URLQueryItem(name: "license", value: "4,5,7,9,10"), URLQueryItem(name: "sort", value: "interestingness-desc"),
            URLQueryItem(name: "extras", value: "owner_name,license,url_m,url_l"), URLQueryItem(name: "content_type", value: "1"),
            URLQueryItem(name: "safe_search", value: "1"), URLQueryItem(name: "per_page", value: "12"),
        ] + params.map { URLQueryItem(name: $0.key, value: $0.value) }
        let data = try await http.get(comps.url!, service: "flickr")
        let photos = try Self.parse(data)
        if let encoded = try? JSONEncoder().encode(photos) { await DiskCache.shared.store(encoded, for: cacheKey) }
        return photos
    }

    static func parse(_ data: Data) throws -> [FlickrPhoto] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("flickr") }
        if json["stat"] as? String == "fail" { throw ServiceError.http(0, json["message"] as? String ?? "flickr") }
        let list = (json["photos"] as? [String: Any])?["photo"] as? [[String: Any]] ?? []
        return list.compactMap { p in
            guard let id = p["id"] as? String, let url = p["url_m"] as? String ?? p["url_l"] as? String,
                  let ownerId = p["owner"] as? String else { return nil }
            let license = (p["license"] as? String) ?? (p["license"] as? Int).map(String.init) ?? ""
            guard let name = licenses[license] else { return nil } // nunca mostra licença fora das permitidas
            return FlickrPhoto(id: id, url: url, largeURL: p["url_l"] as? String, owner: (p["ownername"] as? String) ?? ownerId,
                               ownerId: ownerId, licenseName: name)
        }
    }
}

struct FakeFlickrService: FlickrProviding {
    var isConfigured = true
    var photos: [FlickrPhoto] = []
    func search(text: String) async throws -> [FlickrPhoto] { photos }
    func search(near: CLLocationCoordinate2D, radiusKm: Double) async throws -> [FlickrPhoto] { photos }
}
