import CoreLocation
import Foundation
import Testing
@testable import Must

func fixture() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/wikidata-films.json"))
}

private let parkHyatt = CLLocationCoordinate2D(latitude: 35.6857, longitude: 139.6911)

struct WikidataFilmsParserTests {
    @Test func parsesFixtureKeepingOnlyLatinTitlesAndDedupingByFilm() throws {
        let films = try WikidataFilms.parse(fixture(), from: parkHyatt)
        // Q777 (só japonês), Q888 (só QID) e Q999 (sem coordenada) saem; Q74102 aparece uma vez, como filmado.
        #expect(films.map(\.film.id) == ["Q555", "Q74102"])
        let lost = try #require(films.first { $0.film.id == "Q74102" }).film
        #expect(lost.title == "Encontros e Desencontros" && lost.year == 2003 && lost.director == "Sofia Coppola")
        #expect(lost.location == "Park Hyatt Tokyo" && lost.relation == "filmado")
        #expect(lost.url?.absoluteString == "https://www.wikidata.org/wiki/Q74102")
        // Local só em japonês: o filme fica, sem o nome do local.
        let story = try #require(films.first { $0.film.id == "Q555" }).film
        #expect(story.location == nil && story.relation == "ambientado")
    }

    @Test func coordinatesAreLongitudeFirst() throws {
        let c = try #require(WikidataFilms.coordinate("Point(139.6911 35.6857)"))
        #expect(c.latitude == 35.6857 && c.longitude == 139.6911)
        #expect(WikidataFilms.coordinate("Point(35.6857 139.6911)") == nil) // latitude fora de -90...90
        #expect(WikidataFilms.coordinate("nada") == nil)
    }

    @Test func queryPutsLongitudeFirstAndAsksP915AndP840() {
        let q = WikidataFilms.query(center: parkHyatt, radiusKm: 1.5)
        #expect(q.contains("Point(139.6911 35.6857)"))
        #expect(q.contains("wdt:P915") && q.contains("wdt:P840") && q.contains("wikibase:around") && q.contains("wdt:P625"))
        let url = WikidataFilms.url(center: parkHyatt, radiusKm: 1.5)
        #expect(url?.host() == "query.wikidata.org" && url?.absoluteString.contains("format=json") == true)
    }

    @Test func emptyResponseParsesToEmpty() throws {
        let data = Data(#"{"head":{"vars":[]},"results":{"bindings":[]}}"#.utf8)
        #expect(try WikidataFilms.parse(data, from: parkHyatt).isEmpty)
    }

    @Test func readFiltersByRealRadiusAndSortsFilmedFirst() throws {
        let cached = try WikidataFilms.parse(fixture(), from: parkHyatt)
        let near = WikidataFilms.read(cached, near: parkHyatt, radiusKm: 5)
        #expect(near.map(\.id) == ["Q74102", "Q555"])
        #expect(near.allSatisfy { ($0.distanceMeters ?? -1) >= 0 })
        #expect(WikidataFilms.read(cached, near: parkHyatt, radiusKm: 0.05).map(\.id) == ["Q74102"])
    }

    @Test func userAgentIsDescriptiveWithoutEmail() {
        #expect(WikidataFilms.userAgent.hasPrefix("Must/1.0"))
        #expect(!WikidataFilms.userAgent.contains("@"))
    }
}

struct FilmCacheTests {
    func tempCache() -> FilmCache { FilmCache(directory: FileManager.default.temporaryDirectory.appending(path: "films-\(UUID().uuidString)")) }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func hit() { lock.lock(); n += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    @Test func fetchesOnceThenServesFromCacheForThirtyDays() async throws {
        let data = try fixture()
        let calls = Counter()
        let cache = tempCache()
        let clock = Counter()
        let films = WikidataFilms(cache: cache, fetch: { _ in calls.hit(); return data }, now: { Date(timeIntervalSince1970: 1_800_000_000 + Double(clock.count) * 86_400) })
        let first = await films.films(near: parkHyatt, radiusKm: 1.5)
        #expect(first.map(\.id) == ["Q74102", "Q555"] || first.map(\.id) == ["Q74102"])
        #expect(first.contains { $0.id == "Q74102" })
        _ = await films.films(near: parkHyatt, radiusKm: 1.5)
        #expect(calls.count == 1)
        let key = FilmCache.key(parkHyatt, radiusKm: 1.5)
        let entry = try #require(await cache.entry(key))
        #expect(await cache.isFresh(entry, now: entry.fetchedAt.addingTimeInterval(29 * 86_400)))
        #expect(await !cache.isFresh(entry, now: entry.fetchedAt.addingTimeInterval(31 * 86_400)))
    }

    @Test func emptyResultIsCachedToo() async throws {
        let calls = Counter()
        let cache = tempCache()
        let empty = Data(#"{"head":{"vars":[]},"results":{"bindings":[]}}"#.utf8)
        let films = WikidataFilms(cache: cache) { _ in calls.hit(); return empty }
        #expect(await films.films(near: parkHyatt, radiusKm: 1.5).isEmpty)
        #expect(try #require(await cache.entry(FilmCache.key(parkHyatt, radiusKm: 1.5))).films.isEmpty)
        #expect(await films.films(near: parkHyatt, radiusKm: 1.5).isEmpty)
        #expect(calls.count == 1)
    }

    @Test func offlineAndErrorsNeverThrowAndFallBackToStaleCache() async throws {
        let data = try fixture()
        let cache = tempCache()
        // Cache velho (31 dias) + rede caída: devolve o velho, sem lançar.
        let old = try WikidataFilms.parse(data, from: FilmCache.cellCenter(parkHyatt))
        await cache.store(old, key: FilmCache.key(parkHyatt, radiusKm: 1.5), now: Date().addingTimeInterval(-31 * 86_400))
        let down = WikidataFilms(cache: cache) { _ in throw ServiceError.offline }
        #expect(await down.films(near: parkHyatt, radiusKm: 1.5).contains { $0.id == "Q74102" })
        // Sem cache e sem rede: vazio.
        let nothing = WikidataFilms(cache: tempCache()) { _ in throw URLError(.timedOut) }
        #expect(await nothing.films(near: parkHyatt, radiusKm: 1.5).isEmpty)
        // Resposta quebrada: vazio, e não guarda lixo.
        let junk = WikidataFilms(cache: tempCache()) { _ in Data("<html>".utf8) }
        #expect(await junk.films(near: parkHyatt, radiusKm: 1.5).isEmpty)
    }

    @Test func triesOnlyOncePerPlacePerSession() async {
        let calls = Counter()
        let films = WikidataFilms(cache: tempCache()) { _ in calls.hit(); throw URLError(.timedOut) }
        _ = await films.films(near: parkHyatt, radiusKm: 1.5)
        _ = await films.films(near: parkHyatt, radiusKm: 1.5)
        #expect(calls.count == 1)
    }

    @Test func nearbyPointsShareTheSameCell() {
        let a = FilmCache.key(CLLocationCoordinate2D(latitude: 35.6857, longitude: 139.6911), radiusKm: 1.5)
        let b = FilmCache.key(CLLocationCoordinate2D(latitude: 35.6872, longitude: 139.6934), radiusKm: 1.5)
        #expect(a == b)
        #expect(a != FilmCache.key(parkHyatt, radiusKm: 5))
    }
}
