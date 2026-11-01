import CoreLocation
import Foundation

/// Fonte dos tiles da base: PMTiles no bundle (offline) ou Protomaps hospedado.
enum MapTiles: Equatable, Sendable {
    case bundled(name: String, url: URL)
    case hosted(key: String)
    case none

    /// Áreas com tiles no bundle (ver `Must/Data/tiles/README.md`).
    struct Area: Sendable {
        var name: String
        var region: Region
        var center: CLLocationCoordinate2D
    }

    static let areas: [Area] = [
        Area(name: "bh", region: .bh, center: CLLocationCoordinate2D(latitude: -19.90, longitude: -43.95)),
        Area(name: "jp-tokyo", region: .jp, center: CLLocationCoordinate2D(latitude: 35.675, longitude: 139.75)),
        Area(name: "jp-kansai", region: .jp, center: CLLocationCoordinate2D(latitude: 34.85, longitude: 135.75)),
    ]

    /// Escolhe o arquivo da região mais perto de `center` (Tóquio × Kyoto/Nara no Japão).
    static func pick(region: Region, near center: CLLocationCoordinate2D, bundle: Bundle = .main) -> MapTiles {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let candidates = areas.filter { $0.region == region }
            .compactMap { area -> (Area, URL)? in
                bundle.url(forResource: area.name, withExtension: "pmtiles", subdirectory: "tiles").map { (area, $0) }
            }
            .sorted {
                here.distance(from: CLLocation(latitude: $0.0.center.latitude, longitude: $0.0.center.longitude))
                    < here.distance(from: CLLocation(latitude: $1.0.center.latitude, longitude: $1.0.center.longitude))
            }
        if let (area, url) = candidates.first { return .bundled(name: area.name, url: url) }
        if let key = Secrets.protomapsKey { return .hosted(key: key) }
        return .none
    }

    var sourceURL: String? {
        switch self {
        case .bundled(_, let url): "pmtiles://\(url.absoluteString)"
        case .hosted(let key): "https://api.protomaps.com/tiles/v4.json?key=\(key)"
        case .none: nil
        }
    }
}

/// Monta o style "papel em relevo" pra região: tiles, fontes dos rótulos (Zen Kaku no Japão) e grava em Caches.
enum MapStyleLoader {
    static let japaneseFont = "Zen Kaku Gothic New Medium"

    static func styleURL(region: Region, tiles: MapTiles, bundle: Bundle = .main) -> URL? {
        guard let template = bundle.url(forResource: "must-relief.style", withExtension: "json", subdirectory: "MapStyle"),
              let data = try? Data(contentsOf: template),
              var style = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Log.data.error("mapa: style não encontrado no bundle")
            return nil
        }
        style = customize(style, region: region, tiles: tiles)
        let name: String = switch tiles {
        case .bundled(let n, _): n
        case .hosted: "\(region.rawValue)-hosted"
        case .none: "\(region.rawValue)-empty"
        }
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "map-style")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "must-relief-\(name).json")
        guard let out = try? JSONSerialization.data(withJSONObject: style) else { return nil }
        try? out.write(to: url, options: .atomic)
        return url
    }

    /// Troca a fonte dos tiles e, no Japão, a fonte dos rótulos. Sem tiles, deixa só o fundo.
    static func customize(_ style: [String: Any], region: Region, tiles: MapTiles) -> [String: Any] {
        var style = style
        var layers = style["layers"] as? [[String: Any]] ?? []
        if let url = tiles.sourceURL {
            style["sources"] = ["pm": ["type": "vector", "url": url, "attribution": "© OpenStreetMap · Protomaps"]]
        } else {
            style["sources"] = [String: Any]()
            layers = layers.filter { $0["source"] == nil }
        }
        if region == .jp {
            layers = layers.map { layer in
                guard var layout = layer["layout"] as? [String: Any], layout["text-font"] != nil else { return layer }
                var layer = layer
                layout["text-font"] = [japaneseFont]
                layout["text-letter-spacing"] = 0.04
                layer["layout"] = layout
                return layer
            }
        }
        style["layers"] = layers
        return style
    }
}
