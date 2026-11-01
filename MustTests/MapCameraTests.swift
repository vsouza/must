import CoreLocation
import Foundation
import Testing
@testable import Must

/// Abertura do mapa (prompt 11): perto → bairro; nada a 500 m → o mais perto (próxima parada se < 3×).
struct MapCameraPlannerTests {
    let here = CLLocation(latitude: -19.9318, longitude: -43.9500) // Santo Agostinho

    private func point(north meters: Double, id: String, next: Bool = false) -> MapCandidate {
        MapCandidate(placeId: id, coordinate: CLLocationCoordinate2D(latitude: here.coordinate.latitude + meters / 111_000,
                                                                    longitude: here.coordinate.longitude), isNextStop: next)
    }

    @Test func somethingWithin500mOpensAtNeighborhoodScale() {
        let focus = MapCameraPlanner.focus(here: here, candidates: [point(north: 300, id: "a"), point(north: 2000, id: "b")])
        #expect(focus == .neighborhood(center: .init(here.coordinate)))
    }

    @Test func nothingNearZoomsToNearest() {
        let focus = MapCameraPlanner.focus(here: here, candidates: [point(north: 800, id: "a"), point(north: 5000, id: "b", next: true)])
        #expect(focus.target?.placeId == "a")
        #expect(focus.target?.isNextStop == false)
    }

    @Test func nextStopWinsWhenWithinThreeTimesTheNearest() {
        let focus = MapCameraPlanner.focus(here: here, candidates: [point(north: 800, id: "a"), point(north: 2100, id: "next", next: true)])
        #expect(focus.target?.placeId == "next")
        #expect((focus.target?.meters ?? 0) > 2000)
    }

    @Test func noCandidatesStaysOnUser() {
        #expect(MapCameraPlanner.focus(here: here, candidates: []) == .neighborhood(center: .init(here.coordinate)))
    }

    @Test func fitKeepsBothPointsInsideTheFreeArea() {
        let a = here.coordinate
        let b = CLLocationCoordinate2D(latitude: -19.9226, longitude: -43.9436)
        let size = CGSize(width: 402, height: 874)
        let (center, zoom) = MapLibreView.Coordinator.fit([a, b], size: size, top: 290, bottom: 340, sides: 56)
        // Projeta de volta e confere que os dois caem entre as folgas.
        func screen(_ c: CLLocationCoordinate2D) -> CGPoint {
            func world(_ c: CLLocationCoordinate2D) -> CGPoint {
                let s = sin(c.latitude * .pi / 180)
                return CGPoint(x: (c.longitude + 180) / 360 * 512, y: (0.5 - log((1 + s) / (1 - s)) / (4 * .pi)) * 512)
            }
            let scale = pow(2, zoom)
            let w = world(c), o = world(center)
            return CGPoint(x: size.width / 2 + (w.x - o.x) * scale, y: size.height / 2 + (w.y - o.y) * scale)
        }
        for p in [screen(a), screen(b)] {
            #expect(p.y >= 289 && p.y <= 874 - 339)
            #expect(p.x >= 55 && p.x <= 402 - 55)
        }
    }
}

@MainActor
struct MapCameraControllerTests {
    @Test func gestureHoldsTheCamera() {
        let cam = MapCameraController()
        let here = CLLocation(latitude: -19.9385, longitude: -43.9343)
        cam.evaluate(here: here, candidates: [], fallback: here.coordinate, force: true)
        let first = cam.command?.id
        cam.userGestured()
        cam.cameraIdle()
        cam.evaluate(here: CLLocation(latitude: -19.9300, longitude: -43.9343), candidates: [], fallback: here.coordinate, force: true)
        #expect(cam.command?.id == first) // 20 s depois do gesto: não mexe
        cam.resumeAuto(here: here, candidates: [], fallback: here.coordinate)
        #expect(cam.command?.id != first) // ⌖ volta ao automático
    }

    @Test func smallMovesDoNotReevaluate() {
        let cam = MapCameraController()
        let here = CLLocation(latitude: -19.9385, longitude: -43.9343)
        cam.evaluate(here: here, candidates: [], fallback: here.coordinate, force: true)
        let first = cam.command?.id
        cam.evaluate(here: CLLocation(latitude: -19.9380, longitude: -43.9343), candidates: [], fallback: here.coordinate, force: false)
        #expect(cam.command?.id == first) // ~55 m
        cam.evaluate(here: CLLocation(latitude: -19.9370, longitude: -43.9343), candidates: [], fallback: here.coordinate, force: false)
        #expect(cam.command?.id != first) // ~165 m
    }
}

struct MapTilesAreaTests {
    func area(_ lat: Double, _ lng: Double, _ region: Region) -> String? {
        let c = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        return MapTiles.areas.first { $0.region == region && $0.contains(c) }?.name
    }

    @Test func areasCoverTheTrips() {
        #expect(area(-19.9385, -43.9343, .bh) == "bh")            // Savassi
        #expect(area(-20.125, -44.219, .bh) == "bh-inhotim")      // Inhotim
        #expect(area(35.6442, 139.6985, .jp) == "jp-tokyo")       // Naka-Meguro
        #expect(area(35.0037, 135.7788, .jp) == "jp-kansai")      // Gion
        #expect(area(35.5171, 138.7514, .jp) == "jp-fuji")        // Kawaguchiko
        #expect(area(35.3606, 138.7274, .jp) == "jp-fuji")        // Fuji · 5ª estação (Subaru Line)
    }

    @Test func pickUsesTheContainingFile() throws {
        // Só quando os tiles estão no bundle do app (gerados pelo scripts/tiles.sh).
        guard Bundle.main.url(forResource: "bh-inhotim", withExtension: "pmtiles", subdirectory: "tiles") != nil else { return }
        #expect(MapTiles.pick(region: .bh, near: CLLocationCoordinate2D(latitude: -20.125, longitude: -44.219)).name == "bh-inhotim")
        #expect(MapTiles.pick(region: .bh, near: CLLocationCoordinate2D(latitude: -20.04, longitude: -44.09)).name == "bh")
        #expect(MapTiles.pick(region: .jp, near: CLLocationCoordinate2D(latitude: 35.5171, longitude: 138.7514)).name == "jp-fuji")
    }
}

private extension MapTiles {
    var name: String? { if case .bundled(let n, _) = self { n } else { nil } }
}
