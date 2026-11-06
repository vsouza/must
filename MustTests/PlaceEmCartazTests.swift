import Foundation
import Testing
@testable import Must

/// Rodada 23 · B: bloco "Em cartaz" do Lugar e linha de amigos.
struct PlaceEmCartazTests {
    typealias T = EmCartazUITests

    @Test func visibleDropsExpiredAndPutsNowFirst() {
        let v = PlaceEmCartaz.visible([T.show, T.old, T.expo], now: T.now, calendar: T.cal)
        #expect(v.map(\.id) == ["e", "s"])
        #expect(PlaceEmCartaz.summary(v, now: T.now, calendar: T.cal) == "1 agora · 1 em breve")
    }

    @Test func emptyEventsHaveNoSummary() {
        #expect(PlaceEmCartaz.visible([], now: T.now, calendar: T.cal).isEmpty)
        #expect(PlaceEmCartaz.checked([], now: T.now, calendar: T.cal) == nil)
    }

    @Test func checkedText() {
        var e = T.show
        e.checkedAt = T.day(-3, 9)
        #expect(PlaceEmCartaz.checked([e], now: T.now, calendar: T.cal) == "colado há 3 dias")
    }

    @Test func friendsLine() {
        let a = FriendVisit(id: "1", name: "Ana Beatriz", initials: "AB", when: "x", note: "Vá às 18h.")
        let b = FriendVisit(id: "2", name: "Pedro", initials: "PS", when: "y", note: nil)
        #expect(FriendsLine.summary([a, b]) == "Ana e Pedro foram · “Vá às 18h.”")
        #expect(FriendsLine.names([b]) == "Pedro foi")
        #expect(FriendsLine.summary([]) == nil)
    }
}
