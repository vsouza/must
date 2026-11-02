import Foundation

// "Por perto, agora" (prompt 14 · B): tipos compartilhados pelo serviço, o cache e o ranking.

/// De onde veio um lugar. `.board` é o seu próprio board (não vem de rede).
enum NearbySource: String, Codable, Sendable, CaseIterable {
    case board, google, wikipedia, foursquare

    /// Chip mono da linha ("G", "Wiki", "FSQ").
    var chip: String? {
        switch self {
        case .board: nil
        case .google: "G"
        case .wikipedia: "Wiki"
        case .foursquare: "FSQ"
        }
    }
}

/// Um lugar das fontes externas (Google Nearby, Wikipedia geosearch, Foursquare), já fundido quando as fontes concordam.
struct NearbyPlace: Codable, Hashable, Sendable {
    var name: String
    var lat: Double
    var lng: Double
    var sources: [NearbySource]
    var googlePlaceId: String? = nil
    var fsqId: String? = nil
    /// 0–5 (o Foursquare vem em 0–10 e é convertido).
    var rating: Double? = nil
    var ratingCount: Int? = nil
    var openNow: Bool? = nil
    /// Tipo principal (Google `primaryType`) ou nome da categoria (Foursquare).
    var category: String? = nil
    /// Foursquare: 0–1. Acima de 0,9 é "em alta neste horário".
    var popularity: Double? = nil
    /// Wikipedia: idioma do artigo ("pt", "ja", "en").
    var articleLang: String? = nil

    /// Chave estável dentro de uma busca (só pra listas e testes).
    var id: String { "\(googlePlaceId ?? fsqId ?? articleLang.map { "w\($0)-\(name)" } ?? name)" }
}

/// Resultado de uma rodada das fontes. `complete` = nenhuma fonte falhou (só resposta completa vai pro cache).
struct NearbyFetch: Sendable {
    var places: [NearbyPlace]
    var complete: Bool
}

/// O que ficou no cache pra uma célula (~500 m).
struct NearbyBatch: Codable, Sendable {
    var cell: String
    var fetchedAt: Date
    var places: [NearbyPlace]
}

enum NearbyCell {
    /// Célula de ~500 m por região: a chave do cache (30 min).
    static func key(lat: Double, lng: Double, region: Region) -> String {
        let step = 0.0045 // ~500 m em latitude
        let lngStep = step / max(0.2, cos(lat * .pi / 180))
        return "\(region.rawValue)-\(Int((lat / step).rounded(.down)))-\(Int((lng / lngStep).rounded(.down)))"
    }
}
