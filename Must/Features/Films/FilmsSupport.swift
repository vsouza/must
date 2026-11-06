import CoreLocation
import Foundation

/// Textos puros e memória de sessão da UI de Filmes (prompt 27 §6). Os dados vêm do `FilmsProviding` (cache de 30 dias).
enum FilmsFormat {
    /// "250 m", "3,1 km".
    static func distance(_ meters: Double?) -> String? {
        guard let meters else { return nil }
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return String(format: "%.1f km", meters / 1000).replacingOccurrences(of: ".", with: ",")
    }

    /// Últimos dois dígitos do ano ("03") pro numeral da capa tipográfica; "—" sem ano.
    static func yearDigits(_ year: Int?) -> String {
        guard let year else { return "—" }
        return String(format: "%02d", year % 100)
    }

    /// "2003 · Sofia Coppola".
    static func credit(_ film: Film) -> String {
        [film.year.map(String.init), film.director].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Park Hyatt Tokyo · 250 m".
    static func place(_ film: Film) -> String {
        [film.location, distance(film.distanceMeters)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Mais perto primeiro; sem distância no fim; mesmo filme no mesmo lugar só uma vez.
    static func ordered(_ films: [Film]) -> [Film] {
        var seen = Set<String>()
        return films
            .sorted { ($0.distanceMeters ?? .infinity) < ($1.distanceMeters ?? .infinity) }
            .filter { seen.insert("\($0.id)|\($0.location ?? "")").inserted }
    }
}

/// Uma consulta por lugar por sessão (e por raio): voltar ao Lugar não repete a chamada. O provedor ainda guarda o
/// cache de 30 dias em disco; isto só evita refazer a leitura enquanto o app está aberto.
@MainActor
enum FilmsSessionMemo {
    private static var store: [String: [Film]] = [:]

    static func key(_ id: String, radiusKm: Double) -> String { "\(id)|\(radiusKm)" }
    static func get(_ key: String) -> [Film]? { store[key] }
    static func set(_ key: String, _ films: [Film]) { store[key] = films }
    static func reset() { store.removeAll() }
}

#if DEBUG
/// Filmes de exemplo só pra prints (`-debugScreen filmes | lugar-amigos`), no Japão; BH fica vazio (`FilmesVazio.png`).
struct SampleFilms: FilmsProviding {
    var base: any FilmsProviding
    var region: Region

    static var enabled: Bool {
        let screen = DebugFlags.string("debugScreen") ?? ""
        return screen.hasPrefix("filmes") || screen.hasPrefix("lugar-amigos")
    }

    func films(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async -> [Film] {
        let real = await base.films(near: coordinate, radiusKm: radiusKm)
        guard real.isEmpty, region == .jp else { return real }
        return [
            Film(id: "Q1", title: "Lost in Translation", year: 2003, director: "Sofia Coppola", location: "Park Hyatt Tokyo", distanceMeters: 250),
            Film(id: "Q2", title: "Perfect Days", year: 2023, director: "Wim Wenders", location: "Banheiros públicos de Shibuya", distanceMeters: 3100),
            Film(id: "Q3", title: "Your Name.", year: 2016, director: "Makoto Shinkai", location: "Santuário Suga, Yotsuya", distanceMeters: 2400),
            Film(id: "Q1", title: "Lost in Translation", year: 2003, director: "Sofia Coppola", location: "Cruzamento de Shibuya", distanceMeters: 3000),
        ]
    }
}
#endif

enum FilmsProvider {
    static func resolve(_ base: any FilmsProviding, region: Region) -> any FilmsProviding {
        #if DEBUG
        SampleFilms.enabled ? SampleFilms(base: base, region: region) : base
        #else
        base
        #endif
    }
}
