import CoreLocation
import Observation

/// Direção pra onde o aparelho aponta (bússola). Fica fora do `LocationService`: muda várias vezes por segundo
/// e só o cone do "você" no mapa lê (prompt 18 · A.2). Quem lê posição não é invalidado por ela.
@MainActor
@Observable
final class Compass {
    /// Graus, norte = 0. Nil sem bússola ou antes da primeira leitura.
    private(set) var heading: CLLocationDirection?

    /// Chamado pelo `LocationService` a cada leitura do sensor; só publica se mudou.
    func receive(heading value: CLLocationDirection?) {
        guard heading != value else { return }
        heading = value
    }
}

/// GPS do app. Atualiza a cada ~50 m, só com o app em uso. Respeita o GPS simulado do menu escondido.
@MainActor
@Observable
final class LocationService: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    /// Última posição real do aparelho. Só muda quando o aparelho andou ≥ 50 m (ver `publishable`).
    private(set) var device: CLLocation?
    /// Posição simulada (menu escondido), se ligada.
    private(set) var simulated: CLLocation?
    /// Bússola: observável à parte, pra não invalidar quem só lê a posição.
    let compass = Compass()

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var isUpdating = false

    /// Distância mínima pra publicar uma nova posição.
    nonisolated static let distanceFilter: CLLocationDistance = 50

    /// Decide se uma leitura do GPS vira `device`: nil quando não tem precisão ou não andou ≥ 50 m.
    /// Regra pura (testada): o filtro roda antes de qualquer publicação.
    static func publishable(_ reading: CLLocation, after previous: CLLocation?) -> CLLocation? {
        guard reading.horizontalAccuracy >= 0 else { return nil }
        if let previous, reading.distance(from: previous) < distanceFilter { return nil }
        return reading
    }

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = Self.distanceFilter
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .fitness
        refreshOverrides()
        #if DEBUG
        scheduleDebugHops()
        #endif
    }

    #if DEBUG
    /// `-debugGPSHop "8:35.6909,139.7003;20:-19.9385,-43.9343"` (rodada 23 · G): aos 8 s o GPS simulado pula pra Tóquio,
    /// aos 20 s volta pra BH. Com a região no automático, é a troca de região pelo GPS no meio do uso (sheet aberta,
    /// texto pela metade) — o caso suspeito do "digitar na tela de adicionar quebra".
    private func scheduleDebugHops() {
        let hops = Self.parseHops(DebugFlags.string("debugGPSHop"))
        guard !hops.isEmpty else { return }
        Task { @MainActor [weak self] in
            let start = Date()
            for hop in hops {
                let wait = hop.after - Date().timeIntervalSince(start)
                if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
                Log.location.info("debugGPSHop → \(hop.lat), \(hop.lng)")
                self?.simulated = CLLocation(latitude: hop.lat, longitude: hop.lng)
            }
        }
    }

    /// "8:35.69,139.70;20:-19.93,-43.93" → [(8, 35.69, 139.70), (20, -19.93, -43.93)], em ordem.
    static func parseHops(_ text: String?) -> [(after: Double, lat: Double, lng: Double)] {
        guard let text else { return [] }
        return text.split(separator: ";").compactMap { part in
            let pieces = part.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2, let after = Double(pieces[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let coord = pieces[1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard coord.count == 2 else { return nil }
            return (after, coord[0], coord[1])
        }.sorted { $0.after < $1.after }
    }
    #endif

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
            // Só avisa a cada 10° (antes 8°): a bússola não precisa de mais que isso.
            manager.headingFilter = 10
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
        guard let last = locations.last, let next = Self.publishable(last, after: device) else { return }
        device = next
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
        MainActor.assumeIsolated { compass.receive(heading: value) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.location.error("GPS: \(error.localizedDescription, privacy: .public)")
    }
}
