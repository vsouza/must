import CoreLocation
import Foundation
import Testing
@testable import Must

/// Micro-parada "em cartaz" (RODADA-23 · A): só cabe se está aberto e em temporada, e nunca mexe em âncora.
@MainActor
struct EmCartazDayTests {
    typealias F = ShowFix
    let day = F.at(2026, 11, 14)

    func stop(_ id: String, _ from: (Int, Int), _ to: (Int, Int), lat: Double, lng: Double, anchor: Bool = false) -> DayStop {
        DayStop(id: id, placeId: id, kind: anchor ? .anchor : .must, start: F.at(2026, 11, 14, from.0, from.1), end: F.at(2026, 11, 14, to.0, to.1),
                label: id, note: "", anchor: anchor ? .reservation : nil, lat: lat, lng: lng)
    }

    func input(_ catalog: [SolverPlace]) -> DayComposer.Input {
        let anchor = F.place("a", "A", kind: .place, color: .eat, lat: 35.6800, lng: 139.7600)
        return DayComposer.Input(date: day, region: .jp, stops: [DayComposer.BoardStop(place: anchor, start: F.at(2026, 11, 14, 10), end: F.at(2026, 11, 14, 11), isAnchor: true, reason: "reserva")],
                                 hotel: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76), budget: 10_000, catalog: catalog)
    }

    func gapTimeline() -> [DayStop] {
        [stop("a", (10, 0), (11, 0), lat: 35.6800, lng: 139.7600, anchor: true), stop("b", (15, 0), (16, 0), lat: 35.6820, lng: 139.7620, anchor: true)]
    }

    func museum(until: Date? = ShowFix.jsonDay(2026, 11, 30), from: Date? = nil, hours: PlaceHours? = ShowFix.daily(10, 18), lat: Double = 35.6830) -> SolverPlace {
        F.place("m1", "Moriyama", lat: lat, hours: hours, extra: F.art(until: until, from: from))
    }

    func make(_ catalog: [SolverPlace], timeline: [DayStop]? = nil) -> DayStop? {
        let i = input(catalog)
        let sun = SunService.day(day.addingTimeInterval(12 * 3600), i.hotel, timeZone: F.tokyo)
        return MicroStops.make(.show, timeline: timeline ?? gapTimeline(), input: i, sun: sun)
    }

    @Test func fitsInTheGapWhenOpenAndInSeason() throws {
        let m = try #require(make([museum()]))
        #expect(m.micro == .show && m.kind == .micro && m.placeId == "m1")
        #expect(m.label == "Moriyama · em cartaz")
        #expect(m.note.contains("cabe") && m.note.contains("fecha 18:00"))
        #expect(m.start >= F.at(2026, 11, 14, 11) && m.end <= F.at(2026, 11, 14, 15))
    }

    @Test func outOfSeasonOrClosedOrDoneNeverEnters() {
        #expect(make([museum(until: F.jsonDay(2026, 11, 13))]) == nil)
        #expect(make([museum(until: F.jsonDay(2026, 12, 31), from: F.jsonDay(2026, 11, 20))]) == nil)
        #expect(make([museum(hours: F.daily(18, 21))]) == nil)
        var done = museum(); done.done = true
        #expect(make([done]) == nil)
        #expect(make([F.place("m3", "Permanente", lat: 35.683, extra: PlaceExtra(art: ArtEvent(priceAdult: 10)))]) == nil)
    }

    @Test func closingBeforeTheVisitEndsDoesNotFit() {
        // Gap só a partir das 17:40; o museu fecha às 18:00 e a visita dura 30 min.
        let timeline = [stop("a", (10, 0), (17, 40), lat: 35.68, lng: 139.76, anchor: true), stop("b", (19, 0), (20, 0), lat: 35.682, lng: 139.762, anchor: true)]
        #expect(make([museum()], timeline: timeline) == nil)
    }

    @Test func doesNotFitWhenThereIsNoRoomAndNeverMovesAnchors() {
        let tight = [stop("a", (10, 0), (11, 0), lat: 35.68, lng: 139.76, anchor: true), stop("b", (11, 10), (12, 0), lat: 35.682, lng: 139.762, anchor: true)]
        #expect(make([museum()], timeline: tight) == nil)
        // Com a micro dentro, as âncoras seguem iguais.
        let before = gapTimeline()
        let plan = MicroStops.insert(into: before, input: input([museum()]), sun: SunService.day(day.addingTimeInterval(12 * 3600), CLLocationCoordinate2D(latitude: 35.68, longitude: 139.76), timeZone: F.tokyo),
                                     assigner: AreaAssigner(areas: AreaCatalog.areas(for: .jp)))
        for a in before { #expect(plan.first { $0.id == a.id }?.start == a.start && plan.first { $0.id == a.id }?.end == a.end) }
        #expect(plan.contains { $0.micro == .show })
    }

    @Test func farMuseumAndPlacesAlreadyInTheDayStayOut() {
        #expect(make([museum(lat: 35.75)]) == nil)
        let inDay = gapTimeline() + [stop("m1", (13, 0), (14, 0), lat: 35.683, lng: 139.76)]
        #expect(make([museum()], timeline: inDay.sorted { $0.start < $1.start }) == nil)
    }
}
