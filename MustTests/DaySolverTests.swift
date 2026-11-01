import CoreLocation
import Foundation
import Testing
@testable import Must

/// Seeds carregados como catálogo do solver.
private enum Fixtures {
    final class Token {}

    static func board(_ region: Region) -> Board {
        let url = region.seedURL(in: Bundle(for: Token.self))!
        return try! BoardCodec.decode(Data(contentsOf: url))
    }

    static func catalog(_ region: Region) -> [SolverPlace] {
        let b = board(region)
        let colors = Dictionary(uniqueKeysWithValues: b.lists.map { ($0.id, $0.color) })
        return b.places.map { SolverPlace($0, color: colors[$0.listId] ?? .eat) }
    }

    static let naka = CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)
    static let gion = CLLocationCoordinate2D(latitude: 35.0037, longitude: 135.7788)
    static let nakano = CLLocationCoordinate2D(latitude: 35.7074, longitude: 139.6659)
    static let savassi = CLLocationCoordinate2D(latitude: -19.9385, longitude: -43.9343)

    static func request(_ region: Region, day: String, kind: DayKind = .free, budget: Double? = nil, city: String,
                        daysLeft: Int?, origin: CLLocationCoordinate2D, start: String = "09:30", walk: WalkLevel = .normal,
                        intent: DayIntent = DayIntent(), lists: [String: ListMode] = [:], weather: DayWeather? = nil,
                        seed: Int = 0) -> DayRequest {
        let d = BoardDates(timeZone: region.timeZone)
        let date = d.day(from: day)!
        return DayRequest(date: date, timeZone: region.timeZone, kind: kind, budget: budget ?? region.defaultBudget, walk: walk,
                          lists: lists, intent: intent, startAt: d.time(start, on: date)!, origin: origin, cityId: city,
                          daysLeftInCity: daysLeft, weather: weather, seed: seed)
    }

    static let clear = DayWeather(tempMin: 8, tempMax: 15, code: 0, precipProb: 5, sunrise: nil, sunset: nil)
    static let storm = DayWeather(tempMin: 18, tempMax: 22, code: 65, precipProb: 90, sunrise: nil, sunset: nil)
}

private extension DayProposal {
    var ids: [String] { stops.map(\.place.id) }
    func has(_ id: String) -> Bool { ids.contains(id) }
    func minute(_ stop: ProposedStop) -> Int { Int(stop.at.timeIntervalSince(request.date) / 60) }
}

// MARK: - Japão

struct DaySolverJapanTests {
    let catalog = Fixtures.catalog(.jp)

    /// Domingo 15 nov em Tóquio (dia 3 de 5; restam 1 depois de hoje).
    func sunday(_ kind: DayKind = .free, budget: Double? = nil, walk: WalkLevel = .normal, intent: DayIntent = DayIntent(),
                start: String = "09:30", seed: Int = 0) -> DayRequest {
        Fixtures.request(.jp, day: "2026-11-15", kind: kind, budget: budget, city: "tokyo1", daysLeft: 1, origin: Fixtures.naka,
                         start: start, walk: walk, intent: intent, seed: seed)
    }

    @Test func reservationIsFixedAnchor() throws {
        let p = DaySolver.solve(sunday(), catalog: catalog)
        let udatsu = try #require(p.stops.first { $0.place.id == "j01" })
        #expect(udatsu.isAnchor)
        #expect(p.minute(udatsu) == 19 * 60)
        // Nada antes da âncora termina depois de 19:00 − 10 min.
        for stop in p.stops where stop.at < udatsu.at {
            #expect(stop.end <= udatsu.at.addingTimeInterval(-10 * 60), "\(stop.place.name) termina tarde demais")
        }
    }

    @Test func reservationExceptionStaysOutsideBudget() {
        let p = DaySolver.solve(sunday(), catalog: catalog)
        #expect(p.stops.first { $0.place.id == "j01" }?.isException == true)
        #expect(p.exceptionSpend == 22_000)
        #expect(p.predictedSpend <= 15_000)
    }

    @Test func otherCityNeverEnters() {
        let tokyo = DaySolver.solve(sunday(), catalog: catalog)
        #expect(!tokyo.has("j16")) // Sushi Iwa é de Kyoto
        #expect(tokyo.stops.allSatisfy { $0.place.cityId == "tokyo1" })

        let kyoto = DaySolver.solve(Fixtures.request(.jp, day: "2026-11-18", city: "kyoto", daysLeft: 1, origin: Fixtures.gion), catalog: catalog)
        #expect(kyoto.stops.first { $0.place.id == "j16" }?.isAnchor == true)
        #expect(kyoto.stops.allSatisfy { $0.place.cityId == "kyoto" })
    }

    @Test func saveForEndWaitsForLastDays() {
        let early = DaySolver.solve(Fixtures.request(.jp, day: "2026-11-21", kind: .photo, city: "tokyo2", daysLeft: 3,
                                                      origin: Fixtures.nakano, weather: Fixtures.clear), catalog: catalog)
        #expect(!early.has("j04") && !early.has("j15") && !early.has("j17"))
        #expect(early.reason(for: "j17")?.contains("fica pro fim") == true)
    }

    @Test func saveForEndEntersOnLastDaysWithClearSky() {
        let late = DaySolver.solve(Fixtures.request(.jp, day: "2026-11-23", kind: .photo, city: "tokyo2", daysLeft: 1,
                                                     origin: Fixtures.nakano, start: "07:00", weather: Fixtures.clear), catalog: catalog)
        #expect(late.has("j17"), "Fuji deveria entrar num dia de foto com céu limpo no fim da viagem")
    }

    @Test func fujiNeedsClearSky() {
        let noForecast = DaySolver.solve(Fixtures.request(.jp, day: "2026-11-23", kind: .photo, city: "tokyo2", daysLeft: 1,
                                                           origin: Fixtures.nakano), catalog: catalog)
        #expect(!noForecast.has("j17"))
        #expect(noForecast.reason(for: "j17")?.contains("céu limpo") == true)
    }

    @Test func oneMealPerWindow() {
        let p = DaySolver.solve(sunday(), catalog: catalog)
        for window in [DayWindow.lunch, .dinner] {
            #expect(p.stops.filter { $0.window == window && $0.place.role == .eat }.count <= 1)
        }
    }

    @Test func mealsExceptionAllowsTwoLunches() {
        let intent = RegexIntentParser.parse("hoje sushi e ramen")
        #expect(intent.mealsException)
        let p = DaySolver.solve(sunday(intent: intent), catalog: catalog)
        #expect(p.stops.filter { $0.window == .lunch && $0.place.role == .eat }.count == 2)
    }

    @Test func closedPlaceDoesNotEnterAndUnknownHoursAreFlagged() {
        var places = catalog
        let i = places.firstIndex { $0.id == "j05" }!
        // Fuunji: seg–sáb 11:00–15:00 (fecha domingo).
        places[i].hours = PlaceHours(weekdayText: nil, periods: (1...6).map {
            .init(open: .init(day: $0, hour: 11, minute: 0), close: .init(day: $0, hour: 15, minute: 0))
        }, fetchedAt: nil)
        let p = DaySolver.solve(sunday(intent: DayIntent(preferSubs: ["Ramen"])), catalog: places)
        #expect(!p.has("j05"))
        #expect(p.reason(for: "j05") == "fecha domingo")
        let unknown = p.stops.filter { !$0.isAnchor && $0.place.hours == nil && ($0.place.queueMinutes ?? 0) == 0 }
        #expect(unknown.allSatisfy { $0.reason == "horário não confirmado" || $0.reason == "antes da multidão" || $0.reason == "você pediu" })
    }

    @Test func queueAddsToStopTime() throws {
        let p = DaySolver.solve(sunday(intent: DayIntent(mustInclude: ["Fuunji"])), catalog: catalog)
        let fuunji = try #require(p.stops.first { $0.place.id == "j05" })
        #expect(fuunji.end.timeIntervalSince(fuunji.at) == TimeInterval((75 + 25) * 60))
    }

    @Test func budgetIsRespected() {
        let p = DaySolver.solve(sunday(budget: 8_000), catalog: catalog)
        #expect(p.predictedSpend <= 8_000)
        #expect(p.stops.filter(\.isException).count <= 1)
    }

    @Test func neverTwoExceptions() {
        let p = DaySolver.solve(Fixtures.request(.jp, day: "2026-11-18", city: "kyoto", daysLeft: 1, origin: Fixtures.gion,
                                                  intent: DayIntent(splurge: true)), catalog: catalog)
        #expect(p.stops.filter(\.isException).count <= 1)
        let tokyo = DaySolver.solve(sunday(budget: 5_000, intent: DayIntent(splurge: true)), catalog: catalog)
        #expect(tokyo.stops.filter(\.isException).count == 1) // só o omakase
    }

    @Test func nightDayStartsAtNoonWithListen() {
        let p = DaySolver.solve(sunday(.night), catalog: catalog)
        #expect(p.stops.allSatisfy { p.minute($0) >= 12 * 60 })
        #expect(p.stops.contains { $0.place.role == .listen })
    }

    @Test func shoppingDayHasShopAndNoListen() {
        let p = DaySolver.solve(Fixtures.request(.jp, day: "2026-11-23", kind: .shopping, city: "tokyo2", daysLeft: 1,
                                                  origin: Fixtures.nakano), catalog: catalog)
        #expect(p.stops.contains { $0.place.role == .shop })
        #expect(!p.stops.contains { $0.place.role == .listen })
        let shop = p.stops.first { $0.place.role == .shop }
        #expect(shop?.window == .afternoon || shop?.window == .morning)
    }

    @Test func restDayIsShortAndWalksLittle() {
        let p = DaySolver.solve(sunday(.rest), catalog: catalog)
        #expect(p.stops.count <= 3)
        #expect(p.walkKm <= 2)
    }

    @Test func walkLowCapsWalking() {
        let p = DaySolver.solve(sunday(walk: .low), catalog: catalog)
        #expect(p.walkKm <= 2.0001)
    }

    @Test func templesDayStartsEarlyWithTemple() throws {
        // Acordou cedo (07:30): o templo entra antes das 09:30.
        let p = DaySolver.solve(sunday(.temples, start: "07:30"), catalog: catalog)
        let first = try #require(p.stops.first)
        #expect(first.place.id == "j13") // Senso-ji
        #expect(p.minute(first) < 9 * 60 + 30)
    }

    @Test func deterministicAndSeedStaysValid() {
        let a = DaySolver.solve(sunday(), catalog: catalog)
        let b = DaySolver.solve(sunday(), catalog: catalog)
        #expect(a.ids == b.ids)
        let c = DaySolver.solve(sunday(seed: 3), catalog: catalog)
        #expect(c.predictedSpend <= 15_000)
        #expect(c.has("j01"))
    }

    @Test func explanationNamesWhatWasLeftOut() {
        let p = DaySolver.solve(Fixtures.request(.jp, day: "2026-11-22", city: "tokyo2", daysLeft: 2, origin: Fixtures.nakano), catalog: catalog)
        #expect(p.explanation.hasPrefix("Deixei "))
        #expect(p.leftOut.contains { p.explanation.contains($0.place.name) })
    }

    @Test func swapAlternativesStayInWindowAndApply() throws {
        let p = DaySolver.solve(sunday(intent: DayIntent(preferSubs: ["Ramen"])), catalog: catalog)
        let lunch = try #require(p.stops.first { $0.window == .lunch && $0.place.role == .eat })
        let alts = DaySolver.alternatives(for: lunch.id, in: p, catalog: catalog, filter: .sameRole)
        #expect(!alts.isEmpty && alts.count <= 3)
        #expect(alts.allSatisfy { $0.place.role == .eat && !p.has($0.place.id) })
        let swapped = DaySolver.swap(lunch.id, with: alts[0].place, in: p)
        #expect(swapped.has(alts[0].place.id) && !swapped.has(lunch.id))
        #expect(swapped.stops.count == p.stops.count)
        let skipped = DaySolver.skip(lunch.id, in: p)
        #expect(skipped.stops.count == p.stops.count - 1)
        // Âncora não troca.
        #expect(DaySolver.swap("j01", with: alts[0].place, in: p).has("j01"))
    }
}

// MARK: - Belo Horizonte

struct DaySolverBHTests {
    let catalog = Fixtures.catalog(.bh)

    /// 31 out 2026 é sábado; 1 nov, domingo.
    func day(_ date: String, budget: Double = 200, intent: DayIntent = DayIntent(), lists: [String: ListMode] = [:],
             weather: DayWeather? = nil) -> DayRequest {
        Fixtures.request(.bh, day: date, budget: budget, city: "bh", daysLeft: nil, origin: Fixtures.savassi,
                         intent: intent, lists: lists, weather: weather)
    }

    @Test func saturdayFreeDayHasSeeEatDrink() {
        let p = DaySolver.solve(day("2026-10-31"), catalog: catalog)
        let roles = Set(p.stops.map(\.place.role))
        #expect(roles.isSuperset(of: [.see, .eat, .drink]))
        #expect(!p.has("p18")) // Inhotim
        #expect(!p.stops.contains { $0.isException })
        #expect(p.predictedSpend <= 200)
    }

    @Test func sundayPullsFeiraHippie() throws {
        let p = DaySolver.solve(day("2026-11-01"), catalog: catalog)
        let feira = try #require(p.stops.first { $0.place.id == "p22" })
        #expect(feira.window == .morning)
        #expect(feira.reason == "só hoje")
    }

    @Test func feiraHippieOnlyOnSunday() {
        let p = DaySolver.solve(day("2026-10-31"), catalog: catalog)
        #expect(!p.has("p22"))
        #expect(p.reason(for: "p22") == "só domingo")
    }

    @Test func inhotimNeverInFreeDay() {
        for date in ["2026-10-31", "2026-11-01", "2026-11-03"] {
            let p = DaySolver.solve(day(date, lists: ["see": .on]), catalog: catalog)
            #expect(!p.has("p18"))
            #expect(p.reason(for: "p18")?.contains("dia inteiro") == true)
        }
    }

    @Test func tightBudgetKeepsFineDiningOutUnlessAsked() throws {
        let plain = DaySolver.solve(day("2026-10-31", budget: 100), catalog: catalog)
        #expect(!plain.has("p04") && !plain.has("p05"))
        #expect(plain.predictedSpend <= 100)

        let splurge = DaySolver.solve(day("2026-10-31", budget: 100, intent: RegexIntentParser.parse("quero um jantar bom")), catalog: catalog)
        let fine = try #require(splurge.stops.first { ["p04", "p05"].contains($0.place.id) })
        #expect(fine.isException)
        #expect(splurge.predictedSpend <= 100)
    }

    @Test func heavyRainDropsMirante() {
        let p = DaySolver.solve(day("2026-10-31", intent: DayIntent(preferSubs: ["Mirante"]), weather: Fixtures.storm), catalog: catalog)
        #expect(!p.has("p17"))
    }

    @Test func saveForEndInBHNeedsTheListOn() {
        let p = DaySolver.solve(day("2026-10-31"), catalog: catalog)
        #expect(p.reason(for: "p06")?.contains("ligue a lista") == true)
    }
}

// MARK: - Intenção por texto

struct RegexIntentParserTests {
    @Test func parsesMontarExample() {
        let i = RegexIntentParser.parse("templo cedo, ramen, café e andar pouco")
        #expect(i.kind == .temples)
        #expect(i.startEarly == true)
        #expect(i.walk == .low)
        #expect(i.preferSubs.contains("Ramen") && i.preferSubs.contains("Café"))
        #expect(i.roles[.eat] == .on && i.roles[.drink] == .on)
    }

    @Test func parsesExclusionsBudgetAndNames() {
        let i = RegexIntentParser.parse("sem compras, até R$ 150, quero o Fuunji mas sem Nakano", placeNames: ["Fuunji", "Nakano Broadway"])
        #expect(i.roles[.shop] == .off)
        #expect(i.budget == 150)
        #expect(i.mustInclude == ["Fuunji"])
        #expect(i.mustExclude == ["Nakano Broadway"])
        #expect(i.kind != .shopping)
    }

    @Test func notesRules() {
        let feira = NotesRules(notes: "Só domingo de manhã — regra de dia.")
        #expect(feira.onlyDays == [0] && feira.onlyWindows == [.morning])
        let inhotim = NotesRules(notes: "Dia inteiro, 60 km. Fecha segunda. Fica pro fim / dia dedicado.")
        #expect(inhotim.fullDay && inhotim.closedDays == [1])
        #expect(NotesRules(notes: "Dia de compras; domingo lota.").crowdedDays == [0])
        #expect(NotesRules(notes: "Condicional: só se céu limpo. Ônibus 07:35.").weatherDependent)
    }
}
