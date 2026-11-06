import CoreLocation
import Foundation

/// Região automática com N viagens (prompt 28 §3.10, aprovado em 06/11/2026):
/// 1. a viagem cujas datas incluem hoje;
/// 2. senão a mais recente cujo país bate com o do GPS;
/// 3. senão a de casa (`kind = home`).
/// Puro (o `TripStore` chama com o GPS e a hora do app).
enum RegionAuto {
    static func pick(trips: [Trip], now: Date, gpsCountry: String?) -> TripID? {
        let open = trips.filter { !$0.archived }
        // (1) Hoje dentro das datas. Duas ao mesmo tempo (não deveria): a que começou por último.
        let current = open.filter { $0.contains(now) }
        if let trip = current.max(by: { ($0.start ?? "", $0.createdAt) < ($1.start ?? "", $1.createdAt) }) { return trip.id }
        // (2) País do GPS, a mais recente (casa só se for a única daquele país).
        if let gpsCountry {
            let code = gpsCountry.uppercased()
            let sameCountry = open.filter { $0.countryCode.uppercased() == code }
            let trips = sameCountry.filter { $0.kind != .home }
            if let trip = (trips.isEmpty ? sameCountry : trips).max(by: { $0.createdAt < $1.createdAt }) { return trip.id }
        }
        // (3) Casa.
        return open.first { $0.kind == .home }?.id
    }

    /// País do GPS: as caixas dos perfis (`data/countries/<cc>.json`) e, pra país sem perfil, a cidade de uma viagem a
    /// menos de 150 km. Nada de geocoder aqui (sem rede, síncrono).
    static func country(at c: CLLocationCoordinate2D, trips: [Trip]) -> String? {
        if let code = CountryProfile.detect(c) { return code }
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        for trip in trips where !trip.archived {
            for city in trip.cities where city.lat != 0 || city.lng != 0 {
                if here.distance(from: CLLocation(latitude: city.lat, longitude: city.lng)) < 150_000 { return trip.countryCode }
            }
        }
        return nil
    }
}
