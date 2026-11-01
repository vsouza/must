import CoreLocation
import Observation

/// GPS do app. Atualiza a cada ~50 m, só com o app em uso. Respeita o GPS simulado do menu escondido.
@MainActor
@Observable
final class LocationService: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    /// Última posição real do aparelho.
    private(set) var device: CLLocation?
    /// Posição simulada (menu escondido), se ligada.
    private(set) var simulated: CLLocation?
    /// Direção pra onde o aparelho aponta (graus, norte = 0), pro cone do "você" no mapa.
    private(set) var heading: CLLocationDirection?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var isUpdating = false

    /// Distância mínima pra publicar uma nova posição.
    static let distanceFilter: CLLocationDistance = 50

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = Self.distanceFilter
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .fitness
        refreshOverrides()
    }

    /// Posição usada pelo app: simulada (se ligada) ou a real.
    var current: CLLocation? { simulated ?? device }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }
    var isSimulating: Bool { simulated != nil }

    func requestAuthorization() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            start()
        }
    }

    func start() {
        guard isAuthorized, !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 8
            manager.startUpdatingHeading()
        }
        Log.location.info("GPS ligado")
    }

    func stop() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        Log.location.info("GPS desligado")
    }

    /// Relê o GPS simulado do `DevOverrides` (chamar ao mudar no menu escondido).
    func refreshOverrides() {
        simulated = DevOverrides.simulatedCoordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    fileprivate func handle(authorization status: CLAuthorizationStatus) {
        authorization = status
        if isAuthorized { start() } else { stop() }
    }

    fileprivate func handle(locations: [CLLocation]) {
        guard let last = locations.last, last.horizontalAccuracy >= 0 else { return }
        if let previous = device, last.distance(from: previous) < Self.distanceFilter { return }
        device = last
    }
}

extension LocationService: CLLocationManagerDelegate {
    // O CLLocationManager foi criado na main thread, então os callbacks chegam nela.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { handle(authorization: status) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { handle(locations: locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        MainActor.assumeIsolated { heading = value }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.location.error("GPS: \(error.localizedDescription, privacy: .public)")
    }
}
