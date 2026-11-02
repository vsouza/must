import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 17 · A (fatia 8A, ajustes): "no board" pelo placeId ou pelo nome igual a menos de 150 m; debug fora do host de testes.
@MainActor
struct BuscarNomeTests {
    static let naka = CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)
    static let mameyaSpot = CLLocationCoordinate2D(latitude: 35.668368, longitude: 139.710888)
    static let roasterySpot = CLLocationCoordinate2D(latitude: 35.6683, longitude: 139.7070)

    static func place(_ name: String, placeId: String? = nil, at c: CLLocationCoordinate2D) -> Place {
        let p = Place(id: "t-\(name)", name: name, cityId: "tokyo1", lat: c.latitude, lng: c.longitude)
        p.placeId = placeId
        p.approx = true
        return p
    }

    static func suggestion(_ name: String, id: String, meters: Int?, types: [String] = ["cafe"]) -> PlaceSuggestion {
        PlaceSuggestion(placeId: id, name: name, secondary: "Omotesando, Shibuya", segments: [.init(text: name, highlighted: false)],
                        types: types, distanceMeters: meters)
    }

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Int {
        Int(BuscarNomeModel.distance(a, b).rounded())
    }

    @Test func samePlaceIdIsOnBoardWhateverTheDistance() {
        let board = [Self.place("Koffee Mameya", placeId: "ChIJ-x", at: Self.mameyaSpot)]
        let s = Self.suggestion("Koffee Mameya", id: "ChIJ-x", meters: 9_999)
        #expect(BuscarNomeModel.boardMatch(for: s, coordinate: nil, origin: Self.naka, places: board) != nil)
    }

    @Test func sameNameNearbyWithoutPlaceIdIsOnBoard() {
        // j09 do board: sem placeId, coordenada aproximada. A sugestão vem a uma distância igual à dele, da origem.
        let board = [Self.place("Koffee Mameya", at: Self.mameyaSpot)]
        let s = Self.suggestion("Koffee Mameya", id: "fake-koffee-mameya", meters: Self.meters(Self.naka, Self.mameyaSpot))
        #expect(BuscarNomeModel.boardMatch(for: s, coordinate: nil, origin: Self.naka, places: board)?.name == "Koffee Mameya")
        // Com a coordenada do Details, a distância é exata.
        #expect(BuscarNomeModel.boardMatch(for: s, coordinate: Self.mameyaSpot, origin: Self.naka, places: board) != nil)
    }

    @Test func differentNameOrFarAwayIsNotOnBoard() {
        let board = [Self.place("Koffee Mameya", at: Self.mameyaSpot)]
        // "Roastery" fica a ~120 m do board, mas não é o mesmo nome.
        let roastery = Self.suggestion("Koffee Mameya Roastery", id: "fake-koffee-roastery", meters: Self.meters(Self.naka, Self.roasterySpot))
        #expect(BuscarNomeModel.boardMatch(for: roastery, coordinate: nil, origin: Self.naka, places: board) == nil)
        // Mesmo nome, mas 1 km fora da distância do board.
        let far = Self.suggestion("Koffee Mameya", id: "other", meters: Self.meters(Self.naka, Self.mameyaSpot) + 1_000)
        #expect(BuscarNomeModel.boardMatch(for: far, coordinate: nil, origin: Self.naka, places: board) == nil)
        #expect(BuscarNomeModel.boardMatch(for: far, coordinate: Self.roasterySpot, origin: Self.naka, places: board) == nil)
    }

    @Test func cafeTypeGetsCupAndListFromType() {
        let cafe = Self.suggestion("Koffee Mameya", id: "a", meters: 100, types: ["cafe", "establishment"])
        #expect(cafe.isCafe)
        #expect(BuscarNomeModel.suggestedListId(types: cafe.types) == "drink")
        let store = Self.suggestion("Loja", id: "b", meters: 100, types: ["store"])
        #expect(!store.isCafe)
    }

    @Test func debugFlagsStayOffOnTheTestHost() {
        #expect(DebugFlags.isTestHost)
        #expect(DebugFlags.string("debugRoutes") == nil)
        #expect(DebugFlags.has("-gallery") == false)
    }
}
