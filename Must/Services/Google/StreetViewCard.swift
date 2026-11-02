import CoreLocation
import Foundation

/// "A porta" (Street View): a foto do ponto mais perto do lugar, com o rumo da câmera até ele.
struct StreetViewCard: Sendable, Equatable {
    var panoId: String
    /// "2025-03" → "mar 2025".
    var date: String?
    var copyright: String
    var heading: Double
    /// Imagem em Caches/ (30 dias, a regra de cache do Street View).
    var imageFile: URL
    /// Frase da porta (primeira linha das notas do lugar), se houver.
    var caption: String?

    /// Abre o 360° no Google Maps (app se instalado, senão web).
    var viewURL: URL {
        URL(string: "https://www.google.com/maps/@?api=1&map_action=pano&pano=\(panoId)")!
    }
}

/// Metadata do Street View (grátis). Só se `status == OK` a imagem é pedida (regra do prompt 17 · A).
struct StreetViewMeta: Sendable, Equatable {
    var status: String
    var panoId: String?
    var lat: Double?
    var lng: Double?
    var date: String?
    var copyright: String?

    static func parse(_ data: Data) throws -> StreetViewMeta {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? String else { throw ServiceError.decoding("streetview metadata") }
        let loc = json["location"] as? [String: Any]
        return StreetViewMeta(status: status, panoId: json["pano_id"] as? String, lat: loc?["lat"] as? Double,
                              lng: loc?["lng"] as? Double, date: json["date"] as? String, copyright: json["copyright"] as? String)
    }
}

struct StreetViewService: Sendable {
    typealias Fetch = @Sendable (URL, [String: String]) async throws -> Data

    var apiKey: String?
    var fetch: Fetch
    static let directory = URL.cachesDirectory.appending(path: "must-streetview", directoryHint: .isDirectory)
    static let radius = 60
    static let size = "640x360"

    init(apiKey: String? = Secrets.googlePlacesKey, http: HTTP = HTTP(), fetch: Fetch? = nil) {
        self.apiKey = apiKey
        self.fetch = fetch ?? { url, headers in try await http.get(url, headers: headers, service: "streetview") }
    }

    /// Cartão da porta: metadata (grátis) → se OK, imagem (cobrada, cacheada 30 dias). Qualquer outra coisa = `nil` (o card some).
    func card(for place: CLLocationCoordinate2D, caption: String?) async throws -> StreetViewCard? {
        guard let apiKey else { return nil }
        var meta = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview/metadata")!
        meta.queryItems = [URLQueryItem(name: "location", value: "\(place.latitude),\(place.longitude)"),
                           URLQueryItem(name: "radius", value: "\(Self.radius)"), URLQueryItem(name: "source", value: "outdoor"),
                           URLQueryItem(name: "key", value: apiKey)]
        let info = try await GoogleAPI.run(.streetViewMetadata) {
            let parsed = try StreetViewMeta.parse(await fetch(meta.url!, GoogleAPI.headers(key: apiKey)))
            // REQUEST_DENIED vem com HTTP 200: vira 403 pro `GoogleAPI` marcar a SKU indisponível até amanhã.
            if parsed.status == "REQUEST_DENIED" { throw ServiceError.http(403, "REQUEST_DENIED") }
            return parsed
        }
        guard info.status == "OK", let panoId = info.panoId, let lat = info.lat, let lng = info.lng else { return nil }
        let heading = Self.bearing(from: CLLocationCoordinate2D(latitude: lat, longitude: lng), to: place)
        let file = Self.imageFile(panoId: panoId, heading: heading)
        if !Self.isFresh(file) {
            var image = URLComponents(string: "https://maps.googleapis.com/maps/api/streetview")!
            image.queryItems = [URLQueryItem(name: "size", value: Self.size), URLQueryItem(name: "pano", value: panoId),
                                URLQueryItem(name: "heading", value: "\(Int(heading.rounded()))"), URLQueryItem(name: "pitch", value: "0"),
                                URLQueryItem(name: "fov", value: "80"), URLQueryItem(name: "key", value: apiKey)]
            let bytes = try await GoogleAPI.run(.streetView) { try await fetch(image.url!, GoogleAPI.headers(key: apiKey)) }
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try bytes.write(to: file, options: .atomic)
        }
        return StreetViewCard(panoId: panoId, date: info.date.map(Self.monthName), copyright: info.copyright ?? "© Google",
                              heading: heading, imageFile: file, caption: caption)
    }

    static func imageFile(panoId: String, heading: Double) -> URL {
        let safe = panoId.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return directory.appending(path: "\(safe)-\(Int(heading.rounded())).jpg")
    }

    static func isFresh(_ file: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path()),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < GooglePlacePhotos.maxAge
    }

    /// Rumo (graus, 0 = norte) do ponto da foto até o lugar.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// "2025-03" → "mar 2025" (pt-BR).
    static func monthName(_ raw: String) -> String {
        let parts = raw.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]), (1...12).contains(month) else { return raw }
        let names = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]
        return "\(names[month - 1]) \(parts[0])"
    }
}
