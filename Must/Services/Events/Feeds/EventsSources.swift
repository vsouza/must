import Foundation

/// `data/events-sources.json`: feeds públicos (RSS/Atom) por região, validados um a um (prompt 26 §3, correção do orquestrador:
/// nada de scraping, nada de ler HTML). Feed que cair é ignorado em silêncio.
struct EventsSources: Decodable, Sendable {
    struct Feed: Decodable, Hashable, Sendable, Identifiable {
        var id: String
        var name: String
        var region: String
        var url: URL
        var lang: String?
        /// `events` = todo item é um evento; `agenda`/`guide` = só entra o que cita data.
        var kind: String?
    }

    var feeds: [Feed]
    var ttlHours: Double?
    var maxItemAgeDays: Double?

    static let empty = EventsSources(feeds: [], ttlHours: nil, maxItemAgeDays: nil)

    static func load(bundle: Bundle = .main) -> EventsSources {
        guard let url = bundle.url(forResource: "events-sources", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let sources = try? JSONDecoder().decode(EventsSources.self, from: data) else { return .empty }
        return sources
    }

    func feeds(for region: Region) -> [Feed] { feeds.filter { $0.region == region.rawValue } }

    /// Nome de exibição de uma fonte pelo id do evento (`feed:<fonte>:<hash>`).
    func sourceName(forEventId id: String) -> String? {
        let parts = id.split(separator: ":")
        guard parts.count >= 2, parts[0] == "feed" else { return nil }
        return feeds.first { $0.id == parts[1] }?.name
    }

    var ttl: TimeInterval { (ttlHours ?? 6) * 3600 }
    var maxItemAge: TimeInterval { (maxItemAgeDays ?? 45) * 86_400 }
}
