import CoreLocation
import MapKit

/// Loja de fora do board pro Presente (Local): `MKLocalSearch` (MapKit, sem chave) dentro da cidade da viagem. A região de busca
/// segue o `WantOrigin` (GPS só dentro da cidade; senão a cidade de hoje ou a primeira da viagem), nunca o GPS do Brasil
/// quando a viagem é o Japão.
enum GiftStoreSearch {
    struct Hit: Hashable, Sendable, Identifiable {
        var name: String
        var lat: Double
        var lng: Double
        var address: String
        var id: String { "\(name)|\(lat)|\(lng)" }
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    }

    /// Lado do quadro de busca (cabe um bairro grande e vizinhos).
    static let regionMeters: Double = 8_000

    /// Centro da busca: o GPS se estiver na cidade; senão o centro da cidade.
    static func center(gps: CLLocationCoordinate2D?, cityCenter: CLLocationCoordinate2D, hasCurrentCity: Bool) -> CLLocationCoordinate2D {
        WantOrigin.resolve(gps: gps, cityCenter: cityCenter, hasCurrentCity: hasCurrentCity, areaHint: nil, planArea: nil).origin
    }

    static func searchRegion(gps: CLLocationCoordinate2D?, cityCenter: CLLocationCoordinate2D, hasCurrentCity: Bool) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center(gps: gps, cityCenter: cityCenter, hasCurrentCity: hasCurrentCity),
                           latitudinalMeters: regionMeters, longitudinalMeters: regionMeters)
    }

    /// Centro da cidade de hoje, ou da primeira da viagem; sem viagem, o centro da região.
    @MainActor
    static func cityCenter(trip: TripInfo?, now: Date, region: Region) -> (center: CLLocationCoordinate2D, current: Bool) {
        let city = trip?.city(on: now, calendar: region.calendar)
        let center = city.flatMap { $0.hasCoordinate ? CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) : nil }
            ?? trip?.cities.first(where: \.hasCoordinate).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            ?? region.defaultCenter
        return (center, QueroEnv.tripStarted(trip, now: now, calendar: region.calendar))
    }

    /// Os de fora: tira o que já é loja do board (mesmo nome, ou a menos de 100 m com nome parecido) e limita a lista.
    static func outside(_ hits: [Hit], board: [(name: String, lat: Double, lng: Double)], limit: Int = 12) -> [Hit] {
        let folded = board.map { (WantCategory.fold($0.name), CLLocation(latitude: $0.lat, longitude: $0.lng)) }
        var seen = Set<String>()
        var out: [Hit] = []
        for hit in hits {
            let key = WantCategory.fold(hit.name)
            let here = CLLocation(latitude: hit.lat, longitude: hit.lng)
            let duplicate = folded.contains { $0.0 == key || ($0.1.distance(from: here) < 100 && ($0.0.contains(key) || key.contains($0.0))) }
            guard !duplicate, seen.insert(hit.id).inserted else { continue }
            out.append(hit)
            if out.count == limit { break }
        }
        return out
    }

    /// Busca única (ao enviar, nunca a cada tecla). Sem rede ou com erro: vazio.
    static func search(_ query: String, region: MKCoordinateRegion) async -> [Hit] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.region = region
        request.resultTypes = .pointOfInterest
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap { item in
            guard let name = item.name, !name.isEmpty else { return nil }
            let c = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(c) else { return nil }
            let address = [item.placemark.thoroughfare, item.placemark.subThoroughfare, item.placemark.locality]
                .compactMap { $0 }.joined(separator: " ")
            return Hit(name: name, lat: c.latitude, lng: c.longitude, address: address)
        }
    }
}
