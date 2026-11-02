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

    /// Lista sugerida pelo tipo do lugar (café → coffee, restaurante → eat…); cai na primeira que existir.
    static func suggestedList(for candidate: NearbyCandidate, lists: [MustList]) -> MustList? {
        let role = candidate.role ?? NearbyRanker.role(for: candidate.place)
        let color = NearbyRanker.suggestedColor(candidate.place, role: role)
        return lists.first { $0.color == color && $0.kind == .place } ?? lists.first { $0.color == color } ?? lists.first
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

    /// Frase do porquê, sem modelo: só fatos que a fonte trouxe (até umas poucas palavras).
    static func reason(for place: NearbyPlace) -> String {
        var parts: [String] = []
        if place.popularity.map({ $0 > 0.9 }) == true { parts.append("em alta neste horário") }
        if let rating = place.rating, let count = place.ratingCount, rating >= 4.5, count >= 1000 { parts.append("muito bem avaliado") }
        if let lang = place.articleLang { parts.append("tem artigo em \(lang)") }
        if place.openNow == true { parts.append("aberto agora") }
        return parts.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "perto de você"
    }
}
