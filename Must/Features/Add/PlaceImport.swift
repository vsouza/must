import CoreLocation
import Foundation
import SwiftData

/// Grava os lugares marcados de um Adicionar (link ou texto colado): mesma regra nos dois fluxos (prompt 18 · E).
/// Extraído do `AddLinkView.save` pra o Colar texto reaproveitar. Só cria os lugares novos (sem `existing`).
@MainActor
enum PlaceImport {
    /// Devolve o `Place` criado por id de resultado (`MatchedPlace.id`).
    @discardableResult
    static func insert(_ matches: [MatchedPlace], included: Set<String>, listChoice: [String: String], lists: [MustList],
                       cityId: String, region: Region, source: Source, sync: SyncCoordinator?, context: ModelContext) -> [String: Place] {
        var created: [String: Place] = [:]
        for match in matches where included.contains(match.id) && match.existing == nil {
            let e = match.extracted
            let list = lists.first { $0.id == listChoice[match.id] } ?? lists.first
            let place = Place(id: "m-\(UUID().uuidString.prefix(8).lowercased())", name: e.name, cityId: cityId, lat: match.lat, lng: match.lng)
            place.nameLocal = e.nameLocal
            place.area = e.area
            place.approx = match.approx
            place.placeId = e.placeId
            place.list = list
            if let sub = e.sub, list?.subs.contains(sub) == true { place.sub = sub }
            place.source = source
            let alias = e.aliases.isEmpty ? "" : " Na legenda: \(e.aliases.joined(separator: ", "))."
            place.notes = (e.hint == "link do Maps" ? "" : "Achado \(e.hint).") + alias
            if let art = e.art {
                place.extra = PlaceExtra(art: art)
                if let p = art.priceAdult { place.price = p }
                if let venue = e.venue { place.nameLocal = place.nameLocal ?? venue }
            }
            context.insert(place)
            // Já conferido no Places: só horário e detalhes. Senão, Text Search perto da cidade.
            let candidate = e.placeId.map { PlaceCandidate(id: $0, name: e.name, address: nil, lat: match.lat, lng: match.lng) }
            sync?.resolveNew(place, candidate: candidate, region: region, context: context)
            created[match.id] = place
        }
        return created
    }
}
