import CoreLocation
import MapKit
import Observation

/// Geometria da rota do dia: `MKDirections` a pé entre paradas próximas, linha reta no resto.
/// Nunca bloqueia: enquanto não chega (ou sem dados ao vivo), a perna é desenhada reta.
@MainActor
@Observable
final class RouteGeometry {
    private(set) var legs: [String: [CLLocationCoordinate2D]] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    static func key(_ a: String, _ b: String) -> String { "\(a)>\(b)" }

    func path(from a: Place, to b: Place) -> [CLLocationCoordinate2D] {
        legs[Self.key(a.id, b.id)] ?? [a.coordinate, b.coordinate]
    }

    /// Pede as pernas a pé que faltam (cada par uma vez só).
    func request(stops: [Place], walkMaxKm: Double) {
        guard DevOverrides.liveData, stops.count > 1 else { return }
        for (a, b) in zip(stops, stops.dropFirst()) {
            let key = Self.key(a.id, b.id)
            guard !requested.contains(key) else { continue }
            requested.insert(key)
            guard DaySolver.streetKm(a.coordinate, b.coordinate) <= walkMaxKm else { continue } // metrô: reta
            let from = a.coordinate, to = b.coordinate
            Task { [weak self] in
                let request = MKDirections.Request()
                request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
                request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
                request.transportType = .walking
                do {
                    let response = try await MKDirections(request: request).calculate()
                    guard let polyline = response.routes.first?.polyline else { return }
                    var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
                    polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
                    self?.legs[key] = coords
                    Log.network.info("rota a pé \(key, privacy: .public): \(coords.count) pontos")
                } catch {
                    Log.network.error("rota a pé \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
