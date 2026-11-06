import CoreLocation
import Foundation
import Testing
@testable import Must

/// Busca do mapa (prompt 27 §2.c): "o melhor lámen perto de mim agora" → intent; ranking `nota × log(1 + n)`; só aberto;
/// board antes da rede; nunca item sem coordenada.
struct MapSearchTests {
    private let shinjuku = CLLocationCoordinate2D(latitude: 35.6909, longitude: 139.7003)
    private let savassi = CLLocationCoordinate2D(latitude: -19.9385, longitude: -43.9343)

    /// Conta as chamadas (a rede só sai quando o board e o cache não bastam).
    private final class Counting: WantPlacesSearching, @unchecked Sendable {
        var hits: [PlaceHit]
        var calls = 0
        let isConfigured = true
        init(_ hits: [PlaceHit]) { self.hits = hits }
        func searchPlaces(_ query: PlacesTextQuery) async throws -> [PlaceHit] {
            calls += 1
            return hits
        }
    }

    private final class CountingRated: RatedPlacesSearching, @unchecked Sendable {
        var hits: [RatedHit]
        var calls = 0
        let isConfigured = true
        init(_ hits: [RatedHit]) { self.hits = hits }
        func searchRatedPlaces(_ query: PlacesTextQuery) async throws -> [RatedHit] {
            calls += 1
            return hits
        }
    }

    private func cache() -> WantSearchCache {
        WantSearchCache(directory: URL.temporaryDirectory.appending(path: "map-search-test-\(UUID().uuidString)"))
    }

    /// Lugar a `meters` ao norte do centro.
    private func north(_ c: CLLocationCoordinate2D, _ meters: Double) -> (Double, Double) {
        (c.latitude + meters / 111_000, c.longitude)
    }

    private func entry(_ id: String, _ name: String, sub: String? = nil, at meters: Double, from c: CLLocationCoordinate2D,
                       open: Bool?, rating: KnownRating? = nil, done: Bool = false) -> MapBoardEntry {
        let (lat, lng) = north(c, meters)
        return MapBoardEntry(place: WantBoardPlace(id: id, name: name, lat: lat, lng: lng, listId: "eat", sub: sub, done: done),
                             openNow: open, rating: rating)
    }

    private func nearby(_ name: String, id: String, at meters: Double, from c: CLLocationCoordinate2D, rating: Double?, count: Int?,
                        open: Bool?, category: String = "ramen_restaurant") -> NearbyPlace {
        let (lat, lng) = north(c, meters)
        return NearbyPlace(name: name, lat: lat, lng: lng, sources: [.google], googlePlaceId: id, rating: rating, ratingCount: count,
                           openNow: open, category: category)
    }

    private func input(_ text: String, region: Region = .jp, online: Bool = true, board: [MapBoardEntry] = [],
                       nearby: [NearbyPlace] = []) -> MapSearchInput {
        MapSearchInput(intent: WantParser.parseLocal(text)!, region: region, center: region == .jp ? shinjuku : savassi,
                       cityGroup: region == .jp ? "tokyo" : "bh", online: online, board: board, nearby: nearby, now: Date())
    }

    @Test func intentDoMelhorLamen() {
        let i = input("o melhor lámen perto de mim agora")
        #expect(i.intent.quality == .melhor)
        #expect(i.intent.when == .hoje)
        let category = WantCategory.of(i.intent)
        let q = MapSearch.query(i, category: category, radiusKm: MapSearch.defaultRadiusKm)
        #expect(q.openNow)
        #expect(q.includedType == "restaurant")
        #expect(q.radius == 1_500)
        #expect(q.maxResults == 10)
        #expect(PlacesService.body(for: q)["strictTypeFiltering"] as? Bool == true)
        #expect(MapSearch.keywords(i.intent, category: category).contains("ramen"))
    }

    @Test func rankingPorNotaVezesLogDasAvaliacoes() {
        // 4,8 com 40 avaliações perde de 4,4 com 3.100 (a nota sozinha engana).
        let few = MapSearchCandidate(result: WantResult(id: "a", name: "Pequeno", lat: 35.69, lng: 139.70, origin: .places, distance: 300),
                                     openNow: true, rating: 4.8, ratingCount: 40)
        let many = MapSearchCandidate(result: WantResult(id: "b", name: "Fuunji", lat: 35.69, lng: 139.70, origin: .places, distance: 650),
                                      openNow: true, rating: 4.4, ratingCount: 3_100)
        let none = MapSearchCandidate(result: WantResult(id: "c", name: "Sem nota", lat: 35.69, lng: 139.70, origin: .places, distance: 50),
                                      openNow: true)
        let ranked = MapSearch.rank([few, none, many], quality: .melhor, radiusKm: 1.5)
        #expect(ranked.map(\.id) == ["b", "a", "c"])
        #expect(abs((many.bestScore ?? 0) - 4.4 * log(3_101)) < 1e-9)
        // Empate de nota: o mais perto.
        var twin = many
        twin.result.id = "d"
        twin.result.distance = 200
        #expect(MapSearch.rank([many, twin], quality: .melhor, radiusKm: 1.5).first?.id == "d")
    }

    @Test func soAbertoAgoraENoRaio() {
        let board = [
            entry("p1", "Lámen do Zé", at: 300, from: shinjuku, open: false, rating: KnownRating(rating: 4.9, count: 900)),
            entry("p2", "Ramen Nagi", at: 400, from: shinjuku, open: true),
            entry("p3", "Ramen longe", at: 2_400, from: shinjuku, open: true),
            entry("p4", "Ramen sem horário", at: 500, from: shinjuku, open: nil),
            entry("p5", "Ramen feito", at: 100, from: shinjuku, open: true, done: true),
        ]
        let i = input("o melhor lámen perto de mim agora", board: board)
        let ranked = MapSearch.rank(MapSearch.boardCandidates(i, category: WantCategory.of(i.intent)), quality: .melhor, radiusKm: 1.5)
        // Fechado e longe ficam de fora; aberto antes do "sem horário"; feito nunca.
        #expect(ranked.map(\.result.boardPlaceId) == ["p2", "p4"])
        // Sem o chip "aberto agora", o fechado volta (por último).
        let all = MapSearch.rank(MapSearch.boardCandidates(i, category: WantCategory.of(i.intent)), quality: .melhor, radiusKm: 1.5,
                                 openOnly: false)
        #expect(all.last?.result.boardPlaceId == "p1")
    }

    @Test func boardECacheAntesDaRede() async {
        let board = [entry("p2", "Ramen Nagi", sub: "Ramen", at: 400, from: shinjuku, open: true)]
        let near = [
            nearby("Fuunji", id: "g-fuunji", at: 650, from: shinjuku, rating: 4.4, count: 3_100, open: true),
            nearby("Ichiran Shinjuku", id: "g-ichiran", at: 410, from: shinjuku, rating: 4.2, count: 9_000, open: true),
            nearby("Café Tal", id: "g-cafe", at: 100, from: shinjuku, rating: 4.9, count: 900, open: true, category: "cafe"),
        ]
        let provider = Counting([PlaceHit(id: "g-net", name: "Ramen da rede", address: "Shinjuku", lat: 35.692, lng: 139.700,
                                          types: ["ramen_restaurant", "restaurant"])])
        let out = await MapSearch.run(input("o melhor lámen perto de mim agora", board: board, nearby: near), provider: provider,
                                      cache: cache())
        #expect(provider.calls == 0) // 3 abertos no board + cache: a rede nem é chamada
        #expect(!out.calledNetwork)
        #expect(out.sources == [.board, .cache])
        #expect(out.ranked.count == 3)
        #expect(!out.ranked.contains { $0.result.name == "Café Tal" })
        // Ichiran (4,2 × log 9.001) > Fuunji (4,4 × log 3.101) > board sem nota.
        #expect(out.ranked.map(\.result.name) == ["Ichiran Shinjuku", "Fuunji", "Ramen Nagi"])
        #expect(out.byRating)
    }

    @Test func faltaNoBoardVaiNaRedeUmaVez() async {
        let board = [entry("p2", "Ramen Nagi", at: 400, from: shinjuku, open: true)]
        let provider = Counting([
            PlaceHit(id: "site", name: "Ramen online", address: nil, lat: nil, lng: nil, types: ["store"]),
            PlaceHit(id: "g-1", name: "Afuri", address: "Shinjuku", lat: 35.6925, lng: 139.7003, types: ["ramen_restaurant", "restaurant"],
                     primaryType: "ramen_restaurant"),
            // O mesmo do board (mesmo nome, 30 m): entra uma vez só.
            PlaceHit(id: "g-2", name: "Ramen Nagi", address: "Shinjuku", lat: board[0].place.lat + 0.0002, lng: board[0].place.lng,
                     types: ["restaurant"]),
        ])
        let c = cache()
        let i = input("o melhor lámen perto de mim agora", board: board)
        let out = await MapSearch.run(i, provider: provider, cache: c)
        #expect(provider.calls == 1)
        #expect(out.calledNetwork)
        #expect(out.ranked.map(\.result.name).sorted() == ["Afuri", "Ramen Nagi"])
        #expect(out.ranked.first { $0.result.name == "Ramen Nagi" }?.onBoard == true)
        #expect(out.ranked.allSatisfy { MapSearch.valid($0.result.lat, $0.result.lng) })
        // A mesma busca de novo: cache, nenhuma chamada nova.
        _ = await MapSearch.run(i, provider: provider, cache: c)
        #expect(provider.calls == 1)
    }

    @Test func nuncaItemSemCoordenada() async {
        let board = [MapBoardEntry(place: WantBoardPlace(id: "p0", name: "Ramen sem lugar", lat: 0, lng: 0), openNow: true)]
        let near = [NearbyPlace(name: "Ramen zero", lat: 0, lng: 0, sources: [.google], openNow: true, category: "ramen_restaurant")]
        let provider = Counting([PlaceHit(id: "x", name: "Ramen x", address: "Tóquio", lat: nil, lng: 139.7, types: ["restaurant"])])
        let out = await MapSearch.run(input("ramen", board: board, nearby: near), provider: provider, cache: cache())
        #expect(out.ranked.isEmpty)
    }

    @Test func offlineSoBoardECache() async {
        let board = [entry("p2", "Ramen Nagi", at: 400, from: shinjuku, open: true)]
        let provider = Counting([])
        let out = await MapSearch.run(input("o melhor lámen agora", online: false, board: board), provider: provider, cache: cache())
        #expect(provider.calls == 0)
        #expect(out.offline)
        #expect(out.ranked.map(\.result.boardPlaceId) == ["p2"])
    }

    @Test func nadaAPeAbrePraTresKm() async {
        let board = [entry("p3", "Ramen longe", at: 2_400, from: shinjuku, open: true)]
        let out = await MapSearch.run(input("ramen", online: false, board: board), provider: nil, cache: cache())
        #expect(out.expanded)
        #expect(out.radiusKm == 3)
        #expect(out.ranked.count == 1)
        // Raio dito pela pessoa vale: não abre sozinho.
        let asked = await MapSearch.run(input("ramen até 1 km", online: false, board: board), provider: nil, cache: cache())
        #expect(!asked.expanded)
        #expect(asked.ranked.isEmpty)
    }

    @Test func bhPaoDeQueijoNoBoard() async {
        let board = [
            entry("p01", "Café com Letras", sub: "Pão de queijo", at: 300, from: savassi, open: true),
            entry("p02", "Mercado Central", sub: "Mercado", at: 900, from: savassi, open: true),
            entry("p03", "Casa Bonomi", sub: "Padaria", at: 600, from: savassi, open: false),
        ]
        var b = board
        b[1].place.notes = "o melhor pão de queijo da cidade fica na entrada"
        b[2].place.notes = "pão de queijo quentinho"
        let out = await MapSearch.run(input("o melhor pão de queijo perto de mim agora", region: .bh, online: false, board: b),
                                      provider: nil, cache: cache())
        #expect(out.ranked.map(\.result.boardPlaceId) == ["p01", "p02"])
        #expect(out.ranked.allSatisfy { $0.onBoard })
    }

    @Test func enterpriseSoComOFlag() async {
        #expect(!PlacesEnterpriseFlag.isOn(defaults: UserDefaults(suiteName: "map-ent-\(UUID().uuidString)")!))
        let pro = Counting([PlaceHit(id: "g-1", name: "Afuri", address: "Shinjuku", lat: 35.6925, lng: 139.7003, types: ["restaurant"])])
        let rated = CountingRated([RatedHit(hit: PlaceHit(id: "g-1", name: "Afuri", address: "Shinjuku", lat: 35.6925, lng: 139.7003,
                                                           types: ["restaurant"]), rating: 4.5, ratingCount: 2_000)])
        // Desligado (padrão): Pro, sem nota.
        var i = input("o melhor lámen agora")
        var out = await MapSearch.run(i, provider: pro, rated: rated, cache: cache())
        #expect(pro.calls == 1 && rated.calls == 0)
        #expect(out.ranked.first?.rating == nil)
        #expect(!out.byRating)
        // Ligado: uma chamada com nota (SKU Enterprise), nenhuma no Pro.
        i.enterprise = true
        out = await MapSearch.run(i, provider: pro, rated: rated, cache: cache())
        #expect(pro.calls == 1 && rated.calls == 1)
        #expect(out.ranked.first?.rating == 4.5)
        #expect(out.byRating)
        #expect(PlacesService.ratedMask.contains("places.rating"))
        #expect(PlacesService.ratedMask.contains("places.userRatingCount"))
        #expect(!PlacesService.wantMask.contains("rating"))
    }

    @Test func parseDaNota() throws {
        let json = """
        {"places":[{"id":"a","displayName":{"text":"Fuunji"},"location":{"latitude":35.68,"longitude":139.69},
        "types":["ramen_restaurant"],"rating":4.4,"userRatingCount":3100},{"id":"b","displayName":{"text":"Sem nota"},
        "location":{"latitude":35.68,"longitude":139.69}}]}
        """
        let hits = try PlacesService.parseRated(Data(json.utf8))
        #expect(hits.count == 2)
        #expect(hits[0].rating == 4.4 && hits[0].ratingCount == 3_100)
        #expect(hits[1].rating == nil)
    }
}
