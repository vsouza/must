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
    /// Horário e preço do Places (só quando conferido).
    var details: PlaceDetails? = nil

    var id: String { extracted.id }

    var existing: Place? { if case .existing(let p) = kind { p } else { nil } }

    /// Tem coordenada real (Places ou link do Maps): aparece no mapa e vem marcado.
    var located: Bool { !approx }
}

/// (d) Casa os nomes com o board (por placeId ou nome + distância) e sugere a lista.
@MainActor
enum PlaceMatcher {
    static func match(_ extracted: [ExtractedPlace], places: [Place], lists: [MustList], city: City?, region: Region,
                      details: [String: PlaceDetails] = [:]) -> [MatchedPlace] {
        extracted.map { item in
            let suggested = suggestList(for: item, lists: lists)
            let detail = item.placeId.flatMap { details[$0] }
            if let place = existingPlace(for: item, in: places) {
                // Board com coordenada chute e o Places achou o lugar: mostra no mapa pela posição do Places.
                if place.approx, let lat = item.lat, let lng = item.lng {
                    return MatchedPlace(extracted: item, kind: .existing(place), lat: lat, lng: lng, approx: false,
                                        suggestedListId: place.list?.id ?? suggested, details: detail)
                }
                return MatchedPlace(extracted: item, kind: .existing(place), lat: place.lat, lng: place.lng, approx: place.approx,
                                    suggestedListId: place.list?.id ?? suggested, details: detail)
            }
            if let lat = item.lat, let lng = item.lng {
                return MatchedPlace(extracted: item, kind: .new, lat: lat, lng: lng, approx: false, suggestedListId: suggested, details: detail)
            }
            let center = city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
            return MatchedPlace(extracted: item, kind: .new, lat: center.latitude, lng: center.longitude, approx: true,
                                suggestedListId: suggested, details: detail)
        }
    }

    /// Mesmo placeId; senão nome parecido (ou nome local igual) a até 300 m, se o candidato tem coordenada.
    /// Lugar do board com coordenada aproximada (seed `approx`) aceita até 2 km: a posição dele ainda é chute.
    static func existingPlace(for item: ExtractedPlace, in places: [Place]) -> Place? {
        if let id = item.placeId, let hit = places.first(where: { $0.placeId == id }) { return hit }
        return places.first { place in
            let sameName = similar(place.name, item.name)
                || (place.nameLocal != nil && place.nameLocal == item.nameLocal)
            guard sameName else { return false }
            guard let lat = item.lat, let lng = item.lng else { return true }
            let here = CLLocation(latitude: lat, longitude: lng)
            let limit: CLLocationDistance = place.approx ? 2_000 : 300
            return here.distance(from: CLLocation(latitude: place.lat, longitude: place.lng)) < limit
        }
    }

    static func suggestList(for item: ExtractedPlace, lists: [MustList]) -> String? {
        if let sub = item.sub, let list = lists.first(where: { $0.subs.contains(sub) }) { return list.id }
        if let color = item.category, let list = lists.first(where: { $0.color == color }) { return list.id }
        // café sem lista "coffee": cai na lista com sub "Café".
        if item.category == .coffee, let list = lists.first(where: { $0.subs.contains("Café") }) { return list.id }
        return lists.first?.id
    }

    /// Mesmo nome, ignorando caixa, acento e pontuação, ou um contido no outro (≥ 5 letras),
    /// ou o mesmo nome próprio sem a palavra de tipo ("Meiji Jingu" × "Santuário Meiji").
    nonisolated static func similar(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }
        let (short, long) = na.count < nb.count ? (na, nb) : (nb, na)
        if short.count >= 5 && long.contains(short) { return true }
        let ca = core(a), cb = core(b)
        return ca.count >= 4 && ca == cb
    }

    /// Palavras de tipo (pt, en, romaji) que o texto e o board trocam entre si.
    nonisolated private static let kindWords: Set<String> = [
        "santuario", "templo", "shrine", "temple", "jingu", "jinja", "taisha", "tenmangu",
        "mercado", "market", "museu", "museum", "parque", "park", "jardim", "garden", "gyoen", "koen",
        "castelo", "castle", "jo", "torre", "tower", "o", "a", "do", "da", "de", "the",
    ]

    /// Nome sem as palavras de tipo, normalizado ("Santuário Meiji" → "meiji").
    nonisolated static func core(_ s: String) -> String {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty && !kindWords.contains($0) }
            .joined()
    }

    nonisolated static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }
}
