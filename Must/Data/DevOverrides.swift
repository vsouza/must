import CoreLocation
import Foundation

/// Ajustes do menu escondido: valem pro aparelho (não por região) e ficam no UserDefaults.
/// As chaves são as mesmas usadas pelos `@AppStorage` da sheet Região.
enum DevOverrides {
    enum Key {
        static let liveData = "dev.liveData"
        static let simDateOn = "dev.simDateOn"
        static let simDate = "dev.simDate"
        static let simSetAt = "dev.simSetAt"
        static let simGPSOn = "dev.simGPSOn"
        static let simLat = "dev.simLat"
        static let simLng = "dev.simLng"
    }

    private static var defaults: UserDefaults { .standard }

    /// "Dados ao vivo" (Places, tempo, Flickr). Desligado → só cache. Padrão: ligado.
    static var liveData: Bool {
        get { defaults.object(forKey: Key.liveData) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.liveData) }
    }

    // MARK: Data simulada

    /// Começa a simular a partir de `date`; o relógio continua andando a partir dali.
    static func simulate(date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.simDate)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.simSetAt)
        defaults.set(true, forKey: Key.simDateOn)
    }

    static func stopSimulatingDate() {
        defaults.set(false, forKey: Key.simDateOn)
    }

    static var simulatedNow: Date? {
        guard defaults.bool(forKey: Key.simDateOn) else { return nil }
        let base = defaults.double(forKey: Key.simDate)
        let setAt = defaults.double(forKey: Key.simSetAt)
        guard base > 0 else { return nil }
        let elapsed = setAt > 0 ? Date().timeIntervalSince1970 - setAt : 0
        return Date(timeIntervalSince1970: base + max(0, elapsed))
    }

    // MARK: GPS simulado

    static func simulate(coordinate: CLLocationCoordinate2D) {
        defaults.set(coordinate.latitude, forKey: Key.simLat)
        defaults.set(coordinate.longitude, forKey: Key.simLng)
        defaults.set(true, forKey: Key.simGPSOn)
    }

    static func stopSimulatingGPS() {
        defaults.set(false, forKey: Key.simGPSOn)
    }

    static var simulatedCoordinate: CLLocationCoordinate2D? {
        guard defaults.bool(forKey: Key.simGPSOn) else { return nil }
        let c = CLLocationCoordinate2D(latitude: defaults.double(forKey: Key.simLat),
                                       longitude: defaults.double(forKey: Key.simLng))
        return CLLocationCoordinate2DIsValid(c) ? c : nil
    }

    /// Lugares prontos pro GPS simulado.
    static let gpsPresets: [(name: String, coordinate: CLLocationCoordinate2D)] = [
        ("Savassi", CLLocationCoordinate2D(latitude: -19.9385, longitude: -43.9343)),
        ("Centro BH", CLLocationCoordinate2D(latitude: -19.9191, longitude: -43.9386)),
        ("Pampulha", CLLocationCoordinate2D(latitude: -19.8517, longitude: -43.9733)),
        ("Naka-Meguro", CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6985)),
        ("Shibuya", CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016)),
        ("Kyoto", CLLocationCoordinate2D(latitude: 35.0037, longitude: 135.7788)),
    ]
}

/// Relógio do app. Todo "agora" passa por aqui pra respeitar a data simulada.
/// (Não se chama `Clock` pra não esconder o protocolo `Clock` da biblioteca padrão.)
enum AppClock {
    static var now: Date { DevOverrides.simulatedNow ?? Date() }
}
