import CoreLocation
import Foundation
import SwiftData

/// Resultado de casar um nome extraído com o board.
struct MatchedPlace: Identifiable {
    enum Kind {
        /// Já está no board.
        case existing(Place)
        /// Lugar novo (coordenada aproximada até a sincronização com o Places).
        case new
    }

    var extracted: ExtractedPlace
    var kind: Kind
    var lat: Double
    var lng: Double
    var approx: Bool
    /// Lista sugerida.
    var suggestedListId: String?

    var id: String { extracted.id }

    var existing: Place? { if case .existing(let p) = kind { p } else { nil } }
}

/// (d) Casa os nomes com o board. O prompt 07 acrescenta o Places Text Search restrito à cidade.
@MainActor
enum PlaceMatcher {
    static func match(_ extracted: [ExtractedPlace], caption: Caption, places: [Place], lists: [MustList],
                      city: City?, region: Region) -> [MatchedPlace] {
        extracted.map { item in
            let suggested = suggestList(for: item, lists: lists)
            if let place = places.first(where: { similar($0.name, item.name) || ($0.nameLocal != nil && $0.nameLocal == item.nameLocal) }) {
                return MatchedPlace(extracted: item, kind: .existing(place), lat: place.lat, lng: place.lng, approx: place.approx,
                                    suggestedListId: place.list?.id ?? suggested)
            }
            if let lat = caption.lat, let lng = caption.lng {
                return MatchedPlace(extracted: item, kind: .new, lat: lat, lng: lng, approx: false, suggestedListId: suggested)
            }
            let center = city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
            return MatchedPlace(extracted: item, kind: .new, lat: center.latitude, lng: center.longitude, approx: true,
                                suggestedListId: suggested)
        }
    }

    static func suggestList(for item: ExtractedPlace, lists: [MustList]) -> String? {
        if let sub = item.sub, let list = lists.first(where: { $0.subs.contains(sub) }) { return list.id }
        if let color = item.category, let list = lists.first(where: { $0.color == color }) { return list.id }
        // café sem lista "coffee": cai na lista com sub "Café".
        if item.category == .coffee, let list = lists.first(where: { $0.subs.contains("Café") }) { return list.id }
        return lists.first?.id
    }

    /// Mesmo nome, ignorando caixa, acento e pontuação, ou um contido no outro (≥ 5 letras).
    static func similar(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }
        let (short, long) = na.count < nb.count ? (na, nb) : (nb, na)
        return short.count >= 5 && long.contains(short)
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }
}
