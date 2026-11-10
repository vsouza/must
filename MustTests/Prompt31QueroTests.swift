import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 31 · Quero… nunca volta vazio à toa: origem certa, o board por tipo de Must, fontes externas por vontade e vazio com motivo.
@MainActor
struct Prompt31QueroTests {
    private let brasil = CLLocationCoordinate2D(latitude: -19.9385, longitude: -43.9343)
    private let toquio = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)

    private var nakano: Area { AreaCatalog.areas(for: .jp).first { $0.id == "nakano" }! }
    private var savassi: Area? { AreaCatalog.areas(for: .bh).first }

    // MARK: Origem

    @Test func gpsNoBrasilNaViagemAoJapaoUsaOBairro() {
        let r = WantOrigin.resolve(gps: brasil, cityCenter: toquio, hasCurrentCity: true, areaHint: nakano, planArea: nil)
        #expect(r.basis == .area)
        #expect(r.origin.latitude == nakano.centroid.lat && r.origin.longitude == nakano.centroid.lng)
    }

    @Test func gpsDentroDaCidadeValeEFicaOGps() {
        let here = CLLocationCoordinate2D(latitude: 35.69, longitude: 139.70)
        let r = WantOrigin.resolve(gps: here, cityCenter: toquio, hasCurrentCity: true, areaHint: nakano, planArea: nil)
        #expect(r.basis == .gps && r.origin.latitude == 35.69)
    }

    @Test func semBairroUsaACidadeDeHojeESenaoAPrimeiraDaViagem() {
        let today = WantOrigin.resolve(gps: brasil, cityCenter: toquio, hasCurrentCity: true, areaHint: nil, planArea: nil)
        #expect(today.basis == .todayCity && today.origin.latitude == toquio.latitude)
        let future = WantOrigin.resolve(gps: brasil, cityCenter: toquio, hasCurrentCity: false, areaHint: nil, planArea: nil)
        #expect(future.basis == .firstCity && future.origin.longitude == toquio.longitude)
    }

    @Test func bairroDeOutraCidadeNaoVale() throws {
        // A capa ficou com um bairro de BH: numa viagem ao Japão ele não vira origem.
        let bh = try #require(savassi)
        let r = WantOrigin.resolve(gps: brasil, cityCenter: toquio, hasCurrentCity: false, areaHint: bh, planArea: nil)
        #expect(r.basis == .firstCity)
    }

    @Test func envDeViagemFuturaSaiDaPrimeiraCidade() {
        let day: TimeInterval = 86_400
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let city = City(id: "tokyo1", name: "Tóquio", from: start, to: start.addingTimeInterval(5 * day), tz: "Asia/Tokyo", currency: "JPY",
                        lat: 35.6812, lng: 139.7671)
        let trip = TripInfo(start: start, end: start.addingTimeInterval(13 * day), cities: [city])
        let now = start.addingTimeInterval(-60 * day)
        let env = QueroEnv.make(region: .jp, now: now, places: [], trip: trip, settings: nil, plan: nil, gps: brasil, online: true, upcoming: [])
        #expect(env.originBasis == .firstCity)
        #expect(abs(env.origin.latitude - 35.6812) < 0.001)
        #expect(env.cityGroup == "tokyo")
        // GPS no Brasil + bairro da capa = Nakano.
        let nk = QueroEnv.make(region: .jp, now: now, places: [], trip: trip, settings: nil, plan: nil, gps: brasil, online: true, upcoming: [],
                               areaHint: nakano)
        #expect(nk.originBasis == .area && nk.areaName == "Nakano")
    }

    // MARK: Cada verbo pega o tipo certo de Must

    private func board() -> [WantBoardPlace] {
        func p(_ id: String, _ list: String, sub: String? = nil) -> WantBoardPlace {
            WantBoardPlace(id: id, name: "Lugar \(id)", lat: 35.0, lng: 135.7, listId: list, sub: sub)
        }
        return [p("e", "eat"), p("d", "drink"), p("c", "drink", sub: "Café"), p("s", "see"), p("sh", "shop"), p("l", "listen"),
                p("ph", "photo"), p("a", "art"), p("do", "do")]
    }

    private func boardIds(_ text: String) throws -> Set<String> {
        let intent = try #require(WantParser.parseLocal(text), "'\(text)' precisa virar um pedido, não nada")
        let input = WantSearchInput(intent: intent, region: .jp, center: toquio, cityGroup: "tokyo", online: true, board: board(),
                                    now: Date(), boardAnyDistance: true)
        return Set(WantSearch.boardResults(input, category: WantCategory.of(intent)).compactMap(\.boardPlaceId))
    }

    @Test func cadaVerboMapeiaProTipoDeMust() throws {
        #expect(try boardIds("comer") == ["e"])
        #expect(try boardIds("beber") == ["d", "c"])
        #expect(try boardIds("café") == ["c"])
        #expect(try boardIds("ver") == ["s"])
        #expect(try boardIds("comprar") == ["sh"])
        #expect(try boardIds("ouvir") == ["l"])
        #expect(try boardIds("noite") == ["l", "d", "c"])
        #expect(try boardIds("foto") == ["ph"])
        #expect(try boardIds("arte") == ["a"])
        #expect(try boardIds("fazer") == ["do"])
    }

    @Test func soOVerboNaoViraNada() {
        // O "comer em Nakano não achou nada": "comer" sozinho caía fora do parser e a busca nem saía.
        for word in ["comer", "beber", "ver", "fazer", "comprar", "fotografar", "noite"] {
            #expect(WantParser.parseLocal(word) != nil, "\(word)")
        }
        #expect(WantParser.parseLocal("comer")?.object == "comer")
        #expect(WantParser.parseLocal("quero comer tonkatsu")?.object == "tonkatsu")
    }

    @Test func boardNaoCortaPorDistancia() throws {
        let far = WantBoardPlace(id: "far", name: "Longe", lat: 34.99, lng: 135.76, listId: "eat")
        let intent = try #require(WantParser.parseLocal("comer"))
        var input = WantSearchInput(intent: intent, region: .jp, center: toquio, cityGroup: "tokyo", online: true, board: [far], now: Date())
        input.boardAnyDistance = true
        #expect(WantSearch.boardResults(input, category: WantCategory.of(intent)).count == 1)
    }

    // MARK: Fontes externas

    private struct Stub: WantPlacesSearching {
        var hits: [PlaceHit]
        var isConfigured = true
        func searchPlaces(_ query: PlacesTextQuery) async throws -> [PlaceHit] { hits }
    }

    private func cache() -> WantSearchCache {
        WantSearchCache(directory: URL.temporaryDirectory.appending(path: "p31-\(UUID().uuidString)"))
    }

    /// Meio-dia em Tóquio (fixo): com `Date()`, depois das 23h de Tóquio o show "daqui a 1 h" já era amanhã.
    private static let noon = ISO8601DateFormatter().date(from: "2026-11-13T03:00:00Z")!

    private func input(_ text: String, online: Bool = true, shows: [ShowEvent] = []) throws -> WantSearchInput {
        let center = CLLocationCoordinate2D(latitude: nakano.centroid.lat, longitude: nakano.centroid.lng)
        var i = WantSearchInput(intent: try #require(WantParser.parseLocal(text)), region: .jp, center: center, cityGroup: "tokyo",
                                online: online, board: [], now: Self.noon)
        i.shows = shows
        return i
    }

    @Test func comerBuscaRestauranteNoBairroEmVezDaPalavraComer() throws {
        let i = try input("comer")
        let q = WantSearch.query(for: i)
        #expect(q.text == "restaurant" && q.includedType == "restaurant")
        #expect(abs(q.lat - nakano.centroid.lat) < 0.0001)
        #expect(WantSearch.query(for: try input("ouvir")).text == "live music")
        #expect(WantSearch.query(for: try input("ver")).text == "tourist attraction")
    }

    @Test func comerEmNakanoTrazOGoogleNaFaixaDeFora() async throws {
        let hit = PlaceHit(id: "g1", name: "Ramen Nakano", address: "Nakano", lat: 35.7060, lng: 139.6660, types: ["restaurant"],
                           primaryType: "restaurant")
        let out = await WantSearch.run(try input("comer"), provider: Stub(hits: [hit]), cache: cache())
        #expect(out.results.map(\.name) == ["Ramen Nakano"])
        #expect(out.outsideNote == nil)
    }

    @Test func semRedeSemChaveOuDesligadoADizOMotivo() async throws {
        let off = await WantSearch.run(try input("comer", online: false), provider: Stub(hits: []), cache: cache())
        #expect(off.offline && off.outsideNote == "sem internet")
        let noKey = await WantSearch.run(try input("comer"), provider: Stub(hits: [], isConfigured: false), cache: cache())
        #expect(noKey.outsideNote == "sem chave do Google")
        let none = await WantSearch.run(try input("comer"), provider: nil, cache: cache())
        #expect(none.outsideNote == "dados ao vivo desligados")
    }

    @Test func verSomaAWikipediaEOuvirSomaOEmCartaz() async throws {
        let wiki = WantExtras { lat, lng, _ in
            [NearbyPlace(name: "Santuário Nakano", lat: lat + 0.001, lng: lng, sources: [.wikipedia])]
        }
        let seen = await WantSearch.run(try input("ver"), provider: Stub(hits: []), extras: wiki, cache: cache())
        #expect(seen.results.contains { $0.name == "Santuário Nakano" })
        // Comer não chama a Wikipedia.
        let ate = await WantSearch.run(try input("comer"), provider: Stub(hits: []), extras: wiki, cache: cache())
        #expect(ate.results.isEmpty)

        let now = Self.noon
        let show = ShowEvent(id: "s1", kind: .show, title: "Jazz no Nakano", venue: "Sunplaza", lat: 35.7062, lng: 139.6655,
                             startsAt: now.addingTimeInterval(3600), source: .feed)
        let heard = await WantSearch.run(try input("ouvir", shows: [show]), provider: Stub(hits: []), cache: cache())
        #expect(heard.results.contains { $0.name == "Jazz no Nakano" && $0.note?.hasPrefix("em cartaz hoje") == true })
    }

    // MARK: Carrossel e viagens

    @Test func carrosselAbreComTodasAsFotosDoLugar() throws {
        let refs = (0..<8).map { PlacePhotoRef(name: "places/x/photos/\($0)", author: "Ana") }
        let pages = PhotoViewer.Page.all(placeId: "x", refs: refs, resolver: nil)
        #expect(pages.count == 5 && pages.map(\.id) == [0, 1, 2, 3, 4])
        #expect(pages[2].credit == "foto · Google · @Ana")
        let carousel = try #require(PhotoCarousel.place(placeId: "x", refs: refs, start: 3, resolver: nil))
        #expect(carousel.start == 3)
        #expect(PhotoCarousel.place(placeId: "x", refs: [], resolver: nil) == nil)
    }

    @Test func moedaDaViagemComCodigoESimbolo() {
        #expect(TripSwitcherModel.currencyLabel(.jp) == "JPY ¥")
        #expect(TripSwitcherModel.currencyLabel(.it) == "EUR €")
        #expect(TripSwitcherModel.currencyLabel(.bh) == "BRL R$")
    }
}
