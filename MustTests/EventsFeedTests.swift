import Foundation
import Testing
@testable import Must

/// EventsService (prompt 26 §3): parser de feed, datas, mapeamento pra `ShowEvent`, APIs com chave, cache e Haiku.
@MainActor
struct EventsFeedTests {
    private let region = Region.jp
    private var now: Date { region.calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))! }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/feeds/\(name)")
        return try Data(contentsOf: url)
    }

    private func day(_ d: Int, month: Int = 11, region: Region = .jp) -> Date {
        region.calendar.date(from: DateComponents(year: 2026, month: month, day: d))!
    }

    // MARK: Parser

    @Test func rssVira_itensSemHTML() throws {
        let items = FeedParser.parse(try fixture("tokyocheapo-events.xml"))
        #expect(items.count == 3)
        #expect(items[0].title == "Akasaka Palace Night Opening")
        #expect(items[0].link?.absoluteString == "https://tokyocheapo.com/events/akasaka-palace-night-opening/")
        #expect(!items[0].summary.contains("<"))
        #expect(items[1].summary.contains("Tokyo’s"))
        #expect(items[0].published != nil)
    }

    @Test func atomTambemLe() throws {
        let items = FeedParser.parse(try fixture("atom-sample.xml"))
        #expect(items.count == 1)
        #expect(items[0].link?.absoluteString == "https://exemplo.com.br/mostra")
        #expect(items[0].published != nil)
    }

    @Test func xmlQuebradoNaoCrasha() {
        #expect(FeedParser.parse(Data("<html><body>oi</body></html>".utf8)).isEmpty)
        #expect(FeedParser.parse(Data()).isEmpty)
    }

    // MARK: Datas

    @Test func datasEmIngles() {
        let dates = EventDateExtractor.dates(in: "Saturday, November 21 and Sunday, November 22, 2026.", reference: now, calendar: region.calendar)
        #expect(dates == [day(21), day(22)])
    }

    @Test func datasEmPortuguesEItaliano() {
        let br = Region.bh
        let ref = br.calendar.date(from: DateComponents(year: 2026, month: 11, day: 5))!
        #expect(EventDateExtractor.dates(in: "De 12 de novembro a 20 de novembro de 2026", reference: ref, calendar: br.calendar)
                == [day(12, region: br), day(20, region: br)])
        #expect(EventDateExtractor.dates(in: "il 15/12/2026 alle 21", reference: ref, calendar: br.calendar) == [day(15, month: 12, region: br)])
        #expect(EventDateExtractor.dates(in: "dal 3 dicembre", reference: ref, calendar: br.calendar) == [day(3, month: 12, region: br)])
    }

    @Test func semDataNaoInventa() {
        #expect(EventDateExtractor.dates(in: "A great place to eat in Nakano", reference: now, calendar: region.calendar).isEmpty)
        #expect(EventDateExtractor.span(from: [], now: now, calendar: region.calendar) == nil)
    }

    @Test func temporadaPegaPrimeiraEUltima() throws {
        let span = try #require(EventDateExtractor.span(from: [day(21), day(22)], now: now, calendar: region.calendar))
        #expect(span.start == day(21)); #expect(span.end == day(22))
        #expect(EventDateExtractor.span(from: [day(1)], now: now, calendar: region.calendar) == nil) // já passou
    }

    // MARK: Mapeamento

    private var tokyoFeed: EventsSources.Feed {
        .init(id: "tokyocheapo", name: "Tokyo Cheapo", region: "jp", url: URL(string: "https://tokyocheapo.com/events/feed/")!, lang: "en", kind: "events")
    }

    @Test func feedDeEventosMantemTudoMenosOVelho() throws {
        let items = FeedParser.parse(try fixture("tokyocheapo-events.xml"))
        let events = EventsMapping.feedEvents(items, feed: tokyoFeed, region: region, now: now, maxAge: 45 * 86_400)
        #expect(events.count == 2) // o de março passou do limite de idade
        #expect(events.allSatisfy { $0.source == .feed && $0.id.hasPrefix("feed:tokyocheapo:") })
        #expect(events[0].startsAt == day(21)); #expect(events[0].runsUntil == day(22))
        #expect(events[1].startsAt == nil)
    }

    @Test func feedDeAgendaSoComData() throws {
        var feed = tokyoFeed
        feed.kind = "agenda"
        let events = EventsMapping.feedEvents(FeedParser.parse(try fixture("tokyocheapo-events.xml")), feed: feed, region: region, now: now,
                                              maxAge: 45 * 86_400)
        #expect(events.map(\.title) == ["Akasaka Palace Night Opening"])
    }

    @Test func idEstavel() {
        #expect(EventsMapping.stableHash("a") == EventsMapping.stableHash("a"))
        #expect(EventsMapping.stableHash("a") != EventsMapping.stableHash("b"))
    }

    @Test func ticketmasterLeLugarEHora() {
        let json = """
        {"_embedded":{"events":[{"id":"Z1","name":"Jazz Night","url":"https://tm.example/z1",
          "dates":{"start":{"dateTime":"2026-11-05T22:00:00Z"}},"classifications":[{"segment":{"name":"Music"}}],
          "priceRanges":[{"min":30.0,"currency":"BRL"}],
          "_embedded":{"venues":[{"name":"Bar X","location":{"latitude":"-19.93","longitude":"-43.94"}}]}}]}}
        """
        let events = EventsMapping.ticketmaster(Data(json.utf8), now: now)
        #expect(events.count == 1)
        #expect(events[0].id == "ticketmaster:Z1"); #expect(events[0].source == .ticketmaster); #expect(events[0].kind == .show)
        #expect(events[0].lat == -19.93); #expect(events[0].venue == "Bar X"); #expect(events[0].priceText == "BRL 30")
        #expect(EventsMapping.ticketmaster(Data("{}".utf8), now: now).isEmpty)
    }

    @Test func bandsintownLeNoFusoDaRegiao() throws {
        let json = #"[{"id":"77","datetime":"2026-11-05T20:00:00","title":"","lineup":["Banda A"],"venue":{"name":"Casa","latitude":"-19.9","longitude":"-43.9"},"url":"https://b.example/77"}]"#
        let events = EventsMapping.bandsintown(Data(json.utf8), region: .bh, now: now)
        let e = try #require(events.first)
        #expect(e.id == "bandsintown:77"); #expect(e.title == "Banda A"); #expect(e.source == .bandsintown)
        #expect(Region.bh.calendar.component(.hour, from: try #require(e.startsAt)) == 20)
    }

    @Test func hojeEEmTemporada() {
        let e = ShowEvent(id: "x", placeId: nil, kind: .exhibition, title: "t", venue: nil, lat: nil, lng: nil, startsAt: day(10), runsUntil: day(20),
                          sessions: [], priceText: nil, url: nil, source: .feed, checkedAt: nil)
        #expect(EventsMapping.isOn(e, day: day(15), calendar: region.calendar))
        #expect(!EventsMapping.isOn(e, day: day(21), calendar: region.calendar))
    }

    // MARK: Cache e política de rede

    @Test func cacheVaiEVolta() throws {
        let dir = URL.temporaryDirectory.appending(path: "events-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cache = EventsCache(directory: dir)
        #expect(cache.read(.bh) == nil)
        let event = ShowEvent(id: "e", placeId: nil, kind: .show, title: "T", venue: "V", lat: 1, lng: 2, startsAt: now, runsUntil: nil, sessions: [],
                              priceText: nil, url: nil, source: .feed, checkedAt: now)
        let snap = EventsSnapshot(region: .bh, fetchedAt: now, expiresAt: now.addingTimeInterval(6 * 3600), events: [event], haikuDay: "2026-11-05")
        cache.write(snap)
        #expect(cache.read(.bh) == snap)
        #expect(cache.read(.jp) == nil) // por região
    }

    @Test func politicaDeRede() {
        let fresh = EventsSnapshot(region: .jp, fetchedAt: now, expiresAt: now.addingTimeInterval(3600), events: [])
        let stale = EventsSnapshot(region: .jp, fetchedAt: now, expiresAt: now.addingTimeInterval(-1), events: [])
        typealias P = EventsFetchPolicy
        #expect(!P.shouldFetch(cache: fresh, now: now, status: .online, wifi: true))   // 6 h: não repete
        #expect(P.shouldFetch(cache: stale, now: now, status: .online, wifi: true))
        #expect(!P.shouldFetch(cache: stale, now: now, status: .online, wifi: false))  // vencido no celular: espera o Wi-Fi
        #expect(P.shouldFetch(cache: nil, now: now, status: .online, wifi: false))     // primeira vez vale no celular
        #expect(!P.shouldFetch(cache: nil, now: now, status: .constrained, wifi: true)) // Pouco Dados: só cache
        #expect(!P.shouldFetch(cache: nil, now: now, status: .offline, wifi: true))
    }

    // MARK: Fontes (data/events-sources.json)

    @Test func fontesValidadas() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("data/events-sources.json")
        let sources = try JSONDecoder().decode(EventsSources.self, from: Data(contentsOf: url))
        #expect(!sources.feeds.isEmpty)
        #expect(sources.feeds.allSatisfy { $0.url.scheme == "https" })
        #expect(!sources.feeds.contains { $0.url.host()?.contains("sympla") == true }) // sem feed = sem fonte (nada de scraping)
        #expect(sources.feeds(for: .bh).contains { $0.id == "sescmg" })
        #expect(sources.feeds(for: .jp).contains { $0.id == "tokyocheapo" })
        #expect(sources.ttl == 6 * 3600)
        #expect(sources.sourceName(forEventId: "feed:tokyocheapo:abc") == "Tokyo Cheapo")
    }

    @Test func semChaveAFonteSome() {
        // Hoje não há chave de Bandsintown/Ticketmaster: ler `Secrets` nunca crasha e devolve nil.
        #expect(Secrets.load(from: Bundle(for: Dummy.self))["BANDSINTOWN_APP_ID"] == nil)
        #expect(Secrets.Key.bandsintown.rawValue == "BANDSINTOWN_APP_ID")
        #expect(Secrets.Key.ticketmaster.rawValue == "TICKETMASTER_KEY")
    }
    private final class Dummy {}

    // MARK: Haiku (regra do Vinicius)

    private func candidates() -> [(index: Int, event: ShowEvent, summary: String)] {
        let e = ShowEvent(id: "feed:tokyocheapo:1", placeId: nil, kind: .other, title: "Night Market", venue: nil, lat: nil, lng: nil, startsAt: nil,
                          runsUntil: nil, sessions: [], priceText: nil, url: nil, source: .feed, checkedAt: nil)
        return EventsHaiku.candidates([e], items: [e.id: "Night market on Nov 28 at Yoyogi, ¥500"])
    }

    @Test func haikuSoHaikuEffortLowSemThinking() throws {
        let body = EventsHaiku.requestBody(candidates())
        #expect(body["model"] as? String == "claude-haiku-5-5")
        #expect(body["model"] as? String == CloudBoost.model)
        #expect(((body["output_config"] as? [String: Any])?["effort"]) as? String == "low")
        #expect(body["thinking"] == nil)
        #expect(!(body["model"] as? String ?? "").contains("opus") && !(body["model"] as? String ?? "").contains("sonnet"))
    }

    @Test func haikuNuncaInventaEvento() throws {
        func response(_ rows: String) -> Data {
            let text = #"{"events":[\#(rows)]}"#
            let json: [String: Any] = ["stop_reason": "end_turn", "content": [["type": "text", "text": text]]]
            return try! JSONSerialization.data(withJSONObject: json)
        }
        let list = candidates()
        let ok = try EventsHaiku.apply(response(#"{"index":0,"venue":"Yoyogi","startDate":"2026-11-28","endDate":"","price":"¥500"}"#),
                                       to: list, now: now, calendar: region.calendar)
        #expect(ok.count == 1); #expect(ok[0].venue == "Yoyogi"); #expect(ok[0].startsAt == day(28)); #expect(ok[0].priceText == "¥500")
        // Índice que não existe na lista, data impossível ou ano absurdo: ignorados.
        let bad = try EventsHaiku.apply(response(#"{"index":9,"venue":"X","startDate":"2026-11-28","endDate":"","price":""},"#
                                                 + #"{"index":0,"venue":"X","startDate":"2031-01-01","endDate":"","price":""},"#
                                                 + #"{"index":0,"venue":"X","startDate":"2026-13-45","endDate":"","price":""}"#),
                                        to: list, now: now, calendar: region.calendar)
        #expect(bad.isEmpty)
    }

    @Test func haikuSoOQueNaoTemData() {
        var dated = candidates()[0].event
        dated.startsAt = now
        #expect(EventsHaiku.candidates([dated], items: [:]).isEmpty)
    }
}
