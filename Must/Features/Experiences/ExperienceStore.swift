import Foundation
import SwiftData

/// Lista "Must do" e a gravação de uma experiência colada (prompt 14 · C, item 9).
@MainActor
enum ExperienceStore {
    /// A lista do tipo experiência do board; cria "Must do" se ainda não existir.
    static func list(in context: ModelContext) -> MustList {
        let lists = (try? context.fetch(FetchDescriptor<MustList>(sortBy: [SortDescriptor(\.order)]))) ?? []
        if let found = lists.first(where: { $0.kind == .experience }) { return found }
        let id = lists.contains { $0.id == "exp" } ? "exp-\(UUID().uuidString.prefix(6).lowercased())" : "exp"
        let list = MustList(id: id, name: "do", kanji: "体験", icon: .mustsLista, color: .night,
                            order: (lists.map(\.order).max() ?? 0) + 1, kind: .experience)
        context.insert(list)
        return list
    }

    /// Grava a experiência como lugar do tipo experiência na Must do. O link não traz ponto no mapa:
    /// a coordenada é a do centro da região e o lugar fica marcado como aproximado.
    @discardableResult
    static func add(_ draft: ExperienceDraft, region: Region, context: ModelContext) -> Place {
        let list = list(in: context)
        let trip = (try? context.fetch(FetchDescriptor<TripInfo>()))?.first
        let cityId = draft.session.flatMap { trip?.city(on: $0.at, calendar: region.calendar)?.id }
            ?? trip?.cities.first?.id ?? region.trip.cities.first?.id ?? ""
        let center = region.defaultCenter
        let place = Place(id: "x-\(UUID().uuidString.prefix(8).lowercased())", name: draft.name, cityId: cityId,
                          lat: center.latitude, lng: center.longitude)
        place.approx = true
        place.list = list
        place.order = (list.places.map(\.order).max() ?? 0) + 1
        // O preço do link é "a partir de"; só entra no orçamento quando está na moeda da região.
        place.price = draft.info.currency == nil ? draft.info.priceFrom : nil
        var info = draft.info
        if let session = draft.session { info.sessions = [session] }
        place.extra = PlaceExtra(experience: info)
        place.source = Source(kind: .manual, url: info.url?.absoluteString, savedAt: nil)
        context.insert(place)
        try? context.save()
        return place
    }
}
