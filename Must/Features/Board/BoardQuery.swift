import Foundation
import SwiftData

// Lógica do Board: o que aparece, em que grupo e em que ordem. Pura (sem view), pra testar.

/// Chips de filtro (um por vez). "Fica pro fim" segue o hub: só o que ainda não foi feito.
enum BoardFilter: String, CaseIterable, Identifiable, Sendable {
    case noHours, saveForEnd, done

    var id: String { rawValue }

    var label: String {
        switch self {
        case .noHours: "Sem horário"
        case .saveForEnd: "Fica pro fim"
        case .done: "Feitos"
        }
    }

    @MainActor
    func accepts(_ place: Place) -> Bool {
        switch self {
        case .noHours: place.hours?.hasPeriods != true
        case .saveForEnd: place.saveForEnd && !place.isDone
        case .done: place.isDone
        }
    }
}

enum BoardGrouping: String, CaseIterable, Sendable {
    case list, city

    var label: String {
        switch self {
        case .list: "Por lista"
        case .city: "Cidade"
        }
    }
}

/// Ordem dentro do grupo. `manual` é a do board (a que o arrastar muda).
enum BoardSort: String, CaseIterable, Identifiable, Sendable {
    case manual, name, added, price

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "ordem"
        case .name: "A–Z"
        case .added: "adicionado"
        case .price: "preço"
        }
    }

    var next: BoardSort {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// Um grupo da tela: uma lista (com sub-listas) ou uma cidade.
struct BoardGroup: Identifiable {
    let id: String
    let title: String
    /// Lista de origem; `nil` quando agrupado por cidade (não recebe arrasto nem "editar lista").
    let list: MustList?
    let color: MustColor
    let places: [Place]
    /// "Ramen 9", "Sushi 7" — só do que está visível.
    let subCounts: [SubCount]

    struct SubCount: Equatable {
        let name: String
        let count: Int
    }
}

struct BoardQuery {
    var text = ""
    var filter: BoardFilter?
    var grouping: BoardGrouping = .list
    var sort: BoardSort = .manual

    /// Busca ou filtro ligado: a lista mostra tudo (sem "+ N em …") e grupos vazios somem.
    var isFiltering: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty || filter != nil }

    @MainActor
    func groups(places: [Place], lists: [MustList], trip: TripInfo?, region: Region) -> [BoardGroup] {
        let visible = Self.sorted(places.filter(accepts), by: sort)
        var result: [BoardGroup] = []
        switch grouping {
        case .list:
            for list in lists.sorted(by: { $0.order < $1.order }) {
                let items = visible.filter { $0.list?.id == list.id }
                if isFiltering && items.isEmpty { continue }
                let subs = list.subs.compactMap { sub -> BoardGroup.SubCount? in
                    let n = items.filter { $0.sub == sub }.count
                    return n > 0 ? .init(name: sub, count: n) : nil
                }
                result.append(BoardGroup(id: "list:\(list.id)", title: list.displayName, list: list, color: list.color,
                                         places: items, subCounts: subs))
            }
        case .city:
            let cities = trip?.cities ?? []
            var ids = cities.map(\.id)
            for place in visible where !ids.contains(place.cityId) { ids.append(place.cityId) }
            for id in ids {
                let items = visible.filter { $0.cityId == id }
                if items.isEmpty { continue }
                let city = cities.first { $0.id == id }
                let title = city.flatMap { trip?.label(for: $0, region: region) } ?? city?.name ?? id
                result.append(BoardGroup(id: "city:\(id)", title: title, list: nil, color: region.color,
                                         places: items, subCounts: []))
            }
        }
        return result
    }

    /// Quantos lugares o filtro pega (pro número do chip).
    @MainActor
    static func count(_ filter: BoardFilter, in places: [Place]) -> Int {
        places.filter(filter.accepts).count
    }

    /// Busca em nome, nome local, bairro, notas e fonte ("Reel", autor). Sem acento e sem caixa.
    @MainActor
    func accepts(_ place: Place) -> Bool {
        if let filter, !filter.accepts(place) { return false }
        let needle = Self.fold(text.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return true }
        let haystack = [place.name, place.nameLocal ?? "", place.area ?? "", place.notes,
                        place.source?.kind.label ?? "", place.source?.author ?? ""].joined(separator: " ")
        return Self.fold(haystack).contains(needle)
    }

    @MainActor
    static func sorted(_ places: [Place], by sort: BoardSort) -> [Place] {
        switch sort {
        case .manual:
            return places.sorted(by: BoardEdits.manualOrder)
        case .name:
            return places.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .added:
            // `savedAt` é "yyyy-MM-dd": o mais recente primeiro.
            return places.sorted { a, b in
                let sa = a.source?.savedAt ?? "", sb = b.source?.savedAt ?? ""
                if sa != sb { return sa > sb }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
        case .price:
            // Sem preço vai pro fim.
            return places.sorted { a, b in
                switch (a.price, b.price) {
                case let (x?, y?) where x != y: return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.name.localizedCompare(b.name) == .orderedAscending
                }
            }
        }
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }
}
