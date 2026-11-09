import CoreLocation
import Foundation
import Testing
@testable import Must

/// "Ir pra um bairro": linhas do checklist, catálogo restrito (marcados + âncoras de hoje) e o solver sobre ele.
struct IrBairroTests {
    final class Token {}

    private func info(_ id: String, _ name: String, state: OpenState, done: Bool = false, sub: String? = nil,
                      reserved: Bool = false) -> IrBairro.MustInfo {
        .init(id: id, name: name, sub: sub, isDone: done, state: state, hasReservationToday: reserved)
    }

    @Test func rowsPutOpenFirstKeepBoardOrderAndDropDone() {
        let all = [
            info("a", "Afuri", state: .closed(opensDay: nil, opensAt: "17:00"), sub: "ramen"),
            info("b", "Fuunji", state: .open(until: "16:30"), sub: "ramen"),
            info("c", "Feito", state: .open(until: nil), done: true),
            info("d", "Omoide", state: .unknown),
            info("e", "Golden Gai", state: .open(until: nil)),
        ]
        let rows = IrBairro.mustRows(ids: all.map(\.id), info: Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) }))
        #expect(rows.map(\.id) == ["b", "e", "a", "d"])
        #expect(rows[0].meta == "ramen · aberto até 16:30")
        #expect(rows[1].meta == "aberto")
        #expect(rows[2].meta == "ramen · abre 17:00")
        #expect(rows[3].meta == "horário não confirmado")
    }

    @Test func unknownHoursNeverClaimOpen() {
        let m = info("x", "X", state: .unknown, reserved: true)
        #expect(!IrBairro.metaLine(m).contains("aberto"))
        #expect(IrBairro.metaLine(m).contains("reserva hoje"))
    }

    @Test func areaRowsCountOnlyGivenPlacesAndOpenOnes() {
        let area = AreaCatalog.areas(for: .jp).first { $0.id == "shinjuku" }!
        func p(_ id: String, order: Int) -> AreaPlace {
            AreaPlace(id: id, name: id, areaName: "Shinjuku", cityId: "tokyo1", lat: area.centroid.lat, lng: area.centroid.lng, kind: .eat,
                      isDone: false, verified: false, order: order, hasReservation: false)
        }
        let index = AreaIndex.build(areas: AreaCatalog.areas(for: .jp), places: [p("a", order: 0), p("b", order: 1)], openIds: ["b"])
        let rows = IrBairro.areaRows(index)
        let row = rows.first { $0.id == "shinjuku" }
        #expect(row?.count == 2)
        #expect(row?.openCount == 1)
        #expect(row?.metaLine == "2 MUSTS · 1 ABERTO")
    }

    // MARK: Solver

    private let region = Region.jp
    private var catalog: [SolverPlace] {
        let url = region.seedURL(in: Bundle(for: Token.self))!
        let b = try! BoardCodec.decode(Data(contentsOf: url))
        let colors = Dictionary(uniqueKeysWithValues: b.lists.map { ($0.id, $0.color) })
        return b.places.map { SolverPlace($0, color: colors[$0.listId] ?? .eat) }
    }
    private var day: Date { BoardDates(timeZone: region.timeZone).day(from: "2026-11-15")! }

    @Test func restrictedCatalogKeepsCheckedAndTodaysAnchorsOnly() {
        let all = catalog
        let tokyo = all.filter { $0.cityId == "tokyo1" && $0.reservation == nil }
        let checked = Set(tokyo.prefix(3).map(\.id))
        let out = IrBairro.restrictedCatalog(all, checked: checked, date: day, calendar: region.calendar)
        let anchors = all.filter { IrBairro.isAnchor($0, on: day, calendar: region.calendar) }
        #expect(anchors.contains { $0.id == "j01" }) // reserva de 15/11 no seed
        #expect(Set(out.map(\.id)) == checked.union(anchors.filter { !$0.done }.map(\.id)))
        #expect(out.count < all.count)
    }

    @Test func solverOnRestrictedCatalogOnlyUsesCheckedPlusAnchors() {
        let all = catalog
        let tokyo = all.filter { $0.cityId == "tokyo1" && $0.reservation == nil }
        let checked = Set(tokyo.prefix(4).map(\.id))
        let restricted = IrBairro.restrictedCatalog(all, checked: checked, date: day, calendar: region.calendar)
        var intent = DayIntent()
        intent.mustInclude = IrBairro.mustIncludeNames(all, checked: checked)
        let d = BoardDates(timeZone: region.timeZone)
        let request = DayRequest(date: day, timeZone: region.timeZone, kind: .free, budget: region.defaultBudget, intent: intent,
                                 startAt: d.time("09:30", on: day)!,
                                 origin: CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985), cityId: "tokyo1",
                                 daysLeftInCity: 1, weather: nil)
        let proposal = DaySolver.solve(request, catalog: restricted)
        let allowed = Set(restricted.map(\.id))
        #expect(!proposal.stops.isEmpty)
        #expect(proposal.stops.allSatisfy { allowed.contains($0.place.id) })
        // O que o usuário marcou e ficou de fora tem motivo (ou entrou).
        let missing = IrBairro.missing(proposal, asked: all.filter { checked.contains($0.id) })
        let placed = Set(proposal.stops.map(\.place.id))
        #expect(missing.count == checked.subtracting(placed).count)
        #expect(missing.allSatisfy { !$0.reason.isEmpty })
    }
}
