import Foundation
import Testing
@testable import Must

/// Prompt 17 · A (fatia 8A): orçamento das chamadas Google (`ApiBudget`), corte de 80% e indisponível até amanhã.

struct ApiBudgetTests {
    static let now = Date(timeIntervalSince1970: 1_793_000_000)

    static func defaults() -> UserDefaults {
        UserDefaults(suiteName: "must-api-budget-\(UUID().uuidString)")!
    }

    @Test func countsPerSKUAndMonth() {
        let d = Self.defaults()
        ApiBudget.record(.placesEssentials, now: Self.now, defaults: d)
        ApiBudget.record(.placesEssentials, now: Self.now, defaults: d)
        ApiBudget.record(.autocomplete, units: 3, now: Self.now, defaults: d)
        #expect(ApiBudget.used(.placesEssentials, now: Self.now, defaults: d) == 2)
        #expect(ApiBudget.used(.placesPro, now: Self.now, defaults: d) == 0)
        #expect(ApiBudget.used(.autocomplete, now: Self.now, defaults: d) == 3)
        #expect(ApiBudget.usedToday(now: Self.now, defaults: d) == 5)
        // Outro mês começa do zero.
        let nextMonth = Self.now.addingTimeInterval(40 * 86_400)
        #expect(ApiBudget.used(.placesEssentials, now: nextMonth, defaults: d) == 0)
    }

    @Test func dailyCapZeroBlocksEverything() async throws {
        let d = Self.defaults()
        ApiBudget.setDailyCap(0, defaults: d)
        #expect(ApiBudget.check(.placesIdsOnly, now: Self.now, defaults: d) == .dailyCapZero)
        var called = false
        await #expect(throws: ServiceError.self) {
            try await GoogleAPI.run(.placesIdsOnly, now: Self.now, defaults: d) {
                called = true
                return 1
            }
        }
        #expect(called == false)
        #expect(ApiBudget.used(.placesIdsOnly, now: Self.now, defaults: d) == 0)
    }

    @Test func dailyCapCountsAllSKUs() {
        let d = Self.defaults()
        ApiBudget.setDailyCap(2, defaults: d)
        ApiBudget.record(.placesEssentials, units: 2, now: Self.now, defaults: d)
        #expect(ApiBudget.check(.autocomplete, now: Self.now, defaults: d) == .dailyCapReached(cap: 2))
        // No dia seguinte o teto zera a conta.
        #expect(ApiBudget.check(.autocomplete, now: Self.now.addingTimeInterval(86_400), defaults: d) == nil)
    }

    @Test func cutsAtEightyPercentOfFreeQuota() {
        let d = Self.defaults()
        ApiBudget.setDailyCap(100_000, defaults: d)
        // Autocomplete: 10 mil grátis → corta em 8 mil.
        ApiBudget.record(.autocomplete, units: 7_999, now: Self.now, defaults: d)
        #expect(ApiBudget.check(.autocomplete, now: Self.now, defaults: d) == nil)
        ApiBudget.record(.autocomplete, units: 1, now: Self.now, defaults: d)
        #expect(ApiBudget.check(.autocomplete, now: Self.now, defaults: d) == .monthlyCut(sku: .autocomplete, used: 8_000))
    }

    @Test func idsOnlyHasNoCut() {
        let d = Self.defaults()
        ApiBudget.setDailyCap(100_000, defaults: d)
        ApiBudget.record(.placesIdsOnly, units: 50_000, now: Self.now, defaults: d)
        #expect(ApiBudget.check(.placesIdsOnly, now: Self.now, defaults: d) == nil)
    }

    @Test func forbiddenMarksSKUUnavailableUntilTomorrow() async {
        let d = Self.defaults()
        ApiBudget.setDailyCap(100, defaults: d)
        await #expect(throws: ServiceError.self) {
            try await GoogleAPI.run(.routesEssentials, now: Self.now, defaults: d) {
                throw ServiceError.http(403, "Routes API has not been used in project")
            }
        }
        #expect(ApiBudget.isUnavailable(.routesEssentials, now: Self.now, defaults: d))
        #expect(ApiBudget.check(.routesEssentials, now: Self.now, defaults: d) == .unavailableToday(sku: .routesEssentials))
        // Outra SKU segue livre.
        #expect(ApiBudget.check(.placesEssentials, now: Self.now, defaults: d) == nil)
        // Amanhã volta a tentar.
        #expect(ApiBudget.check(.routesEssentials, now: Self.now.addingTimeInterval(25 * 3600), defaults: d) == nil)
    }

    @Test func requestDeniedBodyCountsAsForbidden() async {
        let d = Self.defaults()
        ApiBudget.setDailyCap(100, defaults: d)
        await #expect(throws: ServiceError.self) {
            try await GoogleAPI.run(.streetViewMetadata, now: Self.now, defaults: d) {
                throw ServiceError.http(200, "{\"status\":\"REQUEST_DENIED\"}")
            }
        }
        #expect(ApiBudget.isUnavailable(.streetViewMetadata, now: Self.now, defaults: d))
    }

    @Test func successRecordsAndErrorsDoNot() async throws {
        let d = Self.defaults()
        ApiBudget.setDailyCap(100, defaults: d)
        let value = try await GoogleAPI.run(.placesPro, now: Self.now, defaults: d) { 42 }
        #expect(value == 42)
        #expect(ApiBudget.used(.placesPro, now: Self.now, defaults: d) == 1)
        await #expect(throws: ServiceError.self) {
            try await GoogleAPI.run(.placesPro, now: Self.now, defaults: d) { throw ServiceError.decoding("x") }
        }
        #expect(ApiBudget.used(.placesPro, now: Self.now, defaults: d) == 1)
    }

    @Test func legacyPlacesCounterMigratesOnce() {
        let d = Self.defaults()
        let month = ApiBudget.monthKey(Self.now)
        d.set(5, forKey: "places.calls.\(month)")
        #expect(ApiBudget.placesUsedThisMonth(now: Self.now, defaults: d) == 5)
        #expect(ApiBudget.used(.placesEssentials, now: Self.now, defaults: d) == 5)
        // Não soma de novo na segunda leitura.
        #expect(ApiBudget.used(.placesEssentials, now: Self.now, defaults: d) == 5)
    }
}
