import CoreLocation
import Foundation
import Testing
@testable import Must

/// Solver por área (prompt 18 · C.15): "Shinjuku+" = Shinjuku + vizinhos a até 15 min, na tabela (offline).
/// Gyoen e Golden Gai vêm do seed JP (j104, j105). O catálogo de fixtures segue pra ordem exata do exemplo.
private final class AreaFocusToken {}

private enum AreaFixtures {
    static func seedCatalog() -> [SolverPlace] {
        let url = Region.jp.seedURL(in: Bundle(for: AreaFocusToken.self))!
        let board = try! BoardCodec.decode(Data(contentsOf: url))
        let colors = Dictionary(uniqueKeysWithValues: board.lists.map { ($0.id, $0.color) })
        return board.places.map { SolverPlace($0, color: colors[$0.listId] ?? .eat) }
    }

    static func fixture(_ id: String, _ name: String, area: String, color: MustColor, kind: ListKind = .place,
                        windows: [DayWindow], lat: Double, lng: Double, extra: PlaceExtra? = nil) -> SolverPlace {
        SolverPlace(id: id, name: name, nameLocal: nil, listId: "fixture-\(color.rawValue)", listColor: color, sub: nil,
                    cityId: "tokyo1", area: area, lat: lat, lng: lng, price: nil, windows: windows, hours: nil,
                    reservation: nil, saveForEnd: false, allowBudgetException: false, queueMinutes: nil, notes: "",
                    sourceKind: nil, done: false, kind: kind, extra: extra, tickets: [])
    }

    /// Catálogo do exemplo: Nakano (loja, manhã), Fuunji (almoço, seed), Gyoen (golden da tarde), Golden Gai (noite),
    /// e um decoy de Ginza (fora do foco, nunca entra).
    static func shinjukuCatalog() -> [SolverPlace] {
        let fuunji = seedCatalog().first { $0.id == "j05" }!
        return [
            fixture("n1", "Nakano Broadway", area: "Nakano", color: .shop, windows: [.morning], lat: 35.7093, lng: 139.6656),
            fuunji,
            fixture("g1", "Shinjuku Gyoen", area: "Shinjuku", color: .photo, kind: .photo, windows: [],
                    lat: 35.6852, lng: 139.7100, extra: PlaceExtra(photo: PhotoSpot(bestLight: [.goldenPM]))),
            fixture("gg1", "Golden Gai", area: "Shinjuku", color: .drink, windows: [.night], lat: 35.6938, lng: 139.7036),
            fixture("gz1", "Loja em Ginza", area: "Ginza", color: .shop, windows: [.morning], lat: 35.6717, lng: 139.7650),
        ]
    }

    static let shinjuku = CLLocationCoordinate2D(latitude: 35.6896, longitude: 139.7006)

    /// Domingo 15 nov em Tóquio, saindo de Shinjuku às 09:30.
    static func shinjukuPlus(travel: TravelMatrix? = nil, includeNeighbors: Bool = true, maxHop: Int = 15,
                             day: String = "2026-11-15") -> DayRequest {
        let d = BoardDates(timeZone: Region.jp.timeZone)
        let date = d.day(from: day)!
        return DayRequest(date: date, timeZone: Region.jp.timeZone, kind: .free, budget: 15000, walk: .normal, lists: [:],
                          intent: DayIntent(), startAt: d.time("09:30", on: date)!, origin: shinjuku, cityId: "tokyo1",
                          daysLeftInCity: 1, travel: travel,
                          focus: .area(id: "shinjuku", includeNeighbors: includeNeighbors, maxHopMinutes: maxHop))
    }
}

struct AreaFocusSolverTests {
    let catalog = AreaFixtures.shinjukuCatalog()

    @Test func shinjukuPlusBuildsNakanoFuunjiGyoenGoldenGai() {
        let p = DaySolver.solve(AreaFixtures.shinjukuPlus(), catalog: catalog)
        #expect(p.stops.map(\.place.id) == ["n1", "j05", "g1", "gg1"])
    }

    @Test func shinjukuPlusKeepsGyoenOnTheGolden() throws {
        let p = DaySolver.solve(AreaFixtures.shinjukuPlus(), catalog: catalog)
        let gyoen = try #require(p.stops.first { $0.place.id == "g1" })
        #expect(gyoen.reason == "golden")
        #expect(gyoen.window == .afternoon)
    }

    @Test func offlineUsesNeighborTableWithoutTravelMatrix() {
        // Sem Routes (travel nil) e com matriz vazia dão a mesma ordem: a tabela de vizinhos segura o foco.
        let offline = DaySolver.solve(AreaFixtures.shinjukuPlus(travel: nil), catalog: catalog)
        let empty = DaySolver.solve(AreaFixtures.shinjukuPlus(travel: TravelMatrix()), catalog: catalog)
        #expect(offline.stops.map(\.place.id) == empty.stops.map(\.place.id))
        #expect(offline.stops.map(\.place.id) == ["n1", "j05", "g1", "gg1"])
    }

    @Test func placeOutsideFocusNeverEnters() {
        let p = DaySolver.solve(AreaFixtures.shinjukuPlus(), catalog: catalog)
        #expect(!p.stops.contains { $0.place.id == "gz1" })
        // Fora do bairro é silencioso: não aparece como "deixei de fora".
        #expect(!p.leftOut.contains { $0.place.id == "gz1" })
    }

    @Test func withoutFocusTheSameDayCanTakeAnyArea() {
        // Sem o Nakano no catálogo, a loja de Ginza é a única loja da manhã: entra sem foco e fica de fora com foco.
        let withoutNakano = catalog.filter { $0.id != "n1" }
        var req = AreaFixtures.shinjukuPlus()
        req.focus = nil
        let open = DaySolver.solve(req, catalog: withoutNakano)
        #expect(open.stops.contains { $0.place.id == "gz1" })
        let focused = DaySolver.solve(AreaFixtures.shinjukuPlus(), catalog: withoutNakano)
        #expect(!focused.stops.contains { $0.place.id == "gz1" })
    }

    @Test func explanationStartsWithTheOrder() {
        let p = DaySolver.solve(AreaFixtures.shinjukuPlus(), catalog: catalog)
        #expect(p.explanation.hasPrefix("Comece por Nakano Broadway, almoço Fuunji, Shinjuku Gyoen no golden, Golden Gai à noite."))
        #expect(p.explanation.contains("trocas de bairro") || p.explanation.contains("troca de bairro") || p.explanation.contains("Tudo no mesmo bairro"))
    }

    @Test func solverIsDeterministic() {
        let a = DaySolver.solve(AreaFixtures.shinjukuPlus(), catalog: catalog)
        let b = DaySolver.solve(AreaFixtures.shinjukuPlus(), catalog: catalog)
        #expect(a.stops.map(\.place.id) == b.stops.map(\.place.id))
        #expect(a.explanation == b.explanation)
    }
}

struct AreaFocusSeedTests {
    /// O seed de verdade (não fixture): Shinjuku+ tem Gyoen e Golden Gai como candidatos, e a Golden Gai fecha a noite.
    @Test func shinjukuPlusOnSeedHasGyoenAndGoldenGaiWithGoldenGaiLast() throws {
        let catalog = AreaFixtures.seedCatalog()
        // Sábado 14 nov: sem reserva de jantar (a do Udatsu é dia 15 e viraria âncora).
        let p = DaySolver.solve(AreaFixtures.shinjukuPlus(day: "2026-11-14"), catalog: catalog)
        let ids = p.stops.map(\.place.id)
        let gyoen = try #require(catalog.first { $0.name == "Shinjuku Gyoen" })
        let golden = try #require(catalog.first { $0.name == "Golden Gai" })
        #expect(ids.contains(gyoen.id))
        #expect(ids.contains(golden.id))
        #expect(ids.last == golden.id)
    }
}

struct AreaFocusPlanTests {
    let areas = AreaCatalog.all

    @Test func neighborsWithinMaxHopOnly() throws {
        let plan = try #require(AreaFocusPlan(focus: .area(id: "shinjuku", includeNeighbors: true, maxHopMinutes: 15), areas: areas))
        #expect(plan.allows("shinjuku"))
        #expect(plan.allows("nakano"))       // 5 min
        #expect(plan.allows("shin-okubo"))   // 3 min
        #expect(plan.allows("harajuku"))     // 4 min
        #expect(plan.allows("koenji"))       // 10 min
        #expect(!plan.allows("kichijoji"))   // 17 min: fora do limite
        #expect(!plan.allows("ginza"))
        #expect(!plan.allows(nil))
    }

    @Test func withoutNeighborsOnlyTheArea() throws {
        let plan = try #require(AreaFocusPlan(focus: .area(id: "shinjuku", includeNeighbors: false, maxHopMinutes: 15), areas: areas))
        #expect(plan.allows("shinjuku"))
        #expect(!plan.allows("nakano"))
    }

    @Test func hopIsSymmetricAndUsesTheTable() throws {
        let plan = try #require(AreaFocusPlan(focus: .area(id: "shinjuku", includeNeighbors: true, maxHopMinutes: 15), areas: areas))
        #expect(plan.hop("shinjuku", "nakano") == 5)
        #expect(plan.hop("nakano", "shinjuku") == 5)
        #expect(plan.hop("nakano", "shinjuku") == plan.hop("shinjuku", "nakano"))
        #expect(plan.hop("shinjuku", "shinjuku") == 0)
        // Sem ligação direta na tabela: nil (o solver cobra 25 min).
        #expect(plan.hop("nakano", "ginza") == nil)
    }

    @Test func unknownAreaHasNoPlan() {
        #expect(AreaFocusPlan(focus: .area(id: "nao-existe", includeNeighbors: true, maxHopMinutes: 15), areas: areas) == nil)
    }
}
