import Foundation

// MARK: - Google (Place Details · reviews)

/// Até 5 avaliações + nota. SKU Enterprise + Atmosphere: só quando o usuário rola até as Dicas, nunca no sync.
struct GoogleReviewsTips: TipsProviding {
    var http = HTTP()
    var apiKey: String? = Secrets.googlePlacesKey
    static let mask = "reviews,rating,userRatingCount"

    var source: TipSource { .google }
    var isConfigured: Bool { apiKey != nil }

    func tips(for query: TipsQuery) async throws -> TipsBatch {
        guard let apiKey else { throw ServiceError.missingKey("GOOGLE_PLACES_KEY") }
        guard let placeId = query.googlePlaceId else { return TipsBatch(tips: []) }
        var comps = URLComponents(string: "https://places.googleapis.com/v1/places/\(placeId)")!
        comps.queryItems = [URLQueryItem(name: "languageCode", value: "pt-BR")]
        let data = try await http.get(comps.url!, headers: [
            "X-Goog-Api-Key": apiKey, "X-Goog-FieldMask": Self.mask,
            "X-Ios-Bundle-Identifier": Bundle.main.bundleIdentifier ?? "dev.viniso.must",
        ], service: "places.reviews")
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> TipsBatch {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServiceError.decoding("reviews") }
        let reviews = json["reviews"] as? [[String: Any]] ?? []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tips: [Tip] = reviews.enumerated().compactMap { i, r in
            let text = (r["text"] as? [String: Any])?["text"] as? String
            let original = r["originalText"] as? [String: Any]
            let originalText = original?["text"] as? String
            guard let shown = text ?? originalText, !shown.isEmpty else { return nil }
            let author = r["authorAttribution"] as? [String: Any]
            let published = (r["publishTime"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return Tip(id: (r["name"] as? String) ?? "g\(i)", source: .google, text: shown,
                       originalText: originalText == shown ? nil : originalText,
                       language: original?["languageCode"] as? String ?? (r["text"] as? [String: Any])?["languageCode"] as? String,
                       author: author?["displayName"] as? String, authorURL: author?["uri"] as? String,
                       rating: r["rating"] as? Double, date: published,
                       relativeDate: r["relativePublishTimeDescription"] as? String)
        }
        return TipsBatch(tips: tips, rating: json["rating"] as? Double, ratingCount: json["userRatingCount"] as? Int)
    }
}

// MARK: - Foursquare (Places API · tips)

/// Match por busca perto da coordenada (o `fsq_place_id` fica no `Place`), depois as tips. Tier gratuito.
struct FoursquareTips: TipsProviding {
    var http = HTTP()
    var apiKey: String? = Secrets.foursquareKey
    static let base = "https://places-api.foursquare.com"
    static let version = "2025-06-17"

    var source: TipSource { .foursquare }
    var isConfigured: Bool { apiKey != nil }

    private func headers(_ key: String) -> [String: String] {
        ["Authorization": "Bearer \(key)", "X-Places-Api-Version": Self.version, "Accept": "application/json"]
    }

    func tips(for query: TipsQuery) async throws -> TipsBatch {
        guard let apiKey else { throw ServiceError.missingKey("FOURSQUARE_KEY") }
        var fsqId = query.fsqId
        if fsqId == nil {
            var comps = URLComponents(string: "\(Self.base)/places/search")!
            comps.queryItems = [
                URLQueryItem(name: "query", value: query.name),
                URLQueryItem(name: "ll", value: "\(query.lat),\(query.lng)"),
                URLQueryItem(name: "radius", value: "300"),
                URLQueryItem(name: "limit", value: "5"),
            ]
            let data = try await http.get(comps.url!, headers: headers(apiKey), service: "fsq.search")
            fsqId = Self.bestMatch(data, name: query.name)
        }
        guard let fsqId else { return TipsBatch(tips: []) }
        var comps = URLComponents(string: "\(Self.base)/places/\(fsqId)/tips")!
        comps.queryItems = [URLQueryItem(name: "limit", value: "10"), URLQueryItem(name: "sort", value: "POPULAR")]
        let data = try await http.get(comps.url!, headers: headers(apiKey), service: "fsq.tips")
        var batch = try Self.parseTips(data)
        batch.fsqId = fsqId
        return batch
    }

    static func bestMatch(_ data: Data, name: String) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }
        let exact = results.first { ($0["name"] as? String).map { PlaceMatcher.similar($0, name) } ?? false }
        return (exact ?? results.first)?["fsq_place_id"] as? String ?? (exact ?? results.first)?["fsq_id"] as? String
    }

    static func parseTips(_ data: Data) throws -> TipsBatch {
        let any = try JSONSerialization.jsonObject(with: data)
        let list = (any as? [[String: Any]]) ?? ((any as? [String: Any])?["results"] as? [[String: Any]]) ?? []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tips = list.compactMap { t -> Tip? in
            guard let text = t["text"] as? String, !text.isEmpty else { return nil }
            let created = (t["created_at"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return Tip(id: t["id"] as? String ?? UUID().uuidString, source: .foursquare, text: text,
                       language: t["lang"] as? String, votes: t["agree_count"] as? Int, date: created)
        }
        return TipsBatch(tips: tips)
    }
}

// MARK: - Reddit (OAuth installed app)

/// Busca o nome do lugar nos subreddits da região e pega os 3 comentários mais votados que citam o nome.
/// Sem `REDDIT_CLIENT_ID`, a fonte é pulada sem erro.
struct RedditTips: TipsProviding {
    var http = HTTP()
    var clientId: String? = Secrets.redditClientId
    static let userAgent = "ios:dev.viniso.must:1.0 (app pessoal)"

    var source: TipSource { .reddit }
    var isConfigured: Bool { clientId != nil }

    static func subreddits(_ region: Region) -> [String] {
        region.profile.day?.subreddits ?? []
    }

    func tips(for query: TipsQuery) async throws -> TipsBatch {
        guard let clientId else { return TipsBatch(tips: []) }
        let token = try await RedditToken.shared.token(clientId: clientId, http: http)
        let headers = ["Authorization": "Bearer \(token)", "User-Agent": Self.userAgent]
        var comps = URLComponents(string: "https://oauth.reddit.com/r/\(Self.subreddits(query.region).joined(separator: "+"))/search")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: "\"\(query.name)\" \(query.city)"),
            URLQueryItem(name: "restrict_sr", value: "1"),
            URLQueryItem(name: "sort", value: "relevance"),
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "raw_json", value: "1"),
        ]
        let search = try await http.get(comps.url!, headers: headers, service: "reddit.search")
        let threads = Self.threadIds(search).prefix(4)
        var comments: [Tip] = []
        for (id, subreddit) in threads {
            var c = URLComponents(string: "https://oauth.reddit.com/comments/\(id)")!
            c.queryItems = [URLQueryItem(name: "sort", value: "top"), URLQueryItem(name: "limit", value: "60"),
                            URLQueryItem(name: "depth", value: "2"), URLQueryItem(name: "raw_json", value: "1")]
            guard let data = try? await http.get(c.url!, headers: headers, service: "reddit.comments") else { continue }
            comments += Self.comments(data, mentioning: [query.name, query.nameLocal].compactMap { $0 }, subreddit: subreddit)
        }
        let top = comments.sorted { ($0.votes ?? 0) > ($1.votes ?? 0) }.prefix(3)
        return TipsBatch(tips: Array(top))
    }

    static func threadIds(_ data: Data) -> [(String, String)] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let children = (json["data"] as? [String: Any])?["children"] as? [[String: Any]] else { return [] }
        return children.compactMap { child in
            guard let d = child["data"] as? [String: Any], let id = d["id"] as? String else { return nil }
            return (id, d["subreddit"] as? String ?? "")
        }
    }

    static func comments(_ data: Data, mentioning names: [String], subreddit: String) -> [Tip] {
        guard let listings = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], listings.count > 1 else { return [] }
        let keys = names.map { PlaceMatcher.normalize($0) }.filter { !$0.isEmpty }
        var out: [Tip] = []
        func walk(_ listing: [String: Any]?) {
            let children = (listing?["data"] as? [String: Any])?["children"] as? [[String: Any]] ?? []
            for child in children where child["kind"] as? String == "t1" {
                guard let d = child["data"] as? [String: Any], let body = d["body"] as? String else { continue }
                let normalized = PlaceMatcher.normalize(body)
                if keys.contains(where: { normalized.contains($0) }) {
                    out.append(Tip(id: d["name"] as? String ?? UUID().uuidString, source: .reddit, text: body,
                                   author: (d["author"] as? String).map { "u/\($0)" }, votes: d["score"] as? Int,
                                   date: (d["created_utc"] as? Double).map { Date(timeIntervalSince1970: $0) },
                                   subreddit: subreddit, url: (d["permalink"] as? String).map { "https://www.reddit.com\($0)" }))
                }
                walk(d["replies"] as? [String: Any])
            }
        }
        walk(listings[1])
        return out
    }
}

/// Token "installed app" (sem usuário), guardado em memória até expirar.
actor RedditToken {
    static let shared = RedditToken()
    private var value: String?
    private var expires = Date.distantPast
    private let deviceId = UUID().uuidString

    func token(clientId: String, http: HTTP) async throws -> String {
        if let value, expires > Date() { return value }
        var request = URLRequest(url: URL(string: "https://www.reddit.com/api/v1/access_token")!)
        request.httpMethod = "POST"
        let basic = Data("\(clientId):".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue(RedditTips.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=https://oauth.reddit.com/grants/installed_client&device_id=\(deviceId)".utf8)
        guard DevOverrides.liveData else { throw ServiceError.liveDataOff }
        let (data, response) = try await http.session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        Log.network.info("reddit.token POST → \(code)")
        guard (200..<300).contains(code),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else { throw ServiceError.http(code, String(data: data, encoding: .utf8) ?? "") }
        value = token
        expires = Date().addingTimeInterval((json["expires_in"] as? Double ?? 3600) - 60)
        return token
    }
}
