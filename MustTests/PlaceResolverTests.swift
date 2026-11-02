import CoreLocation
import Foundation
import Testing
@testable import Must

/// Places de mentira: devolve sempre os mesmos candidatos (nenhuma chamada de rede).
private struct StubPlaces: PlacesProviding {
    var candidates: [PlaceCandidate]
    var isConfigured: Bool { true }

    func searchText(_ query: String, near: CLLocationCoordinate2D, radius: Double, languageCode: String) async throws -> [PlaceCandidate] {
        candidates
    }

    func details(_ placeId: String, languageCode: String) async throws -> PlaceDetails {
        PlaceDetails(id: placeId)
    }
}

private let tsukijiOuter = PlaceCandidate(id: "P1", name: "Tsukiji Outer Market", address: nil,
                                          lat: 35.6654, lng: 139.7707, primaryType: "market")
private let tokyo = CLLocationCoordinate2D(latitude: 35.6654, longitude: 139.7707)

struct PlaceResolverTests {
    @Test func tsukijiAndTsukijiMarketBecomeOneItemWithTwoMentions() async {
        let extracted = PlaceExtractor.extract(text: "📍 Tsukiji · 📍 Tsukiji Market")
        #expect(extracted.map(\.name) == ["Tsukiji", "Tsukiji Market"])
        let stub = StubPlaces(candidates: [tsukijiOuter])
        let conferred = await PlaceResolver.resolve(extracted, provider: stub, centers: [:], fallback: tokyo)
        let merged = PlaceResolver.merge(conferred)
        #expect(merged.count == 1)
        #expect(merged.first?.placeId == "P1")
        #expect(merged.first?.name == "Tsukiji Outer Market")
        #expect(merged.first?.mentions == 2)
        #expect(merged.first?.aliases.contains("Tsukiji") == true)
    }

    @Test func mergeByPlaceIdKeepsOneRowPerPlace() {
        let a = ExtractedPlace(name: "Tsukiji", hint: "citado", placeId: "P1", lat: 35.6654, lng: 139.7707)
        let b = ExtractedPlace(name: "Tsukiji Market", hint: "linha", placeId: "P1", lat: 35.6654, lng: 139.7707)
        let c = ExtractedPlace(name: "Maguroya Kurogin", hint: "pino", placeId: "P2", lat: 35.6651, lng: 139.7706)
        let merged = PlaceResolver.merge([a, b, c])
        #expect(merged.map(\.id) == ["P1", "P2"])
        #expect(Set(merged.map(\.id)).count == merged.count)
        #expect(merged.first?.mentions == 2)
    }

    @Test func mergeByDistanceNeedsSimilarNames() {
        let base = (lat: 35.6654, lng: 139.7707)
        let near = ExtractedPlace(name: "Uogashi Senryo Honten", hint: "a", lat: base.lat + 0.0003, lng: base.lng)  // ~33 m
        let same = ExtractedPlace(name: "Uogashi Senryo", hint: "b", lat: base.lat, lng: base.lng)
        let far = ExtractedPlace(name: "Uogashi Senryo", hint: "c", lat: base.lat + 0.005, lng: base.lng)           // ~550 m
        let other = ExtractedPlace(name: "Bar Benfiddich", hint: "d", lat: base.lat + 0.0003, lng: base.lng)        // perto, nome outro
        let merged = PlaceResolver.merge([same, near, far, other])
        #expect(merged.count == 3)
        #expect(merged.first?.mentions == 2)
        #expect(merged.first?.aliases == ["Uogashi Senryo Honten"])
    }

    @Test func nameWithoutPlacesMatchStaysUnconfirmed() async {
        let stub = StubPlaces(candidates: [tsukijiOuter])
        let item = ExtractedPlace(name: "Uogashi Senryo", hint: "pino")
        let out = await PlaceResolver.resolve(item, provider: stub, near: tokyo)
        #expect(out.placeId == nil)
        #expect(out.hasCoordinate == false)
        #expect(out.name == "Uogashi Senryo")
    }

    @Test func placesCategoryBeatsTheCaptionAndKeepsTheMapsPin() async {
        let stub = StubPlaces(candidates: [tsukijiOuter])
        let item = ExtractedPlace(name: "Tsukiji Outer Market", category: .coffee, hint: "link do Maps", lat: -19.85, lng: -43.99)
        let out = await PlaceResolver.resolve(item, provider: stub, near: tokyo)
        #expect(out.category == .shop)
        #expect(out.sub == "Mercado")
        #expect(out.lat == -19.85 && out.lng == -43.99)
    }

    @Test func jaroWinklerSeparatesCloseAndFarNames() {
        #expect(PlaceResolver.jaroWinkler("tsukijimarket", "tsukijioutermarket") >= PlaceResolver.similarityThreshold)
        #expect(PlaceResolver.jaroWinkler("fuunji", "nakiryu") < PlaceResolver.similarityThreshold)
    }
}

@MainActor
struct PlaceBoardMatchTests {
    private func board(_ name: String, placeId: String?, lat: Double, lng: Double) -> Place {
        let place = Place(id: "b-\(name)", name: name, cityId: "jp", lat: lat, lng: lng)
        place.placeId = placeId
        return place
    }

    @Test func boardPlaceWithSamePlaceIdIsExisting() {
        let place = board("Tsukiji Outer Market", placeId: "P1", lat: 35.6654, lng: 139.7707)
        let item = ExtractedPlace(name: "Mercado de Tsukiji", hint: "x", placeId: "P1")
        #expect(PlaceMatcher.existingPlace(for: item, in: [place]) === place)
    }

    @Test func boardPlaceWithSameNameNearbyIsExistingAndFarIsNot() {
        let place = board("Maguroya Kurogin", placeId: nil, lat: 35.6651, lng: 139.7706)
        let near = ExtractedPlace(name: "Maguroya Kurogin", hint: "x", lat: 35.6652, lng: 139.7706)
        let far = ExtractedPlace(name: "Maguroya Kurogin", hint: "x", lat: 35.6651 + 0.009, lng: 139.7706)
        #expect(PlaceMatcher.existingPlace(for: near, in: [place]) === place)
        #expect(PlaceMatcher.existingPlace(for: far, in: [place]) == nil)
    }
}

@MainActor
struct LinkMapLayoutTests {
    private func match(_ name: String, located: Bool, lat: Double, lng: Double) -> MatchedPlace {
        MatchedPlace(extracted: ExtractedPlace(name: name, hint: "x", placeId: located ? name : nil),
                     kind: .new, lat: lat, lng: lng, approx: !located, suggestedListId: nil)
    }

    @Test func onlyLocatedPlacesGetNumberedPinsAndAnArea() {
        let matches = [
            match("Tsukiji Outer Market", located: true, lat: 35.6654, lng: 139.7707),
            match("November", located: false, lat: 35.68, lng: 139.76),
            match("Maguroya Kurogin", located: true, lat: 35.6627, lng: 139.7706),  // ~300 m ao sul
        ]
        let layout = LinkMapLayout.make(matches: matches, region: .jp, transit: .empty)
        #expect(layout.pins.map(\.number) == [1, 2])
        #expect(layout.number(for: matches[1].id) == nil)
        #expect(layout.area?.count == 65)
        #expect(layout.spreadMeters.map { $0 > 100 && $0 < 400 } == true)
    }
}
