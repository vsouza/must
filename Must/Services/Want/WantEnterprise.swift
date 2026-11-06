import Foundation

// Nota do Google na busca do mapa (prompt 27 §2.c). `rating` e `userRatingCount` ficam no nível **Enterprise** da Places
// API (New), acima do Pro que o Quero… usa. **Decisão pendente do Vinicius:** (i) aceitar o SKU Enterprise nesta busca
// (cota grátis própria de 1.000/mês, contada em `GoogleSKU.placesEnterprise`) ou (ii) ficar no Pro, sem nota, e ranquear
// por aberto + perto + popularidade (o que já está no aparelho). Enquanto ele não decidir, vale (ii): este flag fica
// **desligado** e a busca nunca pede nota ao Google. A nota que já existe sem custo (cache do "Por perto", dicas do Lugar
// já abertas) entra no ranking de qualquer jeito.

/// Liga a opção (i). Só o Vinicius liga (menu de testes / `defaults write … map.search.placesEnterprise -bool YES`).
enum PlacesEnterpriseFlag {
    static let key = "map.search.placesEnterprise"

    static func isOn(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}

/// Um resultado do Text Search com a nota (só com o flag ligado).
struct RatedHit: Codable, Hashable, Sendable {
    var hit: PlaceHit
    var rating: Double?
    var ratingCount: Int?
}

/// Quem faz o Text Search com nota (o `PlacesService` real; os testes).
protocol RatedPlacesSearching: Sendable {
    var isConfigured: Bool { get }
    func searchRatedPlaces(_ query: PlacesTextQuery) async throws -> [RatedHit]
}

extension PlacesService: RatedPlacesSearching {
    /// O mask do Quero… + `rating,userRatingCount`: o SKU cobrado vira o Enterprise (o mais caro do mask).
    static let ratedMask = wantMask + ",places.rating,places.userRatingCount"

    func searchRatedPlaces(_ query: PlacesTextQuery) async throws -> [RatedHit] {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        let data = try await GoogleAPI.run(.placesEnterprise) {
            try await http.post(URL(string: "https://places.googleapis.com/v1/places:searchText")!, json: Self.body(for: query),
                                headers: GoogleAPI.headers(key: apiKey, mask: Self.ratedMask), service: "places.want.rated")
        }
        return try Self.parseRated(data)
    }

    static func parseRated(_ data: Data) throws -> [RatedHit] {
        let hits = try parseHits(data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let raw = (json["places"] as? [[String: Any]] ?? []).reduce(into: [String: [String: Any]]()) { acc, p in
            if let id = p["id"] as? String { acc[id] = p }
        }
        return hits.map { hit in
            RatedHit(hit: hit, rating: raw[hit.id]?["rating"] as? Double, ratingCount: raw[hit.id]?["userRatingCount"] as? Int)
        }
    }
}

#if DEBUG
/// Fake com nota (prints com o flag ligado): os mesmos lugares do `FakeWantPlaces`, com nota e avaliações.
struct FakeRatedPlaces: RatedPlacesSearching {
    var isConfigured = true

    func searchRatedPlaces(_ query: PlacesTextQuery) async throws -> [RatedHit] {
        try await FakeWantPlaces().searchPlaces(query).enumerated().map { i, hit in
            RatedHit(hit: hit, rating: 4.6 - Double(i) * 0.1, ratingCount: 3_100 / (i + 1))
        }
    }
}
#endif
