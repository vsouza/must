import Foundation

/// Cache em disco dos eventos por região, com validade (`expiresAt`, 6 h). Não é SwiftData (correção do orquestrador).
/// `Caches/must-events-<região>.json`; o sistema pode apagar, e a capa continua sem evento.
struct EventsSnapshot: Codable, Sendable, Equatable {
    var region: Region
    var fetchedAt: Date
    var expiresAt: Date
    var events: [ShowEvent]
    /// Dia (yyyy-MM-dd, fuso da região) em que o Haiku leu os feeds desta região. 1×/dia por cidade.
    var haikuDay: String?

    func isFresh(at now: Date) -> Bool { now < expiresAt }
}

struct EventsCache: Sendable {
    var directory: URL

    static let standard = EventsCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0])

    private func file(_ region: Region) -> URL { directory.appending(path: "must-events-\(region.rawValue).json") }

    func read(_ region: Region) -> EventsSnapshot? {
        guard let data = try? Data(contentsOf: file(region)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(EventsSnapshot.self, from: data)
    }

    func write(_ snapshot: EventsSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: file(snapshot.region), options: .atomic)
    }
}

/// Quando o serviço pode ir à rede: 6 h de cache, Wi-Fi, e Modo de Pouco Dados = só cache.
enum EventsFetchPolicy {
    static func shouldFetch(cache: EventsSnapshot?, now: Date, status: Connectivity.Status, wifi: Bool) -> Bool {
        guard status == .online else { return false } // offline ou Pouco Dados: só cache
        if let cache, cache.isFresh(at: now) { return false }
        // No celular só quando nunca houve cache (primeira vez); depois, Wi-Fi.
        return wifi || cache == nil
    }
}
