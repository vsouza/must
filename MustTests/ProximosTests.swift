import Foundation
import Testing
@testable import Must

/// Próximos (prompt 23 §2 · 12): só o que ainda vai acontecer, em ordem; passou, some.
struct ProximosTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!
    }

    func items(now: Date, reservations: [Proximos.ReservationInput] = [], tickets: [Proximos.TicketInput] = [],
               events: [Proximos.EventInput] = [], flights: [Proximos.FlightInput] = []) -> [Proximos.Item] {
        Proximos.items(now: now, reservations: reservations, tickets: tickets, events: events, flights: flights,
                       money: { "¥ \(Int($0))" }, calendar: cal)
    }

    @Test func onlyFutureInOrder() {
        let now = at(15, 14, 20)
        let list = items(
            now: now,
            reservations: [
                .init(placeId: "j01", name: "Udatsu Sushi", sub: "Sushi", area: "Naka-Meguro", at: at(15, 19), party: 2, price: 22_000),
                .init(placeId: "old", name: "Almoço", area: nil, at: at(15, 12), party: 2, price: nil),
            ],
            tickets: [.init(placeId: "j28", ticketId: "t1", name: "teamLab Borderless", area: "Azabudai Hills", at: at(16, 14),
                            people: 2, offline: true, confirmation: nil)],
            events: [.init(id: "e1", kind: .train, title: "Shinkansen Nozomi 219", note: "Tokyo → Kyoto · 2h15 · carro 7", at: at(17, 9, 12),
                           allDay: false)])
        #expect(list.map(\.kind) == [.reservation, .ticket, .train])
        #expect(!list.contains { $0.placeId == "old" })
        #expect(list[0].title == "Udatsu Sushi")
        #expect(list[0].detail == "2 pessoas · ¥ 22000")
        #expect(list[1].corner == "QR offline")
        #expect(list[2].route == "Tokyo → Kyoto · 2h15")
        #expect(list[2].detail == "carro 7")
        #expect(list[2].corner == "JR Pass")
    }

    @Test func passedDisappears() {
        let r = Proximos.ReservationInput(placeId: "j01", name: "Udatsu", area: nil, at: at(15, 19), party: 2, price: nil)
        #expect(items(now: at(15, 18, 59), reservations: [r]).count == 1)
        #expect(items(now: at(15, 19), reservations: [r]).isEmpty)
    }

    @Test func flightIsOneItemWithNextLegAndConnections() {
        let legs = [
            FlightSegment(id: "a", number: "QR 813", from: "HND", to: "DOH", departs: at(24, 23, 55)),
            FlightSegment(id: "b", number: "QR 773", from: "DOH", to: "GRU", departs: at(25, 15)),
        ]
        let flight = Proximos.FlightInput(id: "f", carrier: "LATAM", legs: legs, checklistDone: 2, checklistTotal: 12, checkedKg: 23)
        let list = items(now: at(15, 14), flights: [flight])
        #expect(list.count == 1)
        #expect(list[0].route == "HND → GRU · via DOH")
        #expect(list[0].title == "Checklist · 2 de 12")
        #expect(list[0].detail.hasPrefix("bagagem ≤ 23 kg · check-in abre seg 23, 23:55"))
        #expect(list[0].corner == "LATAM · programado")
        // Primeiro trecho saiu: fica só a conexão.
        let later = items(now: at(25, 2), flights: [flight])
        #expect(later.first?.route == "DOH → GRU")
        #expect(items(now: at(25, 16), flights: [flight]).isEmpty)
    }

    @Test func boardFlightEventsOnlyWithoutFlights() {
        let event = Proximos.EventInput(id: "e", kind: .flight, title: "LA8180", note: "", at: at(20, 10), allDay: false)
        #expect(items(now: at(15, 10), events: [event]).map(\.kind) == [.flight])
        let flight = Proximos.FlightInput(id: "f", carrier: "", legs: [], checklistDone: 0, checklistTotal: 0, checkedKg: nil)
        #expect(items(now: at(15, 10), events: [event], flights: [flight]).isEmpty)
    }

    @Test func dayLabels() {
        let now = at(15, 14)
        #expect(Proximos.dayLabel(at(15, 19), now: now, calendar: cal) == "hoje")
        #expect(Proximos.dayLabel(at(16, 9), now: now, calendar: cal) == "amanhã")
        #expect(Proximos.dayLabel(at(17, 9), now: now, calendar: cal) == "ter 17")
    }

    @Test func tripLine() {
        let line = Proximos.tripLine(start: at(11, 0), end: at(24, 0), now: at(13, 10), calendar: cal, month: { _ in "nov" })
        #expect(line == "11 → 24 nov · dia 3 de 14")
        #expect(Proximos.tripLine(start: at(11, 0), end: at(24, 0), now: at(5, 10), calendar: cal, month: { _ in "nov" })
            == "11 → 24 nov · faltam 6 dias")
        #expect(Proximos.tripLine(start: nil, end: nil, now: at(5, 10), calendar: cal, month: { _ in "nov" }) == nil)
    }
}
