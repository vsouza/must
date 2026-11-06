import CoreLocation
import Foundation

// Busca do mapa (prompt 27 §2.c): "o melhor lámen perto de mim agora". Mesma vontade do Quero… (`WantParser`), outra
// pergunta: não "onde compro", e sim "qual é o melhor aberto aqui perto". Cache primeiro, sempre:
//   1) o seu board (horário em cache, nota que já está no aparelho),
//   2) o último "Por perto" (`NearbyCache`, sem chamada nova),
//   3) só se não bastar e houver rede, **uma** chamada do Text Search do Quero… (`WantSearchCache`: cache, dedupe, `ApiBudget`).
// Ranking no aparelho: `nota × log(1 + nº de avaliações)` quando há nota; senão aberto + perto + popularidade.

/// Nota que já está no aparelho (dicas do Lugar já abertas, "Por perto" em cache): nunca uma chamada nova.
struct KnownRating: Hashable, Sendable, Codable {
    var rating: Double
    var count: Int?
}

/// Um lugar do board pra busca do mapa (sem SwiftData, roda fora do main).
struct MapBoardEntry: Sendable, Hashable {
    var place: WantBoardPlace
    /// Aberto agora pelo horário em cache. `nil` = sem horário no aparelho.
    var openNow: Bool?
    var priceLevel: Int? = nil
    var queueMinutes: Int? = nil
    var rating: KnownRating? = nil
}

struct MapSearchInput: Sendable {
    var intent: WantIntent
    var region: Region
    /// De onde se mede: o GPS (senão o centro do mapa).
    var center: CLLocationCoordinate2D
    var cityGroup: String
    var online: Bool
    var board: [MapBoardEntry] = []
    /// O último lote do "Por perto" pra célula de quem busca (já no disco).
    var nearby: [NearbyPlace] = []
    var now: Date = AppClock.now
    /// Chip "aberto agora" (padrão ligado): fechado nunca entra.
    var openOnly = true
    /// Opção (i) do Vinicius: nota do Google (SKU Enterprise). Desligado por padrão (`PlacesEnterpriseFlag`).
    var enterprise = false
}

/// De onde veio a lista (pros testes e pro rodapé).
enum MapSearchSource: String, Sendable, Hashable { case board, cache, places }

struct MapSearchCandidate: Identifiable, Hashable, Sendable {
    var result: WantResult
    var openNow: Bool?
    var rating: Double?
    var ratingCount: Int?
    var priceLevel: Int?
    var queueMinutes: Int?
    /// "tsukemen", "niboshi": a sub-lista do board ou o tipo do Google, em pt.
    var sub: String?
    /// Foursquare 0–1 (o "em alta" do `NearbyRanker`).
    var popularity: Double?

    var id: String { result.id }
    var onBoard: Bool { result.boardPlaceId != nil }

    /// `nota × log(1 + nº de avaliações)`; sem nota, `nil` (vai depois dos que têm).
    var bestScore: Double? {
        rating.map { $0 * log(1 + Double(max(1, ratingCount ?? 1))) }
    }
}

struct MapSearchOutput: Sendable, Hashable {
    /// Todos os que passaram (aberto, no raio), na ordem. A tela mostra 3 ("3 de 11").
    var ranked: [MapSearchCandidate]
    /// Raio usado (1,5 km a pé; 3 km se nada; ou o que a pessoa disse).
    var radiusKm: Double
    /// Nada no raio pedido: abriu pra 3 km.
    var expanded = false
    var sources: Set<MapSearchSource> = []
    /// Saiu uma chamada de rede nesta busca (o cache não bastou).
    var calledNetwork = false
    /// Sem rede: a lista é só do board e do cache ("offline · só o seu board").
    var offline = false
    var notice: String? = nil
    /// O primeiro tem nota: o cabeçalho diz "por nota" (senão "por distância").
    var byRating = false
}

enum MapSearch {
    /// 1,5 km a pé (prompt 27 §2.c); 3 km se nada.
    static let defaultRadiusKm = 1.5
    static let fallbackRadiusKm = 3.0
    /// Quantos bastam pra não ir à rede.
    static let enough = 3
    static let shown = 3

    // MARK: Palavras

    /// Objeto, marca e (prato) os nomes do prato ("lámen" → lamen, ramen, tsukemen).
    static func keywords(_ intent: WantIntent, category: WantCategory?) -> [String] {
        var words = WantSearch.keywords(intent, category: category)
        if let c = category, isDish(c) { words += c.keywords }
        return Array(Set(words.filter { $0.count >= 3 })).sorted()
    }

    static func isDish(_ c: WantCategory) -> Bool {
        let key = WantCategory.fold(c.label)
        return WantCategory.dishes.contains(key) || WantCategory.dishAliases.values.contains(key)
    }

    static func contains(_ text: String, any words: [String]) -> Bool {
        let hay = " " + WantCategory.fold(text).replacingOccurrences(of: "_", with: " ") + " "
        return words.contains { hay.contains(" \($0)") }
    }

    static func valid(_ lat: Double, _ lng: Double) -> Bool {
        lat.isFinite && lng.isFinite && (lat != 0 || lng != 0) && abs(lat) <= 90 && abs(lng) <= 180
    }

    // MARK: 1 · Board

    static func boardCandidates(_ input: MapSearchInput, category: WantCategory?) -> [MapSearchCandidate] {
        let words = keywords(input.intent, category: category)
        guard !words.isEmpty else { return [] }
        return input.board.compactMap { e in
            let p = e.place
            guard !p.done, valid(p.lat, p.lng), contains("\(p.name) \(p.sub ?? "") \(p.notes)", any: words) else { return nil }
            let result = WantResult(id: "board:\(p.id)", name: p.name, lat: p.lat, lng: p.lng, origin: .board, area: p.area,
                                    googlePlaceId: p.placeId, boardPlaceId: p.id, note: "no seu board", until: p.until,
                                    distance: WantSearch.meters(input.center, p.lat, p.lng))
            return MapSearchCandidate(result: result, openNow: e.openNow, rating: e.rating?.rating, ratingCount: e.rating?.count,
                                      priceLevel: e.priceLevel, queueMinutes: e.queueMinutes, sub: p.sub?.lowercased())
        }
    }

    // MARK: 2 · Cache do "Por perto"

    /// O que o último "Por perto" já trouxe (Google Nearby, Foursquare) e casa com a vontade. Wikipedia é contexto: fica fora.
    static func nearbyCandidates(_ input: MapSearchInput, category: WantCategory?) -> [MapSearchCandidate] {
        let words = keywords(input.intent, category: category)
        let types = Set(category.flatMap { isDish($0) ? nil : $0.types } ?? [])
        return input.nearby.compactMap { p in
            guard valid(p.lat, p.lng), p.sources.contains(where: { $0 != .wikipedia }) else { return nil }
            let byWord = contains("\(p.name) \(p.category ?? "")", any: words)
            let byType = p.category.map(types.contains) ?? false
            guard byWord || byType else { return nil }
            let id = p.googlePlaceId.map { "g:\($0)" } ?? "near:\(p.id)"
            let result = WantResult(id: id, name: p.name, lat: p.lat, lng: p.lng, origin: .places, types: p.category.map { [$0] } ?? [],
                                    primaryType: p.category, googlePlaceId: p.googlePlaceId,
                                    distance: WantSearch.meters(input.center, p.lat, p.lng))
            return MapSearchCandidate(result: result, openNow: p.openNow, rating: p.rating, ratingCount: p.ratingCount,
                                      sub: p.category.flatMap(subLabel), popularity: p.popularity)
        }
    }

    // MARK: 3 · Rede (uma chamada)

    static func query(_ input: MapSearchInput, category: WantCategory?, radiusKm: Double) -> PlacesTextQuery {
        PlacesTextQuery(text: WantSearch.text(for: input.intent, category: category), lat: input.center.latitude,
                        lng: input.center.longitude, radius: radiusKm * 1000, includedType: category?.includedType,
                        openNow: input.openOnly, rankByDistance: true, maxResults: 10)
    }

    /// Resultado do Text Search → candidato (só lugar físico, com coordenada: o filtro do Quero…).
    static func placesCandidates(_ rated: [RatedHit], input: MapSearchInput, category: WantCategory?, openNow: Bool)
        -> (candidates: [MapSearchCandidate], dropped: Int) {
        let (kept, dropped) = WantSearch.filter(rated.map(\.hit), category: category)
        let byId = Dictionary(rated.map { ($0.hit.id, $0) }, uniquingKeysWith: { a, _ in a })
        let want = WantSearchInput(intent: input.intent, region: input.region, center: input.center, cityGroup: input.cityGroup,
                                   online: input.online, now: input.now)
        let areas = AreaCatalog.areas(for: input.region)
        let out = kept.compactMap { hit -> MapSearchCandidate? in
            guard let r = WantSearch.result(hit, input: want, areas: areas), valid(r.lat, r.lng) else { return nil }
            let extra = byId[hit.id]
            return MapSearchCandidate(result: r, openNow: openNow ? true : nil, rating: extra?.rating, ratingCount: extra?.ratingCount,
                                      sub: subLabel(hit.primaryType ?? hit.types.first ?? ""))
        }
        return (out, dropped)
    }

    // MARK: Juntar e ranquear

    /// Board primeiro (é seu), depois o cache, depois a rede; o mesmo lugar aparece uma vez, com o que faltar do outro.
    static func merge(_ groups: [MapSearchCandidate]...) -> [MapSearchCandidate] {
        var out: [MapSearchCandidate] = []
        for item in groups.joined() {
            if let i = out.firstIndex(where: { WantSearch.same($0.result, item.result) }) {
                out[i].result.googlePlaceId = out[i].result.googlePlaceId ?? item.result.googlePlaceId
                out[i].openNow = out[i].openNow ?? item.openNow
                if out[i].rating == nil { out[i].rating = item.rating; out[i].ratingCount = item.ratingCount }
                out[i].popularity = out[i].popularity ?? item.popularity
                out[i].sub = out[i].sub ?? item.sub
                if out[i].result.photos.isEmpty { out[i].result.photos = item.result.photos }
                continue
            }
            out.append(item)
        }
        return out
    }

    /// Só aberto agora (com o chip; sem horário conhecido entra depois dos abertos), só até o raio, nunca sem coordenada.
    static func rank(_ candidates: [MapSearchCandidate], quality: WantQuality, radiusKm: Double, openOnly: Bool = true)
        -> [MapSearchCandidate] {
        candidates
            .filter { valid($0.result.lat, $0.result.lng) && $0.result.distance <= radiusKm * 1000 }
            .filter { !openOnly || $0.openNow != false }
            .sorted { before($0, $1, quality: quality) }
    }

    static func before(_ a: MapSearchCandidate, _ b: MapSearchCandidate, quality: WantQuality) -> Bool {
        // Aberto (confirmado) antes de "sem horário no aparelho"; fechado só chega aqui com o chip desligado.
        func openRank(_ c: MapSearchCandidate) -> Int { c.openNow == true ? 0 : (c.openNow == nil ? 1 : 2) }
        if openRank(a) != openRank(b) { return openRank(a) < openRank(b) }
        switch quality {
        case .melhor:
            switch (a.bestScore, b.bestScore) {
            case let (x?, y?) where abs(x - y) > 1e-6: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
        case .barato:
            switch (a.priceLevel, b.priceLevel) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
        case .qualquer: break
        }
        // Sem nota (opção ii): popularidade, o mais perto e, no empate, o do board.
        if quality == .melhor {
            let (x, y) = (a.popularity ?? 0, b.popularity ?? 0)
            if abs(x - y) > 0.05 { return x > y }
        }
        if abs(a.result.distance - b.result.distance) > 1 { return a.result.distance < b.result.distance }
        if a.onBoard != b.onBoard { return a.onBoard }
        return a.id < b.id
    }

    // MARK: Rodar

    /// Board → cache → (se não bastar e houver rede) uma chamada. Offline = board e cache, sem espera.
    static func run(_ input: MapSearchInput, provider: (any WantPlacesSearching)?, rated: (any RatedPlacesSearching)? = nil,
                    cache: WantSearchCache = .shared) async -> MapSearchOutput {
        let category = WantCategory.of(input.intent)
        let quality = input.intent.quality
        let asked = input.intent.radiusKm
        let base = asked ?? defaultRadiusKm
        let board = boardCandidates(input, category: category)
        let near = nearbyCandidates(input, category: category)
        var pool = merge(board, near)
        var sources: Set<MapSearchSource> = []
        if !board.isEmpty { sources.insert(.board) }
        if !near.isEmpty { sources.insert(.cache) }
        var output = MapSearchOutput(ranked: rank(pool, quality: quality, radiusKm: base, openOnly: input.openOnly), radiusKm: base)

        if output.ranked.count < enough {
            let query = query(input, category: category, radiusKm: base)
            var hits: [RatedHit]?
            do {
                if input.enterprise, let rated, rated.isConfigured {
                    if let cached = await cache.cachedRated(query, now: input.now) {
                        hits = cached
                    } else if input.online {
                        output.calledNetwork = true
                        hits = try await cache.fetchRated(query, now: input.now) { try await rated.searchRatedPlaces(query) }
                    } else {
                        output.offline = true
                    }
                } else if let cached = await cache.cached(query, now: input.now) {
                    hits = cached.map { RatedHit(hit: $0) }
                } else if !input.online {
                    output.offline = true
                } else if let provider, provider.isConfigured {
                    output.calledNetwork = true
                    hits = try await cache.fetch(query, now: input.now) { try await provider.searchPlaces(query) }.map { RatedHit(hit: $0) }
                }
            } catch ServiceError.budget(let message) {
                output.notice = message
            } catch ServiceError.missingKey {
                output.notice = nil
            } catch {
                if WantSearch.isOffline(error) { output.offline = true } else { output.notice = "o Google não respondeu · só o que está no aparelho" }
            }
            if let hits {
                let places = placesCandidates(hits, input: input, category: category, openNow: query.openNow).candidates
                if !places.isEmpty { sources.insert(.places) }
                pool = merge(pool, places)
            }
            output.ranked = rank(pool, quality: quality, radiusKm: base, openOnly: input.openOnly)
        }
        // Nada a pé: abre pra 3 km (sem outra chamada). Raio dito pela pessoa vale.
        if output.ranked.isEmpty, asked == nil {
            output.radiusKm = fallbackRadiusKm
            output.expanded = true
            output.ranked = rank(pool, quality: quality, radiusKm: fallbackRadiusKm, openOnly: input.openOnly)
        }
        output.sources = sources
        // Sem rede é sempre "offline" (mesmo que o cache tenha respondido): a tela diz de onde veio.
        if !input.online { output.offline = true }
        output.byRating = quality == .melhor && output.ranked.first?.rating != nil
        return output
    }

    // MARK: Textos

    /// Tipo do Google → pt curto ("ramen_restaurant" → "ramen", "bakery" → "padaria").
    static func subLabel(_ type: String) -> String? {
        let t = type.lowercased()
        guard !t.isEmpty else { return nil }
        let map: [String: String] = [
            "ramen_restaurant": "ramen", "japanese_restaurant": "japonês", "sushi_restaurant": "sushi", "bakery": "padaria",
            "cafe": "café", "coffee_shop": "café", "brazilian_restaurant": "mineiro", "restaurant": "restaurante", "bar": "bar",
            "snack_bar": "lanchonete", "confectionery": "doceria", "dessert_shop": "doceria", "ice_cream_shop": "sorveteria",
            "izakaya_restaurant": "izakaya", "pizza_restaurant": "pizza", "hamburger_restaurant": "hambúrguer",
        ]
        if let hit = map[t] { return hit }
        if t.hasSuffix("_restaurant") { return t.replacingOccurrences(of: "_restaurant", with: "").replacingOccurrences(of: "_", with: " ") }
        return t.contains("_") ? nil : t
    }
}
