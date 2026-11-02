import CoreLocation
import Foundation
import SwiftData

/// Liga o board (SwiftData) e o cache de "por perto" no ranking. Sem rede: a chamada real fica no `NearbyLoader`.
@MainActor
enum DiscoverBuilder {
    static func boardCandidates(_ places: [Place], origin: CLLocation, now: Date, region: Region) -> [NearbyCandidate] {
        places.compactMap { place -> NearbyCandidate? in
            guard let list = place.list else { return nil }
            let open: Bool?
            switch place.openState(at: now, timeZone: region.timeZone) {
            case .open: open = true
            case .closed: open = false
            case .unknown: open = nil
            }
            return NearbyCandidates.board(id: place.id, name: place.name, lat: place.lat, lng: place.lng, openNow: open,
                                          listId: list.id, listName: list.displayName, role: StopRole(kind: list.kind, color: list.color),
                                          isDone: place.isDone, isExperience: list.kind == .experience, origin: origin)
        }
    }

    /// Board + cache, já ranqueado (dentro de 600 m).
    static func ranked(batch: NearbyBatch?, places: [Place], origin: CLLocation, now: Date, region: Region) -> [NearbyScored] {
        let hour = region.calendar.component(.hour, from: now)
        let candidates = boardCandidates(places, origin: origin, now: now, region: region)
            + NearbyCandidates.external(batch?.places ?? [], origin: origin)
        return NearbyRanker.rank(candidates, hour: hour)
    }

    /// O melhor item fora do board, com score alto e a menos de 600 m: a linha "Por perto:" da Home.
    static func hint(batch: NearbyBatch?, places: [Place], origin: CLLocation, now: Date, region: Region) -> NearbyScored? {
        ranked(batch: batch, places: places, origin: origin, now: now, region: region).first { item in
            !item.candidate.isOnBoard && item.score >= NearbyRanker.highScore && item.candidate.distance < NearbyRanker.radius
        }
    }

    /// Lista sugerida pela categoria (restaurante → eat, café → drink, museu → art…). `nil` quando não há categoria clara.
    static func suggestedList(for candidate: NearbyCandidate, lists: [MustList]) -> MustList? {
        guard let id = NearbyRanker.suggestedListId(candidate.place) else { return nil }
        return lists.first { $0.id == id }
    }

    /// "+ Must": cria o lugar no board com o placeId que a fonte já deu.
    @discardableResult
    static func addToBoard(_ candidate: NearbyCandidate, list: MustList, region: Region, now: Date, context: ModelContext) -> Place {
        let trip = (try? context.fetch(FetchDescriptor<TripInfo>()))?.first
        let cityId = trip?.city(on: now, calendar: region.calendar)?.id ?? trip?.cities.first?.id ?? (region == .jp ? "tokyo1" : "bh")
        let place = Place(id: "n-\(UUID().uuidString.prefix(8).lowercased())", name: candidate.place.name, cityId: cityId,
                          lat: candidate.place.lat, lng: candidate.place.lng)
        place.list = list
        place.order = (list.places.map(\.order).max() ?? 0) + 1
        place.placeId = candidate.place.googlePlaceId
        place.fsqId = candidate.place.fsqId
        place.source = Source(kind: .manual, url: nil, savedAt: nil)
        context.insert(place)
        try? context.save()
        return place
    }

    /// Frase do hero em serif, só quando há algo útil: o começo do extrato da Wikipedia, ou nota alta com muitas avaliações.
    /// Sem nada útil, `nil` (a frase some).
    static func phrase(for place: NearbyPlace) -> String? {
        if let summary = place.summary, !summary.isEmpty { return summary }
        if let rating = place.rating, let count = place.ratingCount, rating >= 4.5, count >= 1000 { return "muito bem avaliado aqui perto" }
        return nil
    }
}
