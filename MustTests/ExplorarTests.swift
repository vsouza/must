import CoreLocation
import Foundation
import Testing
@testable import Must

@MainActor
struct ExplorarTests {
    private var tokyo: [Area] { AreaCatalog.jp.filter { AreaCatalog.cityGroup(forCityId: $0.cityId) == "tokyo" } }

    private func stations(origin: String? = "shinjuku", populated: Set<String>? = nil, today: [String: String?] = [:],
                          done: Set<String> = [], here: String? = "shinjuku") -> [ExplorarStation] {
        ExplorarRail.stations(areas: AreaCatalog.jp, cityGroup: "tokyo", originId: origin,
                              populated: populated ?? Set(tokyo.map(\.id)), today: today, done: done, hereId: here)
    }

    private func item(_ id: String, own: Bool, open: Bool, done: Bool = false, meters: Double, lat: Double = 35.69, lng: Double = 139.70) -> ExplorarItem {
        ExplorarItem(id: id, placeId: own ? id : nil, name: id, lat: lat, lng: lng,
                     tone: own ? (open && !done ? .own : .paper) : .outside, isOpen: open, done: done, inPlan: false, meta: "", meters: meters)
    }

    private func days(_ pairs: [(String, String?)]) -> [String: String?] { Dictionary(uniqueKeysWithValues: pairs) }

    // MARK: Trilho

    @Test func railOrdersByTrainTimeFromOrigin() {
        let list = stations()
        #expect(list.first?.id == "shinjuku")
        #expect(list.first?.minutes == 0)
        let minutes = list.map(\.minutes)
        #expect(minutes == minutes.sorted())
        // O vizinho direto vem antes do que passa por ele.
        let reach = ExplorarRail.minutes(from: "shinjuku", areas: AreaCatalog.jp)
        if let nakano = reach["nakano"], let neighbor = AreaCatalog.jp.first(where: { $0.id == "shinjuku" })?.neighbors.first(where: { $0.areaId == "nakano" }) {
            #expect(nakano <= neighbor.minutes)
        }
    }

    @Test func railOriginChangesTheOrder() {
        let fromAsakusa = stations(origin: "asakusa", here: nil)
        #expect(fromAsakusa.first?.id == "asakusa")
        let fromShinjuku = stations()
        #expect(fromAsakusa.map(\.id) != fromShinjuku.map(\.id))
    }

    @Test func railMarksHereTodayAndDone() {
        let list = stations(today: days([("nakano", "19h")]), done: ["harajuku"])
        #expect(list.first { $0.id == "shinjuku" }?.mark == .here)
        #expect(list.first { $0.id == "nakano" }?.mark == .today(time: "19h"))
        #expect(list.first { $0.id == "nakano" }?.caption == "hoje 19h")
        #expect(list.first { $0.id == "harajuku" }?.mark == .done)
    }

    @Test func railOnlyHasPopulatedTodayAndNeighborsOfToday() {
        let list = stations(origin: "shinjuku", populated: ["shinjuku", "ginza"], today: days([("ueno", nil)]), here: nil)
        let ids = Set(list.map(\.id))
        #expect(ids.contains("shinjuku") && ids.contains("ginza") && ids.contains("ueno"))
        // Vizinho de um bairro de hoje entra mesmo sem Musts; um bairro solto não.
        let ueno = AreaCatalog.jp.first { $0.id == "ueno" }!
        for n in ueno.neighbors { #expect(ids.contains(n.areaId)) }
        #expect(!ids.contains("daikanyama") || ueno.neighbors.contains { $0.areaId == "daikanyama" })
    }

    @Test func railOnlyHasTheCityOfThePage() {
        let kyoto = ExplorarRail.stations(areas: AreaCatalog.jp, cityGroup: "kyoto", originId: nil, populated: [], today: [:], done: [], hereId: nil)
        #expect(!kyoto.isEmpty)
        #expect(kyoto.allSatisfy { AreaCatalog.cityGroup(forCityId: $0.area.cityId) == "kyoto" })
        #expect(kyoto.first?.minutes == 0)
        #expect(kyoto.first?.caption == "hotel")
    }

    @Test func railOriginPrefersGpsThenPlanThenFirst() {
        let areas = AreaCatalog.jp
        #expect(ExplorarRail.origin(hereId: "ginza", planAreaId: "ueno", areas: areas, cityGroup: "tokyo") == "ginza")
        #expect(ExplorarRail.origin(hereId: nil, planAreaId: "ueno", areas: areas, cityGroup: "tokyo") == "ueno")
        // GPS de outra cidade não vale.
        #expect(ExplorarRail.origin(hereId: "gion", planAreaId: "ueno", areas: areas, cityGroup: "tokyo") == "ueno")
        #expect(ExplorarRail.origin(hereId: nil, planAreaId: nil, areas: areas, cityGroup: "kyoto") == areas.first { $0.cityId == "kyoto" }?.id)
    }

    @Test func railStepAndFractionStopAtTheEnds() {
        let list = stations()
        #expect(ExplorarRail.step(list, from: list[0].id, by: -1) == list[0].id)
        #expect(ExplorarRail.step(list, from: list[0].id, by: 1) == list[1].id)
        #expect(ExplorarRail.step(list, from: list.last!.id, by: 1) == list.last!.id)
        #expect(ExplorarRail.station(atFraction: 0, count: 10) == 0)
        #expect(ExplorarRail.station(atFraction: 0.55, count: 10) == 5)
        #expect(ExplorarRail.station(atFraction: 1.4, count: 10) == 9)
        #expect(ExplorarRail.station(atFraction: -1, count: 10) == 0)
    }

    @Test func railWindowKeepsTheCurrentStation() {
        let list = (0..<20).map { i -> ExplorarStation in
            var a = AreaCatalog.jp[0]
            a.id = "a\(i)"
            return ExplorarStation(area: a, minutes: i, mark: .other)
        }
        let window = ExplorarRailView.window(list, currentId: "a15")
        #expect(window.count == ExplorarRailView.maxRows)
        #expect(window.contains { $0.id == "a15" })
        #expect(ExplorarRailPanel.window(list, around: "a15").contains { $0.id == "a15" })
    }

    // MARK: Camadas e lista ↔ pinos

    @Test func layersFilterOwnOutsideAndOpenNow() {
        let all = [item("a", own: true, open: true, meters: 100), item("b", own: true, open: false, meters: 50),
                   item("x", own: false, open: true, meters: 80), item("y", own: false, open: false, meters: 60)]
        #expect(ExplorarLayers.filter(all, layers: [.own, .outside]).count == 4)
        #expect(ExplorarLayers.filter(all, layers: [.own]).map(\.id).sorted() == ["a", "b"])
        #expect(ExplorarLayers.filter(all, layers: [.outside]).map(\.id).sorted() == ["x", "y"])
        #expect(ExplorarLayers.filter(all, layers: [.own, .outside, .openNow]).map(\.id).sorted() == ["a", "x"])
        #expect(ExplorarLayers.filter(all, layers: [.trail]).isEmpty)
    }

    @Test func listOrderIsOwnOpenFirstThenOwnThenOutside() {
        let all = [item("far-open", own: true, open: true, meters: 900), item("near-closed", own: true, open: false, meters: 10),
                   item("out", own: false, open: true, meters: 5), item("near-open", own: true, open: true, meters: 100),
                   item("done-open", own: true, open: true, done: true, meters: 1)]
        let listed = ExplorarLayers.listed(all, layers: ExplorarLayer.standard)
        #expect(listed.map(\.id) == ["near-open", "far-open", "near-closed", "done-open", "out"])
        #expect(listed.map(\.number) == [1, 2, 3, 4, 5])
    }

    @Test func pinNumbersMatchTheListAndOverflowBecomesDots() {
        let all = (0..<12).map { item("p\($0)", own: true, open: true, meters: Double($0)) }
        let listed = ExplorarLayers.listed(all, layers: [.own])
        for (i, row) in listed.prefix(ExplorarLayers.numberedLimit).enumerated() { #expect(row.number == i + 1) }
        #expect(listed.dropFirst(ExplorarLayers.numberedLimit).allSatisfy { $0.number == nil })
    }

    @Test func onScreenListFollowsTheMapRectAndRenumbers() {
        let inside = item("in", own: true, open: true, meters: 300, lat: 35.690, lng: 139.700)
        let outside = item("out", own: true, open: true, meters: 100, lat: 35.800, lng: 139.900)
        let rect = GeoRect(minLat: 35.68, maxLat: 35.70, minLng: 139.69, maxLng: 139.71)
        let listed = ExplorarLayers.listed([inside, outside], layers: [.own], in: rect)
        #expect(listed.map(\.id) == ["in"])
        #expect(listed.first?.number == 1)
        // Sem recorte, os dois; o mais perto vira o 1.
        #expect(ExplorarLayers.listed([inside, outside], layers: [.own]).first?.id == "out")
    }

    @Test func swipingTheBlockMovesToTheNextPinAndStopsAtTheEnds() {
        let list = ExplorarLayers.listed((0..<3).map { item("p\($0)", own: true, open: true, meters: Double($0)) }, layers: [.own])
        #expect(ExplorarLayers.index(ofPin: "p1", in: list) == 1)
        #expect(ExplorarLayers.neighbor(of: "p1", in: list, by: 1) == "p2")
        #expect(ExplorarLayers.neighbor(of: "p2", in: list, by: 1) == "p2")
        #expect(ExplorarLayers.neighbor(of: "p0", in: list, by: -1) == "p0")
    }

    @Test func trailNeedsTwoStops() {
        let c = CLLocationCoordinate2D(latitude: 1, longitude: 1)
        #expect(ExplorarLayers.trail(stops: [c]).isEmpty)
        #expect(ExplorarLayers.trail(stops: [c, c]).count == 1)
    }

    // MARK: Projeção e distância

    @Test func projectionPutsTheCenterInTheMiddleAndNorthUp() {
        let area = AreaCatalog.jp.first { $0.id == "shinjuku" }!
        let p = ExplorarSnapshot.projection(for: area)
        let mid = p.point(area.centroid.clCoordinate)
        #expect(abs(mid.x - 88) < 0.01 && abs(mid.y - 88) < 0.01)
        let north = p.point(CLLocationCoordinate2D(latitude: area.centroid.lat + 0.002, longitude: area.centroid.lng))
        #expect(north.y < mid.y && abs(north.x - mid.x) < 0.01)
        // 900 m cabem em 176 pt: o canto do quadro está a ~450 m do centro.
        let r = p.rect
        let edge = CLLocation(latitude: area.centroid.lat, longitude: r.maxLng).distance(from: CLLocation(latitude: area.centroid.lat, longitude: area.centroid.lng))
        #expect(abs(edge - 450) < 15)
        #expect(r.contains(lat: area.centroid.lat, lng: area.centroid.lng))
    }

    @Test func travelTextWalksUnderOneAndAHalfKm() {
        #expect(ExplorarTravel.distance(240).value == "240" && ExplorarTravel.distance(240).unit == "m")
        #expect(ExplorarTravel.distance(2_900).value == "2,9" && ExplorarTravel.distance(2_900).unit == "km")
        #expect(ExplorarTravel.caption(240).hasSuffix("a pé"))
        #expect(ExplorarTravel.caption(2_900).hasSuffix("trem"))
    }
}
