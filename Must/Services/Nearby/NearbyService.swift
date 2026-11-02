import Foundation

/// Fontes externas do "Por perto". Cada fonte que não tem chave some sem erro; uma que falha marca `complete = false`.
protocol NearbyProviding: Sendable {
    func fetch(lat: Double, lng: Double, region: Region) async -> NearbyFetch
}

/// Google Places Nearby (New) + Wikipedia geosearch + Foursquare search. Sem tips (são pagas).
/// Google é cobrado por chamada: uma rodada por célula a cada 30 min (`NearbyLoader`), contada no `PlacesUsage`.
struct NearbyService: NearbyProviding {
    var http = HTTP()
    var googleKey: String? = Secrets.googlePlacesKey
    var foursquareKey: String? = Secrets.foursquareKey

    static let radius: Double = 600
    /// Só tipos que fazem sentido pro roteiro (SKU Pro com `rankPreference` POPULARITY).
    static let includedTypes = ["restaurant", "cafe", "bar", "museum", "tourist_attraction", "park"]
    /// Campos mínimos: id, nome, local, nota, contagem, aberto agora e tipo.
    static let nearbyMask = "places.id,places.displayName,places.location,places.rating,places.userRatingCount,places.currentOpeningHours.openNow,places.primaryType"

    func fetch(lat: Double, lng: Double, region: Region) async -> NearbyFetch {
        async let google = Self.attempt { try await self.googleNearby(lat: lat, lng: lng) }
        async let wiki = Self.attempt { try await self.wikipedia(lat: lat, lng: lng) }
        async let fsq = Self.attempt { try await self.foursquare(lat: lat, lng: lng) }
        var places: [NearbyPlace] = []
        var complete = true
        for result in await [google, wiki, fsq] {
            switch result {
            case .success(let found): places += found
            case .failure: complete = false
            }
        }
        return NearbyFetch(places: places, complete: complete)
    }

    private static func attempt<T: Sendable>(_ body: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }

    // MARK: Google Places Nearby (New)

    func googleNearby(lat: Double, lng: Double) async throws -> [NearbyPlace] {
        guard let googleKey else { return [] }
        let body: [String: Any] = [
            "includedTypes": Self.includedTypes,
            "maxResultCount": 12,
            "rankPreference": "POPULARITY",
            "languageCode": "pt-BR",
            "locationRestriction": ["circle": ["center": ["latitude": lat, "longitude": lng], "radius": Self.radius]],
        ]
        let data = try await http.post(URL(string: "https://places.googleapis.com/v1/places:searchNearby")!, json: body,
                                       headers: ["X-Goog-Api-Key": googleKey, "X-Goog-FieldMask": Self.nearbyMask,
                                                 "X-Ios-Bundle-Identifier": Bundle.main.bundleIdentifier ?? "dev.viniso.must"],
                                       service: "places.nearby")
        await MainActor.run { PlacesUsage.record() }
        return try Self.parseGoogle(data)
    }

    static func parseGoogle(_ data: Data) throws -> [NearbyPlace] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("nearby") }
        let places = json["places"] as? [[String: Any]] ?? []
        return places.compactMap { p in
            guard let loc = p["location"] as? [String: Any], let lat = loc["latitude"] as? Double, let lng = loc["longitude"] as? Double,
                  let name = (p["displayName"] as? [String: Any])?["text"] as? String, !name.isEmpty else { return nil }
            let open = (p["currentOpeningHours"] as? [String: Any])?["openNow"] as? Bool
            return NearbyPlace(name: name, lat: lat, lng: lng, sources: [.google], googlePlaceId: p["id"] as? String,
                               rating: p["rating"] as? Double, ratingCount: p["userRatingCount"] as? Int, openNow: open,
                               category: p["primaryType"] as? String)
        }
    }

    // MARK: Wikipedia geosearch (sem chave)

    /// Artigo em pt; sem nada, ja e en. Cada chamada é gratuita.
    func wikipedia(lat: Double, lng: Double) async throws -> [NearbyPlace] {
        for lang in ["pt", "ja", "en"] {
            var comps = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
            comps.queryItems = [
                URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "list", value: "geosearch"),
                URLQueryItem(name: "gscoord", value: "\(lat)|\(lng)"), URLQueryItem(name: "gsradius", value: "\(Int(Self.radius))"),
                URLQueryItem(name: "gslimit", value: "10"), URLQueryItem(name: "format", value: "json"),
            ]
            let data = try await http.get(comps.url!, headers: ["User-Agent": CommonsPhotoService.userAgent], service: "wiki.geosearch")
            let places = try Self.parseWikipedia(data, lang: lang)
            if !places.isEmpty { return places }
        }
        return []
    }

    static func parseWikipedia(_ data: Data, lang: String) throws -> [NearbyPlace] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("wikipedia") }
        let items = (json["query"] as? [String: Any])?["geosearch"] as? [[String: Any]] ?? []
        return items.compactMap { item in
            guard let title = item["title"] as? String, let lat = item["lat"] as? Double, let lng = item["lon"] as? Double else { return nil }
            return NearbyPlace(name: title, lat: lat, lng: lng, sources: [.wikipedia], articleLang: lang)
        }
    }

    // MARK: Foursquare search (sem tips)

    func foursquare(lat: Double, lng: Double) async throws -> [NearbyPlace] {
        guard let foursquareKey else { return [] }
        var comps = URLComponents(string: "\(FoursquareTips.base)/places/search")!
        comps.queryItems = [
            URLQueryItem(name: "ll", value: "\(lat),\(lng)"), URLQueryItem(name: "radius", value: "\(Int(Self.radius))"),
            URLQueryItem(name: "sort", value: "POPULARITY"), URLQueryItem(name: "open_now", value: "true"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        let data = try await http.get(comps.url!, headers: ["Authorization": "Bearer \(foursquareKey)",
                                                             "X-Places-Api-Version": FoursquareTips.version, "Accept": "application/json"],
                                      service: "fsq.nearby")
        return try Self.parseFoursquare(data)
    }

    static func parseFoursquare(_ data: Data) throws -> [NearbyPlace] {
        let json = try JSONSerialization.jsonObject(with: data)
        let results = (json as? [String: Any])?["results"] as? [[String: Any]] ?? []
        return results.compactMap { r in
            guard let name = r["name"] as? String, let geo = r["geocodes"] as? [String: Any], let main = geo["main"] as? [String: Any],
                  let lat = main["latitude"] as? Double, let lng = main["longitude"] as? Double else { return nil }
            let rating10 = r["rating"] as? Double
            let category = (r["categories"] as? [[String: Any]])?.first?["name"] as? String
            return NearbyPlace(name: name, lat: lat, lng: lng, sources: [.foursquare],
                               fsqId: (r["fsq_place_id"] as? String) ?? (r["fsq_id"] as? String),
                               rating: rating10.map { $0 / 2 }, openNow: true, category: category, popularity: r["popularity"] as? Double)
        }
    }
}

#if DEBUG
/// Fontes de mentira (`-debugNearby fake`, prints e testes). Conta as chamadas pra provar o cache.
actor FakeNearbyProvider: NearbyProviding {
    private(set) var calls = 0
    let places: [NearbyPlace]
    let complete: Bool

    init(places: [NearbyPlace], complete: Bool = true) {
        self.places = places
        self.complete = complete
    }

    func fetch(lat: Double, lng: Double, region: Region) async -> NearbyFetch {
        calls += 1
        return NearbyFetch(places: places, complete: complete)
    }

    /// Naka-Meguro (18:42), do design Descobrir.png.
    static var samples: [NearbyPlace] {
        [
            NearbyPlace(name: "Starbucks Reserve Roastery Tokyo", lat: 35.6470, lng: 139.6960, sources: [.google], googlePlaceId: "fake-starbucks",
                        rating: 4.5, ratingCount: 23_000, openNow: true, category: "cafe"),
            NearbyPlace(name: "Rio Meguro · passarela", lat: 35.6425, lng: 139.6990, sources: [.wikipedia], articleLang: "pt"),
            NearbyPlace(name: "Blue Bottle Coffee Nakameguro", lat: 35.6436, lng: 139.6993, sources: [.google], googlePlaceId: "fake-bluebottle",
                        rating: 4.3, ratingCount: 2_100, openNow: true, category: "cafe"),
            NearbyPlace(name: "Tsutaya Books Daikanyama", lat: 35.6490, lng: 139.7030, sources: [.foursquare], fsqId: "fake-tsutaya",
                        rating: 4.4, openNow: true, category: "Bookstore", popularity: 0.95),
        ]
    }
}
#endif
