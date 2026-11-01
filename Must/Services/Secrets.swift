import Foundation

/// Lê `Secrets.plist` do bundle (gitignored; modelo em `Secrets.example.plist`).
/// Nunca crasha: chave ausente ou vazia → `nil`.
enum Secrets {
    enum Key: String, CaseIterable {
        case googlePlaces = "GOOGLE_PLACES_KEY"
        case flickr = "FLICKR_KEY"
        case anthropic = "ANTHROPIC_KEY"
    }

    static subscript(key: Key) -> String? {
        guard let value = values[key.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    static var googlePlacesKey: String? { self[.googlePlaces] }
    static var flickrKey: String? { self[.flickr] }
    static var anthropicKey: String? { self[.anthropic] }

    private static let values: [String: String] = load(from: .main)

    static func load(from bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any] else { return [:] }
        return dict.compactMapValues { $0 as? String }
    }
}
