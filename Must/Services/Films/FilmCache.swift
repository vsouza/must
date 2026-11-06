import CoreLocation
import Foundation

/// Filme guardado com a coordenada do local (a distância é refeita a cada leitura, pra qualquer ponto da mesma célula).
struct CachedFilm: Codable, Hashable, Sendable {
    var film: Film
    var lat: Double
    var lng: Double
}

struct FilmCacheEntry: Codable, Sendable {
    var fetchedAt: Date
    var films: [CachedFilm]
}

/// Cache em disco dos filmes (RODADA-23 · A): `Caches/Films/<célula de ~1 km>-<raio>.json`, 30 dias.
/// Resultado vazio também fica guardado (BH tem pouco), pra não repetir a consulta.
actor FilmCache {
    static let shared = FilmCache()
    static let maxAge: TimeInterval = 30 * 86_400

    private let directory: URL

    init(directory: URL = URL.cachesDirectory.appending(path: "Films", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    /// Célula de ~1,1 km (0,01°) + raio: "-19.92_-43.94-1.5".
    static func key(_ coordinate: CLLocationCoordinate2D, radiusKm: Double) -> String {
        String(format: "%.2f_%.2f-%g", coordinate.latitude, coordinate.longitude, radiusKm)
    }

    /// Centro da célula da chave (é de onde a consulta sai, pra o cache servir qualquer ponto da célula).
    static func cellCenter(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (coordinate.latitude * 100).rounded() / 100, longitude: (coordinate.longitude * 100).rounded() / 100)
    }

    func entry(_ key: String) -> FilmCacheEntry? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? JSONDecoder.films.decode(FilmCacheEntry.self, from: data)
    }

    func isFresh(_ entry: FilmCacheEntry, now: Date = Date()) -> Bool {
        now.timeIntervalSince(entry.fetchedAt) < Self.maxAge
    }

    func store(_ films: [CachedFilm], key: String, now: Date = Date()) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.films.encode(FilmCacheEntry(fetchedAt: now, films: films)) else { return }
        try? data.write(to: file(key), options: .atomic)
    }

    func clear() { try? FileManager.default.removeItem(at: directory) }

    private func file(_ key: String) -> URL { directory.appending(path: "\(key).json") }
}

private extension JSONDecoder {
    static var films: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970; return d }
}

private extension JSONEncoder {
    static var films: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970; return e }
}
