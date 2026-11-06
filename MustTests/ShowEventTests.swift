import CoreLocation
import Foundation
import Testing
@testable import Must

enum ShowFix {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static var cal: Calendar { Region.jp.calendar }

    static func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, tz: TimeZone = tokyo) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// "2026-11-30" como o JSON guarda: meia-noite UTC.
    static func jsonDay(_ y: Int, _ m: Int, _ d: Int) -> Date { at(y, m, d, tz: .gmt) }

    static func daily(_ open: Int, _ close: Int) -> PlaceHours {
        PlaceHours(weekdayText: nil, periods: (0...6).map {
            PlaceHours.Period(open: .init(day: $0, hour: open, minute: 0), close: .init(day: $0, hour: close, minute: 0))
        }, fetchedAt: nil)
    }

    static func place(_ id: String, _ name: String, kind: ListKind = .art, color: MustColor = .see, lat: Double = 35.68, lng: Double = 139.76,
                      hours: PlaceHours? = nil, extra: PlaceExtra? = nil, tickets: [Ticket] = [], done: Bool = false) -> SolverPlace {
        SolverPlace(id: id, name: name, listId: "l", listColor: color, sub: nil, cityId: "tokyo1", area: nil, lat: lat, lng: lng, price: nil,
                    windows: [], hours: hours, reservation: nil, saveForEnd: false, allowBudgetException: false, queueMinutes: nil, notes: "",
                    sourceKind: nil, done: done, kind: kind, extra: extra, tickets: tickets)
    }

    static func art(until: Date? = nil, from: Date? = nil, sessions: [EventSession] = [], price: Double? = 1_200) -> PlaceExtra {
        PlaceExtra(art: ArtEvent(priceAdult: price, runsFrom: from, runsUntil: until, ticketURL: URL(string: "https://example.com/t"), sessions: sessions))
    }
}

@MainActor
struct ShowEventTests {
    typealias F = ShowFix

    func provider(_ places: [SolverPlace]) -> BoardShowEvents { BoardShowEvents(region: .jp, places: { places }) }

    @Test func exhibitionComesFromArtEvent() throws {
        let p = F.place("m1", "Museu Moriyama", extra: F.art(until: F.jsonDay(2026, 11, 30), from: F.jsonDay(2026, 10, 1)))
        let events = provider([p]).today(region: .jp, at: F.at(2026, 11, 14, 10))
        let e = try #require(events.first)
        #expect(events.count == 1)
        #expect(e.kind == .exhibition && e.source == .board && e.placeId == "m1")
        #expect(e.title == "Museu Moriyama")
        #expect(e.priceText?.contains("1,200") == true || e.priceText?.contains("1.200") == true)
        #expect(e.url?.absoluteString == "https://example.com/t")
    }

    @Test func expiredExhibitionDisappears() {
        let p = F.place("m1", "Museu", extra: F.art(until: F.jsonDay(2026, 11, 13)))
        #expect(provider([p]).today(region: .jp, at: F.at(2026, 11, 14, 10)).isEmpty)
        #expect(provider([p]).upcoming(region: .jp, from: F.at(2026, 11, 14, 10), days: 30).isEmpty)
        #expect(provider([p]).events(placeId: "m1", at: F.at(2026, 11, 14, 10)).isEmpty)
    }

    @Test func todayFollowsTheRegionTimeZone() {
        let p = F.place("m1", "Museu", extra: F.art(until: F.jsonDay(2026, 11, 14)))
        // 23:30 em Tóquio ainda é 14/11 (14:30 UTC): em cartaz. 00:30 de 15/11 em Tóquio (15:30 de 14/11 UTC): acabou.
        #expect(provider([p]).today(region: .jp, at: F.at(2026, 11, 14, 23, 30)).count == 1)
        #expect(provider([p]).today(region: .jp, at: F.at(2026, 11, 15, 0, 30)).isEmpty)
    }

    @Test func sessionJustAfterLocalMidnightIsToday() {
        let s = EventSession(at: F.at(2026, 11, 14, 0, 30), title: "Madrugada")
        let p = F.place("c1", "Casa", kind: .place, color: .listen, extra: PlaceExtra(program: [s]))
        #expect(provider([p]).today(region: .jp, at: F.at(2026, 11, 14, 12)).count == 1)
        #expect(provider([p]).today(region: .jp, at: F.at(2026, 11, 13, 12)).isEmpty)
    }

    @Test func sportSessionsBecomeMatchesAndPastOnesDrop() {
        let past = EventSession(at: F.at(2026, 11, 10, 19), title: "Antigo")
        let next = EventSession(at: F.at(2026, 11, 16, 19), title: "Flamengo x Cruzeiro", price: 90)
        let p = F.place("s1", "Mineirão", kind: .sport, color: .listen, extra: PlaceExtra(sport: SportSpot(sessions: [past, next])))
        let events = provider([p]).upcoming(region: .jp, from: F.at(2026, 11, 14, 9), days: 7)
        #expect(events.map(\.title) == ["Flamengo x Cruzeiro"])
        #expect(events.first?.kind == .match)
        #expect(provider([p]).today(region: .jp, at: F.at(2026, 11, 14, 9)).isEmpty)
        #expect(provider([p]).upcoming(region: .jp, from: F.at(2026, 11, 14, 9), days: 1).isEmpty)
    }

    @Test func ticketMarksItsSessionBoughtAndOrphanTicketsBecomeEvents() throws {
        let s = EventSession(at: F.at(2026, 11, 20, 20), title: "Show")
        let linked = Ticket(at: s.at, sessionId: s.id, qrPayload: "QR")
        let loose = Ticket(at: F.at(2026, 11, 21, 15), paid: 3_000)
        let p = F.place("c1", "Zepp", kind: .place, color: .listen, extra: PlaceExtra(program: [s]), tickets: [linked, loose])
        let events = provider([p]).upcoming(region: .jp, from: F.at(2026, 11, 14), days: 10)
        #expect(events.count == 2)
        #expect(try #require(events.first { $0.title == "Show" }).sessions.first?.bought == true)
        let orphan = try #require(events.first { $0.id.contains("-t-") })
        #expect(orphan.sessions.first?.bought == true && orphan.startsAt == loose.at)
    }

    @Test func programKeepsOriginAndCheckDate() throws {
        let s = EventSession(at: F.at(2026, 11, 20, 20), title: "Show")
        let checked = F.at(2026, 11, 10)
        let p = F.place("c1", "Zepp", kind: .place, color: .listen, extra: PlaceExtra(program: [s], programSource: .poster, programCheckedAt: checked))
        let e = try #require(provider([p]).events(placeId: "c1", at: F.at(2026, 11, 14)).first)
        #expect(e.source == .poster && e.checkedAt == checked && e.kind == .show)
    }

    @Test func doneAndUnrelatedPlacesAddNothing() {
        let done = F.place("m1", "Museu", extra: F.art(until: F.jsonDay(2026, 12, 1)), done: true)
        let permanent = F.place("m2", "Museu fixo", extra: PlaceExtra(art: ArtEvent(priceAdult: 100)))
        let plain = F.place("e1", "Lámen", kind: .place, color: .eat)
        #expect(provider([done, permanent, plain]).upcoming(region: .jp, from: F.at(2026, 11, 14), days: 30).isEmpty)
    }

    @Test func externalEventsMergeWithoutDuplicatingTheBoard() {
        let s = EventSession(at: F.at(2026, 11, 20, 20), title: "Banda X")
        let p = F.place("c1", "Zepp", kind: .place, color: .listen, extra: PlaceExtra(program: [s]))
        let dup = ShowEvent(id: "bit-1", kind: .show, title: "banda x", venue: "ZEPP", startsAt: F.at(2026, 11, 20, 19), source: .bandsintown)
        let fresh = ShowEvent(id: "bit-2", kind: .show, title: "Outra", venue: "Outro", startsAt: F.at(2026, 11, 21, 19), source: .bandsintown)
        let old = ShowEvent(id: "bit-3", kind: .show, title: "Velha", startsAt: F.at(2026, 11, 1, 19), source: .feed)
        let merged = provider([p]).merging([dup, fresh, old]).upcoming(region: .jp, from: F.at(2026, 11, 14), days: 30)
        #expect(merged.map(\.title) == ["Banda X", "Outra"])
        #expect(merged.map(\.source) == [.link, .bandsintown])
    }

    @Test func eventsAreStableAndSorted() {
        let a = F.place("a", "A", kind: .sport, color: .listen, extra: PlaceExtra(sport: SportSpot(sessions: [EventSession(at: F.at(2026, 11, 18, 19), title: "B")])))
        let b = F.place("b", "B", kind: .sport, color: .listen, extra: PlaceExtra(sport: SportSpot(sessions: [EventSession(at: F.at(2026, 11, 16, 19), title: "A")])))
        let one = provider([a, b]).upcoming(region: .jp, from: F.at(2026, 11, 14), days: 10)
        let two = provider([b, a]).upcoming(region: .jp, from: F.at(2026, 11, 14), days: 10)
        #expect(one == two)
        #expect(one.map(\.title) == ["A", "B"])
    }
}

@MainActor
struct EventPasteTests {
    typealias F = ShowFix
    let now = F.at(2026, 11, 5, 9)

    @Test func readsSessionsPriceAndKindFromPastedText() {
        let text = """
        Retrospectiva Moriyama
        Sáb 21/11 · 19h30 Abertura
        2026-11-28 15:00 Palestra
        Ingresso ¥ 1.500
        """
        let d = EventPaste.draft(text: text, source: .link, timeZone: F.tokyo, now: now)
        #expect(d.title == "Retrospectiva Moriyama")
        #expect(d.sessions.map(\.at) == [F.at(2026, 11, 21, 19, 30), F.at(2026, 11, 28, 15)])
        #expect(d.sessions.first?.title == "Abertura")
        #expect(d.kind == .exhibition)
        #expect(d.art.priceAdult == 1_500)
        #expect(d.confidence["sessions"] != nil)
    }

    @Test func linesWithoutTimeAreIgnored() {
        #expect(EventExtractor.sessions(in: "Até 30/11\nAberto de terça a domingo", timeZone: F.tokyo, now: now).isEmpty)
    }

    @Test func monthNamesAndJapaneseDates() {
        let s = EventExtractor.sessions(in: "20 nov 21h Show\n12月3日 19:00 ライブ", timeZone: F.tokyo, now: now)
        #expect(s.map(\.at) == [F.at(2026, 11, 20, 21), F.at(2026, 12, 3, 19)])
    }

    @Test func applyFillsProgramWithoutDuplicatingAndStampsOrigin() {
        let d = EventPaste.draft(text: "Show\n20/11 21h Banda", source: .poster, timeZone: F.tokyo, now: now)
        let once = EventPaste.apply(d, to: nil, now: now)
        let twice = EventPaste.apply(d, to: once, now: now)
        #expect(once.program.count == 1 && twice.program.count == 1)
        #expect(twice.programSource == .poster && twice.programCheckedAt == now)
    }

    @Test func applyCompletesTheSeasonOfAnExistingExhibition() {
        let d = EventPaste.draft(text: "Retrospectiva até 16/12\nIngresso ¥ 2.000", source: .link, timeZone: F.tokyo, now: now)
        let extra = EventPaste.apply(d, to: PlaceExtra(art: ArtEvent()), now: now)
        #expect(extra.art?.runsUntil != nil && extra.art?.priceAdult == 2_000)
    }

    @Test func matchesAPlaceByNameOrAsksWhichOne() {
        let places = [F.place("m1", "Museu Moriyama"), F.place("m2", "Zepp Shinjuku", kind: .place, color: .listen)]
        let hit = EventPaste.draft(text: "Moriyama · retrospectiva", source: .link, timeZone: F.tokyo, now: now)
        #expect(EventPaste.match(hit, in: places)?.id == "m1")
        let miss = EventPaste.draft(text: "Exposição qualquer", source: .link, timeZone: F.tokyo, now: now)
        #expect(EventPaste.match(miss, in: places) == nil)
    }
}
