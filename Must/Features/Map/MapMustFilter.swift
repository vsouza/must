import Foundation

/// Filtro por Must no mapa (prompt 27 §2.b, `MapaFiltro.png`): pílulas **Todos N · Eat N · Drink N…** com a contagem do
/// board da região (em memória, sem rede). Uma ou várias; vazio = Todos. Camadas (`MapLayer`) dizem **quando**, o Must diz
/// **o quê**: o filtro só esconde pinos de lugar (hoje, amanhã, sem plano, feitos), nunca o metrô, "você está aqui", a
/// pílula de distância nem os resultados da busca. Fica salvo por região (`map.mustFilter.<regionId>`).
struct MapMustFilter: Equatable, Sendable {
    var listIds: Set<String> = []

    var isAll: Bool { listIds.isEmpty }

    static func key(_ region: Region) -> String { "map.mustFilter.\(region.rawValue)" }

    static func load(_ region: Region, defaults: UserDefaults = .standard) -> MapMustFilter {
        MapMustFilter(listIds: Set(defaults.stringArray(forKey: key(region)) ?? []))
    }

    func save(_ region: Region, defaults: UserDefaults = .standard) {
        if isAll { defaults.removeObject(forKey: Self.key(region)) } else { defaults.set(listIds.sorted(), forKey: Self.key(region)) }
    }

    /// Liga/desliga uma lista. Desligar a última volta pro Todos.
    mutating func toggle(_ listId: String) {
        if listIds.contains(listId) { listIds.remove(listId) } else { listIds.insert(listId) }
    }

    mutating func showAll() { listIds = [] }

    func allows(listId: String?) -> Bool {
        isAll || listId.map(listIds.contains) == true
    }

    /// Camadas de lugar: o resto (metrô é camada de linha, não pino) passa sempre.
    static let filteredLayers: Set<MapLayer> = [.today, .tomorrow, .unplanned, .done]

    /// Pinos depois do filtro. `listOf`: lista de cada lugar (id do `Place` → id da `MustList`).
    func apply(_ pins: [MapPin], listOf: [String: String]) -> [MapPin] {
        guard !isAll else { return pins }
        return pins.filter { pin in
            guard Self.filteredLayers.contains(pin.layer), let placeId = pin.placeId else { return true }
            return allows(listId: listOf[placeId])
        }
    }

    // MARK: Contagem

    struct Count: Identifiable, Hashable, Sendable {
        var id: String
        var label: String
        var count: Int
    }

    /// "Todos 105" e uma pílula por lista com lugar (na ordem do board). `places`: o id da lista de cada lugar.
    static func counts(listIdsOfPlaces places: [String?], lists: [(id: String, name: String)]) -> (total: Int, lists: [Count]) {
        var byList: [String: Int] = [:]
        for id in places { if let id { byList[id, default: 0] += 1 } }
        let pills = lists.compactMap { list -> Count? in
            guard let n = byList[list.id], n > 0 else { return nil }
            return Count(id: list.id, label: label(list.name), count: n)
        }
        return (places.count, pills)
    }

    /// "eat" → "Eat", "must do" → "Do".
    static func label(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        if n.lowercased().hasPrefix("must ") { n = String(n.dropFirst(5)) }
        return n.prefix(1).uppercased() + n.dropFirst()
    }
}
