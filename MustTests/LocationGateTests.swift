import CoreLocation
import Foundation
import Observation
import Testing
@testable import Must

/// Prompt 18 · A.2: GPS só publica movimento ≥ 50 m; bússola separada (não invalida quem lê posição).


@MainActor
struct LocationGateTests {
    private let base = CLLocation(latitude: -23.5505, longitude: -46.6333)

    private func moved(meters: Double, accuracy: Double = 10) -> CLLocation {
        // 1° de latitude ≈ 111.32 km.
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: base.coordinate.latitude + meters / 111_320, longitude: base.coordinate.longitude),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: Date())
    }

    @Test func leituraAbaixoDe50MNaoPublica() {
        #expect(LocationService.publishable(moved(meters: 20), after: base) == nil)
        #expect(LocationService.publishable(moved(meters: 49), after: base) == nil)
    }

    @Test func leituraAcimaDe50MPublica() {
        #expect(LocationService.publishable(moved(meters: 80), after: base) != nil)
    }

    @Test func primeiraLeituraPublica() {
        #expect(LocationService.publishable(base, after: nil) != nil)
    }

    @Test func leituraSemPrecisaoNaoPublica() {
        #expect(LocationService.publishable(moved(meters: 500, accuracy: -1), after: base) == nil)
    }

    @Test func bussolaNaoInvalidaQuemLePosicao() {
        let service = LocationService()
        let flag = ObservedFlag()
        withObservationTracking { _ = service.current } onChange: { flag.fired = true }
        service.compass.receive(heading: 120)
        #expect(flag.fired == false)
        #expect(service.compass.heading == 120)
    }

    @Test func bussolaInvalidaSoQuemLeBussola() {
        let service = LocationService()
        let flag = ObservedFlag()
        withObservationTracking { _ = service.compass.heading } onChange: { flag.fired = true }
        service.compass.receive(heading: 45)
        #expect(flag.fired)
    }
}
