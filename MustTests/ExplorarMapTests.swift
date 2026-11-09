import CoreLocation
import Foundation
import Testing
@testable import Must

/// Explorar = o mapa (prompt 32 §4): camadas, filtro por lista, o que está na tela, a lista agrupada, o "Ver no mapa",
/// a abertura, o centro como contexto e as alturas do painel. Tudo puro (sem rede, sem SwiftData, sem relógio real).
@MainActor
struct ExplorarMapTests {
    private let shinjuku = CLLocationCoordinate2D(latitude: 35.6905, longitude: 139.7005)
    private let lists: [(id: String, name: String)] = [("eat", "eat"), ("drink", "drink"), ("shop", "shop"), ("photo", "photo")]

    private func must(_ id: String, list: String? = "eat", lat: Double = 35.6905, lng: Double = 139.7005, done: Bool = false,
                      stop: Int? = nil, next: Bool = false, open: PinOpenState = .unknown, golden: Bool = false) -> ExplorarMapItem {
        ExplorarMapItem(id: id, kind: .must, name: id, lat: lat, lng: lng, placeId: id, listId: list,
                        listName: list.map { MapMustFilter.label($0) } ?? "", color: list.flatMap(MustColor.init(rawValue:)),
                        done: done, stopNumber: stop, isNextStop: next, open: open, golden: golden)
    }

    private func event(_ id: String) -> ExplorarMapItem {
        ExplorarMapItem(id: "ev-\(id)", kind: .event, name: id, lat: 35.69, lng: 139.70, eventId: id)
    }

    private func outside(_ id: String, lat: Double = 35.69, lng: Double = 139.70) -> ExplorarMapItem {
        ExplorarMapItem(id: "out-\(id)", kind: .indicated, name: id, lat: lat, lng: lng)
    }

    // MARK: Camadas

    @Test func mustsLayerNeverTurnsOff() {
        let layers = ExplorarMapLayer.toggled(ExplorarMapLayer.defaults, .musts)
        #expect(layers.contains(.musts))
        let off = ExplorarMapLayer.toggled([.musts, .today], .today)
        #expect(off == [.musts])
    }

    @Test func indicatedIsOffByDefault() {
        #expect(!ExplorarMapLayer.defaults.contains(.indicated))
        #expect(ExplorarMapLayer.defaults.contains(.musts))
    }

    @Test func eventsNeedNowLayerAndIndicatedNeedIndicatedLayer() {
        let items = [must("a"), event("show"), outside("x")]
        let base = ExplorarMapFilter.shown(items, layers: [.musts], filter: MapMustFilter())
        #expect(base.map(\.id) == ["a"])
        let now = ExplorarMapFilter.shown(items, layers: [.musts, .now], filter: MapMustFilter())
        #expect(Set(now.map(\.id)) == ["a", "ev-show"])
        let all = ExplorarMapFilter.shown(items, layers: [.musts, .now, .indicated], filter: MapMustFilter())
        #expect(all.count == 3)
    }

    @Test func listFilterOnlyHidesMusts() {
        let items = [must("a", list: "eat"), must("b", list: "drink"), event("show")]
        let filter = MapMustFilter(listIds: ["drink"])
        let shown = ExplorarMapFilter.shown(items, layers: [.musts, .now], filter: filter)
        #expect(Set(shown.map(\.id)) == ["b", "ev-show"])
    }

    // MARK: Pinos

    @Test func pinsFollowLayers() {
        let items = [must("stop", stop: 2, next: true), must("feito", done: true), must("aberto", open: .open)]
        let withToday = ExplorarMapPins.pins(items, layers: [.musts, .today, .now], selected: nil)
        #expect(withToday[0].kind == .v9(style: .stop(number: 2, next: true, done: false), selected: false))
        #expect(withToday[1].kind == .v9(style: .done, selected: false))
        #expect(withToday[2].kind == .v9(style: .must(letter: "E", rgb: ExplorarMapPins.rgb(.eat), state: .open), selected: false))
        // Sem Hoje a parada vira pino normal; sem Agora o estado de horário some.
        let plain = ExplorarMapPins.pins(items, layers: [.musts], selected: "aberto")
        #expect(plain[0].kind == .v9(style: .must(letter: "E", rgb: ExplorarMapPins.rgb(.eat), state: .unknown), selected: false))
        #expect(plain[2].kind == .v9(style: .must(letter: "E", rgb: ExplorarMapPins.rgb(.eat), state: .unknown), selected: true))
    }

    @Test func goldenLightsUpPhotoPinsWithNowLayer() {
        let photo = must("rua", list: "photo", open: .closed, golden: true)
        let pin = ExplorarMapPins.pins([photo], layers: [.musts, .now], selected: nil)[0]
        #expect(pin.kind == .v9(style: .must(letter: "P", rgb: ExplorarMapPins.rgb(.photo), state: .open), selected: false))
    }

    @Test func eachListHasItsOwnColor() {
        let colors = Set(MustColor.allCases.map(ExplorarMapPins.rgb))
        #expect(colors.count == MustColor.allCases.count)
    }

    @Test func routeSplitsDoneAndFuture() {
        let items = [must("a", lat: 35.69, stop: 1, open: .open), must("b", lat: 35.70, done: true, stop: 2),
                     must("c", lat: 35.71, stop: 3)]
        let route = ExplorarMapPins.route(items, layers: [.musts, .today])
        #expect(route.done.count == 1)
        #expect(route.future.count == 1)
        #expect(ExplorarMapPins.route(items, layers: [.musts]).future.isEmpty)
    }

    // MARK: Na tela e lista grande

    @Test func visibleIsInsideBoundsSortedByDistance() {
        let near = must("perto", lat: 35.6906, lng: 139.7006)
        let far = must("longe", lat: 35.6950, lng: 139.7050)
        let out = must("fora", lat: 35.80, lng: 139.90)
        let rect = ExplorarCenter.rect(center: shinjuku, widthMeters: 1_600, size: CGSize(width: 400, height: 800))
        let visible = ExplorarMapFilter.visible([far, out, near], in: rect, center: shinjuku)
        #expect(visible.map(\.id) == ["perto", "longe"])
    }

    @Test func sectionsFollowBoardOrderWithDoneLast() {
        let items = [must("d1", list: "drink"), must("e1", list: "eat", done: true), must("e2", list: "eat"),
                     outside("x"), event("show")]
        let sections = ExplorarMapFilter.sections(items, lists: lists)
        #expect(sections.map(\.title) == ["Eat", "Drink", "Eventos de hoje", "Indicados"])
        #expect(sections[0].items.map(\.id) == ["e2", "e1"])
    }

    @Test func chipsOnlyListsWithPlaces() {
        let chips = ExplorarMapFilter.chips(items: [must("a", list: "eat"), must("b", list: "shop"), event("x")], lists: lists)
        #expect(chips.map(\.label) == ["Eat", "Shop"])
    }

    // MARK: Centro do mapa

    @Test func smallDragDoesNotRerank() {
        let moved = CLLocationCoordinate2D(latitude: shinjuku.latitude + 0.0002, longitude: shinjuku.longitude)
        #expect(!ExplorarCenter.moved(from: shinjuku, to: moved))
        let far = CLLocationCoordinate2D(latitude: shinjuku.latitude + 0.002, longitude: shinjuku.longitude)
        #expect(ExplorarCenter.moved(from: shinjuku, to: far))
        #expect(ExplorarCenter.moved(from: nil, to: shinjuku))
    }

    @Test func openingPrefersGPSInsideTripCityThenContextThenCity() {
        let cityCenter = CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671)
        let nakano = AreaCatalog.jp.first { $0.id == "nakano" }
        #expect(ExplorarCenter.opening(gps: shinjuku, cityCenter: cityCenter, contextArea: nakano).latitude == shinjuku.latitude)
        let saoPaulo = CLLocationCoordinate2D(latitude: -23.55, longitude: -46.63)
        let fromContext = ExplorarCenter.opening(gps: saoPaulo, cityCenter: cityCenter, contextArea: nakano)
        #expect(fromContext.latitude == nakano?.centroid.lat)
        let fromCity = ExplorarCenter.opening(gps: nil, cityCenter: cityCenter, contextArea: nil)
        #expect(fromCity.latitude == cityCenter.latitude)
    }

    @Test func rankKeepsThreeCardsWithoutPlan() {
        let region = Region.jp
        let now = Date(timeIntervalSince1970: 1_794_538_800)
        let places = (0..<6).map { i in
            SuggestPlace(id: "p\(i)", name: "Lugar \(i)", listName: "eat", color: "eat", kind: .place, sub: nil,
                         lat: shinjuku.latitude + Double(i) * 0.0005, lng: shinjuku.longitude, done: false,
                         state: .open(until: "23:00"), windows: [])
        }
        let plan = SuggestPlanStop(id: "s", placeId: "p0", label: "Lugar 0", action: "saia 12:10", lat: shinjuku.latitude, lng: shinjuku.longitude)
        let inputs = SuggestInputs(region: region, now: now, here: shinjuku, places: places, plan: plan)
        let cards = ExplorarMapModel.rank(inputs)
        #expect(cards.count <= 3)
        #expect(!cards.isEmpty)
        #expect(!cards.contains { $0.kind == .plan })
    }

    // MARK: Ver no mapa

    @Test func showcaseOnlyItsPins() {
        let board = [must("a"), must("b"), must("c")]
        let showcase = MapShowcase(title: "ramen", placeIds: ["a", "c", "nao-existe"],
                                   outside: [.init(name: "Konbini", lat: 35.69, lng: 139.70), .init(name: "sem", lat: 0, lng: 0)])
        let result = ExplorarShowcaseLogic.items(showcase, board: board)
        #expect(result.extra.count == 1)
        let shown = ExplorarMapFilter.shown(board + result.extra, layers: [.musts], filter: MapMustFilter(listIds: ["drink"]),
                                            showcase: result.ids)
        // O filtro e as camadas não valem no "Ver no mapa": só o pedido.
        #expect(Set(shown.map(\.id)) == Set(["a", "c"] + result.extra.map(\.id)))
    }

    @Test func showcaseFitsOnlyTheNearestCity() {
        let kyoto = must("k", lat: 35.0116, lng: 135.7681)
        let tokyo = [must("t1"), must("t2", lat: 35.70, lng: 139.71)]
        let points = ExplorarShowcaseLogic.fitPoints(tokyo + [kyoto], near: shinjuku)
        #expect(points.count == 2)
        #expect(ExplorarShowcaseLogic.fitPoints([kyoto] + tokyo, near: CLLocationCoordinate2D(latitude: 35.0, longitude: 135.77)).count == 1)
    }

    @Test func modelConsumesShowcaseAndClears() {
        let model = ExplorarMapModel()
        #expect(model.setShowcase(MapShowcase(title: "x", outside: [.init(name: "A", lat: 35.69, lng: 139.70)])).count == 1)
        #expect(model.shown.count == 1)
        model.setShowcase(nil)
        #expect(model.showcase == nil)
        #expect(model.shown.isEmpty)
    }

    // MARK: Painel

    @Test func detentHeightsAndSettle() {
        let collapsed: CGFloat = 130, available: CGFloat = 700
        #expect(ExplorarDetent.height(.collapsed, collapsed: collapsed, available: available) == 130)
        #expect(ExplorarDetent.height(.medium, collapsed: collapsed, available: available) == 350)
        #expect(ExplorarDetent.height(.large, collapsed: collapsed, available: available) == 700)
        #expect(ExplorarDetent.settle(predicted: 600, collapsed: collapsed, available: available) == .large)
        #expect(ExplorarDetent.settle(predicted: 300, collapsed: collapsed, available: available) == .medium)
        #expect(ExplorarDetent.settle(predicted: 90, collapsed: collapsed, available: available) == .collapsed)
        #expect(ExplorarDetent.collapsed.next == .medium)
        #expect(ExplorarDetent.large.next == .collapsed)
        // Dynamic Type enorme: o recolhido nunca passa do disponível e o médio nunca fica menor que ele.
        #expect(ExplorarDetent.height(.medium, collapsed: 500, available: 600) == 500)
    }

    @Test func pinStateClosingSoon() {
        #expect(ExplorarMapModel.pinState(.open(until: "12:20"), minutesNow: 12 * 60) == .closingSoon(remaining: 20.0 / 30))
        #expect(ExplorarMapModel.pinState(.open(until: "22:00"), minutesNow: 12 * 60) == .open)
        #expect(ExplorarMapModel.pinState(.closed(opensDay: nil, opensAt: "18:00"), minutesNow: 0) == .closed)
    }
}
