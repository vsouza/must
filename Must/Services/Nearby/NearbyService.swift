import Foundation

/// Fontes externas do "Por perto". Cada fonte que não tem chave some sem erro; uma que falha marca `complete = false`.
protocol NearbyProviding: Sendable {
    func fetch(lat: Double, lng: Double, region: Region) async -> NearbyFetch
}

/// Google Places Nearby (New) + Wikipedia geosearch + Foursquare search. Sem tips (são pagas).
/// Google é cobrado por chamada: uma rodada por célula a cada 30 min (`NearbyLoader`), contada no `ApiBudget`.
struct NearbyService: NearbyProviding {
    var http = HTTP()
    var googleKey: String? = Secrets.googlePlacesKey
    var foursquareKey: String? = Secrets.foursquareKey

    static let radius: Double = 600
    /// Só tipos que fazem sentido pro roteiro (SKU Pro com `rankPreference` POPULARITY).
    static let includedTypes = ["restaurant", "cafe", "bar", "museum", "tourist_attraction", "park", "book_store", "shopping_mall"]
    /// Campos mínimos: id, nome, local, nota, contagem, aberto agora e tipo.
    static let nearbyMask = "places.id,places.displayName,places.location,places.rating,places.userRatingCount,places.currentOpeningHours.openNow,places.primaryType"
    /// Wikipedia é contexto: no máximo esse tanto na lista, em pt, depois en, e só então ja.
    static let wikiCap = 3
    static let wikiLanguages = ["pt", "en", "ja"]

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
        // Nota e "aberto agora" fazem a chamada ser Pro (cota de 5 mil); o orçamento confere antes.
        let data = try await GoogleAPI.run(.placesPro) {
            try await http.post(URL(string: "https://places.googleapis.com/v1/places:searchNearby")!, json: body,
                                headers: GoogleAPI.headers(key: googleKey, mask: Self.nearbyMask), service: "places.nearby")
        }
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

    // MARK: Wikipedia geosearch (sem chave): contexto, não recomendação

    /// pt, depois en, depois ja; para quando já tem o teto. Cada chamada é gratuita.
    func wikipedia(lat: Double, lng: Double) async throws -> [NearbyPlace] {
        var out: [NearbyPlace] = []
        for lang in Self.wikiLanguages {
            out += try await wikiGeosearch(lang: lang, lat: lat, lng: lng)
            if out.count >= Self.wikiCap { break }
        }
        return Array(out.prefix(Self.wikiCap))
    }

    private func wikiGeosearch(lang: String, lat: Double, lng: Double) async throws -> [NearbyPlace] {
        var comps = URLComponents(string: "https://\(lang).wikipedia.org/w/api.php")!
        comps.queryItems = [
            URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "generator", value: "geosearch"),
            URLQueryItem(name: "ggscoord", value: "\(lat)|\(lng)"), URLQueryItem(name: "ggsradius", value: "\(Int(Self.radius))"),
            URLQueryItem(name: "ggslimit", value: "10"), URLQueryItem(name: "prop", value: "coordinates|extracts"),
            URLQueryItem(name: "colimit", value: "10"), URLQueryItem(name: "exintro", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"), URLQueryItem(name: "exchars", value: "200"),
            URLQueryItem(name: "format", value: "json"),
        ]
        let data = try await http.get(comps.url!, headers: ["User-Agent": CommonsPhotoService.userAgent], service: "wiki.geosearch")
        return try Self.parseWikipedia(data, lang: lang)
    }

    static func parseWikipedia(_ data: Data, lang: String) throws -> [NearbyPlace] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("wikipedia") }
        let pages = (json["query"] as? [String: Any])?["pages"] as? [String: [String: Any]] ?? [:]
        let ordered = pages.values.sorted { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }
        return ordered.compactMap { page in
            guard let title = page["title"] as? String,
                  let coord = (page["coordinates"] as? [[String: Any]])?.first,
                  let lat = coord["lat"] as? Double, let lng = coord["lon"] as? Double else { return nil }
            let extract = (page["extract"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isContextNoise(title: title, extract: extract) else { return nil }
            return NearbyPlace(name: title, lat: lat, lng: lng, sources: [.wikipedia], articleLang: lang,
                               summary: extract.flatMap { $0.isEmpty ? nil : String($0.prefix(160)) })
        }
    }

    /// Estação, bairro/endereço, empresa ou prédio genérico não é "o que fazer aqui": fica fora.
    static let contextNoiseTerms = ["駅", "station", "estação", "丁目", "chome", "ゲートタウン", "gate town", "株式会社", "corporation",
                                    "company", "empresa", "edifício", "edifice", "building", "bairro", "neighbourhood", "neighborhood",
                                    "distrito", "district", "rua ", "avenida"]

    static func isContextNoise(title: String, extract: String?) -> Bool {
        let haystack = (title + " " + String((extract ?? "").prefix(120))).lowercased()
        return contextNoiseTerms.contains { haystack.contains($0) }
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

    /// Naka-Meguro (18:42). Formato dos itens do Google igual ao da resposta real (primaryType, nota, contagem, aberto agora).
    static var samples: [NearbyPlace] {
        [
            NearbyPlace(name: "Starbucks Reserve Roastery Tokyo", lat: 35.6470, lng: 139.6960, sources: [.google], googlePlaceId: "fake-starbucks",
                        rating: 4.5, ratingCount: 23_000, openNow: true, category: "cafe"),
            NearbyPlace(name: "Tsutaya Books Daikanyama", lat: 35.6478, lng: 139.7018, sources: [.google], googlePlaceId: "fake-tsutaya",
                        rating: 4.5, ratingCount: 10_013, openNow: false, category: "book_store"),
            NearbyPlace(name: "Ivy Place", lat: 35.6440, lng: 139.6992, sources: [.google], googlePlaceId: "fake-ivy",
                        rating: 4.2, ratingCount: 3_149, openNow: true, category: "restaurant"),
            NearbyPlace(name: "DAIKANYAMA T-SITE", lat: 35.6486, lng: 139.7018, sources: [.google], googlePlaceId: "fake-tsite",
                        rating: 4.3, ratingCount: 7_695, openNow: true, category: "shopping_mall"),
            NearbyPlace(name: "Blue Bottle Coffee Nakameguro", lat: 35.6436, lng: 139.6993, sources: [.google], googlePlaceId: "fake-bluebottle",
                        rating: 4.3, ratingCount: 2_100, openNow: true, category: "cafe"),
            NearbyPlace(name: "Rio Meguro · passarela", lat: 35.6425, lng: 139.6990, sources: [.wikipedia], articleLang: "pt",
                        summary: "Passarela sobre o Rio Meguro, com as cerejeiras nas margens."),
        ]
    }
}
#endif
