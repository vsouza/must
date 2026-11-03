import CoreLocation
import Foundation

/// (d) Confere cada candidato no Places (Text Search perto da área citada) e junta os que são o mesmo lugar.
/// Nunca inventa lugar: sem nome parecido no Places, o candidato fica "não achei no mapa" (o usuário decide).
enum PlaceResolver {
    static let searchRadius: CLLocationDistance = 5_000
    /// Candidatos a menos disso com nomes parecidos são o mesmo lugar.
    static let mergeDistance: CLLocationDistance = 60
    static let similarityThreshold = 0.85

    /// Preenche placeId, coordenada, nome oficial (guardando o da legenda como alias) e categoria do Places.
    /// Sem chave ou com dados ao vivo desligados, devolve os candidatos como vieram.
    static func resolve(_ items: [ExtractedPlace], provider: any PlacesProviding,
                        centers: [String: CLLocationCoordinate2D], fallback: CLLocationCoordinate2D) async -> [ExtractedPlace] {
        guard provider.isConfigured, DevOverrides.liveData else { return items }
        var out: [ExtractedPlace] = []
        for item in items {
            let near = item.area.flatMap { centers[$0] } ?? fallback
            out.append(await resolve(item, provider: provider, near: near))
        }
        return out
    }

    static func resolve(_ item: ExtractedPlace, provider: any PlacesProviding, near: CLLocationCoordinate2D) async -> ExtractedPlace {
        let query = [item.name, item.area].compactMap { $0 }.joined(separator: " ")
        guard let results = try? await provider.searchText(query, near: near, radius: searchRadius, languageCode: "pt-BR"),
              let hit = pick(results, for: item.name) else { return item }
        var out = item
        out.placeId = hit.id
        // Link do Maps já traz a coordenada que o usuário pediu: ela fica.
        if !item.hasCoordinate {
            out.lat = hit.lat
            out.lng = hit.lng
        }
        if PlaceMatcher.normalize(hit.name) != PlaceMatcher.normalize(item.name) {
            out.aliases = ([item.name] + item.aliases).filter { $0 != hit.name }
            out.name = hit.name
        }
        if let mapped = category(primaryType: hit.primaryType) {
            out.category = mapped.color
            out.sub = mapped.sub ?? out.sub
        }
        return out
    }

    /// Mesmo nome (sem acento/caixa/pontuação) > nome parecido > Jaro-Winkler ≥ 0,85. Nada disso, nil.
    static func pick(_ results: [PlaceCandidate], for name: String) -> PlaceCandidate? {
        let key = PlaceMatcher.normalize(name)
        guard key.count >= 3 else { return nil }
        return results.first { PlaceMatcher.normalize($0.name) == key }
            ?? results.first { PlaceMatcher.similar($0.name, name) }
            ?? results.first { key.count >= 5 && jaroWinkler(PlaceMatcher.normalize($0.name), key) >= similarityThreshold }
    }

    /// Tipo do Places → categoria e sub do Must. Manda antes do nome e da legenda.
    static func category(primaryType: String?) -> (color: MustColor, sub: String?)? {
        switch primaryType ?? "" {
        case "ramen_restaurant": (.eat, "Ramen")
        case "sushi_restaurant": (.eat, "Sushi")
        case "restaurant", "japanese_restaurant", "brazilian_restaurant", "fast_food_restaurant", "meal_takeaway",
             "izakaya_restaurant", "japanese_izakaya_restaurant", "bakery": (.eat, nil)
        case "cafe", "coffee_shop", "tea_house": (.coffee, "Café")
        case "bar", "wine_bar", "cocktail_bar", "pub", "brewpub": (.drink, "Bar")
        case "night_club": (.night, nil)
        case "museum", "art_gallery", "art_museum": (.see, "Arte")
        case "buddhist_temple", "hindu_temple", "shinto_shrine", "place_of_worship": (.temple, "Templos")
        case "market", "supermarket", "grocery_store": (.shop, "Mercado")
        case "camera_store": (.shop, "Câmeras")
        case "record_store", "music_store": (.listen, "Discos")
        case "clothing_store", "shoe_store", "book_store", "store", "shopping_mall", "department_store", "home_goods_store": (.shop, nil)
        case "park", "tourist_attraction", "observation_deck": (.see, nil)
        default: nil
        }
    }

    /// Junta candidatos do mesmo lugar: mesmo placeId, ou a < 60 m com nomes parecidos.
    /// A ordem da lista é a da primeira menção; cada grupo vira um item com `mentions` somado.
    static func merge(_ items: [ExtractedPlace]) -> [ExtractedPlace] {
        var groups: [[ExtractedPlace]] = []
        for item in items {
            if let index = groups.firstIndex(where: { group in group.contains { isSamePlace($0, item) } }) {
                groups[index].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups.map(combine)
    }

    static func isSamePlace(_ a: ExtractedPlace, _ b: ExtractedPlace) -> Bool {
        if let pa = a.placeId, let pb = b.placeId { return pa == pb }
        guard let la = a.lat, let ga = a.lng, let lb = b.lat, let gb = b.lng else { return false }
        let meters = CLLocation(latitude: la, longitude: ga).distance(from: CLLocation(latitude: lb, longitude: gb))
        return meters < mergeDistance && sameName(a.name, b.name)
    }

    static func sameName(_ a: String, _ b: String) -> Bool {
        if PlaceMatcher.similar(a, b) { return true }
        let (na, nb) = (PlaceMatcher.normalize(a), PlaceMatcher.normalize(b))
        return min(na.count, nb.count) >= 5 && jaroWinkler(na, nb) >= similarityThreshold
    }

    /// Um item só: quem tem placeId (ou coordenada) é o representante; nomes e menções se juntam.
    private static func combine(_ group: [ExtractedPlace]) -> ExtractedPlace {
        let rep = group.first { $0.placeId != nil } ?? group.first { $0.hasCoordinate } ?? group[0]
        var out = rep
        var aliases: [String] = []
        for item in group {
            for name in [item.name] + item.aliases where name != out.name && !aliases.contains(name) {
                aliases.append(name)
            }
        }
        out.aliases = aliases
        out.mentions = group.reduce(0) { $0 + $1.mentions }
        out.placeId = group.lazy.compactMap(\.placeId).first
        if !out.hasCoordinate, let located = group.first(where: \.hasCoordinate) {
            out.lat = located.lat
            out.lng = located.lng
        }
        out.category = rep.category ?? group.lazy.compactMap(\.category).first
        out.sub = rep.sub ?? group.lazy.compactMap(\.sub).first
        out.nameLocal = rep.nameLocal ?? group.lazy.compactMap(\.nameLocal).first
        out.area = rep.area ?? group.lazy.compactMap(\.area).first
        out.dayIndex = rep.dayIndex ?? group.lazy.compactMap(\.dayIndex).first
        out.art = rep.art ?? group.lazy.compactMap(\.art).first
        out.venue = rep.venue ?? group.lazy.compactMap(\.venue).first
        return out
    }

    /// Horário e preço dos lugares conferidos (cache em `PlaceDetails`). Um pedido por placeId.
    static func details(_ placeIds: [String], provider: any PlacesProviding) async -> [String: PlaceDetails] {
        guard provider.isConfigured, DevOverrides.liveData else { return [:] }
        var out: [String: PlaceDetails] = [:]
        for id in Set(placeIds) {
            if let details = try? await provider.details(id, languageCode: "pt-BR") { out[id] = details }
        }
        return out
    }

    /// Jaro-Winkler (0…1) entre duas strings já normalizadas.
    static func jaroWinkler(_ a: String, _ b: String) -> Double {
        let s1 = Array(a), s2 = Array(b)
        guard !s1.isEmpty, !s2.isEmpty else { return 0 }
        if s1 == s2 { return 1 }
        let window = max(max(s1.count, s2.count) / 2 - 1, 0)
        var used2 = [Bool](repeating: false, count: s2.count)
        var matched1 = [Bool](repeating: false, count: s1.count)
        var matches = 0
        for i in s1.indices {
            let lo = max(0, i - window), hi = min(i + window + 1, s2.count)
            guard lo < hi else { continue }
            for j in lo..<hi where !used2[j] && s1[i] == s2[j] {
                used2[j] = true
                matched1[i] = true
                matches += 1
                break
            }
        }
        guard matches > 0 else { return 0 }
        var halfTranspositions = 0
        var k = 0
        for i in s1.indices where matched1[i] {
            while !used2[k] { k += 1 }
            if s1[i] != s2[k] { halfTranspositions += 1 }
            k += 1
        }
        let m = Double(matches)
        let jaro = (m / Double(s1.count) + m / Double(s2.count) + (m - Double(halfTranspositions) / 2) / m) / 3
        var prefix = 0
        for (x, y) in zip(s1, s2).prefix(4) {
            guard x == y else { break }
            prefix += 1
        }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }
}
