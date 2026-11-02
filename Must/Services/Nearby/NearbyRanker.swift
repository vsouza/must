import CoreLocation
import Foundation

/// Um candidato a "por perto": um lugar do board ou de uma fonte externa, já com a distância de quem olha.
struct NearbyCandidate: Sendable, Hashable {
    var place: NearbyPlace
    /// Metros de quem está olhando.
    var distance: Double
    /// Id do `Place` quando o lugar já está no board.
    var boardPlaceId: String?
    var listId: String?
    var listName: String?
    var isDone: Bool = false
    /// Papel do lugar: manda na hora boa e na lista sugerida.
    var role: StopRole?
    /// Lista do tipo experiência (Must do).
    var isExperience: Bool = false

    var isOnBoard: Bool { boardPlaceId != nil }
    var id: String { boardPlaceId.map { "b:\($0)" } ?? place.id }
}

struct NearbyScored: Sendable, Hashable, Identifiable {
    var candidate: NearbyCandidate
    var score: Double
    var id: String { candidate.id }
}

/// Ranking local (pura, testada): score = nota, popularidade, distância, aberto agora, hora do dia × tipo, novidade.
enum NearbyRanker {
    static let radius: Double = NearbyService.radius
    /// Score a partir do qual um lugar de fora do board vira "Por perto" na Home.
    static let highScore: Double = 4.5
    /// Dois itens com o mesmo nome (parecido) a menos de 60 m são o mesmo lugar.
    static let dedupeMeters: Double = 60

    /// Mais alto primeiro; empate → o do board; depois o mais perto. Fora do raio, nada.
    static func rank(_ candidates: [NearbyCandidate], hour: Int) -> [NearbyScored] {
        dedupe(candidates.filter { $0.distance <= radius })
            .map { NearbyScored(candidate: $0, score: score($0, hour: hour)) }
            .sorted { a, b in
                if abs(a.score - b.score) > 1e-9 { return a.score > b.score }
                if a.candidate.isOnBoard != b.candidate.isOnBoard { return a.candidate.isOnBoard }
                return a.candidate.distance < b.candidate.distance
            }
    }

    static func score(_ c: NearbyCandidate, hour: Int) -> Double {
        let p = c.place
        var s = 0.0
        if let rating = p.rating { s += min(1, max(0, (rating - 3.5) / 1.5)) * 3 }
        if let count = p.ratingCount, count > 0 { s += min(1, log10(Double(count)) / 4.5) * 1.5 }
        s += max(0, 1 - c.distance / radius) * 1.5
        if p.openNow == true { s += 1.5 } else if p.openNow == false { s -= 2 }
        s += timeFit(c.role ?? role(for: p), hour: hour)
        if !c.isOnBoard { s += 0.6 } // novidade pra você
        if c.isDone { s -= 2 }
        if let popularity = p.popularity, popularity > 0.9 { s += 0.5 }
        if p.articleLang != nil { s += 0.3 }
        return s
    }

    /// Hora boa pro tipo: refeição no almoço e no jantar, bar à noite, museu e templo de dia.
    static func timeFit(_ role: StopRole, hour: Int) -> Double {
        switch role {
        case .eat: (11...14).contains(hour) || (18...21).contains(hour) ? 0.8 : 0
        case .drink: (17...23).contains(hour) || hour <= 1 ? 0.8 : 0
        case .see, .photo: (9...17).contains(hour) ? 0.6 : 0
        case .shop: (10...19).contains(hour) ? 0.6 : 0
        case .listen: (20...23).contains(hour) || hour <= 1 ? 0.8 : 0
        case .sport: (6...9).contains(hour) || (16...18).contains(hour) ? 0.5 : 0
        }
    }

    /// Papel pelo tipo do Google (`primaryType`) ou pelo nome da categoria do Foursquare.
    static func role(for place: NearbyPlace) -> StopRole {
        let c = (place.category ?? "").lowercased()
        func has(_ words: [String]) -> Bool { words.contains { c.contains($0) } }
        if has(["restaurant", "ramen", "sushi", "food", "bakery", "izakaya", "noodle", "bistro", "pizza", "steak"]) { return .eat }
        if has(["bar", "pub", "cafe", "coffee", "wine", "brew", "sake"]) { return .drink }
        if has(["night_club", "club", "karaoke", "music"]) { return .listen }
        if has(["shop", "store", "market", "mall", "book", "boutique"]) { return .shop }
        if has(["sport", "gym", "trail", "stadium"]) { return .sport }
        return .see
    }

    /// Cor da lista sugerida no "+ Must": café vira coffee, templo vira temple.
    static func suggestedColor(_ place: NearbyPlace, role: StopRole) -> MustColor {
        let c = (place.category ?? "").lowercased()
        switch role {
        case .eat: return .eat
        case .drink: return c.contains("cafe") || c.contains("coffee") ? .coffee : .drink
        case .see, .photo: return c.contains("temple") || c.contains("shrine") ? .temple : .see
        case .shop: return .shop
        case .listen: return .listen
        case .sport: return .sport
        }
    }

    // MARK: Dedupe

    static func dedupe(_ items: [NearbyCandidate]) -> [NearbyCandidate] {
        var out: [NearbyCandidate] = []
        for item in items {
            if let i = out.firstIndex(where: { isSame($0, item) }) {
                out[i] = merge(out[i], item)
            } else {
                out.append(item)
            }
        }
        return out
    }

    static func isSame(_ a: NearbyCandidate, _ b: NearbyCandidate) -> Bool {
        let meters = CLLocation(latitude: a.place.lat, longitude: a.place.lng).distance(from: CLLocation(latitude: b.place.lat, longitude: b.place.lng))
        return meters < dedupeMeters && PlaceMatcher.similar(a.place.name, b.place.name)
    }

    /// Fica o do board (lista e estado); os campos vazios vêm do outro; as fontes se somam.
    static func merge(_ a: NearbyCandidate, _ b: NearbyCandidate) -> NearbyCandidate {
        let (base, other) = b.isOnBoard && !a.isOnBoard ? (b, a) : (a, b)
        var out = base
        var p = base.place
        let o = other.place
        p.sources += o.sources.filter { !p.sources.contains($0) }
        p.googlePlaceId = p.googlePlaceId ?? o.googlePlaceId
        p.fsqId = p.fsqId ?? o.fsqId
        p.rating = p.rating ?? o.rating
        p.ratingCount = p.ratingCount ?? o.ratingCount
        p.openNow = p.openNow ?? o.openNow
        p.category = p.category ?? o.category
        p.popularity = p.popularity ?? o.popularity
        p.articleLang = p.articleLang ?? o.articleLang
        out.place = p
        out.distance = min(a.distance, b.distance)
        out.role = base.role ?? other.role
        return out
    }
}

/// Candidatos vindos do board e do cache (pura; o `Place` fica no lado da view).
enum NearbyCandidates {
    /// Externos: a distância é medida daqui.
    static func external(_ places: [NearbyPlace], origin: CLLocation) -> [NearbyCandidate] {
        places.map { place in
            let distance = CLLocation(latitude: place.lat, longitude: place.lng).distance(from: origin)
            return NearbyCandidate(place: place, distance: distance, role: NearbyRanker.role(for: place))
        }
    }

    /// Dados de um lugar do board (já lidos do SwiftData pelo chamador).
    static func board(id: String, name: String, lat: Double, lng: Double, openNow: Bool?, listId: String?, listName: String?,
                      role: StopRole?, isDone: Bool, isExperience: Bool, origin: CLLocation) -> NearbyCandidate {
        let distance = CLLocation(latitude: lat, longitude: lng).distance(from: origin)
        let place = NearbyPlace(name: name, lat: lat, lng: lng, sources: [.board], openNow: openNow)
        return NearbyCandidate(place: place, distance: distance, boardPlaceId: id, listId: listId, listName: listName,
                               isDone: isDone, role: role, isExperience: isExperience)
    }
}
