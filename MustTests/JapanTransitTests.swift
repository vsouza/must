import CoreLocation
import Foundation
import Synchronization
import Testing
@testable import Must

/// No Japão a API do Google não tem trem/metrô (TRANSIT volta `{}`): transporte vem do MapKit, matriz só a pé.
@Suite(.serialized) struct JapanTransitTests {
    private struct FixedETA: RoutesProviding {
        var seconds: TimeInterval
        func eta(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transit: Bool) async throws -> TimeInterval { seconds }
    }

    /// Anota a field mask de cada chamada e responde "sem rede" (nenhuma chamada sai do teste).
    final class MaskRecorder: URLProtocol, @unchecked Sendable {
        static let masks = Mutex<[String]>([])
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let mask = request.value(forHTTPHeaderField: "X-Goog-FieldMask") ?? ""
            Self.masks.withLock { $0.append(mask) }
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        override func stopLoading() {}
    }

    private static func recordingHTTP() -> HTTP {
        MaskRecorder.masks.withLock { $0.removeAll() }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MaskRecorder.self]
        return HTTP(session: URLSession(configuration: config))
    }

    private let nakameguro = CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)
    private let shibuya = CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016)

    @Test func googleTransitOnlyOutsideJapan() {
        #expect(GoogleRoutes.hasTransit(in: .bh))
        #expect(!GoogleRoutes.hasTransit(in: .jp))
        #expect(GoogleRoutes.matrixModes(for: .bh) == ["WALK", "TRANSIT"])
        #expect(GoogleRoutes.matrixModes(for: .jp) == ["WALK"])
    }

    @Test func japanTransitIsMapKitTimeAndNeverAsksGoogle() async {
        let http = Self.recordingHTTP()
        let options = await TravelOptions.build(from: nakameguro, to: shibuya, departAt: Date(), region: .jp,
                                                routes: FixedETA(seconds: 545), apiKey: "test", http: http)
        let transit = options.first { $0.mode == .transit }
        #expect(transit?.source == .mapKit)
        #expect(transit?.minutes == 10)
        #expect(transit?.steps.isEmpty == true)
        #expect(options.map(\.mode) == [.transit, .walk, .taxi])
        #expect(!MaskRecorder.masks.withLock { $0 }.contains { $0.contains("transitDetails") })
    }

    @Test func outsideJapanTransitFallsBackToMapKitWhenRoutesFails() async {
        let http = Self.recordingHTTP()
        let options = await TravelOptions.build(from: nakameguro, to: shibuya, departAt: Date(), region: .bh,
                                                routes: FixedETA(seconds: 300), apiKey: "test", http: http)
        #expect(MaskRecorder.masks.withLock { $0 }.contains { $0.contains("transitDetails") })
        #expect(options.first { $0.mode == .transit }?.source == .mapKit)
    }

    @Test func matrixWithoutModesDoesNothing() async {
        let http = Self.recordingHTTP()
        #expect(await TravelMatrixLoader.load(points: [nakameguro, shibuya], departAt: Date(), day: "2026-11-15",
                                              modes: [], apiKey: "test", http: http) == nil)
        #expect(MaskRecorder.masks.withLock { $0 }.isEmpty)
    }
}
