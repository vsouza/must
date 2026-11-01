import CoreLocation
import Foundation
import MapKit

/// ETA (MapKit), "saia às" e último trem pra casa.
protocol RoutesProviding: Sendable {
    func eta(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transit: Bool) async throws -> TimeInterval
}

struct RoutesService: RoutesProviding {
    /// `MKDirections.calculateETA` (transporte só pra ETA; a pé tem geometria no `RouteGeometry`).
    func eta(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transit: Bool) async throws -> TimeInterval {
        guard DevOverrides.liveData else { throw ServiceError.liveDataOff }
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: from.latitude, longitude: from.longitude), address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: to.latitude, longitude: to.longitude), address: nil)
        request.transportType = transit ? .transit : .walking
        let response = try await MKDirections(request: request).calculateETA()
        Log.network.info("eta \(transit ? "transporte" : "a pé", privacy: .public): \(Int(response.expectedTravelTime / 60)) min")
        return response.expectedTravelTime
    }

    /// "Saia às" = hora marcada − deslocamento − 5 min.
    static func leaveAt(_ at: Date, travelMinutes: Int) -> Date {
        at.addingTimeInterval(TimeInterval(-(travelMinutes + 5) * 60))
    }
}

struct FakeRoutesService: RoutesProviding {
    var minutes: Double = 12
    func eta(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, transit: Bool) async throws -> TimeInterval { minutes * 60 }
}

/// ETAs já calculados (10 min de validade), pra Hoje e Mapa não pedirem de novo a cada render.
@MainActor
@Observable
final class ETACache {
    private(set) var minutes: [String: Int] = [:]
    @ObservationIgnored private var fetchedAt: [String: Date] = [:]
    @ObservationIgnored private let routes: any RoutesProviding

    init(routes: any RoutesProviding) { self.routes = routes }

    static func key(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, transit: Bool) -> String {
        String(format: "%.3f,%.3f>%.4f,%.4f-%d", a.latitude, a.longitude, b.latitude, b.longitude, transit ? 1 : 0)
    }

    /// Minutos em cache (ou nil) e dispara o cálculo se faltar/vencido.
    func minutes(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D, transit: Bool) -> Int? {
        let key = Self.key(a, b, transit: transit)
        if (fetchedAt[key] ?? .distantPast) < Date().addingTimeInterval(-600) {
            fetchedAt[key] = Date()
            Task { [weak self, routes] in
                guard let seconds = try? await routes.eta(from: a, to: b, transit: transit) else { return }
                self?.minutes[key] = Int((seconds / 60).rounded(.up))
            }
        }
        return minutes[key]
    }
}

/// Último trem pra casa (tabela estática no Japão; horário fixo do metrô em BH).
struct LastTrain: Sendable, Hashable {
    var label: String
    var time: String
}

enum LastTrains {
    private struct Table: Decodable {
        struct Train: Decodable { var line: String; var lineName: String; var from: String; var fromLatin: String; var to: String; var last: String }
        var home: String
        var trains: [Train]
    }

    @MainActor private static var table: Table? = {
        guard let url = Bundle.main.url(forResource: "last-trains", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Table.self, from: data)
    }()

    /// Pro fim do dia em `near` (última parada).
    @MainActor
    static func home(region: Region, near: CLLocationCoordinate2D?, transit: TransitMap) -> LastTrain? {
        if region == .bh {
            return transit.lines.first?.lastTrain.map { LastTrain(label: "Metrô até", time: $0) }
        }
        guard let table, let near else { return nil }
        // Estação da tabela mais perto da última parada.
        let here = CLLocation(latitude: near.latitude, longitude: near.longitude)
        let best = table.trains.compactMap { train -> (Table.Train, CLLocationDistance)? in
            guard let station = transit.stations.first(where: { $0.name == train.from }) else { return nil }
            return (train, CLLocation(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude).distance(from: here))
        }.min { $0.1 < $1.1 }
        guard let (train, distance) = best, distance < 6000 else { return nil }
        return LastTrain(label: "Último \(train.lineName) \(train.fromLatin) → \(table.home)", time: train.last)
    }
}
