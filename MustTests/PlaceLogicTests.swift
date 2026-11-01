import Foundation
import Testing
@testable import Must

struct PlaceHoursTests {
    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    /// Ter–dom 18:00–23:00 (fecha segunda).
    private var dinner: PlaceHours {
        PlaceHours(weekdayText: nil, periods: [0, 2, 3, 4, 5, 6].map { day in
            .init(open: .init(day: day, hour: 18, minute: 0), close: .init(day: day, hour: 23, minute: 0))
        }, fetchedAt: nil)
    }

    /// Bar que vira a noite: sex 20:00 → sáb 02:00.
    private var lateBar: PlaceHours {
        PlaceHours(weekdayText: nil, periods: [.init(open: .init(day: 5, hour: 20, minute: 0), close: .init(day: 6, hour: 2, minute: 0))], fetchedAt: nil)
    }

    private func date(_ s: String) -> Date { BoardDates.parseDateTime(s)! }

    @Test func openInsidePeriod() {
        // 2026-11-15 é domingo.
        #expect(dinner.isOpen(at: date("2026-11-15T19:00:00+09:00"), timeZone: tokyo) == true)
        #expect(dinner.closesAt(date("2026-11-15T19:00:00+09:00"), timeZone: tokyo) == "23:00")
    }

    @Test func closedBeforeOpening() {
        let at = date("2026-11-15T12:00:00+09:00")
        #expect(dinner.isOpen(at: at, timeZone: tokyo) == false)
        let next = dinner.nextOpening(after: at, timeZone: tokyo)
        #expect(next?.day == nil)
        #expect(next?.time == "18:00")
    }

    @Test func closedDayPointsToNextDay() {
        // Segunda 2026-11-16 12:00 → abre ter 18:00.
        let next = dinner.nextOpening(after: date("2026-11-16T12:00:00+09:00"), timeZone: tokyo)
        #expect(next?.day == "ter")
        #expect(dinner.closedDays == ["seg"])
    }

    @Test func periodCrossingMidnight() {
        #expect(lateBar.isOpen(at: date("2026-11-14T01:30:00+09:00"), timeZone: tokyo) == true) // sáb 01:30
        #expect(lateBar.isOpen(at: date("2026-11-14T02:30:00+09:00"), timeZone: tokyo) == false)
        #expect(lateBar.isOpen(at: date("2026-11-13T21:00:00+09:00"), timeZone: tokyo) == true) // sex 21:00
    }

    @Test func noHoursIsUnknownNotOpen() {
        let place = Place(id: "x", name: "Sem horário", cityId: "bh")
        #expect(place.openState(at: .now, timeZone: tokyo) == .unknown)
        #expect(place.openState(at: .now, timeZone: tokyo).isOpen == false)
    }

    @Test func todayText() {
        #expect(dinner.todayText(date("2026-11-15T10:00:00+09:00"), timeZone: tokyo) == "18:00–23:00")
        #expect(dinner.todayText(date("2026-11-16T10:00:00+09:00"), timeZone: tokyo) == "fechado hoje")
    }
}

@MainActor
struct TripCityTests {
    private let region = Region.jp

    private func trip() -> TripInfo {
        let d = BoardDates(timeZone: region.timeZone)
        func city(_ id: String, _ name: String, _ from: String, _ to: String) -> City {
            City(id: id, name: name, from: d.day(from: from), to: d.day(from: to), tz: "Asia/Tokyo", currency: "JPY", lat: 0, lng: 0)
        }
        return TripInfo(start: d.day(from: "2026-11-11"), end: d.day(from: "2026-11-24"), home: "Naka-Meguro", cities: [
            city("tokyo1", "Tóquio", "2026-11-13", "2026-11-17"),
            city("kyoto", "Kyoto", "2026-11-17", "2026-11-20"),
            city("tokyo2", "Tóquio", "2026-11-20", "2026-11-24"),
        ])
    }

    private func at(_ s: String) -> Date { BoardDates.parseDateTime(s)! }

    @Test func cityOnEachDay() {
        let t = trip()
        let cal = region.calendar
        #expect(t.city(on: at("2026-10-31T12:00:00+09:00"), calendar: cal)?.id == "tokyo1") // antes da viagem
        #expect(t.city(on: at("2026-11-15T12:00:00+09:00"), calendar: cal)?.id == "tokyo1")
        #expect(t.city(on: at("2026-11-17T12:00:00+09:00"), calendar: cal)?.id == "kyoto") // dia de troca → cidade nova
        #expect(t.city(on: at("2026-11-22T12:00:00+09:00"), calendar: cal)?.id == "tokyo2")
        #expect(t.city(on: at("2026-12-01T12:00:00+09:00"), calendar: cal)?.id == "tokyo2")
    }

    @Test func labelsRepeatedCityNames() {
        let t = trip()
        #expect(t.label(for: t.cities[0], region: region) == "Tóquio 13–17")
        #expect(t.label(for: t.cities[1], region: region) == "Kyoto")
    }
}

struct LinkResolverTests {
    @Test(arguments: [
        ("https://www.instagram.com/reel/C8xQ2abc/", LinkSource.instagram),
        ("instagram.com/reel/C8xQ2abc", .instagram),
        ("https://vm.tiktok.com/ZMabc123/", .tiktok),
        ("https://youtu.be/dQw4w9WgXcQ", .youtube),
        ("https://www.youtube.com/shorts/abc", .youtube),
        ("https://maps.app.goo.gl/AbCdEf123", .maps),
        ("https://www.google.com/maps/place/Fuunji/@35.6870,139.6970,17z", .maps),
        ("https://maps.apple.com/?q=Sushi+Dai&ll=35.645,139.784", .maps),
        ("https://tabelog.com/tokyo/A1304/", .web),
    ])
    func detectsSource(input: String, expected: LinkSource) {
        #expect(LinkResolver.resolve(input).source == expected)
    }

    @Test func plainTextIsAName() {
        let r = LinkResolver.resolve("Kissa Sabouru")
        #expect(r.source == .text)
        #expect(r.url == nil)
        #expect(r.text == "Kissa Sabouru")
    }

    @Test func parsesGoogleMapsPlaceURL() throws {
        let url = try #require(URL(string: "https://www.google.com/maps/place/Menya+Kaijin/@35.6903,139.6995,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d35.6904!4d139.6998"))
        let p = LinkResolver.parseMaps(url)
        #expect(p.name == "Menya Kaijin")
        #expect(p.lat == 35.6904) // !3d tem prioridade sobre @
        #expect(p.lng == 139.6998)
    }

    @Test func parsesAppleMapsQuery() throws {
        let p = LinkResolver.parseMaps(try #require(URL(string: "https://maps.apple.com/?q=Sushi%20Dai&ll=35.645,139.784")))
        #expect(p.name == "Sushi Dai")
        #expect(p.lat == 35.645)
    }
}

struct HTMLMetaTests {
    @Test func readsOpenGraphInBothAttributeOrders() {
        let a = #"<meta property="og:description" content="Ramen de peixe no Menya Kaijin &amp; fila curta">"#
        let b = #"<meta content="Kissa antigo &#x2615; em Kanda" property="og:title" />"#
        #expect(HTMLMeta.content(of: "og:description", in: a) == "Ramen de peixe no Menya Kaijin & fila curta")
        #expect(HTMLMeta.content(of: "og:title", in: b) == "Kissa antigo ☕ em Kanda")
    }

    @Test func readsYouTubeShortDescription() {
        let html = #"..."shortDescription":"Top 3 ramen\n📍 Fuunji\n📍 Nakiryu","isCrawlable"..."#
        #expect(HTMLMeta.shortDescription(in: html) == "Top 3 ramen\n📍 Fuunji\n📍 Nakiryu")
    }
}

struct PlaceExtractorTests {
    @Test func findsPinnedPlaces() {
        let text = "Melhores ramens de Tóquio 🍜\n📍 Fuunji, Shinjuku\n📍 Nakiryu · Otsuka\n#ramen #tokyo"
        let names = PlaceExtractor.extract(text: text, knownAreas: ["Shinjuku", "Otsuka"]).map(\.name)
        #expect(names.contains("Fuunji"))
        #expect(names.contains("Nakiryu"))
        #expect(!names.contains { $0.lowercased().contains("tokyo") || $0 == "Tóquio" })
    }

    @Test func findsMentionsAndConnectors() {
        let text = "Jantar ontem no Menya Kaijin, depois drinks at Bar Benfiddich com @kissa_sabouru"
        let names = PlaceExtractor.extract(text: text).map(\.name)
        #expect(names.contains("Menya Kaijin"))
        #expect(names.contains("Bar Benfiddich"))
        #expect(names.contains("Kissa Sabouru"))
    }

    @Test func guessesCategoryAndSub() {
        let place = PlaceExtractor.extract(text: "📍 Menya Kaijin — ramen de peixe imperdível").first
        #expect(place?.category == .eat)
        #expect(place?.sub == "Ramen")
    }

    @Test func picksJapaneseNameAsLocal() {
        let place = PlaceExtractor.extract(text: "📍 Menya Kaijin 麺屋 海神 em Shinjuku", knownAreas: ["Shinjuku"]).first
        #expect(place?.name == "Menya Kaijin 麺屋 海神" || place?.nameLocal != nil)
        #expect(place?.area == "Shinjuku")
    }

    @Test func mapsCaptionUsesPlaceName() {
        let caption = Caption(source: .maps, title: "Xapuri", text: "Xapuri", placeName: "Xapuri", lat: -19.85, lng: -43.99)
        let found = PlaceExtractor.extract(from: caption)
        #expect(found.map(\.name) == ["Xapuri"])
        #expect(found.first?.hint == "link do Maps")
    }

    @Test func nothingFromNoise() {
        #expect(PlaceExtractor.extract(text: "que dia!!! 😍😍 #tokyo #japan").isEmpty)
    }
}

@MainActor
struct PlaceMatcherTests {
    @Test func similarNames() {
        #expect(PlaceMatcher.similar("Café de l'Ambre", "cafe de lambre"))
        #expect(PlaceMatcher.similar("Sushi Dai", "Sushi Dai Toyosu"))
        #expect(!PlaceMatcher.similar("Fuunji", "Nakiryu"))
        #expect(!PlaceMatcher.similar("Bar", "Bar Benfiddich")) // curto demais pra "contém"
    }
}

struct SavedPlacesImporterTests {
    @Test func parsesKML() {
        let kml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <kml xmlns="http://www.opengis.net/kml/2.2"><Document>
          <Placemark><name>Kissa Sabouru</name><description>café antigo</description>
            <Point><coordinates>139.7105,35.6950,0</coordinates></Point></Placemark>
          <Placemark><name>Chatei Hatou</name><Point><coordinates>
            139.6990,35.6585,0
          </coordinates></Point></Placemark>
        </Document></kml>
        """
        let places = SavedPlacesImporter.parse(Data(kml.utf8))
        #expect(places.map(\.name) == ["Kissa Sabouru", "Chatei Hatou"])
        #expect(places.first?.lat == 35.6950)
        #expect(places.first?.lng == 139.7105)
        #expect(places.first?.note == "café antigo")
    }

    @Test func parsesTakeoutGeoJSON() {
        let json = #"{"type":"FeatureCollection","features":[{"geometry":{"coordinates":[139.784,35.645],"type":"Point"},"properties":{"google_maps_url":"http://maps.google.com/?cid=1","location":{"name":"Sushi Dai","address":"Toyosu"}},"type":"Feature"},{"geometry":{"coordinates":[0,0],"type":"Point"},"properties":{"Title":"sem coordenada"},"type":"Feature"}]}"#
        let places = SavedPlacesImporter.parse(Data(json.utf8))
        #expect(places.map(\.name) == ["Sushi Dai"])
        #expect(places.first?.note == "Toyosu")
    }
}

@MainActor
struct TripStatsTests {
    private let region = Region.jp

    private func trip() -> TripInfo {
        let d = BoardDates(timeZone: region.timeZone)
        func city(_ id: String, _ name: String, _ from: String, _ to: String) -> City {
            City(id: id, name: name, from: d.day(from: from), to: d.day(from: to), tz: "Asia/Tokyo", currency: "JPY", lat: 0, lng: 0)
        }
        return TripInfo(start: d.day(from: "2026-11-11"), end: d.day(from: "2026-11-24"), home: "Naka-Meguro", cities: [
            city("tokyo1", "Tóquio", "2026-11-13", "2026-11-17"), city("kyoto", "Kyoto", "2026-11-17", "2026-11-20"),
            city("tokyo2", "Tóquio", "2026-11-20", "2026-11-24"),
        ])
    }

    @Test func dayStatesAcrossTheTrip() {
        let cal = region.calendar
        let d = BoardDates(timeZone: region.timeZone)
        let now = BoardDates.parseDateTime("2026-11-15T10:00:00+09:00")!
        let t = trip()
        let period = TripStats.period(trip: t, now: now, calendar: cal)
        let cells = TripStats.days(in: period, trip: t, now: now, calendar: cal, doneDays: [d.day(from: "2026-11-13")!, d.day(from: "2026-11-14")!])
        func state(_ day: String) -> TripStats.DayState? { cells.first { $0.date == d.day(from: day) }?.state }
        #expect(cells.count == 14)
        #expect(state("2026-11-13") == .done)
        #expect(state("2026-11-15") == .today)
        #expect(state("2026-11-16") == .future)
        #expect(state("2026-11-18") == .otherCity) // Kyoto
        #expect(state("2026-11-21") == .future)    // Tóquio de novo: mesma cidade de hoje
        #expect(state("2026-11-12") == .past)
        #expect(TripStats.elapsedDays(period, now: now, calendar: cal) == 5)
    }

    @Test func bhUsesTheCurrentMonth() {
        let cal = Region.bh.calendar
        let now = BoardDates.parseDateTime("2026-11-01T10:00:00-03:00")!
        let period = TripStats.period(trip: nil, now: now, calendar: cal)
        let d = BoardDates(timeZone: Region.bh.timeZone)
        #expect(d.dayString(period.lowerBound) == "2026-11-01")
        #expect(d.dayString(period.upperBound) == "2026-11-30")
        #expect(TripStats.elapsedDays(period, now: now, calendar: cal) == 1)
    }
}
