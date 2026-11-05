import Foundation

/// Um lugar do board visto pela Coleção: feito (com colecionável) ou "a fazer".
struct CollectionSlot: Identifiable, Hashable, Sendable {
    var placeId: String
    var name: String
    var cityId: String
    var cityName: String
    var listId: String
    var listName: String
    var collectible: Collectible?
    var id: String { placeId }
}

/// Seção da página Coleção: "Tóquio 14 de 52".
struct CollectionSection: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var done: [Collectible]
    /// Total de lugares da seção (nil na visão por data, que não tem "de N").
    var total: Int?
    /// Os primeiros "a fazer" (pra mostrar o que falta).
    var todo: [CollectionSlot]
}

enum CollectionGrouping {
    static let todoPerSection = 2

    /// Agrupa por cidade, lista ou data. Feitos do mais novo (maior nº) pro mais antigo; seções com mais feitos primeiro.
    /// `hidden` some da grade; a vitrine é montada à parte (`showcase`).
    static func sections(_ slots: [CollectionSlot], by group: CollectionPrefs.Group, hidden: Set<String> = [],
                         timeZone: TimeZone = .current) -> [CollectionSection] {
        let visible = slots.filter { !hidden.contains($0.placeId) }
        switch group {
        case .city: return build(visible, key: { ($0.cityId.hasPrefix("tokyo") ? "tokyo" : $0.cityId, $0.cityName) })
        case .list: return build(visible, key: { ($0.listId, $0.listName) })
        case .date:
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            let doneSlots = visible.filter { $0.collectible != nil }
            let byDay = Dictionary(grouping: doneSlots) { cal.startOfDay(for: $0.collectible!.doneAt) }
            return byDay.keys.sorted(by: >).map { day in
                let items = (byDay[day] ?? []).compactMap(\.collectible).sorted { $0.order > $1.order }
                return CollectionSection(id: "d\(Int(day.timeIntervalSince1970))",
                                         title: CollectibleText.dateLabel(day, timeZoneId: timeZone.identifier, withYear: false),
                                         done: items, total: nil, todo: [])
            }
        }
    }

    private static func build(_ slots: [CollectionSlot], key: (CollectionSlot) -> (String, String)) -> [CollectionSection] {
        var order: [String] = []
        var groups: [String: [CollectionSlot]] = [:]
        var titles: [String: String] = [:]
        for slot in slots {
            let (id, title) = key(slot)
            if groups[id] == nil { order.append(id); titles[id] = title }
            groups[id, default: []].append(slot)
        }
        let result = order.map { id -> CollectionSection in
            let members = groups[id] ?? []
            let done = members.compactMap(\.collectible).sorted { $0.order > $1.order }
            let todo = members.filter { $0.collectible == nil }.sorted { $0.name < $1.name }.prefix(todoPerSection)
            return CollectionSection(id: id, title: titles[id] ?? id, done: done, total: members.count, todo: Array(todo))
        }
        return result.enumerated()
            .sorted { a, b in a.element.done.count != b.element.done.count ? a.element.done.count > b.element.done.count : a.offset < b.offset }
            .map(\.element)
    }

    /// Vitrine: os fixados (até 3, na ordem em que foram fixados) que ainda são feitos e não estão escondidos.
    static func showcase(_ slots: [CollectionSlot], pinned: [String], hidden: Set<String> = []) -> [Collectible] {
        let byId = Dictionary(uniqueKeysWithValues: slots.compactMap { s in s.collectible.map { (s.placeId, $0) } })
        return pinned.compactMap { hidden.contains($0) ? nil : byId[$0] }.prefix(CollectionPrefs.maxPinned).map { $0 }
    }
}
