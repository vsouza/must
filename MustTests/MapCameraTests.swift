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
        MapPack.containing(CLLocationCoordinate2D(latitude: lat, longitude: lng), region: region)?.id
    }

    @Test func catalogLoadsFromBundle() {
        let ids = MapPack.catalog.map(\.id)
        #expect(ids.count == 10) // + it-roma (prompt 24, v8/E)
        #expect(Set(ids).count == ids.count)
        for pack in MapPack.catalog {
            #expect(pack.bbox.count == 4 && pack.bbox[0] < pack.bbox[2] && pack.bbox[1] < pack.bbox[3], "\(pack.id)")
            #expect(pack.contains(pack.centerCoordinate), "\(pack.id) centro fora do recorte")
        }
    }

    @Test func areasCoverTheTrips() {
        #expect(area(-19.9385, -43.9343, .bh) == "bh")            // Savassi
        #expect(area(-19.8516, -43.9686, .bh) == "bh")            // Pampulha
        #expect(area(-19.9856, -43.8467, .bh) == "bh")            // Nova Lima
        #expect(area(-20.125, -44.219, .bh) == "bh-inhotim")      // Inhotim
        #expect(area(35.6442, 139.6985, .jp) == "jp-tokyo")       // Naka-Meguro
        #expect(area(35.7033, 139.5797, .jp) == "jp-tokyo")       // Kichijoji
        #expect(area(35.5494, 139.7798, .jp) == "jp-tokyo")       // Haneda
        #expect(area(35.0037, 135.7788, .jp) == "jp-kansai")      // Gion
        #expect(area(34.8893, 135.8077, .jp) == "jp-kansai")      // Uji
        #expect(area(35.5171, 138.7514, .jp) == "jp-fuji")        // Kawaguchiko
        #expect(area(35.3606, 138.7274, .jp) == "jp-fuji")        // Fuji · 5ª estação (Subaru Line)
        #expect(area(34.6687, 135.5013, .jp) == "jp-osaka")       // Dotonbori
        #expect(area(35.3167, 139.5358, .jp) == "jp-yokohama")    // Kamakura · Daibutsu
        #expect(area(36.7580, 139.5989, .jp) == "jp-nikko")       // Toshogu
        #expect(area(34.8394, 134.6939, .jp) == "jp-himeji")      // castelo
    }

    let inhotim = CLLocationCoordinate2D(latitude: -20.125, longitude: -44.219)
    let fakeDir = URL(filePath: "/tmp/tiles")
    let r2 = URL(string: "https://pub-x.r2.dev")!

    func local(_ ids: Set<String>) -> (String) -> URL? {
        { id in ids.contains(id) ? self.fakeDir.appending(path: "\(id).pmtiles") : nil }
    }

    @Test func downloadedFileWins() {
        let t = MapTiles.pick(region: .bh, near: inhotim, local: local(["bh", "bh-inhotim"]), remoteBase: r2, hostedKey: nil)
        #expect(t == .local(name: "bh-inhotim", url: fakeDir.appending(path: "bh-inhotim.pmtiles")))
    }

    @Test func notDownloadedStreamsTheSameFileFromR2() {
        let t = MapTiles.pick(region: .bh, near: inhotim, local: local(["bh"]), remoteBase: r2, hostedKey: nil)
        #expect(t == .remote(name: "bh-inhotim", url: r2.appending(path: "bh-inhotim.pmtiles")))
        #expect(t.sourceURL == "pmtiles://https://pub-x.r2.dev/bh-inhotim.pmtiles")
    }

    @Test func outsideEveryPackUsesTheNearest() {
        let confins = CLLocationCoordinate2D(latitude: -19.6337, longitude: -43.9686) // aeroporto, fora do recorte
        #expect(MapTiles.pick(region: .bh, near: confins, local: local([]), remoteBase: r2, hostedKey: nil).name == "bh")
        #expect(MapTiles.pick(region: .bh, near: confins, local: local(["bh"]), remoteBase: r2, hostedKey: nil)
            == .local(name: "bh", url: fakeDir.appending(path: "bh.pmtiles")))
        let narita = CLLocationCoordinate2D(latitude: 35.772, longitude: 140.3929)
        #expect(MapTiles.pick(region: .jp, near: narita, local: local([]), remoteBase: r2, hostedKey: nil).name == "jp-tokyo")
    }

    @Test func offlineWithoutServerFallsBackToNearestDownload() {
        let t = MapTiles.pick(region: .jp, near: CLLocationCoordinate2D(latitude: 35.0037, longitude: 135.7788),
                              local: local(["jp-tokyo"]), remoteBase: nil, hostedKey: "k")
        #expect(t.name == "jp-tokyo")
        #expect(MapTiles.pick(region: .jp, near: inhotim, local: local([]), remoteBase: nil, hostedKey: "k") == .hosted(key: "k"))
        #expect(MapTiles.pick(region: .jp, near: inhotim, local: local([]), remoteBase: nil, hostedKey: nil) == .none)
    }

    @Test func manifestDecodesScriptOutput() throws {
        let json = #"{"packs": [{"id": "bh", "bytes": 11532865, "sha256": "9ca9", "build": "20261102"}]}"#
        let manifest = try JSONDecoder().decode(MapPackManifest.self, from: Data(json.utf8))
        #expect(manifest["bh"]?.bytes == 11_532_865)
        #expect(manifest["jp-tokyo"] == nil)
        #expect(OfflineMapsView.buildDate("20261102") == "2 nov 2026")
    }

    @Test func sha256MatchesShasum() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "sha-test.bin")
        try Data("must".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try OfflineMaps.sha256(of: url) == "4137b01e139589b7a1d3b3fc4da031d8ce5bb415808734e970c3a58ea0e98f0f") // shasum -a 256
    }
}

struct MapStyleWriteTests {
    @Test func writesStyleForEverySource() throws {
        let r2 = URL(string: "https://pub-x.r2.dev/bh.pmtiles")!
        for tiles: MapTiles in [.remote(name: "bh", url: r2), .local(name: "bh", url: URL(filePath: "/tmp/bh.pmtiles")), .none] {
            let url = try #require(MapStyleLoader.styleURL(region: .bh, tiles: tiles), "\(tiles)")
            let style = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
            #expect(style?["layers"] != nil)
        }
    }
}
