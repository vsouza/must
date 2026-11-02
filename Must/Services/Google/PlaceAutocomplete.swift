import CoreLocation
import Foundation

/// Uma sugestão do Places Autocomplete (New). `segments` é o nome com o trecho digitado marcado (destaque verde).
struct PlaceSuggestion: Sendable, Hashable, Identifiable {
    struct Segment: Sendable, Hashable {
        var text: String
        var highlighted: Bool
    }

    var id: String { placeId }
    var placeId: String
    var name: String
    /// "Omotesando, Shibuya" · bairro e cidade.
    var secondary: String?
    var segments: [Segment]
    var types: [String]
    /// Metros da origem (posição atual) até o lugar, como o Autocomplete devolve com `origin`.
    var distanceMeters: Int? = nil

    /// Tipo principal pra lista sugerida: o primeiro dos `types` (Autocomplete não manda `primaryType`).
    var primaryType: String? { types.first }
}

protocol AutocompleteProviding: Sendable {
    var isConfigured: Bool { get }
    func suggest(_ input: String, sessionToken: String, near: CLLocationCoordinate2D, origin: CLLocationCoordinate2D?, radius: Double) async throws -> [PlaceSuggestion]
}

/// Places Autocomplete (New) com session token. Cada pedido conta como `autocomplete` no `ApiBudget`.
/// O session token é do chamador: gera um por busca e manda o mesmo no Details de fim de sessão.
struct PlaceAutocomplete: AutocompleteProviding, Sendable {
    var http = HTTP()
    var apiKey: String? = Secrets.googlePlacesKey

    var isConfigured: Bool { apiKey != nil }

    /// Viés pela cidade/bairro atual (raio de 3 km, como o design).
    func suggest(_ input: String, sessionToken: String, near: CLLocationCoordinate2D, origin: CLLocationCoordinate2D? = nil,
                 radius: Double = 3_000) async throws -> [PlaceSuggestion] {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        var body: [String: Any] = [
            "input": input,
            "sessionToken": sessionToken,
            "languageCode": "pt-BR",
            "includeQueryPredictions": false,
            "locationBias": ["circle": ["center": ["latitude": near.latitude, "longitude": near.longitude], "radius": radius]],
        ]
        // Com `origin`, cada sugestão volta com `distanceMeters` (a distância a pé do card).
        if let origin { body["origin"] = ["latitude": origin.latitude, "longitude": origin.longitude] }
        let data = try await GoogleAPI.run(.autocomplete) {
            try await http.post(URL(string: "https://places.googleapis.com/v1/places:autocomplete")!, json: body,
                                headers: GoogleAPI.headers(key: apiKey), service: "places.autocomplete")
        }
        return try Self.parse(data)
    }

    /// `suggestions[].placePrediction` → sugestões. Sem `placeId` (previsão de consulta), a linha some.
    static func parse(_ data: Data) throws -> [PlaceSuggestion] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("autocomplete") }
        let suggestions = json["suggestions"] as? [[String: Any]] ?? []
        return suggestions.compactMap { item -> PlaceSuggestion? in
            guard let p = item["placePrediction"] as? [String: Any], let placeId = p["placeId"] as? String else { return nil }
            let full = (p["text"] as? [String: Any])?["text"] as? String ?? ""
            let fullMatches = matches(in: p["text"] as? [String: Any])
            let structured = p["structuredFormat"] as? [String: Any]
            let mainNode = structured?["mainText"] as? [String: Any]
            let main = mainNode?["text"] as? String ?? full
            let secondary = (structured?["secondaryText"] as? [String: Any])?["text"] as? String
            let mainMatches = matches(in: mainNode)
            let segments = segmentize(main: main, full: full, fullMatches: fullMatches, mainMatches: mainMatches)
            return PlaceSuggestion(placeId: placeId, name: main, secondary: secondary, segments: segments,
                                   types: p["types"] as? [String] ?? [], distanceMeters: p["distanceMeters"] as? Int)
        }
    }

    /// `matches[{startOffset, endOffset}]` como intervalos de escalares Unicode.
    static func matches(in node: [String: Any]?) -> [Range<Int>] {
        (node?["matches"] as? [[String: Any]] ?? []).compactMap { m in
            let start = m["startOffset"] as? Int ?? 0
            let end = m["endOffset"] as? Int ?? start
            return end > start ? start..<end : nil
        }
    }

    /// Marca o trecho do nome: os `matches` do texto completo caem dentro do `mainText` (que é o fim do texto,
    /// "… KOFFEE MAMEYA"); se não der pra achar o nome no texto completo, usa os `matches` do próprio `mainText`.
    static func segmentize(main: String, full: String, fullMatches: [Range<Int>], mainMatches: [Range<Int>]) -> [PlaceSuggestion.Segment] {
        let mainScalars = Array(main.unicodeScalars)
        let fullScalars = Array(full.unicodeScalars)
        var hits = [Bool](repeating: false, count: mainScalars.count)
        if let base = find(mainScalars, in: fullScalars), !fullMatches.isEmpty {
            for range in fullMatches {
                for i in range where i >= base && i < base + mainScalars.count { hits[i - base] = true }
            }
        } else {
            for range in mainMatches {
                for i in range where i >= 0 && i < mainScalars.count { hits[i] = true }
            }
        }
        var out: [PlaceSuggestion.Segment] = []
        var current = ""
        var currentHit = hits.first ?? false
        for (i, scalar) in mainScalars.enumerated() {
            if hits[i] != currentHit, !current.isEmpty {
                out.append(.init(text: current, highlighted: currentHit))
                current = ""
            }
            currentHit = hits[i]
            current.unicodeScalars.append(scalar)
        }
        if !current.isEmpty { out.append(.init(text: current, highlighted: currentHit)) }
        return out
    }

    private static func find(_ needle: [Unicode.Scalar], in hay: [Unicode.Scalar]) -> Int? {
        guard !needle.isEmpty, needle.count <= hay.count else { return nil }
        for start in 0...(hay.count - needle.count) where Array(hay[start..<start + needle.count]) == needle {
            return start
        }
        return nil
    }
}

#if DEBUG
/// `-debugAutocomplete fake` (prints): as sugestões do design pra "koffee mam", sem gastar cota.
/// As distâncias saem da origem de verdade (como o Google faria) até os pontos de mentira.
struct FakeAutocomplete: AutocompleteProviding {
    var isConfigured = true

    /// Coordenadas de mentira: a do board (Koffee Mameya, j09) e a da torrefação.
    static let spots: [(id: String, name: String, secondary: String, lat: Double, lng: Double, types: [String])] = [
        ("fake-koffee-mameya", "Koffee Mameya", "Omotesando, Shibuya", 35.668368, 139.710888, ["cafe", "establishment"]),
        ("fake-koffee-kakeru", "Koffee Mameya Kakeru", "Kiyosumi, Koto", 35.6843, 139.7968, ["cafe"]),
        ("fake-koffee-roastery", "Koffee Mameya Roastery", "Shibuya", 35.6683, 139.7070, ["store", "cafe"]),
    ]

    func suggest(_ input: String, sessionToken: String, near: CLLocationCoordinate2D, origin: CLLocationCoordinate2D?, radius: Double) async throws -> [PlaceSuggestion] {
        guard input.lowercased().hasPrefix("koffee") else { return [] }
        let from = origin ?? near
        return Self.spots.map { spot in
            let meters = CLLocation(latitude: from.latitude, longitude: from.longitude)
                .distance(from: CLLocation(latitude: spot.lat, longitude: spot.lng))
            // Destaque: "Koffee Mam" (o que foi digitado), o resto sem destaque.
            let typed = "Koffee Mam"
            let rest = String(spot.name.dropFirst(typed.count))
            return PlaceSuggestion(placeId: spot.id, name: spot.name, secondary: spot.secondary,
                                   segments: [.init(text: typed, highlighted: true), .init(text: rest, highlighted: false)],
                                   types: spot.types, distanceMeters: Int(meters.rounded()))
        }
    }
}

extension FakePlacesService {
    /// Detalhes do card de "koffee mam" (nota, preço, horário até 18:00) pro `-debugAutocomplete fake`.
    static var koffeeSamples: FakePlacesService {
        let hours = PlaceHours(weekdayText: nil, periods: (0...6).map { day in
            .init(open: .init(day: day, hour: 8, minute: 0), close: .init(day: day, hour: 18, minute: 0))
        }, fetchedAt: nil)
        let roastery = PlaceDetails(id: "fake-koffee-roastery", hours: hours, priceLevel: 2, rating: 4.6, ratingCount: 2_100,
                                    name: "Koffee Mameya Roastery", address: "4-15-3 Jingumae, Shibuya", lat: 35.6683, lng: 139.7070,
                                    primaryType: "cafe")
        let mameya = PlaceDetails(id: "fake-koffee-mameya", hours: hours, priceLevel: 2, rating: 4.5, ratingCount: 980,
                                  name: "Koffee Mameya", address: "Omotesando, Shibuya", lat: 35.668368, lng: 139.710888, primaryType: "cafe")
        return FakePlacesService(candidates: [], detailsById: ["fake-koffee-roastery": roastery, "fake-koffee-mameya": mameya])
    }
}
#endif
