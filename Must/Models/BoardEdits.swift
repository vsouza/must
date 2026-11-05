import Foundation
import SwiftData

/// Edições do Board sobre o modelo local: mover, ordenar, ação em lote, apagar, editar lista.
/// Só SwiftData — nada aqui fala com a rede. Cada função grava no fim.
@MainActor
enum BoardEdits {
    enum EditError: LocalizedError {
        case needsTarget

        var errorDescription: String? {
            "Escolhe pra qual lista levar os lugares antes de apagar a lista."
        }
    }

    /// Ordem do board: `order`, e o nome pra desempatar.
    static func manualOrder(_ a: Place, _ b: Place) -> Bool {
        if a.order != b.order { return a.order < b.order }
        return a.name.localizedCompare(b.name) == .orderedAscending
    }

    // MARK: Lugares

    /// Leva os lugares pro fim de `target`, na ordem em que estavam. Nome, notas, reserva, 済, gastos e
    /// horário ficam como estão. O `sub` some: ele é da lista de origem (Ramen não existe em "drink").
    static func move(_ places: [Place], to target: MustList, context: ModelContext) throws {
        let moving = places.filter { $0.list?.id != target.id }.sorted(by: manualOrder)
        guard !moving.isEmpty else { return }
        let movingIds = Set(moving.map(\.id))
        let stay = target.places.filter { !movingIds.contains($0.id) }.sorted(by: manualOrder)
        for place in moving {
            place.list = target
            place.sub = nil
        }
        renumber(stay + moving)
        try context.save()
    }

    /// Arrastar dentro da lista. `places` vem na ordem da tela; `from`/`to` são os do `onMove`.
    static func reorder(_ places: [Place], from source: IndexSet, to destination: Int, context: ModelContext) throws {
        var sequence = places
        let indices = source.sorted()
        let moved = indices.map { sequence[$0] }
        for index in indices.reversed() { sequence.remove(at: index) }
        let removedBefore = indices.filter { $0 < destination }.count
        sequence.insert(contentsOf: moved, at: destination - removedBefore)
        renumber(sequence)
        try context.save()
    }

    static func setSaveForEnd(_ places: [Place], on: Bool, context: ModelContext) throws {
        for place in places { place.saveForEnd = on }
        try context.save()
    }

    static func setCity(_ places: [Place], cityId: String, context: ModelContext) throws {
        for place in places { place.cityId = cityId }
        try context.save()
    }

    /// "Resolver no Places": marca o pedido; a sincronização (Ajustes › Dados) resolve até 50 por vez.
    static func queueResolve(_ places: [Place], context: ModelContext) throws {
        for place in places { place.resolveQueued = true }
        try context.save()
    }

    static func delete(_ places: [Place], context: ModelContext) throws {
        for place in places { context.delete(place) }
        try context.save()
    }

    // MARK: Listas

    /// Sobe (−1) ou desce (+1) a lista no hub e no board. A ordem vira 0…n−1, sem buracos.
    static func moveList(_ list: MustList, by offset: Int, in lists: [MustList], context: ModelContext) throws {
        var sequence = lists.sorted { $0.order < $1.order }
        guard let from = sequence.firstIndex(where: { $0.id == list.id }) else { return }
        let to = min(max(0, from + offset), sequence.count - 1)
        guard to != from else { return }
        let item = sequence.remove(at: from)
        sequence.insert(item, at: to)
        for (index, each) in sequence.enumerated() { each.order = index }
        try context.save()
    }

    /// Salva nome, kanji, ícone, cor, foto e sub-listas. Sub tirada da lista deixa os lugares sem sub.
    /// O `id` não muda (é a chave dos seeds e dos links `must://`).
    static func saveList(_ list: MustList, name: String, kanji: String?, icon: MustIcon, color: MustColor,
                         photo: ListPhoto?, changePhoto: Bool, subs: [String], context: ModelContext) throws {
        let removed = Set(list.subs).subtracting(subs)
        list.name = name
        list.kanji = kanji
        list.icon = icon
        list.color = color
        if changePhoto {
            list.photo = photo
            // Escolhida à mão vale sempre; tirar a foto volta pra capa automática (`ListCover`).
            ListCover.mark(list, chosen: photo != nil, context: context)
        }
        for place in list.places where place.sub.map({ removed.contains($0) }) == true {
            place.sub = nil
        }
        list.subs = subs
        try context.save()
    }

    /// Apaga a lista. Com lugares, eles vão pra `target` antes (nada some junto).
    static func deleteList(_ list: MustList, moveTo target: MustList?, lists: [MustList], context: ModelContext) throws {
        let items = list.places
        if !items.isEmpty {
            guard let target, target.id != list.id else { throw EditError.needsTarget }
            try move(items, to: target, context: context)
        }
        context.delete(list)
        let rest = lists.filter { $0.id != list.id }.sorted { $0.order < $1.order }
        for (index, each) in rest.enumerated() { each.order = index }
        try context.save()
    }

    // MARK: Helpers

    private static func renumber(_ places: [Place]) {
        for (index, place) in places.enumerated() { place.order = index }
    }
}
