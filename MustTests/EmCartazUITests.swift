import Foundation
import Testing
@testable import Must

/// Rodada 23 · B: seções, filtros e textos da tela Em cartaz (lógica pura).
struct EmCartazUITests {
    static let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c }()
    static let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 14))!

    static func day(_ d: Int, _ h: Int = 19) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 15 + d, hour: h))! }

    static let expo = ShowEvent(id: "e", kind: .exhibition, title: "Expo", startsAt: day(-30, 10), runsUntil: day(90, 18), source: .board)
    static let show = ShowEvent(id: "s", kind: .show, title: "Show", startsAt: day(1), source: .link)
    static let match = ShowEvent(id: "m", kind: .match, title: "Jogo", startsAt: day(6, 14), source: .poster)
    static let old = ShowEvent(id: "o", kind: .exhibition, title: "Velha", startsAt: day(-90, 10), runsUntil: day(-2, 18), source: .board)

    @Test func todayFirstThenLater() {
        let s = EmCartazModel.sections(today: [Self.expo], upcoming: [Self.match, Self.show, Self.expo], filter: .trip, now: Self.now, calendar: Self.cal)
        #expect(s.today.map(\.id) == ["e"])
        #expect(s.later.map(\.id) == ["s", "m"])
    }

    @Test func expiredDisappears() {
        let s = EmCartazModel.sections(today: [], upcoming: [Self.old, Self.show], filter: .trip, now: Self.now, calendar: Self.cal)
        #expect(s.all.map(\.id) == ["s"])
    }

    @Test func filters() {
        let all = [Self.expo, Self.show, Self.match]
        func ids(_ f: EmCartazFilter) -> [String] { EmCartazModel.sections(today: [], upcoming: all, filter: f, now: Self.now, calendar: Self.cal).all.map(\.id) }
        #expect(ids(.museums) == ["e"])
        #expect(ids(.shows) == ["s"])
        #expect(ids(.matches) == ["m"])
        #expect(ids(.today) == ["e"])
    }

    @Test func trailingAndHeader() {
        #expect(EmCartazModel.trailing(Self.show, region: .jp, now: Self.now).top == "amanhã")
        #expect(EmCartazModel.trailing(Self.show, region: .jp, now: Self.now).bottom == "19:00")
        let s = EmCartazModel.sections(today: [], upcoming: [Self.expo, Self.show, Self.match], filter: .trip, now: Self.now, calendar: Self.cal)
        let h = EmCartazModel.headerCounts(s)
        #expect(h.left == "1 museu · 1 show")
        #expect(h.right == "1 jogo · 2 em breve")
    }

    @Test func originLabels() {
        #expect(EmCartazModel.origin(.board) == "do board")
        #expect(EmCartazModel.origin(.link) == "link colado")
        #expect(EmCartazModel.origin(.poster) == "foto do cartaz")
    }
}
