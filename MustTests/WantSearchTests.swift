import CoreLocation
import Foundation
import Testing
@testable import Must

/// Quero… (prompt 25 · A.2): só lugar físico, com coordenada; lojas de marca e board entram mesmo offline.
struct WantSearchTests {
    private let shinjuku = CLLocationCoordinate2D(latitude: 35.6909, longitude: 139.7003)
    private let savassi = CLLocationCoordinate2D(latitude: -19.9385, longitude: -43.9343)

    private struct Stub: WantPlacesSearching {
        var hits: [PlaceHit]
        var isConfigured = true
        func searchPlaces(_ query: PlacesTextQuery) async throws -> [PlaceHit] { hits }
    }

    private struct Offline: WantPlacesSearching {
        var isConfigured = true
        func searchPlaces(_ query: PlacesTextQuery) async throws -> [PlaceHit] { throw URLError(.notConnectedToInternet) }
    }

    private func input(_ text: String, region: Region = .jp, online: Bool = true, board: [WantBoardPlace] = []) -> WantSearchInput {
        WantSearchInput(intent: WantParser.parseLocal(text)!, region: region, center: region == .jp ? shinjuku : savassi,
                        cityGroup: region == .jp ? "tokyo" : "bh", online: online, board: board, now: Date())
    }

    private func cache() -> WantSearchCache {
        WantSearchCache(directory: URL.temporaryDirectory.appending(path: "want-test-\(UUID().uuidString)"))
    }

    @Test func nuncaDevolveSemCoordenadaNemOnline() {
        let hits = [
            PlaceHit(id: "site", name: "Seiko loja online", address: nil, lat: nil, lng: nil, types: ["store"]),
            PlaceHit(id: "web", name: "Seiko Online Store", address: nil, lat: 35.69, lng: 139.70, types: ["point_of_interest", "establishment"]),
            PlaceHit(id: "ecom", name: "Seiko e-shop", address: "Tóquio", lat: 35.69, lng: 139.70, types: ["online_store"]),
            PlaceHit(id: "fechou", name: "Relojoaria", address: "Tóquio", lat: 35.69, lng: 139.70, types: ["jewelry_store"],
                     businessStatus: "CLOSED_PERMANENTLY"),
            PlaceHit(id: "bic", name: "Bic Camera", address: "Shinjuku", lat: 35.6918, lng: 139.7028, types: ["electronics_store", "store"]),
        ]
        let (kept, dropped) = WantSearch.filter(hits, category: WantCategory.match("relógio"))
        #expect(kept.map(\.id) == ["bic"])
        #expect(dropped == 4)
        #expect(kept.allSatisfy { $0.lat != nil && $0.lng != nil })
    }

    @Test func pedidoTemTipoRaioOpenNowEDistancia() {
        var i = input("comer um tonkatsu hoje")
        var q = WantSearch.query(for: i)
        #expect(q.includedType == "restaurant")
        #expect(q.openNow)
        #expect(q.radius == 6_000)
        let body = PlacesService.body(for: q)
        #expect(body["strictTypeFiltering"] as? Bool == true)
        #expect(body["rankPreference"] as? String == "DISTANCE")
        #expect((body["locationBias"] as? [String: Any])?["circle"] != nil)
        i = input("quero comprar um Seiko")
        q = WantSearch.query(for: i)
        #expect(q.includedType == nil) // vários tipos: filtro local
        #expect(!q.openNow)
        #expect(PlacesService.body(for: q)["strictTypeFiltering"] == nil)
        #expect(PlacesService.wantMask.contains("places.location") && !PlacesService.wantMask.contains("OpeningHours"))
    }

    @Test func seikoEmShinjukuJuntaPlacesEMarca() async {
        let bic = PlaceHit(id: "bic", name: "Bic Camera Shinjuku Higashi-guchi", address: "Shinjuku", lat: 35.69185, lng: 139.7028,
                           types: ["electronics_store"])
        let out = await WantSearch.run(input("quero comprar um Seiko"), provider: Stub(hits: [bic]), cache: cache())
        #expect(out.results.first?.name == "Bic Camera Shinjuku Higashi-guchi")
        #expect(out.results.contains { $0.name == "Seiko House Ginza (Wako)" && $0.origin == .brand })
        #expect(out.results.allSatisfy { $0.lat != 0 && $0.lng != 0 })
        // Loja de marca de outra cidade (Kyoto) não entra.
        #expect(!out.results.contains { $0.name.contains("Kyoto") })
    }

    @Test func offlineMostraOQueEstaNoAparelho() async {
        let board = [WantBoardPlace(id: "p9", name: "Café com pão de queijo", lat: -19.937, lng: -43.935)]
        let out = await WantSearch.run(input("quero comer um pão de queijo", region: .bh, online: false, board: board),
                                       provider: Stub(hits: []), cache: cache())
        #expect(out.offline)
        #expect(out.results.first?.origin == .board)
        #expect(out.results.contains { $0.name == "Mercado Central de BH" })
        let failed = await WantSearch.run(input("quero comer um pão de queijo", region: .bh), provider: Offline(), cache: cache())
        #expect(failed.offline)
    }

    @Test func mesmaConsultaNaoRepete() async throws {
        let c = cache()
        let q = WantSearch.query(for: input("quero comprar um Seiko"))
        let hit = PlaceHit(id: "x", name: "X", address: "a", lat: 35.69, lng: 139.70, types: ["electronics_store"])
        _ = try await c.fetch(q, now: Date()) { [hit] }
        #expect(await c.cached(q, now: Date())?.map(\.id) == ["x"])
        #expect(await c.cached(q, now: Date().addingTimeInterval(25 * 3600)) == nil)
    }

    @Test func lojasDeMarcaCarregam() {
        #expect(BrandStores.all.count >= 10)
        #expect(BrandStores.all.allSatisfy { $0.lat != 0 && $0.lng != 0 && !$0.categories.isEmpty })
        #expect(Set(BrandStores.all.map(\.region)) == ["jp", "bh", "it"])
    }
}

extension WantSearchTests {
    @Test func mesmoLugarDoBoardEDaTabelaApareceUmaVez() {
        let board = WantResult(id: "board:p1", name: "Mercado Central (queijo e cachaça)", lat: -19.9233, lng: -43.9437, origin: .board)
        let brand = WantResult(id: "brand:m", name: "Mercado Central de BH", lat: -19.9234, lng: -43.9436, origin: .brand, note: "cachaça")
        let out = WantSearch.merge(board: [board], places: [], brand: [brand])
        #expect(out.count == 1)
        #expect(out.first?.origin == .board)
    }
}
