import Foundation
import Testing
@testable import Must

/// "Agora", "saia às", "chegue às" e a próxima parada ao longo do dia (prompt 23 §3): o dia de QA do stub (`Dia.png`) e
/// o dia do motor real.
struct UpcomingTests {
    private let qa = DayEngineStub.qaDay
    private let stub = DayEngineStub()

    private func t(_ hhmm: String) -> Date { DayFixtures.time(hhmm) }
    private func clock(_ d: Date?) -> String { d.map { Region.jp.timeString($0) } ?? "-" }

    // MARK: Dia de QA (stub)

    @Test func nothingBeforeTheFirstStopNorAfterTheLast() {
        #expect(stub.now(in: qa, at: t("08:00")) == nil)
        #expect(stub.now(in: qa, at: t("23:45")) == nil)
    }

    @Test func afterTheKonbiniTheNextLeaveIsForFuunjiWithQueue() throws {
        let now = try #require(stub.now(in: qa, at: t("13:00")))
        #expect(now.current.id == "s3")
        #expect(now.next?.id == "s4")
        // Fuunji tem fila de 20 min e não tem reserva: chegue às 14:15; saia às 14:15 − 24 min de metrô − 5 = 13:46.
        #expect(clock(now.arriveBy) == "14:15")
        #expect(clock(now.leaveAt) == "13:46")
    }

    @Test func atFuunjiTheLeaveIsForGyoen() throws {
        let now = try #require(stub.now(in: qa, at: t("14:20")))
        #expect(now.current.label == "Fuunji · tsukemen")
        #expect(now.next?.label == "Shinjuku Gyoen · golden")
        // Gyoen 15:48 − 14 min a pé − 5 = 15:29. Gyoen é âncora sem fila: sem "chegue às".
        #expect(clock(now.leaveAt) == "15:29")
        #expect(now.arriveBy == nil)
    }

    @Test func theDayWalksStopByStop() {
        let expected: [(String, String, String?, String)] = [
            ("15:40", "s5", "s6", "16:45"),
            ("18:00", "s6", "s7", "18:05"),
            ("18:20", "s7", "s8", "18:33"),
            ("21:10", "s8", "s9", "21:25"),
            ("23:00", "s9", nil, "23:30"),
        ]
        for (at, current, next, leave) in expected {
            let now = stub.now(in: qa, at: t(at))
            #expect(now?.current.id == current, "\(at)")
            #expect(now?.next?.id == next, "\(at)")
            #expect(clock(now?.leaveAt) == leave, "\(at)")
        }
        // A reserva da Udatsu é hora marcada: nunca "chegue às".
        #expect(stub.now(in: qa, at: t("18:20"))?.arriveBy == nil)
    }

    @Test func headingIsWhereYouGoNext() {
        // Antes do dia: a primeira parada que falta (no QA, o konbini; café e aula já estão feitos).
        #expect(DayNowRules.heading(in: qa, at: t("08:00"))?.stop.id == "s3")
        // Na aula de sushi já feita, depois do konbini: vai pro Fuunji.
        #expect(DayNowRules.heading(in: qa, at: t("13:00"))?.stop.id == "s4")
        #expect(clock(DayNowRules.heading(in: qa, at: t("13:00"))?.leaveAt) == "13:46")
        // No Fuunji: vai pro Gyoen às 15:29.
        let atFuunji = DayNowRules.heading(in: qa, at: t("14:50"))
        #expect(atFuunji?.stop.id == "s5")
        #expect(atFuunji?.index == 4)
        #expect(clock(atFuunji?.leaveAt) == "15:29")
        #expect(DayNowRules.heading(in: qa, at: t("23:10")) == nil)
    }

    // MARK: "Chegue às" (CapaIT: Da Enzo · chegue 12:15)

    @Test func queueWithoutBookingArrivesAtOpening() throws {
        let rome = Region.it
        let day = BoardDates(timeZone: rome.timeZone).day(from: "2027-04-13")!
        func r(_ hhmm: String) -> Date { BoardDates(timeZone: rome.timeZone).time(hhmm, on: day)! }
        let plan = DayPlan(date: day, title: "Trastevere", dayNumber: 4, area: "trastevere", stops: [
            DayStop(id: "a", placeId: "r40", kind: .must, start: r("10:30"), end: r("11:45"), label: "Gianicolo", note: ""),
            DayStop(id: "b", placeId: "r02", kind: .must, start: r("12:30"), end: r("13:45"), label: "Da Enzo al 29", note: "",
                    queueMinutes: 30, opensAt: r("12:15")),
            DayStop(id: "c", placeId: "r46", kind: .anchor, start: r("15:00"), end: r("17:00"), label: "Borghese", note: "",
                    anchor: .reservation, queueMinutes: 15),
        ], legs: [DayLeg(mode: .walk, minutes: 14, from: "a", to: "b", detail: "a pé 14 min"),
                  DayLeg(mode: .bus, minutes: 30, from: "b", to: "c", detail: "bus 910 · 30 min")],
                           lastTrain: nil, pace: .normal, budget: 120)
        let now = try #require(stub.now(in: plan, at: r("11:00")))
        #expect(now.next?.id == "b")
        #expect(rome.timeString(try #require(now.arriveBy)) == "12:15")
        // Saia às = chegue às − 14 min − 5.
        #expect(rome.timeString(now.leaveAt) == "11:56")
        // Reserva com fila: vale a hora marcada.
        let lunch = try #require(stub.now(in: plan, at: r("13:00")))
        #expect(lunch.arriveBy == nil)
        #expect(rome.timeString(lunch.leaveAt) == "14:25")
    }

    // MARK: Motor real

    @Test func realDayHasAConsistentNowAllDayLong() async {
        let engine = DayFixtures.engine(pace: .normal)
        let plan = await engine.build(area: nil, pace: .normal, budget: 15_000, until: t("23:30"), includes: [.micro, .goldenPhoto])
        var lastIndex = -1
        var seen: Set<String> = []
        var date = t("07:00")
        while date < t("23:59") {
            if let now = engine.now(in: plan, at: date) {
                let index = plan.stops.firstIndex(of: now.current)!
                #expect(index >= lastIndex, "volta no tempo às \(clock(date))")
                lastIndex = index
                seen.insert(now.current.id)
                #expect(now.leaveAt > date)
                #expect(now.leaveAt >= now.current.start)
                #expect(now.next == (index + 1 < plan.stops.count ? plan.stops[index + 1] : nil))
                if let next = now.next {
                    #expect(now.leaveAt == DayNowRules.departure(from: index, in: plan))
                    #expect((now.arriveBy != nil) == ((next.queueMinutes ?? 0) > 0 && !next.isBooked && next.kind != .micro))
                }
            } else {
                #expect(date < plan.stops.first!.start || date >= plan.stops.last!.end)
            }
            date = date.addingTimeInterval(60)
        }
        // Toda parada é "agora" em algum momento do dia.
        #expect(seen.count == plan.stops.count)
    }

    @Test func realDayLeaveForUdatsuCountsTheTrainAndMargin() async throws {
        let engine = DayFixtures.engine(pace: .normal)
        let plan = await engine.build(area: nil, pace: .normal, budget: 15_000, until: t("23:30"), includes: [.micro, .goldenPhoto])
        let udatsu = try #require(plan.stops.first { $0.placeId == "j01" })
        let index = try #require(plan.stops.firstIndex(of: udatsu))
        let before = plan.stops[index - 1]
        let travel = plan.leg(before: udatsu)?.minutes ?? 0
        let now = try #require(engine.now(in: plan, at: before.start))
        #expect(now.current == before)
        #expect(now.next == udatsu)
        #expect(now.leaveAt == udatsu.start.addingTimeInterval(-Double(travel + 5) * 60))
        #expect(now.arriveBy == nil)
    }
}
