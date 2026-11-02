import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 14 · B (fatia 4): ranking do "Por perto", dedupe entre fontes, cache de 30 min e parsers das fontes.
struct NearbyRankingTests {
    static let origin = CLLocation(latitude: 35.6442, longitude: 139.6985)

    /// Deslocamento em metros pro norte (1° de latitude ≈ 111 km).
    static func north(_ meters: Double) -> (lat: Double, lng: Double) {
        (origin.coordinate.latitude + meters / 111_000, origin.coordinate.longitude)
    }

    static func external(_ name: String, meters: Double = 0, source: NearbySource = .google, rating: Double? = nil, count: Int? = nil,
                         open: Bool? = nil, category: String? = nil, popularity: Double? = nil, articleLang: String? = nil) -> NearbyCandidate {
        let (lat, lng) = north(meters)
        let place = NearbyPlace(name: name, lat: lat, lng: lng, sources: [source], rating: rating, ratingCount: count, openNow: open,
                                category: category, popularity: popularity, articleLang: articleLang)
        return NearbyCandidate(place: place, distance: CLLocation(latitude: lat, longitude: lng).distance(from: origin),
                               role: NearbyRanker.role(for: place))
    }

    static func board(_ name: String, meters: Double = 0, role: StopRole = .see, done: Bool = false) -> NearbyCandidate {
        let (lat, lng) = north(meters)
        return NearbyCandidates.board(id: "b-\(name)", name: name, lat: lat, lng: lng, openNow: nil, listId: "see", listName: "Must see",
                                      role: role, isDone: done, isExperience: false, origin: origin)
    }

    @Test func boardWinsAnExactTie() {
        // Board (distância 0): popularidade 0,95 (+0,5) + distância (+1,5) + see às 14h (+0,6) = 2,6.
        var boardTwin = Self.board("Jardim Botânico", role: .see)
        boardTwin.place.popularity = 0.95
        // Fora do board (240 m): nota 3,75 (+0,5) + distância (+0,9) + see (+0,6) + novidade (+0,6) = 2,6.
        var outsideTwin = Self.external("Parque Jardim", rating: 3.75, category: "park")
        outsideTwin.distance = 240
        outsideTwin.role = .see
        #expect(abs(NearbyRanker.score(boardTwin, hour: 14) - NearbyRanker.score(outsideTwin, hour: 14)) < 1e-9)
        let ranked = NearbyRanker.rank([outsideTwin, boardTwin], hour: 14)
        #expect(ranked.first?.candidate.isOnBoard == true)
    }

    @Test func contextLinksNeverLeadAndStayCapped() {
        let google = Self.external("Ivy Place", meters: 100, source: .google, rating: 4.2, count: 3149, open: true, category: "restaurant")
        let wikis = (1...5).map { i in
            NearbyCandidate(place: NearbyPlace(name: "Artigo \(i)", lat: 35.6442, lng: 139.6985, sources: [.wikipedia],
                                               articleLang: i % 2 == 0 ? "en" : "pt"),
                            distance: Double(i), role: .see)
        }
        let ranked = NearbyRanker.rank(wikis + [google], hour: 12)
        #expect(ranked.first?.candidate.place.name == "Ivy Place")
        #expect(ranked.filter { $0.candidate.isContextOnly }.count == NearbyService.wikiCap)
        #expect(ranked.first { $0.candidate.isContextOnly }?.candidate.place.articleLang == "pt")
    }

    @Test func fakeGoogleSamplesRankBeforeWikipedia() throws {
        let candidates = NearbyCandidates.external(FakeNearbyProvider.samples, origin: Self.origin)
        let ranked = NearbyRanker.rank(candidates, hour: 18)
        #expect(ranked.first?.candidate.place.googlePlaceId == "fake-starbucks")
        let names = Set(ranked.map(\.candidate.place.name))
        #expect(names.isSuperset(of: ["Tsutaya Books Daikanyama", "Ivy Place", "DAIKANYAMA T-SITE"]))
        let lastRecommended = try #require(ranked.lastIndex { !$0.candidate.isContextOnly })
        let firstContext = try #require(ranked.firstIndex { $0.candidate.isContextOnly })
        #expect(firstContext > lastRecommended)
    }

    @Test func openAndWellRatedBeatsClosedAndFarAway() {
        let good = Self.external("Starbucks Reserve", meters: 380, rating: 4.5, count: 23_000, open: true, category: "cafe")
        let poor = Self.external("Lanchonete", meters: 550, rating: 3.6, count: 40, open: false, category: "fast_food_restaurant")
        let ranked = NearbyRanker.rank([poor, good], hour: 18)
        #expect(ranked.map(\.candidate.place.name) == ["Starbucks Reserve", "Lanchonete"])
        #expect(ranked[0].score >= NearbyRanker.highScore) // destaque da Home
    }

    @Test func outsideTheRadiusNothingShows() {
        let far = Self.external("Longe", meters: 900, rating: 5, count: 9_000, open: true)
        #expect(NearbyRanker.rank([far], hour: 12).isEmpty)
    }

    @Test func doneBoardPlacesFallBehind() {
        let done = Self.board("Já fui", done: true)
        let fresh = Self.board("Ainda não")
        let ranked = NearbyRanker.rank([done, fresh], hour: 12)
        #expect(ranked.first?.candidate.place.name == "Ainda não")
    }

    @Test func sameNameWithinSixtyMetersIsOnePlaceAndKeepsTheBoardOne() {
        let fromGoogle = Self.external("Starbucks Reserve Roastery Tokyo", meters: 0, source: .google, rating: 4.5, count: 23_000, open: true)
        let fromWiki = Self.external("Starbucks Reserve Roastery", meters: 20, source: .wikipedia, articleLang: "en")
        let mine = Self.board("Starbucks Reserve Roastery", meters: 40, role: .drink)
        let ranked = NearbyRanker.rank([fromGoogle, fromWiki, mine], hour: 18)
        #expect(ranked.count == 1)
        let merged = ranked.first?.candidate
        #expect(merged?.isOnBoard == true)
        #expect(merged?.place.sources.contains(.google) == true)
        #expect(merged?.place.rating == 4.5)
        #expect(merged?.place.articleLang == "en")
    }

    @Test func differentNamesOrFarPointsAreNotMerged() {
        let a = Self.external("Blue Bottle Coffee", meters: 0, source: .google, rating: 4.3)
        let b = Self.external("Blue Bottle Coffee", meters: 150, source: .foursquare, rating: 4.2)
        let c = Self.external("Rio Meguro", meters: 0, source: .wikipedia, articleLang: "pt")
        #expect(NearbyRanker.rank([a, b, c], hour: 12).count == 3)
    }

    @Test func primaryTypesMapToRoles() {
        #expect(NearbyRanker.role(for: NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.google], category: "ramen_restaurant")) == .eat)
        #expect(NearbyRanker.role(for: NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.google], category: "cafe")) == .drink)
        #expect(NearbyRanker.role(for: NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.foursquare], category: "Bookstore")) == .shop)
        #expect(NearbyRanker.role(for: NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.google], category: "museum")) == .see)
        let coffee = NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.google], category: "cafe")
        #expect(NearbyRanker.suggestedColor(coffee, role: .drink) == .coffee)
    }

    @Test func listSuggestionFollowsTheCategory() {
        func place(_ category: String?, _ source: NearbySource = .google, _ name: String = "x") -> NearbyPlace {
            NearbyPlace(name: name, lat: 0, lng: 0, sources: [source], category: category)
        }
        #expect(NearbyRanker.suggestedListId(place("restaurant")) == "eat")
        #expect(NearbyRanker.suggestedListId(place("cafe")) == "drink")
        #expect(NearbyRanker.suggestedListId(place("museum")) == "art")
        #expect(NearbyRanker.suggestedListId(place("temple")) == "see")
        #expect(NearbyRanker.suggestedListId(place("book_store")) == "shop")
        #expect(NearbyRanker.suggestedListId(place("shopping_mall")) == "shop")
        #expect(NearbyRanker.suggestedListId(place(nil)) == nil)
        // Wikipedia: "see" só pra passarela/templo/parque; o resto fica sem lista sugerida.
        #expect(NearbyRanker.suggestedListId(place(nil, .wikipedia, "Rio Meguro · passarela")) == "see")
        #expect(NearbyRanker.suggestedListId(place(nil, .wikipedia, "Daikanyama Hills")) == nil)
    }

    @Test func labelsAreInPortugueseNotTheRawType() {
        #expect(NearbyRanker.categoryLabel(NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.google], category: "book_store")) == "livraria")
        #expect(NearbyRanker.categoryLabel(NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.google], category: "restaurant")) == "restaurante")
        #expect(NearbyRanker.categoryLabel(NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.wikipedia])) == "ponto histórico")
        #expect(NearbyRanker.categoryLabel(NearbyPlace(name: "x", lat: 0, lng: 0, sources: [.google], category: "zzz")) == nil)
    }
}

struct NearbyCacheTests {
    static func tempDirectory() -> URL {
        URL.temporaryDirectory.appending(path: "must-nearby-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    static let places = [NearbyPlace(name: "Starbucks Reserve", lat: 35.6470, lng: 139.6960, sources: [.google], rating: 4.5)]

    @Test func secondLookInsideThirtyMinutesDoesNotCallTheSourcesAgain() async {
        let provider = FakeNearbyProvider(places: Self.places)
        let loader = NearbyLoader(provider: provider, cache: NearbyCache(directory: Self.tempDirectory()))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let first = await loader.load(lat: 35.6442, lng: 139.6985, region: .jp, now: t0)
        #expect(first.places == Self.places)
        // 10 min depois, mesma célula (~500 m): cache.
        let again = await loader.load(lat: 35.6443, lng: 139.6986, region: .jp, now: t0.addingTimeInterval(10 * 60))
        #expect(again.places == Self.places)
        #expect(await provider.calls == 1)
        // Depois de 30 min, chama de novo.
        _ = await loader.load(lat: 35.6442, lng: 139.6985, region: .jp, now: t0.addingTimeInterval(31 * 60))
        #expect(await provider.calls == 2)
    }

    @Test func homeReadsOnlyTheCache() async {
        let provider = FakeNearbyProvider(places: Self.places)
        let loader = NearbyLoader(provider: provider, cache: NearbyCache(directory: Self.tempDirectory()))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await loader.cached(lat: 35.6442, lng: 139.6985, region: .jp, now: t0) == nil)
        #expect(await provider.calls == 0) // a Home não dispara fonte nenhuma
        _ = await loader.load(lat: 35.6442, lng: 139.6985, region: .jp, now: t0)
        #expect(await loader.cached(lat: 35.6442, lng: 139.6985, region: .jp, now: t0.addingTimeInterval(5 * 60))?.places == Self.places)
        #expect(await loader.cached(lat: 35.6442, lng: 139.6985, region: .jp, now: t0.addingTimeInterval(31 * 60)) == nil)
        #expect(await provider.calls == 1)
    }

    @Test func incompleteAnswersAreNotCached() async {
        // Uma fonte que falhou não fica 30 min no cache: a próxima abertura tenta de novo.
        let provider = FakeNearbyProvider(places: Self.places, complete: false)
        let loader = NearbyLoader(provider: provider, cache: NearbyCache(directory: Self.tempDirectory()))
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = await loader.load(lat: 35.6442, lng: 139.6985, region: .jp, now: t0)
        _ = await loader.load(lat: 35.6442, lng: 139.6985, region: .jp, now: t0.addingTimeInterval(60))
        #expect(await provider.calls == 2)
    }

    @Test func cellsAreAboutFiveHundredMetres() {
        let a = NearbyCell.key(lat: 35.6442, lng: 139.6985, region: .jp)
        #expect(a == NearbyCell.key(lat: 35.6443, lng: 139.6986, region: .jp))
        #expect(a != NearbyCell.key(lat: 35.6442 + 0.02, lng: 139.6985, region: .jp))
        #expect(a != NearbyCell.key(lat: 35.6442, lng: 139.6985, region: .bh))
    }
}

struct NearbyParserTests {
    @Test func parsesGoogleNearbyWithTheMinimalFields() throws {
        let json = #"""
        {"places":[{"id":"ChIJ-starbucks","displayName":{"text":"Starbucks Reserve Roastery Tokyo","languageCode":"en"},
          "location":{"latitude":35.6470,"longitude":139.6960},"rating":4.5,"userRatingCount":23000,
          "currentOpeningHours":{"openNow":true},"primaryType":"cafe"},
          {"id":"ChIJ-no-name","location":{"latitude":35.6,"longitude":139.6}}]}
        """#
        let places = try NearbyService.parseGoogle(Data(json.utf8))
        #expect(places.count == 1)
        let p = try #require(places.first)
        #expect(p.name == "Starbucks Reserve Roastery Tokyo")
        #expect(p.googlePlaceId == "ChIJ-starbucks")
        #expect(p.rating == 4.5 && p.ratingCount == 23_000 && p.openNow == true && p.category == "cafe")
        #expect(p.sources == [.google])
    }

    @Test func parsesWikipediaGeosearchWithItsSummary() throws {
        let json = #"{"query":{"pages":{"123":{"pageid":123,"index":1,"title":"Rio Meguro","coordinates":[{"lat":35.6425,"lon":139.6990}],"extract":"O Rio Meguro é um curso d'água de Tóquio."}}}}"#
        let places = try NearbyService.parseWikipedia(Data(json.utf8), lang: "pt")
        #expect(places.map(\.name) == ["Rio Meguro"])
        #expect(places.first?.articleLang == "pt")
        #expect(places.first?.summary?.hasPrefix("O Rio Meguro") == true)
        #expect(places.first?.sources == [.wikipedia])
    }

    @Test func dropsStationsNeighbourhoodsAndCompanies() throws {
        let json = #"""
        {"query":{"pages":{
          "1":{"index":1,"title":"中目黒駅","coordinates":[{"lat":35.6442,"lon":139.6985}],"extract":"中目黒駅は東京都目黒区の駅"},
          "2":{"index":2,"title":"Daikanyama","coordinates":[{"lat":35.6480,"lon":139.7030}],"extract":"Daikanyama é um bairro de Shibuya"},
          "3":{"index":3,"title":"Rio Meguro","coordinates":[{"lat":35.6425,"lon":139.6990}],"extract":"Rio."}}}}
        """#
        let places = try NearbyService.parseWikipedia(Data(json.utf8), lang: "ja")
        #expect(places.map(\.name) == ["Rio Meguro"])
    }

    @Test func noiseTermsAreCaughtInTitleOrIntro() {
        #expect(NearbyService.isContextNoise(title: "Shibuya Station", extract: nil))
        #expect(NearbyService.isContextNoise(title: "渋谷1丁目", extract: nil))
        #expect(NearbyService.isContextNoise(title: "ABC", extract: "ABC é uma empresa de software"))
        #expect(!NearbyService.isContextNoise(title: "Templo Tenryu-ji", extract: "Templo zen em Kyoto"))
    }

    @Test func parsesFoursquareWithTenPointRatingHalved() throws {
        let json = #"{"results":[{"fsq_place_id":"abc","name":"Tsutaya Books","geocodes":{"main":{"latitude":35.649,"longitude":139.703}},"rating":8.8,"popularity":0.95,"categories":[{"name":"Bookstore"}]}]}"#
        let places = try NearbyService.parseFoursquare(Data(json.utf8))
        let p = try #require(places.first)
        #expect(p.fsqId == "abc")
        #expect(abs((p.rating ?? 0) - 4.4) < 1e-9)
        #expect(p.popularity == 0.95)
        #expect(p.category == "Bookstore")
    }

    @Test func withoutKeysTheSourcesSayNothingAndNoCallIsMade() async throws {
        let service = NearbyService(googleKey: nil, foursquareKey: nil)
        #expect(try await service.googleNearby(lat: 35.6, lng: 139.7).isEmpty)
        #expect(try await service.foursquare(lat: 35.6, lng: 139.7).isEmpty)
    }
}
