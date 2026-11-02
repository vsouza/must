import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 14 · C (fatia 2): ingresso é âncora no solver; experiência entra com ingresso e avisa quando se sobrepõe.
private enum S {
    final class Token {}

    static let tz = Region.jp.timeZone
    static let dates = BoardDates(timeZone: tz)
    /// Domingo 15 nov em Tóquio (o seed tem a Udatsu reservada às 19:00).
    static let day = dates.day(from: "2026-11-15")!
    static let naka = CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)

    static func time(_ hhmm: String) -> Date { dates.time(hhmm, on: day)! }

    static func catalog() -> [SolverPlace] {
        let board = try! BoardCodec.decode(Data(contentsOf: Region.jp.seedURL(in: Bundle(for: Token.self))!))
        let lists = Dictionary(uniqueKeysWithValues: board.lists.map { ($0.id, $0) })
        return board.places.map { SolverPlace($0, color: lists[$0.listId]?.color ?? .eat, kind: lists[$0.listId]?.kind ?? .place) }
    }

    static func sunday() -> DayRequest {
        DayRequest(date: day, timeZone: tz, kind: .free, budget: Region.jp.defaultBudget, startAt: time("09:30"),
                   origin: naka, cityId: "tokyo1", daysLeftInCity: 1, weather: nil)
    }

    /// Experiência em Tsukiji (lista "do", cor night) com os ingressos dados.
    static func experience(_ id: String, tickets: [Ticket], duration: Int = 180) -> SolverPlace {
        SolverPlace(id: id, name: "Aula de sushi com chef em Tsukiji", nameLocal: nil, listId: "do", listColor: .night, sub: nil,
                    cityId: "tokyo1", area: "Tsukiji", lat: 35.6654, lng: 139.7707, price: 12_000, windows: [], hours: nil,
                    reservation: nil, saveForEnd: false, allowBudgetException: false, queueMinutes: nil, notes: "",
                    sourceKind: nil, done: false, kind: .experience,
                    extra: PlaceExtra(experience: ExperienceInfo(supplier: .viator, durationMinutes: duration)),
                    tickets: tickets)
    }
}

struct SolverTicketTests {
    let catalog = S.catalog()

    @Test func ticketAtTenIsAnAnchor() throws {
        let ticket = Ticket(at: S.time("10:00"), confirmation: "BR-7K2M-9931")
        let p = DaySolver.solve(S.sunday(), catalog: catalog + [S.experience("x-sushi", tickets: [ticket])])
        let stop = try #require(p.stops.first { $0.place.id == "x-sushi" })
        #expect(stop.isAnchor)
        #expect(stop.at == S.time("10:00"))
        #expect(stop.reason == "ingresso")
        // Sem sobreposição com a Udatsu (19:00): nenhum aviso.
        #expect(p.warnings.isEmpty)
    }

    @Test func experienceAt7pmConflictsWithReservationAndSolverWarns() throws {
        let ticket = Ticket(at: S.time("19:00"), confirmation: "BR-7K2M-9931")
        let p = DaySolver.solve(S.sunday(), catalog: catalog + [S.experience("x-sushi", tickets: [ticket])])
        // As duas são âncoras: o solver não escolhe por você, avisa.
        #expect(p.stops.first { $0.place.id == "j01" }?.isAnchor == true)
        #expect(p.stops.first { $0.place.id == "x-sushi" }?.isAnchor == true)
        #expect(p.warnings.count == 1)
        let warning = try #require(p.warnings.first)
        #expect(warning.contains("Udatsu Sushi"))
        #expect(warning.contains("se sobrepõem"))
        #expect(p.explanation.contains("Atenção"))
    }

    @Test func experienceWithoutTicketStaysOutOfTheDay() {
        let p = DaySolver.solve(S.sunday(), catalog: catalog + [S.experience("x-sushi", tickets: [])])
        #expect(p.stops.first { $0.place.id == "x-sushi" } == nil)
    }

    @Test func boughtSessionOfAnExperienceIsAnAnchorToo() throws {
        var sushi = S.experience("x-sushi", tickets: [])
        sushi.extra?.experience?.sessions = [EventSession(at: S.time("11:00"), title: "Turma das 11h", bought: true)]
        let p = DaySolver.solve(S.sunday(), catalog: catalog + [sushi])
        let stop = try #require(p.stops.first { $0.place.id == "x-sushi" })
        #expect(stop.isAnchor)
        #expect(stop.at == S.time("11:00"))
    }
}

/// Prompt 15 · C (fatia 6): voo é âncora dura; dia de voo vira `rest` e para em partida − 4 h.
struct SolverFlightDayTests {
    let catalog = S.catalog()

    private func flight(at hhmm: String) -> DayFlight {
        let departs = S.time(hhmm)
        return DayFlight(number: "LA 8084", departs: departs, leaveAt: departs.addingTimeInterval(-4 * 3600))
    }

    @Test func flightDeadlineIsFourHoursBeforeDeparture() {
        var request = S.sunday()
        request.flights = [flight(at: "22:10")]
        #expect(request.flightDeadline == S.time("18:10"))
        #expect(S.sunday().flightDeadline == nil)
    }

    @Test func flightDayIsRestAndStopsBeforeFourHoursBeforeTheFlight() throws {
        var request = S.sunday()
        request.flights = [flight(at: "22:10")]
        let p = DaySolver.solve(request, catalog: catalog)
        #expect(p.stops.isEmpty == false)
        // Nenhuma parada começa depois de partida − 4 h.
        #expect(p.stops.allSatisfy { $0.at < S.time("18:10") })
        // Descanso: só comer, beber e ver (sem noite, sem compras).
        #expect(p.stops.allSatisfy { [StopRole.eat, .drink, .see].contains($0.place.role) })
        // A reserva das 19:00 cai depois do voo: sai do dia, com o motivo.
        #expect(p.stops.first { $0.place.id == "j01" } == nil)
        #expect(p.leftOut.first { $0.place.id == "j01" }?.reason == "depois do voo")
    }

    @Test func morningFlightLeavesNoStopsAtAll() {
        var request = S.sunday()
        request.flights = [flight(at: "06:00")]
        let p = DaySolver.solve(request, catalog: catalog)
        #expect(p.stops.isEmpty)
    }
}
