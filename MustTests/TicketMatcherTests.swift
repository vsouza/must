import Foundation
import SwiftData
import Testing
@testable import Must

/// Prompt 15 · A (fatia 3): casar o ingresso com o lugar do board — placeId, coordenada, endereço; nome não basta.
@MainActor
struct TicketMatcherTests {
    static func container() throws -> ModelContainer {
        try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// "Aula de sushi com chef em Tsukiji" já no board, com o ponto de encontro do fornecedor e o `placeId` do Places.
    static func sushiPlace(in context: ModelContext) -> Place {
        let place = Place(id: "jp-sushi", name: "Aula de sushi com chef em Tsukiji", cityId: "tokyo1", lat: 35.6654, lng: 139.7707)
        place.area = "Tsukiji"
        place.placeId = "ChIJ-tsukiji-outer-market"
        place.extra = PlaceExtra(experience: ExperienceInfo(supplier: .viator, meetingPoint: "Tsukiji Outer Market, Gate 1"))
        context.insert(place)
        return place
    }

    @Test func placeIdMatchesBeforeAnyName() throws {
        let container = try Self.container()
        let context = container.mainContext
        let sushi = Self.sushiPlace(in: context)
        let candidate = TicketCandidate(title: "Sushi Making Class with a Chef in Tsukiji", placeId: "ChIJ-tsukiji-outer-market",
                                        lat: nil, lng: nil, address: nil)
        let best = try #require(TicketMatcher.best(candidate, places: [sushi]))
        #expect(best.placeId == "jp-sushi")
        #expect(best.reason == .placeId)
        #expect(best.percent == 98)
    }

    /// O nome em inglês do ingresso não parece com o do board. O que casa é o endereço (ponto de encontro).
    @Test func addressMatchesWhenNameDoesNotAndNameIsNotTheReason() throws {
        let container = try Self.container()
        let context = container.mainContext
        let sushi = Self.sushiPlace(in: context)
        let candidate = TicketCandidate(title: "Sushi Making Class with a Chef in Tsukiji", placeId: nil, lat: nil, lng: nil,
                                        address: "Tsukiji Outer Market, Gate 1")
        let ranked = TicketMatcher.rank(candidate, places: [sushi])
        let best = try #require(ranked.first)
        #expect(best.placeId == "jp-sushi")
        #expect(best.reason == .address)
        #expect(best.score >= TicketMatcher.autoLinkScore)
        // O nome sozinho não chega: sem endereço nem placeId, não há escolha automática.
        let nameOnly = TicketCandidate(title: "Sushi Making Class with a Chef in Tsukiji", placeId: nil, lat: nil, lng: nil, address: nil)
        #expect(TicketMatcher.best(nameOnly, places: [sushi]) == nil)
    }

    @Test func coordinateWithinRadiusMatches() throws {
        let container = try Self.container()
        let context = container.mainContext
        let sushi = Self.sushiPlace(in: context)
        let near = TicketCandidate(title: "Outro nome", placeId: nil, lat: 35.6656, lng: 139.7709, address: nil)
        let match = try #require(TicketMatcher.best(near, places: [sushi]))
        #expect(match.reason == .coordinate)
        let far = TicketCandidate(title: "Outro nome", placeId: nil, lat: 35.7000, lng: 139.8000, address: nil)
        #expect(TicketMatcher.best(far, places: [sushi]) == nil)
    }

    @Test func unrelatedPlaceDoesNotMatchAndAreaAloneIsOnlyAHint() throws {
        let container = try Self.container()
        let context = container.mainContext
        let sushi = Self.sushiPlace(in: context)
        let shrine = Place(id: "jp-shrine", name: "Meiji Jingu", cityId: "tokyo1", lat: 35.6764, lng: 139.6993)
        shrine.area = "Harajuku"
        context.insert(shrine)
        let candidate = TicketCandidate(title: "Sushi Making Class", placeId: nil, lat: nil, lng: nil, address: "Tsukiji Outer Market")
        let ranked = TicketMatcher.rank(candidate, places: [sushi, shrine])
        #expect(ranked.first?.placeId == "jp-sushi")
        #expect(!ranked.contains { $0.placeId == "jp-shrine" })
        // Só a área ("Tsukiji") dá um sinal fraco: aparece como sugestão, não como escolha.
        let areaOnly = TicketCandidate(title: "Passeio", placeId: nil, lat: nil, lng: nil, address: "Tsukiji, Chuo City")
        #expect(TicketMatcher.best(areaOnly, places: [sushi]) == nil)
        #expect(TicketMatcher.rank(areaOnly, places: [sushi]).first?.score ?? 0 < TicketMatcher.autoLinkScore)
    }

    @Test func tokensIgnoreNoiseWords() {
        #expect(TicketMatcher.tokens("Portão 1 do Mercado Externo de Tsukiji") == ["mercado", "externo", "tsukiji"])
        #expect(TicketMatcher.dice(["a1", "tsukiji"], ["tsukiji"]) == 2.0 / 3.0)
    }
}
