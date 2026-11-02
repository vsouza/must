import CoreLocation
import Foundation
import Testing
@testable import Must

/// Prompt 17 · A (fatia 8A): Routes (TRANSIT, WALK, DRIVE) e Route Matrix, parsers e máscaras (sem rede).
struct GoogleRoutesTests {
    @Test func transitParsesLineColorStopsAndFare() throws {
        let option = try #require(try GoogleRoutes.parseTransit(Data(RoutesSamples.transitJSON.utf8)))
        #expect(option.mode == .transit)
        #expect(option.minutes == 14)
        #expect(option.steps.count == 3)
        #expect(option.steps[0].kind == .walk)
        #expect(option.steps[0].instruction == "Caminhe até a estação Hibiya, entrada oeste")

        let line = option.steps[1]
        #expect(line.kind == .transit)
        #expect(line.lineShort == "H")
        #expect(line.lineName == "Hibiya Line")
        #expect(line.colorHex == "#b5b5ac")
        #expect(line.textColorHex == "#ffffff")
        #expect(line.headsign == "Kita-Senju")
        #expect(line.vehicle == "Subway")
        #expect(line.agency == "Tokyo Metro")
        #expect(line.from?.name == "Hibiya")
        #expect(line.to?.name == "Ebisu")
        #expect(line.from?.lat == 35.6736)
        #expect(line.stopCount == 2)
        #expect(line.from?.departs == GoogleRoutes.date("2026-11-15T09:47:00Z"))

        #expect(option.fare == 180)
        #expect(option.fareCurrency == "JPY")
        #expect(option.transfers == 0)
        #expect(option.departs == GoogleRoutes.date("2026-11-15T09:47:00Z"))
        #expect(option.arrives == GoogleRoutes.date("2026-11-15T09:55:00Z"))
    }

    @Test func transitWithoutRouteIsNil() throws {
        #expect(try GoogleRoutes.parseTransit(Data(#"{"routes": []}"#.utf8)) == nil)
    }

    @Test func fareIsOnlyRequestedForTransit() {
        #expect(GoogleRoutes.routeCall(mode: "TRANSIT", fare: true).sku == .routesPro)
        #expect(GoogleRoutes.routeCall(mode: "TRANSIT", fare: false).sku == .routesEssentials)
        #expect(GoogleRoutes.routeCall(mode: "WALK", fare: false).sku == .routesEssentials)
        #expect(GoogleRoutes.transitMask.contains("routes.legs.steps.transitDetails"))
        #expect(GoogleRoutes.transitMask.contains("routes.travelAdvisory.transitFare"))
    }

    @Test func transitBodyAsksDepartureTimeAndNoFieldsItDoesNotNeed() {
        let body = GoogleRoutes.body(from: CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985),
                                     to: CLLocationCoordinate2D(latitude: 35.6700, longitude: 139.7560), mode: "TRANSIT",
                                     departAt: Date(timeIntervalSince1970: 1_793_000_000))
        #expect(body["travelMode"] as? String == "TRANSIT")
        #expect(body["departureTime"] != nil)
        #expect(body["extraComputations"] == nil)
    }

    @Test func walkParsesSingleStep() throws {
        let option = try #require(try GoogleRoutes.parseSimple(Data(RoutesSamples.walkJSON.utf8), mode: .walk))
        #expect(option.minutes == 22)
        #expect(option.meters == 1640)
        #expect(option.steps.first?.kind == .walk)
    }

    @Test func matrixParsesCellsAndKeepsStatusErrorsOut() throws {
        let cells = try GoogleRoutes.parseMatrix(Data(RoutesSamples.matrixJSON.utf8))
        #expect(cells.count == 4)
        let cell = try #require(cells.first { $0.originIndex == 0 && $0.destinationIndex == 1 })
        #expect(cell.minutes == 11)
        #expect(cell.meters == 900)

        let failed = Data(#"[{"originIndex": 0, "destinationIndex": 0, "status": {"code": 3, "message": "x"}}]"#.utf8)
        #expect(try GoogleRoutes.parseMatrix(failed).isEmpty)
    }

    @Test func matrixBodyHasOneWaypointPerPoint() {
        let points = [CLLocationCoordinate2D(latitude: 35.1, longitude: 139.1), CLLocationCoordinate2D(latitude: 35.2, longitude: 139.2)]
        let body = GoogleRoutes.matrixBody(origins: points, destinations: points, mode: "WALK", departAt: Date())
        #expect((body["origins"] as? [Any])?.count == 2)
        #expect((body["destinations"] as? [Any])?.count == 2)
        #expect(body["departureTime"] == nil)
    }

    @Test func taxiEstimateIsRoughAndRounded() {
        #expect(TaxiEstimate.jpy(km: 1.052) == 500)
        #expect(TaxiEstimate.jpy(km: 2.0) == 800)
        #expect(TaxiEstimate.brl(km: 3) == 13.5)
    }

    @Test func travelMatrixLoaderKeepsOriginFirstAndCapsPoints() {
        let origin = CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)
        let many = (1...20).map { CLLocationCoordinate2D(latitude: 35.6 + Double($0) * 0.001, longitude: 139.7) }
        let points = TravelMatrixLoader.points(origin: origin, candidates: [origin] + many)
        #expect(points.count == TravelMatrixLoader.maxPoints)
        #expect(points[0].latitude == origin.latitude)
    }

    @Test func matrixLoaderWithoutKeyDoesNothing() async {
        let points = [CLLocationCoordinate2D(latitude: 35.1, longitude: 139.1), CLLocationCoordinate2D(latitude: 35.2, longitude: 139.2)]
        #expect(await TravelMatrixLoader.load(points: points, departAt: Date(), day: "2026-11-15", apiKey: nil) == nil)
    }
}
