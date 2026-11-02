import CoreLocation
import Foundation

/// Minutos reais entre pontos do dia (Routes `computeRouteMatrix`, a pé e transporte), pedidos antes de o solver rodar.
/// O solver continua puro: lê este mapa; sem par na matriz, usa a estimativa de sempre (`DaySolver.leg`).
struct TravelMatrix: Sendable, Equatable, Codable {
    /// "lat,lng>lat,lng" com 5 casas (~1 m).
    var walk: [String: Int] = [:]
    var transit: [String: Int] = [:]

    static func key(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.5f,%.5f>%.5f,%.5f", a.latitude, a.longitude, b.latitude, b.longitude)
    }

    var isEmpty: Bool { walk.isEmpty && transit.isEmpty }

    /// Perna com o tempo real: a pé se `km` cabe no andar máximo e há tempo a pé; senão, transporte se houver.
    /// `nil` = não há dado pra esse par (o solver faz a estimativa).
    func leg(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, km: Double, walkMaxKm: Double) -> Leg? {
        let k = Self.key(a, b)
        if km <= walkMaxKm, let minutes = walk[k] { return Leg(km: km, mode: .walk, minutes: minutes) }
        if km > walkMaxKm, let minutes = transit[k] { return Leg(km: km, mode: .metro, minutes: minutes) }
        return nil
    }
}
