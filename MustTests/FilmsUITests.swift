import Foundation
import Testing
@testable import Must

/// Rodada 23 · B: textos da UI de Filmes e a ordem da lista.
struct FilmsUITests {
    @Test func distanceFormat() {
        #expect(FilmsFormat.distance(250) == "250 m")
        #expect(FilmsFormat.distance(3100) == "3,1 km")
        #expect(FilmsFormat.distance(nil) == nil)
    }

    @Test func yearDigits() {
        #expect(FilmsFormat.yearDigits(2003) == "03")
        #expect(FilmsFormat.yearDigits(2023) == "23")
        #expect(FilmsFormat.yearDigits(nil) == "—")
    }

    @Test func orderedByDistanceWithoutDuplicates() {
        let a = Film(id: "A", title: "A", year: 2003, director: "D", location: "L1", distanceMeters: 3000)
        let b = Film(id: "B", title: "B", year: 2016, director: nil, location: "L2", distanceMeters: 250)
        let out = FilmsFormat.ordered([a, b, a])
        #expect(out.map(\.id) == ["B", "A"])
        #expect(FilmsFormat.credit(b) == "2016")
        #expect(FilmsFormat.place(b) == "L2 · 250 m")
    }

    @Test @MainActor func sessionMemoKeepsEmptyResult() {
        FilmsSessionMemo.reset()
        let key = FilmsSessionMemo.key("p01", radiusKm: 1.5)
        #expect(FilmsSessionMemo.get(key) == nil)
        FilmsSessionMemo.set(key, [])
        #expect(FilmsSessionMemo.get(key) == [])
    }
}
