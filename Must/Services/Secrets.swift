import Foundation

/// Lê `Secrets.plist` do bundle (gitignored; modelo em `Secrets.example.plist`).
/// Nunca crasha: chave ausente ou vazia → `nil`.
enum Secrets {
    enum Key: String, CaseIterable {
        case googlePlaces = "GOOGLE_PLACES_KEY"
        case anthropic = "ANTHROPIC_KEY"
        case protomaps = "PROTOMAPS_KEY"
        case mapTilesURL = "MAP_TILES_URL"
        case foursquare = "FOURSQUARE_KEY"
        case redditClientId = "REDDIT_CLIENT_ID"
        /// RapidAPI (AeroDataBox): status de voo. Só ela; sem chave, o voo mostra o horário programado.
        case aerodatabox = "AERODATABOX_KEY"
    }

    static subscript(key: Key) -> String? {
        guard let value = values[key.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    static var googlePlacesKey: String? { self[.googlePlaces] }
    static var anthropicKey: String? { self[.anthropic] }
    /// Tiles hospedados pela Protomaps, só quando não há `MAP_TILES_URL`.
    static var protomapsKey: String? { self[.protomaps] }
    /// Bucket R2 público com os mapas offline por cidade (`scripts/tiles-upload.sh`).
    static var mapTilesURL: String? { self[.mapTilesURL] }
    static var foursquareKey: String? { self[.foursquare] }
    static var redditClientId: String? { self[.redditClientId] }
    static var aerodataboxKey: String? { self[.aerodatabox] }

    private static let values: [String: String] = load(from: .main)

    static func load(from bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return [:] }
        return dict.compactMapValues { $0 as? String }
    }
}
