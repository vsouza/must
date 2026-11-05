import CoreLocation
import Foundation
import Testing
@testable import Must

/// Regras de Roma no solver (prompt 24 §2), com lugares sintéticos (o seed-it ainda não decodifica nesta rodada):
/// jantar nunca antes das 19:30, almoço 12:30–15, riposo 13–16, museu estatal fecha segunda, Borghese com turno de 2 h,
/// domingo da Appia de manhã.
private enum Roma {
    static let region = Region.it
    static let dates = BoardDates(timeZone: Region.it.timeZone)
    static let monti = CLLocationCoordinate2D(latitude: 41.8955, longitude: 12.4943)
    /// Seg 12, qua 14 e dom 11 de abril de 2027.
    static let monday = dates.day(from: "2027-04-12")!
    static let wednesday = dates.day(from: "2027-04-14")!
    static let sunday = dates.day(from: "2027-04-11")!

    static func time(_ hhmm: String, on day: Date) -> Date { dates.time(hhmm, on: day)! }

    static func place(_ id: String, _ name: String, list: String, color: MustColor, kind: ListKind = .place, sub: String? = nil,
                      windows: [DayWindow] = [], lat: Double, lng: Double, price: Double? = nil, notes: String = "",
                      reservation: Reservation? = nil, queue: Int? = nil) -> SolverPlace {
        SolverPlace(id: id, name: name, nameLocal: nil, listId: list, listColor: color, sub: sub, cityId: "roma", area: nil,
                    lat: lat, lng: lng, price: price, windows: windows, hours: nil, reservation: reservation, saveForEnd: false,
                    allowBudgetException: false, queueMinutes: queue, notes: notes, sourceKind: nil, done: false, kind: kind,
                    extra: nil, tickets: [])
    }

    static func catalog(borgheseAt: Date? = nil) -> [SolverPlace] {
        [
            place("r02", "Da Enzo al 29", list: "eat", color: .eat, sub: "Trattoria", windows: [.lunch, .dinner],
                  lat: 41.8885, lng: 12.4770, price: 30, queue: 30),
            place("r03", "Roscioli", list: "eat", color: .eat, sub: "Trattoria", windows: [.dinner], lat: 41.8936, lng: 12.4730, price: 45),
            place("r04", "Pizzarium", list: "eat", color: .eat, sub: "Pizza", windows: [.lunch, .dinner], lat: 41.9067, lng: 12.4469, price: 12),
            place("r05", "Emma", list: "eat", color: .eat, sub: "Pizza", windows: [.dinner], lat: 41.8941, lng: 12.4729, price: 25),
            place("r20", "Ai Tre Scalini", list: "drink", color: .drink, sub: "Vinho", windows: [.afternoon, .night],
                  lat: 41.8953, lng: 12.4926, price: 8),
            place("r21", "Sant'Eustachio", list: "drink", color: .coffee, sub: "Café", windows: [.morning, .afternoon],
                  lat: 41.8984, lng: 12.4753, price: 2),
            place("r22", "Freni e Frizioni", list: "drink", color: .drink, sub: "Bar", windows: [.night], lat: 41.8914, lng: 12.4699, price: 10),
            place("r33", "Piazza Navona", list: "see", color: .temple, sub: "Praça", windows: [.morning, .afternoon],
                  lat: 41.8992, lng: 12.4731),
            place("r37", "Via Appia Antica", list: "see", color: .temple, sub: "Passeio", windows: [.morning],
                  lat: 41.8556, lng: 12.5156, notes: "Domingo fecha pra carros. Bike na Appia Antica Caffè."),
            place("r46", "Galleria Borghese", list: "art", color: .art, kind: .art, sub: "Museu", windows: [.morning],
                  lat: 41.9142, lng: 12.4922, price: 15, notes: "Bernini e Caravaggio. Só 2 horas, sem exceção.",
                  reservation: borgheseAt.map { Reservation(at: $0, party: 2, note: "reserva obrigatória · turno de 2 h") }),
            place("r48", "Palazzo Massimo", list: "art", color: .art, kind: .art, sub: "Museu", windows: [.morning, .afternoon],
                  lat: 41.9015, lng: 12.4985, price: 10, notes: "Afrescos da Villa di Livia. Vazio, perto da Termini."),
            place("r49", "Musei Capitolini", list: "art", color: .art, kind: .art, sub: "Museu", windows: [.morning, .afternoon],
                  lat: 41.8930, lng: 12.4828, price: 16, notes: "A Loba e a vista do Foro."),
            place("r62", "Via del Governo Vecchio", list: "shop", color: .shop, sub: "Vintage", windows: [.morning, .afternoon],
                  lat: 41.8978, lng: 12.4700, price: 30, notes: "Brechós e vintage."),
            place("r65", "Castroni", list: "shop", color: .shop, sub: "Comidinhas", windows: [.morning, .afternoon],
                  lat: 41.9070, lng: 12.4640, price: 20, notes: "Café, chocolate e conservas."),
        ]
    }

    static func request(on day: Date, kind: DayKind = .free, start: String = "09:00", pace: Pace? = nil,
                        include: [String] = [], region: Region? = .it) -> DayRequest {
        var intent = DayIntent()
        intent.mustInclude = include
        return DayRequest(date: day, timeZone: Region.it.timeZone, kind: kind, budget: 200, intent: intent,
                          startAt: time(start, on: day), origin: monti, cityId: "roma", daysLeftInCity: 3, weather: nil,
                          cityCenter: monti, region: region, pace: pace)
    }

    static func minute(_ date: Date, _ day: Date) -> Int { Int(date.timeIntervalSince(day) / 60) }
}

struct SolverItalyTests {
    @Test func dinnerIsNeverBefore1930InRome() {
        for day in [Roma.monday, Roma.wednesday, Roma.sunday] {
            for kind in [DayKind.free, .night, .shopping, .temples] {
                for start in ["09:00", "14:00", "17:00"] {
                    for pace in [nil, Pace.normal, .intense] {
                        let p = DaySolver.solve(Roma.request(on: day, kind: kind, start: start, pace: pace), catalog: Roma.catalog())
                        for stop in p.stops where stop.place.role == .eat {
                            let m = Roma.minute(stop.at, day)
                            // Almoço 12:30–15; o resto é jantar, e jantar é 19:30 ou depois.
                            if stop.window == .lunch {
                                #expect((12 * 60 + 30)..<(15 * 60) ~= m, "\(stop.place.name) \(m)")
                            } else {
                                #expect(m >= 19 * 60 + 30, "\(kind) \(start) \(stop.place.name) às \(m / 60):\(m % 60)")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func withoutTheRomeRulesDinnerWouldComeEarlier() {
        // Mesmo pedido sem região: o jantar cai nas 18–21 de sempre (a regra italiana é o que empurra pras 19:30).
        let general = DaySolver.solve(Roma.request(on: Roma.wednesday, kind: .night, start: "17:00", region: nil), catalog: Roma.catalog())
        let rome = DaySolver.solve(Roma.request(on: Roma.wednesday, kind: .night, start: "17:00"), catalog: Roma.catalog())
        let g = general.stops.first { $0.place.role == .eat && $0.window == .dinner }
        let r = rome.stops.first { $0.place.role == .eat && $0.window == .dinner }
        #expect(g.map { Roma.minute($0.at, Roma.wednesday) < 19 * 60 + 30 } == true)
        #expect(r.map { Roma.minute($0.at, Roma.wednesday) >= 19 * 60 + 30 } == true)
    }

    @Test func borgheseShiftEndsInTwoHours() throws {
        let at = Roma.time("11:00", on: Roma.wednesday)
        let p = DaySolver.solve(Roma.request(on: Roma.wednesday), catalog: Roma.catalog(borgheseAt: at))
        let stop = try #require(p.stops.first { $0.place.id == "r46" })
        #expect(stop.isAnchor)
        #expect(stop.at == at)
        #expect(stop.end == Roma.time("13:00", on: Roma.wednesday))
        #expect(stop.reason == "reserva · turno")
        // Nada começa dentro do turno.
        #expect(p.stops.filter { $0.place.id != "r46" }.allSatisfy { $0.at >= stop.end || $0.end <= stop.at })
        // Relido do dia aceito (sem o solver), o fim é o mesmo.
        #expect(DayEngineV8.boardTiming(stop.place, at: at, isAnchor: true, region: .it).end == stop.end)
        // Na Linha: âncora de reserva com o turno e a hora de chegar.
        let plan = DayComposer.compose(DayComposer.Input(
            date: Roma.wednesday, region: .it, stops: p.stops.map {
                DayComposer.BoardStop(place: $0.place, start: $0.at, end: $0.end, isAnchor: $0.isAnchor, reason: $0.reason)
            }, hotel: Roma.monti, budget: 120))
        let line = try #require(plan.stops.first { $0.placeId == "r46" })
        #expect(line.kind == .anchor && line.anchor == .reservation)
        #expect(line.end == stop.end)
        #expect(line.note.contains("turno 11:00–13:00"))
        #expect(line.note.contains("chegue 10:30"))
    }

    @Test func borgheseWithoutReservationStaysOut() {
        let p = DaySolver.solve(Roma.request(on: Roma.wednesday, include: ["Galleria Borghese"]), catalog: Roma.catalog())
        #expect(p.stops.allSatisfy { $0.place.id != "r46" })
        #expect(p.leftOut.first { $0.place.id == "r46" }?.reason.contains("só com reserva") == true)
    }

    @Test func mondayHasNoStateMuseum() {
        // Pedindo o Palazzo Massimo pelo nome: na quarta entra, na segunda não (museu estatal fecha).
        let wednesday = DaySolver.solve(Roma.request(on: Roma.wednesday, include: ["Palazzo Massimo"]), catalog: Roma.catalog())
        #expect(wednesday.stops.contains { $0.place.id == "r48" })
        for kind in [DayKind.free, .temples, .photo] {
            let monday = DaySolver.solve(Roma.request(on: Roma.monday, kind: kind, include: ["Palazzo Massimo"]), catalog: Roma.catalog())
            #expect(monday.stops.allSatisfy { $0.place.id != "r48" })
            #expect(monday.stops.filter { $0.place.kind == .art }.allSatisfy { !ItalyRules.isStateMuseum($0.place) })
        }
        let monday = DaySolver.solve(Roma.request(on: Roma.monday, include: ["Palazzo Massimo"]), catalog: Roma.catalog())
        #expect(monday.leftOut.first { $0.place.id == "r48" }?.reason == "museu estatal fecha segunda")
        // A Borghese abre na segunda (com reserva) e os Capitolinos também.
        let borghese = Roma.time("11:00", on: Roma.monday)
        let withShift = DaySolver.solve(Roma.request(on: Roma.monday), catalog: Roma.catalog(borgheseAt: borghese))
        #expect(withShift.stops.contains { $0.place.id == "r46" && $0.isAnchor })
        #expect(!ItalyRules.isStateMuseum(Roma.catalog().first { $0.id == "r49" }!))
    }

    @Test func sundayAppiaIsAMorningAnchor() throws {
        let p = DaySolver.solve(Roma.request(on: Roma.sunday), catalog: Roma.catalog())
        let appia = try #require(p.stops.first { $0.place.id == "r37" })
        #expect(appia.isAnchor)
        #expect(appia.reason == "domingo sem carros")
        #expect(appia.at == Roma.time("09:30", on: Roma.sunday))
        // Na quarta a Appia não é âncora.
        let wednesday = DaySolver.solve(Roma.request(on: Roma.wednesday), catalog: Roma.catalog())
        #expect(wednesday.stops.first { $0.place.id == "r37" }?.isAnchor != true)
        // Fora de Roma, domingo é domingo.
        let general = DaySolver.solve(Roma.request(on: Roma.sunday, region: nil), catalog: Roma.catalog())
        #expect(general.stops.first { $0.place.id == "r37" }?.isAnchor != true)
    }

    @Test func smallShopsRespectRiposo() {
        for day in [Roma.monday, Roma.wednesday] {
            for start in ["09:00", "12:00", "13:30"] {
                let p = DaySolver.solve(Roma.request(on: day, kind: .shopping, start: start, pace: .intense), catalog: Roma.catalog())
                for stop in p.stops where ItalyRules.hasRiposo(stop.place) {
                    let a = Roma.minute(stop.at, day), b = Roma.minute(stop.end, day)
                    #expect(!(a..<b).overlaps(ItalyRules.riposo), "\(stop.place.name) \(a)–\(b)")
                }
            }
        }
        #expect(ItalyRules.hasRiposo(Roma.catalog().first { $0.id == "r62" }!))
    }

    @Test func turnoIsReadFromTheNotes() {
        let borghese = Roma.catalog().first { $0.id == "r46" }!
        #expect(ItalyRules.shiftMinutes(borghese) == 120)
        #expect(ItalyRules.requiresReservation(borghese))
        #expect(ItalyRules.shiftMinutes(Roma.catalog().first { $0.id == "r49" }!) == nil)
    }
}
