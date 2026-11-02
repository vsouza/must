import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 17 · A (fatia 8A): o solver usa a matriz do Routes quando ela vem pronta, e cai na estimativa sem ela.
private enum MatrixFixtures {
    final class Token {}

    static func catalog() -> [SolverPlace] {
        let url = Region.jp.seedURL(in: Bundle(for: Token.self))!
        let board = try! BoardCodec.decode(Data(contentsOf: url))
        let colors = Dictionary(uniqueKeysWithValues: board.lists.map { ($0.id, $0.color) })
        return board.places.map { SolverPlace($0, color: colors[$0.listId] ?? .eat) }
    }

    static let naka = CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)

    static func request(origin: CLLocationCoordinate2D, travel: TravelMatrix?) -> DayRequest {
        let d = BoardDates(timeZone: Region.jp.timeZone)
        let date = d.day(from: "2026-11-15")!
        return DayRequest(date: date, timeZone: Region.jp.timeZone, kind: .free, budget: 30_000, walk: .normal, lists: [:],
                          intent: DayIntent(), startAt: d.time("09:30", on: date)!, origin: origin, cityId: "tokyo1",
                          daysLeftInCity: 3, travel: travel)
    }
}

struct TravelMatrixTests {
    static let a = CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)
    static let near = CLLocationCoordinate2D(latitude: 35.6462, longitude: 139.6985)
    static let far = CLLocationCoordinate2D(latitude: 35.6942, longitude: 139.6985)

    @Test func matrixWalkReplacesEstimateWithinWalkLimit() {
        let matrix = TravelMatrix(walk: [TravelMatrix.key(Self.a, Self.near): 11], transit: [:])
        let real = DaySolver.leg(Self.a, Self.near, walkMax: 1.5, matrix: matrix)
        #expect(real.mode == .walk)
        #expect(real.minutes == 11)
        // Sem a matriz, a mesma perna sai da estimativa (80 m/min).
        let estimate = DaySolver.leg(Self.a, Self.near, walkMax: 1.5)
        #expect(estimate.minutes != 11)
    }

    @Test func matrixTransitReplacesEstimateBeyondWalkLimit() {
        let matrix = TravelMatrix(walk: [:], transit: [TravelMatrix.key(Self.a, Self.far): 17])
        let real = DaySolver.leg(Self.a, Self.far, walkMax: 1.5, matrix: matrix)
        #expect(real.mode == .metro)
        #expect(real.minutes == 17)
    }

    @Test func missingPairFallsBackToEstimate() {
        let estimate = DaySolver.leg(Self.a, Self.far, walkMax: 1.5)
        #expect(DaySolver.leg(Self.a, Self.far, walkMax: 1.5, matrix: TravelMatrix()) == estimate)
        #expect(DaySolver.leg(Self.a, Self.far, walkMax: 1.5, matrix: TravelMatrix(walk: [TravelMatrix.key(Self.a, Self.near): 3])) == estimate)
    }

    @Test func solverUsesMatrixLegsWhenPassed() {
        let catalog = MatrixFixtures.catalog()
        // Todo par origem → lugar com tempo conhecido: a pé 7 min, transporte 9 min.
        var matrix = TravelMatrix()
        for place in catalog {
            let to = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
            matrix.walk[TravelMatrix.key(MatrixFixtures.naka, to)] = 7
            matrix.transit[TravelMatrix.key(MatrixFixtures.naka, to)] = 9
        }
        let proposal = DaySolver.solve(MatrixFixtures.request(origin: MatrixFixtures.naka, travel: matrix), catalog: catalog)
        let first = proposal.stops.min { $0.at < $1.at }
        let leg = try? #require(first?.legFromPrevious)
        #expect([7, 9].contains(leg?.minutes ?? 0))
    }

    @Test func solverWithoutMatrixStillSolves() {
        let proposal = DaySolver.solve(MatrixFixtures.request(origin: MatrixFixtures.naka, travel: nil), catalog: MatrixFixtures.catalog())
        #expect(!proposal.stops.isEmpty)
        #expect(proposal.stops.allSatisfy { $0.legFromPrevious != nil })
    }
}
