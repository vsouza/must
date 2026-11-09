import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 32 §6: o Pedir sempre termina num lugar com coordenada ("Ver no mapa"). Fakes, sem rede, data fixa.
@MainActor
struct QueroAcceptanceTests {
    /// 13/11/2026 12:00 em Tóquio (fixo).
    private static let noon = Date(timeIntervalSince1970: 1_794_538_800)
    private let here = CLLocationCoordinate2D(latitude: 35.6905, longitude: 139.7005)

    private func env(online: Bool = true, board: [WantBoardPlace] = [], shows: [ShowEvent] = []) -> QueroEnv {
        var e = QueroEnv.make(region: .jp, now: Self.noon, places: [], trip: nil, settings: nil, plan: nil, gps: here, online: online,
                              upcoming: [], shows: shows)
        e.useModel = false
        e.boardAnyDistance = true
        e.board = board
        return e
    }

    private func temp() -> WantSearchCache { WantSearchCache(directory: URL.temporaryDirectory.appending(path: "r32-\(UUID().uuidString)")) }

    private struct Stub: WantPlacesSearching {
        var hits: [PlaceHit]
        var isConfigured = true
        func searchPlaces(_ query: PlacesTextQuery) async throws -> [PlaceHit] { hits }
    }

    private func ask(_ text: String, env: QueroEnv, provider: (any WantPlacesSearching)? = FakeWantPlaces()) async -> QueroModel {
        let model = QueroModel(text: text, provider: provider, questionCache: temp())
        await model.perform(text, env)
        return model
    }

    private func hasCoordinates(_ s: MapShowcase?) -> Bool {
        guard let s else { return false }
        return !(s.placeIds.isEmpty && s.outside.isEmpty) && s.outside.allSatisfy { $0.lat != 0 || $0.lng != 0 }
    }

    @Test func comprarUmSeikoSoLojaFisica() async {
        let m = await ask("quero comprar um Seiko", env: env())
        #expect(m.phase == .done && m.question == nil)
        #expect(!m.rows.isEmpty)
        #expect(m.rows.allSatisfy { ($0.result.lat != 0 || $0.result.lng != 0) && !$0.result.name.localizedCaseInsensitiveContains("online") })
        #expect(m.rows.allSatisfy { !($0.result.id == "fake-site" || $0.result.id == "fake-online") })
        #expect(hasCoordinates(m.showcase()))
    }

    private static let konbiniHits = [
        PlaceHit(id: "k-far", name: "7-Eleven Shinjuku Sul", address: "Shinjuku", lat: 35.6850, lng: 139.7000, types: ["convenience_store"],
                 primaryType: "convenience_store", businessStatus: "OPERATIONAL"),
        PlaceHit(id: "k-near", name: "7-Eleven Kabukicho", address: "Kabukicho", lat: 35.6908, lng: 139.7010, types: ["convenience_store"],
                 primaryType: "convenience_store", businessStatus: "OPERATIONAL"),
        PlaceHit(id: "k-law", name: "Lawson Shinjuku", address: "Shinjuku", lat: 35.6906, lng: 139.7006, types: ["convenience_store"],
                 primaryType: "convenience_store", businessStatus: "OPERATIONAL"),
    ]

    @Test func drinkNoSevenElevenDaReceitasEOKonbiniMaisPerto() async {
        let model = await ask("que drink monto no 7-Eleven?", env: env(), provider: Stub(hits: Self.konbiniHits))
        let q = try? #require(model.question)
        #expect(q?.answer != nil)
        let extras = q?.extras
        #expect((2...3).contains(extras?.recipes.count ?? 0))
        #expect(extras?.recipes.allSatisfy { $0.kind == "drink" } == true)
        #expect(extras?.places.count == 1)
        #expect(extras?.places.first?.name == "7-Eleven Kabukicho")
        #expect(hasCoordinates(model.showcase()))
    }

    @Test func drinkOfflineSoAsReceitasComAviso() async {
        let extras = await QueroQuestionPlaces.resolve("que drink monto no 7-Eleven?", env: env(online: false),
                                                       provider: Stub(hits: Self.konbiniHits), cache: temp())
        #expect((extras?.recipes.count ?? 0) >= 2)
        #expect(extras?.places.isEmpty == true)
        #expect(extras?.note?.contains("sem internet") == true)
    }

    @Test func guiaKonbiniCarregaSemKanji() {
        let all = KonbiniGuide.all
        #expect(all.count >= 5 && all.count <= 8)
        let kanji = CharacterSet(charactersIn: "\u{4E00}"..."\u{9FFF}").union(CharacterSet(charactersIn: "\u{3040}"..."\u{30FF}"))
        for r in all {
            let text = ([r.title, r.step, r.when] + r.ingredients).joined()
            #expect(text.rangeOfCharacter(from: kanji) == nil, "\(r.id)")
        }
    }

    @Test func ruaPraTirarFotoTemLuz() async {
        let board = [WantBoardPlace(id: "ph1", name: "Rua do Omoide", lat: 35.6935, lng: 139.6995, listId: "photo")]
        let m = await ask("rua pra tirar foto", env: env(board: board))
        #expect(m.rows.contains { $0.result.boardPlaceId == "ph1" })
        let row = m.rows.first { $0.result.boardPlaceId == "ph1" }
        #expect(row?.meta.contains("luz dourada") == true)
        #expect(hasCoordinates(m.showcase()))
    }

    @Test func presentePertoDaquiTrazPresentesELojas() async {
        var e = env()
        e.giftPeople = ["Ana"]
        e.giftRows = [GiftNearby(giftId: "g1", title: "Caneta", person: "Ana", quantity: 1, storeName: "Loft Shinjuku", storeId: nil,
                                 coordinate: CLLocationCoordinate2D(latitude: 35.6915, longitude: 139.7020), meters: 300, minutes: 4, isOpen: true)]
        let m = await ask("presente perto daqui", env: e)
        #expect(m.giftRows.count == 1)
        let show = m.showcase()
        #expect(hasCoordinates(show))
        #expect(show?.outside.contains { $0.name == "Loft Shinjuku" } == true)
    }

    @Test func ondeAlmocoPertoTemMustEIndicados() async {
        let board = [WantBoardPlace(id: "e1", name: "Tonkatsu do Seu Must", lat: 35.6910, lng: 139.7010, listId: "eat", until: "22h")]
        let m = await ask("onde almoço perto", env: env(board: board))
        #expect(m.question == nil)
        #expect(m.rows.contains { $0.result.origin == .board && $0.result.boardPlaceId == "e1" })
        #expect(m.rows.contains { $0.result.origin != .board })
        #expect(hasCoordinates(m.showcase()))
    }

    @Test func algoRolandoHojeListaEventosDeHoje() async {
        let show = ShowEvent(id: "s1", kind: .show, title: "Jazz em Nakano", venue: "Sunplaza", lat: 35.7062, lng: 139.6655,
                             startsAt: Self.noon.addingTimeInterval(3600), source: .feed)
        let m = await ask("tem algo rolando hoje?", env: env(shows: [show]))
        #expect(m.question != nil)
        let places = m.question?.extras?.places ?? []
        #expect(places.map(\.name) == ["Jazz em Nakano"])
        #expect(hasCoordinates(m.showcase()))
    }

    @Test func algoRolandoSemEventosDizQueNaoTem() async {
        let m = await ask("tem algo rolando hoje?", env: env())
        #expect(m.question?.extras?.places.isEmpty == true)
        #expect(m.question?.answer?.contains("Não tenho") == true)
    }
}
