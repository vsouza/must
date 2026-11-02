import CoreLocation
import Foundation

/// Fonte dos tiles da base: arquivo baixado (offline), o mesmo PMTiles lido do R2, ou Protomaps hospedado.
enum MapTiles: Equatable, Sendable {
    case local(name: String, url: URL)
    case remote(name: String, url: URL)
    case hosted(key: String)
    case none

    /// Recorte que contém `center`; fora de todos, o mais perto. `local` diz se a cidade está baixada.
    static func pick(region: Region, near center: CLLocationCoordinate2D,
                     packs: [MapPack] = MapPack.catalog,
                     local: (String) -> URL? = MapPackFiles.localURL,
                     remoteBase: URL? = MapPackFiles.remoteBase,
                     hostedKey: String? = Secrets.protomapsKey) -> MapTiles {
        let candidates = packs.filter { $0.region == region }
        let installed = candidates.compactMap { p in local(p.id).map { (pack: p, url: $0) } }
        if let hit = installed.first(where: { $0.pack.contains(center) }) { return .local(name: hit.pack.id, url: hit.url) }
        // Fora do que está baixado: o recorte da câmera (ou o mais perto), baixado ou lido do R2.
        if let target = candidates.first(where: { $0.contains(center) }) ?? MapPack.nearest(center, in: candidates) {
            if let url = local(target.id) { return .local(name: target.id, url: url) }
            if let remoteBase { return .remote(name: target.id, url: remoteBase.appending(path: "\(target.id).pmtiles")) }
        }
        if let near = MapPack.nearest(center, in: installed.map(\.pack)), let url = local(near.id) {
            return .local(name: near.id, url: url)
        }
        if let hostedKey { return .hosted(key: hostedKey) }
        return .none
    }

    var name: String? {
        switch self {
        case .local(let n, _), .remote(let n, _): n
        case .hosted, .none: nil
        }
    }

    var sourceURL: String? {
        switch self {
        case .local(_, let url), .remote(_, let url): "pmtiles://\(url.absoluteString)"
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
        case .local(let n, _): n
        case .remote(let n, _): "\(n)-remote"
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
