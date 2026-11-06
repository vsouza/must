import CoreLocation
import Foundation
import Testing
@testable import Must

/// Filtro por Must no mapa (prompt 27 §2.b): contagem por lista; o filtro não esconde metrô, posição, distância nem busca;
/// persistência por região.
struct MapFilterTests {
    private let c = CLLocationCoordinate2D(latitude: 35.69, longitude: 139.70)

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "map-filter-\(UUID().uuidString)")! }

    @Test func contagemPorLista() {
        let places: [String?] = ["eat", "eat", "drink", "eat", nil, "art"]
        let lists = [(id: "eat", name: "eat"), (id: "drink", name: "drink"), (id: "see", name: "see"), (id: "art", name: "art")]
        let (total, pills) = MapMustFilter.counts(listIdsOfPlaces: places, lists: lists)
        #expect(total == 6)
        // Na ordem do board; lista vazia (see) não vira pílula.
        #expect(pills.map(\.label) == ["Eat", "Drink", "Art"])
        #expect(pills.map(\.count) == [3, 1, 1])
        #expect(MapMustFilter.label("must do") == "Do")
    }

    @Test func filtroSoEscondePinoDeLugar() {
        let pins = [
            MapPin(id: "today-a", coordinate: c, kind: .today(number: 1, status: .next, label: nil), placeId: "a", layer: .today),
            MapPin(id: "tomorrow-b", coordinate: c, kind: .tomorrow(number: 1), placeId: "b", layer: .tomorrow),
            MapPin(id: "must-c", coordinate: c, kind: .unplanned(kanji: "D", color: .drink, open: .open), placeId: "c", layer: .unplanned),
            MapPin(id: "done-d", coordinate: c, kind: .today(number: 0, status: .done, label: nil), placeId: "d", layer: .done),
            MapPin(id: "distance-badge", coordinate: c, kind: .badge(text: "2 km"), placeId: nil, layer: .unplanned),
            MapPin(id: "result-x", coordinate: c, kind: .result(number: 1), placeId: nil, layer: .search),
        ]
        let listOf = ["a": "eat", "b": "drink", "c": "drink", "d": "eat"]
        var f = MapMustFilter()
        #expect(f.apply(pins, listOf: listOf).count == pins.count) // Todos
        f.toggle("drink")
        let shown = f.apply(pins, listOf: listOf).map(\.id)
        #expect(shown == ["tomorrow-b", "must-c", "distance-badge", "result-x"])
        // Várias: eat + drink = tudo de volta.
        f.toggle("eat")
        #expect(f.apply(pins, listOf: listOf).count == pins.count)
        // Desligar todas volta pro Todos.
        f.toggle("eat"); f.toggle("drink")
        #expect(f.isAll)
    }

    @Test func metroEVoceNaoSaoPinos() {
        // Metrô é camada de linha e "você" é anotação própria: o filtro nem passa por eles.
        #expect(!MapMustFilter.filteredLayers.contains(.metro))
        #expect(!MapMustFilter.filteredLayers.contains(.search))
        #expect(!MapLayer.legend.contains(.search))
    }

    @Test func persistePorRegiao() {
        let d = defaults()
        var jp = MapMustFilter()
        jp.toggle("eat")
        jp.save(.jp, defaults: d)
        #expect(MapMustFilter.load(.jp, defaults: d).listIds == ["eat"])
        #expect(MapMustFilter.load(.bh, defaults: d).isAll)
        #expect(d.stringArray(forKey: "map.mustFilter.jp") == ["eat"])
        jp.showAll()
        jp.save(.jp, defaults: d)
        #expect(MapMustFilter.load(.jp, defaults: d).isAll)
    }
}
