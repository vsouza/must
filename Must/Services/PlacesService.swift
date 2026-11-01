import CoreLocation
import Foundation

/// Resultado do Text Search (campos mínimos).
struct PlaceCandidate: Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var address: String?
    var lat: Double
    var lng: Double
}

/// Detalhes que o Must guarda em cache (horário + preço).
struct PlaceDetails: Sendable, Hashable {
    var id: String
    var hours: PlaceHours?
    var priceLevel: Int?
    /// Preço típico (início da faixa), na moeda que o Places devolveu.
    var priceFrom: Double?
    var priceCurrency: String?
    var rating: Double?
}

protocol PlacesProviding: Sendable {
    var isConfigured: Bool { get }
    func searchText(_ query: String, near: CLLocationCoordinate2D, radius: Double, languageCode: String) async throws -> [PlaceCandidate]
    func details(_ placeId: String, languageCode: String) async throws -> PlaceDetails
}

/// Google Places API (New). Cada chamada conta no contador do mês (Ajustes).
struct PlacesService: PlacesProviding {
    var http = HTTP()
    var apiKey: String? = Secrets.googlePlacesKey

    var isConfigured: Bool { apiKey != nil }

    /// Campos mínimos (SKU barato).
    static let searchMask = "places.id,places.displayName,places.location,places.formattedAddress"
    static let detailsMask = "id,regularOpeningHours,currentOpeningHours,priceLevel,priceRange,rating"

    /// Chave restrita a apps iOS exige o bundle id no cabeçalho.
    private func headers(_ key: String, mask: String) -> [String: String] {
        ["X-Goog-Api-Key": key, "X-Goog-FieldMask": mask, "X-Ios-Bundle-Identifier": Bundle.main.bundleIdentifier ?? "dev.viniso.must"]
    }

    func searchText(_ query: String, near: CLLocationCoordinate2D, radius: Double = 30_000, languageCode: String = "pt-BR") async throws -> [PlaceCandidate] {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        let body: [String: Any] = [
            "textQuery": query,
            "languageCode": languageCode,
            "maxResultCount": 8,
            "locationBias": ["circle": ["center": ["latitude": near.latitude, "longitude": near.longitude], "radius": min(radius, 50_000)]],
        ]
        let data = try await http.post(URL(string: "https://places.googleapis.com/v1/places:searchText")!, json: body,
                                       headers: headers(apiKey, mask: Self.searchMask), service: "places.search")
        await MainActor.run { PlacesUsage.record() }
        return try Self.parseSearch(data)
    }

    func details(_ placeId: String, languageCode: String = "pt-BR") async throws -> PlaceDetails {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        var comps = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")!
        comps.queryItems = [URLQueryItem(name: "languageCode", value: languageCode)]
        let data = try await http.get(comps.url!, headers: headers(apiKey, mask: Self.detailsMask), service: "places.details")
        await MainActor.run { PlacesUsage.record() }
        return try Self.parseDetails(data)
    }

    // MARK: Parse (testado)

    static func parseSearch(_ data: Data) throws -> [PlaceCandidate] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("places") }
        let places = json["places"] as? [[String: Any]] ?? []
        return places.compactMap { p in
            guard let id = p["id"] as? String, let loc = p["location"] as? [String: Any],
                  let lat = loc["latitude"] as? Double, let lng = loc["longitude"] as? Double else { return nil }
            let name = (p["displayName"] as? [String: Any])?["text"] as? String ?? id
            return PlaceCandidate(id: id, name: name, address: p["formattedAddress"] as? String, lat: lat, lng: lng)
        }
    }

    static func parseDetails(_ data: Data, fetchedAt: Date = Date()) throws -> PlaceDetails {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["id"] as? String else {
            throw ServiceError.decoding("place details")
        }
        let opening = (json["regularOpeningHours"] ?? json["currentOpeningHours"]) as? [String: Any]
        var hours: PlaceHours?
        if let opening {
            let periods = (opening["periods"] as? [[String: Any]] ?? []).compactMap { period -> PlaceHours.Period? in
                guard let open = point(period["open"]) else { return nil }
                return PlaceHours.Period(open: open, close: point(period["close"]))
            }
            hours = PlaceHours(weekdayText: opening["weekdayDescriptions"] as? [String], periods: periods, fetchedAt: fetchedAt)
        }
        let levels = ["PRICE_LEVEL_FREE": 0, "PRICE_LEVEL_INEXPENSIVE": 1, "PRICE_LEVEL_MODERATE": 2,
                      "PRICE_LEVEL_EXPENSIVE": 3, "PRICE_LEVEL_VERY_EXPENSIVE": 4]
        let start = ((json["priceRange"] as? [String: Any])?["startPrice"] as? [String: Any])
        let units = (start?["units"] as? String).flatMap(Double.init) ?? (start?["units"] as? Double)
        return PlaceDetails(id: id, hours: hours, priceLevel: (json["priceLevel"] as? String).flatMap { levels[$0] },
                            priceFrom: units, priceCurrency: start?["currencyCode"] as? String, rating: json["rating"] as? Double)
    }

    private static func point(_ any: Any?) -> PlaceHours.Point? {
        guard let p = any as? [String: Any], let day = p["day"] as? Int else { return nil }
        return PlaceHours.Point(day: day, hour: p["hour"] as? Int ?? 0, minute: p["minute"] as? Int ?? 0)
    }
}

/// Pra previews e testes.
struct FakePlacesService: PlacesProviding {
    var isConfigured = true
    var candidates: [PlaceCandidate] = []
    var detailsById: [String: PlaceDetails] = [:]

    func searchText(_ query: String, near: CLLocationCoordinate2D, radius: Double, languageCode: String) async throws -> [PlaceCandidate] {
        candidates.filter { PlaceMatcher.similar($0.name, query) || query.localizedCaseInsensitiveContains($0.name) }
    }

    func details(_ placeId: String, languageCode: String) async throws -> PlaceDetails {
        detailsById[placeId] ?? PlaceDetails(id: placeId)
    }
}

extension PlaceHours {
    /// Cache vence em 7 dias.
    var isStale: Bool { (fetchedAt ?? .distantPast) < Date().addingTimeInterval(-7 * 86_400) }
}
