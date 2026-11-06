import CoreLocation
import Foundation
import SwiftUI

// Contrato da RODADA-23: filmes gravados perto de um lugar (Wikidata P915/P840, sem chave; agente A).

struct Film: Identifiable, Hashable, Sendable, Codable {
    /// QID do Wikidata ("Q193756").
    var id: String
    var title: String
    var year: Int?
    var director: String?
    /// Onde foi gravado (rótulo do local no Wikidata), pra a linha de meta.
    var location: String?
    var distanceMeters: Double?
    var url: URL?
    /// "filmado" (P915) ou "ambientado" (P840). Aditivo ao contrato.
    var relation: String?
}

protocol FilmsProviding: Sendable {
    /// Filmes gravados até `radiusKm` do ponto. Cache primeiro; sem rede, só o cache; nunca lança.
    func films(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async -> [Film]
}

/// Stub do contrato: nenhum filme.
struct FilmsStub: FilmsProviding {
    init() {}
    func films(near coordinate: CLLocationCoordinate2D, radiusKm: Double) async -> [Film] { [] }
}

private struct FilmsKey: EnvironmentKey {
    static var defaultValue: any FilmsProviding { FilmsStub() }
}

extension EnvironmentValues {
    var films: any FilmsProviding {
        get { self[FilmsKey.self] }
        set { self[FilmsKey.self] = newValue }
    }
}
