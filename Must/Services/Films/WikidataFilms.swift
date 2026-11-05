import CoreLocation
import Foundation

/// Filmes gravados (P915) e ambientados (P840) perto de um ponto, pelo SPARQL do Wikidata (sem chave; CC0).
/// Cache primeiro (30 dias, em disco; vazio também), uma consulta por célula por sessão, só com o Lugar aberto.
/// Offline, Modo de Pouco Dados sem permissão ou erro: devolve o cache (ou nada). Nunca lança.
/// Atribuição na UI: "Wikidata · CC0".
final class WikidataFilms: FilmsProviding, @unchecked Sendable {
    static let shared = WikidataFilms()
    static let endpoint = URL(string: "https://query.wikidata.org/sparql")!
    /// Política da Wikimedia pede nome do app + contato; o contato é decisão do Vinicius (TODO(r23:A)).
    static let userAgent = "Must/1.0 (app pessoal; iOS)"

    typealias Fetcher = @Sendable (URL) async throws -> Data

    private let fetch: Fetcher
    private let cache: FilmCache
    private let now: @Sendable () -> Date
    private let session = Session()

    init(cache: FilmCache = .shared, now: @escaping @Sendable () -> Date = { Date() }, fetch: Fetcher? = nil) {
        self.cache = cache
        self.now = now
        self.fetch = fetch ?? { url in
            try await HTTP().get(url, headers: ["User-Agent": WikidataFilms.userAgent, "Accept": "application/sparql-results+json"], service: "wikidata")
        }
    }

    /// Chaves já consultadas nesta sessão (uma vez por lugar por sessão).
    private actor Session {
        private var asked: Set<String> = []
        func first(_ key: String) -> Bool { asked.insert(key).inserted }
    }

    // MARK: FilmsProviding

    func films(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async -> [Film] {
        let key = FilmCache.key(coordinate, radiusKm: radiusKm)
        let cached = await cache.entry(key)
        if let cached, await cache.isFresh(cached, now: now()) { return Self.read(cached.films, near: coordinate, radiusKm: radiusKm) }
        // Vencido ou sem nada: uma tentativa por sessão. Sem rede ou já tentado, fica o que tem.
        guard await session.first(key) else { return Self.read(cached?.films ?? [], near: coordinate, radiusKm: radiusKm) }
        let center = FilmCache.cellCenter(coordinate)
        guard let url = Self.url(center: center, radiusKm: radiusKm + Self.cellSlackKm),
              let data = try? await fetch(url), let fresh = try? Self.parse(data, from: center) else {
            return Self.read(cached?.films ?? [], near: coordinate, radiusKm: radiusKm)
        }
        await cache.store(fresh, key: key, now: now())
        return Self.read(fresh, near: coordinate, radiusKm: radiusKm)
    }

    // MARK: Consulta

    /// Meia diagonal da célula de 0,01°: a consulta sai do centro da célula com essa folga.
    static let cellSlackKm = 0.8

    static func query(center: CLLocationCoordinate2D, radiusKm: Double) -> String {
        // Longitude primeiro no WKT.
        """
        SELECT ?film ?filmLabel ?year ?directorLabel ?loc ?locLabel ?coord ?rel WHERE {
          SERVICE wikibase:around {
            ?loc wdt:P625 ?coord .
            bd:serviceParam wikibase:center "Point(\(center.longitude) \(center.latitude))"^^geo:wktLiteral .
            bd:serviceParam wikibase:radius "\(radiusKm)" .
          }
          { ?film wdt:P915 ?loc . BIND("filmado" AS ?rel) } UNION { ?film wdt:P840 ?loc . BIND("ambientado" AS ?rel) }
          VALUES ?class { wd:Q11424 wd:Q202866 wd:Q24862 wd:Q506240 }
          ?film wdt:P31 ?class .
          OPTIONAL { ?film wdt:P577 ?date . BIND(YEAR(?date) AS ?year) }
          OPTIONAL { ?film wdt:P57 ?director }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "pt,en". }
        } LIMIT 60
        """
    }

    static func url(center: CLLocationCoordinate2D, radiusKm: Double) -> URL? {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "query", value: query(center: center, radiusKm: radiusKm))]
        return c?.url
    }

    // MARK: Resposta

    struct Response: Decodable {
        struct Value: Decodable {
            var value: String
            var lang: String?
            private enum CodingKeys: String, CodingKey { case value, lang = "xml:lang" }
        }
        struct Results: Decodable { var bindings: [[String: Value]] }
        var results: Results
    }

    /// Lê a resposta do SPARQL. Fica só com rótulo em letras latinas (pt/en); título só em japonês é descartado.
    /// Um filme por QID: "filmado" ganha de "ambientado"; entre iguais, o mais perto de `center`.
    static func parse(_ data: Data, from center: CLLocationCoordinate2D) throws -> [CachedFilm] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        // Menor `rank` ganha: filmado antes de ambientado, depois o mais perto.
        var best: [String: (film: CachedFilm, rank: Double)] = [:]
        for row in response.results.bindings {
            guard let entity = row["film"]?.value, let id = entity.split(separator: "/").last.map(String.init), id.hasPrefix("Q"),
                  let title = label(row["filmLabel"]), let point = coordinate(row["coord"]?.value) else { continue }
            let location = label(row["locLabel"])
            let year = row["year"].flatMap { Int($0.value) }
            let meters = CLLocation(latitude: center.latitude, longitude: center.longitude).distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
            let filmado = row["rel"]?.value != "ambientado"
            let film = Film(id: id, title: title, year: year, director: label(row["directorLabel"]), location: location,
                            distanceMeters: nil, url: URL(string: "https://www.wikidata.org/wiki/\(id)"), relation: filmado ? "filmado" : "ambientado")
            let rank = (filmado ? 0 : 1_000_000_000) + meters
            if let old = best[id], old.rank <= rank { continue }
            best[id] = (CachedFilm(film: film, lat: point.latitude, lng: point.longitude), rank)
        }
        return best.values.map(\.film).sorted { $0.film.id < $1.film.id }
    }

    /// Rótulo útil: não é QID (sem rótulo em pt/en o serviço devolve o QID), está em pt/en e não tem ideograma nem kana.
    static func label(_ value: Response.Value?) -> String? {
        guard let value else { return nil }
        let text = value.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.range(of: #"^Q\d+$"#, options: .regularExpression) == nil else { return nil }
        if let lang = value.lang?.lowercased(), !(lang.hasPrefix("pt") || lang.hasPrefix("en")) { return nil }
        let hasCJK = text.unicodeScalars.contains { s in
            (0x3040...0x30FF).contains(s.value) || (0x3400...0x9FFF).contains(s.value) || (0xAC00...0xD7AF).contains(s.value) || (0xFF66...0xFF9F).contains(s.value)
        }
        return hasCJK ? nil : text
    }

    /// "Point(139.69 35.69)" (longitude primeiro).
    static func coordinate(_ wkt: String?) -> CLLocationCoordinate2D? {
        guard let wkt, let open = wkt.firstIndex(of: "("), let close = wkt.lastIndex(of: ")") else { return nil }
        let parts = wkt[wkt.index(after: open)..<close].split(separator: " ").compactMap { Double($0) }
        guard parts.count == 2, (-90...90).contains(parts[1]), (-180...180).contains(parts[0]) else { return nil }
        return CLLocationCoordinate2D(latitude: parts[1], longitude: parts[0])
    }

    /// Filtra pelo raio do ponto real, calcula a distância e ordena: filmados primeiro, depois ambientados; do mais perto ao mais longe.
    static func read(_ cached: [CachedFilm], near coordinate: CLLocationCoordinate2D, radiusKm: Double) -> [Film] {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return cached.compactMap { c -> Film? in
            let meters = here.distance(from: CLLocation(latitude: c.lat, longitude: c.lng))
            guard meters <= radiusKm * 1_000 else { return nil }
            var film = c.film
            film.distanceMeters = meters
            return film
        }.sorted {
            let a = $0.relation == "ambientado" ? 1 : 0, b = $1.relation == "ambientado" ? 1 : 0
            return (a, $0.distanceMeters ?? 0, $0.title) < (b, $1.distanceMeters ?? 0, $1.title)
        }
    }
}
