import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Must

struct ServiceParsingTests {
    // MARK: Places

    @Test func parsesTextSearch() throws {
        let json = #"{"places":[{"id":"ChIJ-fuunji","formattedAddress":"2-14-3 Yoyogi, Shibuya","location":{"latitude":35.6871,"longitude":139.6990},"displayName":{"text":"Fuunji","languageCode":"en"}},{"displayName":{"text":"sem id"}}]}"#
        let results = try PlacesService.parseSearch(Data(json.utf8))
        #expect(results.count == 1)
        #expect(results.first == PlaceCandidate(id: "ChIJ-fuunji", name: "Fuunji", address: "2-14-3 Yoyogi, Shibuya", lat: 35.6871, lng: 139.6990))
    }

    @Test func parsesDetailsIntoPlaceHours() throws {
        let json = #"""
        {"id":"ChIJ-udatsu","rating":4.7,"priceLevel":"PRICE_LEVEL_VERY_EXPENSIVE",
         "priceRange":{"startPrice":{"currencyCode":"JPY","units":"20000"},"endPrice":{"currencyCode":"JPY","units":"30000"}},
         "regularOpeningHours":{"openNow":false,
           "periods":[{"open":{"day":2,"hour":18,"minute":0},"close":{"day":2,"hour":23,"minute":0}},
                      {"open":{"day":6,"hour":17,"minute":30},"close":{"day":0,"hour":1,"minute":0}}],
           "weekdayDescriptions":["segunda-feira: Fechado","terça-feira: 18:00–23:00"]}}
        """#
        let d = try PlacesService.parseDetails(Data(json.utf8), fetchedAt: Date(timeIntervalSince1970: 0))
        #expect(d.id == "ChIJ-udatsu")
        #expect(d.priceLevel == 4)
        #expect(d.priceFrom == 20_000 && d.priceCurrency == "JPY")
        #expect(d.rating == 4.7)
        let hours = try #require(d.hours)
        #expect(hours.periods?.count == 2)
        #expect(hours.weekdayText?.first == "segunda-feira: Fechado")
        #expect(hours.isStale) // fetchedAt em 1970
        // Sábado 23:30 (atravessa a meia-noite) está aberto.
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        #expect(hours.isOpen(at: BoardDates.parseDateTime("2026-11-14T23:30:00+09:00")!, timeZone: tokyo) == true)
    }

    @Test func detailsWithoutHoursIsNotOpen() throws {
        let d = try PlacesService.parseDetails(Data(#"{"id":"x"}"#.utf8))
        #expect(d.hours == nil && d.priceLevel == nil)
    }

    // MARK: Open-Meteo

    /// Resposta real com `models=jma_seamless,best_match` (JMA sem probabilidade de chuva).
    @Test func parsesOpenMeteoPreferringJMA() throws {
        let json = #"""
        {"timezone":"Asia/Tokyo","current":{"time":"2026-11-01T12:15","temperature_2m_jma_seamless":19.5,"weather_code_jma_seamless":1},
         "daily":{"time":["2026-11-01","2026-11-02"],
          "weather_code_jma_seamless":[3,53],"weather_code_best_match":[2,61],
          "temperature_2m_max_jma_seamless":[19.9,22.2],"temperature_2m_min_jma_seamless":[12.2,13.1],
          "precipitation_probability_max_jma_seamless":[null,null],"precipitation_probability_max_best_match":[10,85],
          "sunrise_jma_seamless":["2026-11-01T06:02","2026-11-02T06:03"],"sunset_jma_seamless":["2026-11-01T16:43","2026-11-02T16:42"]}}
        """#
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        let f = try WeatherService.parse(Data(json.utf8), timeZone: tz)
        let cal = Region.jp.calendar
        let d1 = try #require(f.day(BoardDates(timeZone: tz).day(from: "2026-11-01")!, calendar: cal))
        #expect(d1.code == 3) // JMA ganha do best_match
        #expect(d1.tempMax == 19.9)
        #expect(d1.precipProb == 10) // best_match completa
        #expect(d1.sunset == BoardDates.parseDateTime("2026-11-01T16:43:00+09:00"))
        #expect(d1.short == "20° e nublado")
        let d2 = try #require(f.day(BoardDates(timeZone: tz).day(from: "2026-11-02")!, calendar: cal))
        #expect(d2.precipProb == 85 && !d2.isClear)
        #expect(f.now?.temp == 19.5)
    }

    @Test func parsesOpenMeteoBH() throws {
        let json = #"{"current":{"temperature_2m":20.1,"weather_code":3},"daily":{"time":["2026-11-01"],"weather_code":[95],"temperature_2m_max":[26.9],"temperature_2m_min":[18.5],"precipitation_probability_max":[98],"sunrise":["2026-11-01T05:14"],"sunset":["2026-11-01T18:04"]}}"#
        let tz = Region.bh.timeZone
        let f = try WeatherService.parse(Data(json.utf8), timeZone: tz)
        let d = try #require(f.days.values.first)
        #expect(d.isHeavyRain)
        #expect(d.label == "tempestade")
        #expect(f.now?.code == 3)
    }

    // MARK: Wikimedia Commons

    /// Formato real de `prop=imageinfo&iiprop=url|extmetadata|mime` (Senso-ji, geosearch).
    @Test func parsesCommonsAndDropsNonFreeLicenses() throws {
        let json = #"""
        {"query":{"pages":{
          "127799441":{"pageid":127799441,"index":1,"title":"File:Lantern above Sensō-ji.jpg","imageinfo":[{"mime":"image/jpeg",
            "thumburl":"https://upload.wikimedia.org/thumb/9/96/Lantern.jpg/1024px-Lantern.jpg","url":"https://upload.wikimedia.org/9/96/Lantern.jpg",
            "descriptionurl":"https://commons.wikimedia.org/wiki/File:Lantern_above_Sens%C5%8D-ji.jpg",
            "extmetadata":{"LicenseShortName":{"value":"CC BY 2.0"},"License":{"value":"cc-by-2.0"},
              "Artist":{"value":"<a rel=\"nofollow\" class=\"external text\" href=\"https://www.flickr.com/people/65847118@N06\">Maarten Heerlien</a> from Voorschoten"}}}]},
          "2":{"pageid":2,"index":2,"imageinfo":[{"mime":"image/jpeg","thumburl":"https://x/2.jpg","descriptionurl":"https://c/2",
            "extmetadata":{"LicenseShortName":{"value":"CC BY-NC 2.0"},"License":{"value":"cc-by-nc-2.0"}}}]},
          "3":{"pageid":3,"index":3,"imageinfo":[{"mime":"image/svg+xml","thumburl":"https://x/3.png","descriptionurl":"https://c/3",
            "extmetadata":{"License":{"value":"cc0"}}}]},
          "4":{"pageid":4,"index":0,"imageinfo":[{"mime":"image/jpeg","thumburl":"https://x/4.jpg","descriptionurl":"https://c/4",
            "extmetadata":{"LicenseShortName":{"value":"Public domain"},"License":{"value":"pd"},"Artist":{"value":"Unknown"}}}]}
        }}}
        """#
        let photos = try CommonsPhotoService.parse(Data(json.utf8))
        #expect(photos.map(\.id) == ["4", "127799441"]) // ordem do índice; NC e SVG ficam de fora
        let p = try #require(photos.last)
        #expect(p.owner == "Maarten Heerlien")
        #expect(p.credit == "foto · Wikimedia CC BY 2.0 · @Maarten Heerlien")
        #expect(p.pageURL?.host() == "commons.wikimedia.org")
        #expect(p.listPhoto.url == "https://upload.wikimedia.org/thumb/9/96/Lantern.jpg/1024px-Lantern.jpg")
    }

    @Test func freeLicenseRules() {
        #expect(CommonsPhotoService.isFree("cc-by-sa-4.0"))
        #expect(CommonsPhotoService.isFree("cc0"))
        #expect(CommonsPhotoService.isFree("pd"))
        #expect(!CommonsPhotoService.isFree("cc-by-nc-sa-2.0"))
        #expect(!CommonsPhotoService.isFree("cc-by-nd-3.0"))
        #expect(!CommonsPhotoService.isFree("arr"))
    }

    // MARK: Rotas

    @Test func leaveAtIsTravelPlusFive() {
        let at = BoardDates.parseDateTime("2026-11-15T19:00:00+09:00")!
        #expect(RoutesService.leaveAt(at, travelMinutes: 5) == BoardDates.parseDateTime("2026-11-15T18:50:00+09:00"))
    }
}

/// Sincronização do Places com serviço falso (sem rede).
@MainActor
struct PlacesSyncTests {
    private final class Token {}

    @Test func syncResolvesApproxPlacesWithinBatch() async throws {
        let container = try ModelContainer(for: MustSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        try RegionStore.seedIfEmpty(ctx, region: .bh, bundle: Bundle(for: Token.self))
        let places = try ctx.fetch(FetchDescriptor<Place>())
        let fake = FakePlacesService(
            candidates: places.map { PlaceCandidate(id: "g-\($0.id)", name: $0.name, address: nil, lat: $0.lat + 0.001, lng: $0.lng) },
            detailsById: ["g-p07": PlaceDetails(id: "g-p07", hours: PlaceHours(weekdayText: nil, periods: [
                .init(open: .init(day: 1, hour: 7, minute: 0), close: .init(day: 1, hour: 19, minute: 0)),
            ], fetchedAt: Date()), priceLevel: 1, priceFrom: 12, priceCurrency: "BRL")]
        )
        let sync = SyncCoordinator(places: fake, weather: FakeWeatherService(forecast: Forecast(days: [:], now: nil, fetchedAt: Date())),
                                   photos: FakePhotoService())
        DevOverrides.liveData = true
        await sync.syncPlaces(context: ctx, region: .bh)

        let after = try ctx.fetch(FetchDescriptor<Place>())
        #expect(after.allSatisfy { $0.placeId == "g-\($0.id)" && !$0.approx })
        let nice = try #require(after.first { $0.id == "p07" })
        #expect(nice.hours?.periods?.count == 1)
        #expect(nice.priceLevel == 1)
        #expect(nice.price == 15) // preço do board não é sobrescrito
        #expect(sync.placesSummary?.contains("28 resolvidos") == true)
        #expect(sync.placesProgress == nil)
    }
}
