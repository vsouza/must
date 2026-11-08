import CoreLocation
import Foundation

// Quero… (prompt 31 · 2): de onde a busca sai. Nunca "perto" do Brasil numa viagem ao Japão: o GPS só vale dentro da cidade da
// viagem; fora dela, o bairro da capa (ou escolhido), senão a cidade de hoje, senão a primeira cidade da viagem (viagem futura).

enum WantOrigin {
    enum Basis: String, Sendable {
        /// GPS dentro da cidade da viagem.
        case gps
        /// Centro do bairro da capa ou escolhido à mão.
        case area
        /// Centro da cidade de hoje.
        case todayCity
        /// Viagem que ainda não começou: a primeira cidade.
        case firstCity
    }

    struct Resolved: Sendable {
        var origin: CLLocationCoordinate2D
        var basis: Basis
        /// Bairro que manda na busca (`nil` = GPS puro ou o centro da cidade).
        var area: Area?
    }

    /// Dentro da cidade: raio da cidade da viagem (Tóquio inteira cabe).
    static let cityKm: Double = 40

    /// `cityCenter` = cidade de hoje, ou a primeira da viagem; `hasCurrentCity` diz qual dos dois é.
    static func resolve(gps: CLLocationCoordinate2D?, cityCenter: CLLocationCoordinate2D, hasCurrentCity: Bool, areaHint: Area?,
                        planArea: Area?) -> Resolved {
        if let gps, DaySolver.streetKm(gps, cityCenter) < cityKm {
            return Resolved(origin: gps, basis: .gps, area: planArea)
        }
        // Bairro de outra cidade (a capa ficou com o do Brasil, por exemplo) não vale.
        let area = [areaHint, planArea].compactMap { $0 }.first { DaySolver.streetKm($0.centroid.clCoordinate, cityCenter) < cityKm }
        if let area { return Resolved(origin: area.centroid.clCoordinate, basis: .area, area: area) }
        return Resolved(origin: cityCenter, basis: hasCurrentCity ? .todayCity : .firstCity, area: nil)
    }
}
