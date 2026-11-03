import CoreLocation
import Foundation
import Testing
@testable import Must

/// Bairros e Guia (prompt 18 · C.14 e C.16): geometria das bolhas, projeção da câmera, deslocamento entre paradas
/// (tabela de vizinhos, offline) e o número das paradas no mini-mapa.
@MainActor
struct BairroGeometryTests {
    @Test func bubbleGrowsWithSquareRootOfMusts() {
        #expect(BairroGeometry.diameter(count: 0) == 26)
        #expect(BairroGeometry.diameter(count: 4) == 42)
        #expect(BairroGeometry.diameter(count: 16) == 58)
        // Teto: nunca passa de 76 pt, mesmo com muitos musts.
        #expect(BairroGeometry.diameter(count: 400) == 76)
        // Sublinear: 4× mais musts não é 4× o raio.
        #expect(BairroGeometry.diameter(count: 16) - 26 < 4 * (BairroGeometry.diameter(count: 4) - 26))
    }

    @Test func centerProjectsToScreenCenter() {
        let camera = MapCameraState(center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.70),
                                    zoom: 14, metersPerPoint: 5, widthMeters: 2000)
        let size = CGSize(width: 390, height: 844)
        let p = BairroGeometry.project(lat: 35.68, lng: 139.70, camera: camera, size: size)
        #expect(abs(p.x - 195) < 0.01)
        #expect(abs(p.y - 422) < 0.01)
    }

    @Test func oneKilometerEastIsTwoHundredPointsAtFivePerPoint() {
        // A 35,68° a escala é cos(φ) do Mercator; 1 km de chão a 5 m/pt = 200 pt (com o cosseno do centro compensado).
        let lat = 35.68
        let camera = MapCameraState(center: CLLocationCoordinate2D(latitude: lat, longitude: 139.70),
                                    zoom: 14, metersPerPoint: 5, widthMeters: 2000)
        let r = 6_378_137.0
        let dLng = 1000 / (r * cos(lat * .pi / 180) * .pi / 180)
        let p = BairroGeometry.project(lat: lat, lng: 139.70 + dLng, camera: camera, size: CGSize(width: 100, height: 100))
        #expect(abs((p.x - 50) - 200) < 0.5)
        #expect(abs(p.y - 50) < 0.01)
    }

    @Test func northIsUpOnScreen() {
        let camera = MapCameraState(center: CLLocationCoordinate2D(latitude: 35.68, longitude: 139.70),
                                    zoom: 14, metersPerPoint: 5, widthMeters: 2000)
        let north = BairroGeometry.project(lat: 35.69, lng: 139.70, camera: camera, size: CGSize(width: 100, height: 100))
        #expect(north.y < 50)
    }
}

@MainActor
struct GuideLegTests {
    let areas = Dictionary(AreaCatalog.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let shinjuku = CLLocationCoordinate2D(latitude: 35.6896, longitude: 139.7006)
    let nakano = CLLocationCoordinate2D(latitude: 35.7056, longitude: 139.6656)

    @Test func neighborsUseTheTableWithTheLine() {
        let leg = GuideModel.leg(fromArea: "shinjuku", toArea: "nakano", from: shinjuku, to: nakano, areas: areas)
        #expect(leg.minutes == 5)
        #expect(leg.walk == false)
        #expect(leg.line?.code == "JC")
    }

    @Test func walkingEdgeFromTableHasNoLine() {
        let shibuya = CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016)
        let daikanyama = CLLocationCoordinate2D(latitude: 35.6494, longitude: 139.7027)
        let leg = GuideModel.leg(fromArea: "shibuya", toArea: "daikanyama", from: shibuya, to: daikanyama, areas: areas)
        #expect(leg.walk == true)
        #expect(leg.line == nil)
        #expect(leg.minutes == 18)
    }

    @Test func unlinkedAreasFallBackToTheEstimate() {
        // Sem ligação na tabela (Shinjuku → Ginza): estimativa de sempre, nunca zero.
        let ginza = CLLocationCoordinate2D(latitude: 35.6717, longitude: 139.7650)
        let leg = GuideModel.leg(fromArea: "shinjuku", toArea: "ginza", from: shinjuku, to: ginza, areas: areas)
        #expect(leg.minutes > 0)
        #expect(leg.line == nil)
        #expect(leg.walk == false)
    }

    @Test func noAreaFallsBackToTheEstimateToo() {
        let leg = GuideModel.leg(fromArea: nil, toArea: nil, from: shinjuku, to: nakano, areas: areas)
        #expect(leg.minutes > 0)
    }

    @Test func stopPinCarriesNumberAndStatus() {
        let stop = GuideModel.GuideStop(id: UUID(), placeId: "j05", name: "Fuunji", at: Date(), number: 2, areaSeal: "新宿",
                                        detail: "", color: .eat, status: .current, isGolden: false, isNight: false,
                                        lat: 35.6873, lng: 139.6994, legMinutes: 9, leaveAt: nil)
        let pin = GuideModel.pin(stop)
        #expect(pin.kind == .today(number: 2, status: .next, label: nil))
        #expect(pin.layer == .today)
        #expect(pin.placeId == "j05")
    }
}
