import CoreLocation
import Foundation

/// Resultado do Text Search (campos mínimos).
struct PlaceCandidate: Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var address: String?
    var lat: Double
    var lng: Double
    /// Tipo principal do Places ("ramen_restaurant", "market"…): manda na categoria do lugar.
    var primaryType: String? = nil
}

/// Detalhes que o Must guarda em cache (horário + preço) e o card de Buscar por nome (nome, endereço, nota).
struct PlaceDetails: Sendable, Hashable {
    var id: String
    var hours: PlaceHours?
    var priceLevel: Int?
    /// Preço típico (início da faixa), na moeda que o Places devolveu.
    var priceFrom: Double?
    var priceCurrency: String?
    var rating: Double?
    var ratingCount: Int? = nil
    var name: String? = nil
    var address: String? = nil
    var lat: Double? = nil
    var lng: Double? = nil
    var primaryType: String? = nil
    /// `photos[]` do mesmo Details (prompt 19): o que o `Place` guarda pra foto principal e a galeria.
    var photos: [PlacePhotoRef] = []
}

protocol PlacesProviding: Sendable {
    var isConfigured: Bool { get }
    func searchText(_ query: String, near: CLLocationCoordinate2D, radius: Double, languageCode: String) async throws -> [PlaceCandidate]
    func details(_ placeId: String, languageCode: String) async throws -> PlaceDetails
    /// Fecha a sessão do Autocomplete (o Details com o mesmo token).
    func details(_ placeId: String, languageCode: String, sessionToken: String?) async throws -> PlaceDetails
}

extension PlacesProviding {
    func details(_ placeId: String, languageCode: String, sessionToken: String?) async throws -> PlaceDetails {
        try await details(placeId, languageCode: languageCode)
    }
}

/// Google Places API (New). Cada chamada passa pelo `GoogleAPI` (orçamento por SKU, `ApiBudget`).
struct PlacesService: PlacesProviding {
    var http = HTTP()
    var apiKey: String? = Secrets.googlePlacesKey

    var isConfigured: Bool { apiKey != nil }

    /// Conferir/juntar (Text Search). O nome entra porque o candidato é escolhido pelo nome: a máscara
    /// `places.id` sozinha não dá pra conferir (regra do projeto: código existente ganha, ver commit).
    static let searchMask = "places.id,places.displayName,places.location,places.formattedAddress,places.primaryType"
    /// Pro: horário, nota, preço + o que o card de Buscar por nome mostra (uma chamada só, mais barata que Essentials + Pro).
    /// `photos` entra sem chamada extra (prompt 19): o SKU cobrado é o mais caro do mask (Pro), que já é este.
    static let detailsMask = "id,displayName,formattedAddress,location,primaryType,regularOpeningHours,currentOpeningHours,priceLevel,priceRange,rating,userRatingCount,photos"

    /// Chave restrita a apps iOS exige o bundle id no cabeçalho.
    private func headers(_ key: String, mask: String) -> [String: String] {
        GoogleAPI.headers(key: key, mask: mask)
    }

    func searchText(_ query: String, near: CLLocationCoordinate2D, radius: Double = 30_000, languageCode: String = "pt-BR") async throws -> [PlaceCandidate] {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        let body: [String: Any] = [
            "textQuery": query,
            "languageCode": languageCode,
            "maxResultCount": 8,
            "locationBias": ["circle": ["center": ["latitude": near.latitude, "longitude": near.longitude], "radius": min(radius, 50_000)]],
        ]
        let data = try await GoogleAPI.run(.placesEssentials) {
            try await http.post(URL(string: "https://places.googleapis.com/v1/places:searchText")!, json: body,
                                headers: headers(apiKey, mask: Self.searchMask), service: "places.search")
        }
        return try Self.parseSearch(data)
    }

    /// Pro (horário, nota, preço, nome/endereço pro card). `sessionToken` fecha a sessão do Autocomplete.
    func details(_ placeId: String, languageCode: String) async throws -> PlaceDetails {
        try await details(placeId, languageCode: languageCode, sessionToken: nil)
    }

    func details(_ placeId: String, languageCode: String, sessionToken: String?) async throws -> PlaceDetails {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        var comps = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")!
        comps.queryItems = [URLQueryItem(name: "languageCode", value: languageCode)]
            + (sessionToken.map { [URLQueryItem(name: "sessionToken", value: $0)] } ?? [])
        let data = try await GoogleAPI.run(.placesPro) {
            try await http.get(comps.url!, headers: headers(apiKey, mask: Self.detailsMask), service: "places.details")
        }
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
            return PlaceCandidate(id: id, name: name, address: p["formattedAddress"] as? String, lat: lat, lng: lng,
                                  primaryType: p["primaryType"] as? String)
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
        let name = (json["displayName"] as? [String: Any])?["text"] as? String
        let loc = json["location"] as? [String: Any]
        return PlaceDetails(id: id, hours: hours, priceLevel: (json["priceLevel"] as? String).flatMap { levels[$0] },
                            priceFrom: units, priceCurrency: start?["currencyCode"] as? String, rating: json["rating"] as? Double,
                            ratingCount: json["userRatingCount"] as? Int, name: name, address: json["formattedAddress"] as? String,
                            lat: loc?["latitude"] as? Double, lng: loc?["longitude"] as? Double, primaryType: json["primaryType"] as? String,
                            photos: GooglePlacePhotos.refs(from: json))
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

#if DEBUG
extension FakePlacesService {
    /// Prints do Adicionar por link (`-debugPlaces fake`): Tsukiji e Maguroya "conferidos", o resto não.
    static var linkSamples: FakePlacesService {
        let tsukiji = PlaceCandidate(id: "fake-tsukiji-outer", name: "Tsukiji Outer Market", address: "Tsukiji, Chuo City",
                                     lat: 35.6654, lng: 139.7707, primaryType: "market")
        let maguro = PlaceCandidate(id: "fake-maguroya", name: "Maguroya Kurogin", address: "Tsukiji, Chuo City",
                                    lat: 35.6651, lng: 139.7706, primaryType: "sushi_restaurant")
        let hours = PlaceHours(weekdayText: nil, periods: (0...6).map { day in
            .init(open: .init(day: day, hour: 5, minute: 0), close: .init(day: day, hour: 14, minute: 0))
        }, fetchedAt: nil)
        // Os lugares do texto colado de amostra (prompt 18 · E) entram junto: nenhum outro nome casa com eles.
        return FakePlacesService(candidates: [tsukiji, maguro] + ColarTextoSample.candidates, detailsById: [
            "fake-tsukiji-outer": PlaceDetails(id: "fake-tsukiji-outer", hours: hours),
            "fake-maguroya": PlaceDetails(id: "fake-maguroya", hours: hours, priceFrom: 3000, priceCurrency: "JPY"),
        ].merging(ColarTextoSample.details) { a, _ in a })
    }
}
#endif

extension PlaceHours {
    /// Cache vence em 7 dias.
    var isStale: Bool { (fetchedAt ?? .distantPast) < Date().addingTimeInterval(-7 * 86_400) }
}
