import CoreLocation
import Foundation

/// Uma cidade baixável do mapa offline (ver `data/map-packs.json` e `data/map-packs.md`).
struct MapPack: Decodable, Sendable, Identifiable, Equatable {
    var id: String
    var region: Region
    var title: String
    var subtitle: String
    /// lat, lng
    var center: [Double]
    /// Recorte do `scripts/tiles.sh`: oeste, sul, leste, norte.
    var bbox: [Double]

    var centerCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: center[0], longitude: center[1]) }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        guard bbox.count == 4 else { return false }
        return (bbox[0]...bbox[2]).contains(c.longitude) && (bbox[1]...bbox[3]).contains(c.latitude)
    }

    func distance(to c: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: center[0], longitude: center[1]).distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }

    static func nearest(_ c: CLLocationCoordinate2D, in packs: [MapPack]) -> MapPack? {
        packs.min { $0.distance(to: c) < $1.distance(to: c) }
    }

    /// Recorte onde `c` está (o primeiro do catálogo, que tem as principais primeiro).
    static func containing(_ c: CLLocationCoordinate2D, region: Region) -> MapPack? {
        catalog.first { $0.region == region && $0.contains(c) }
    }

    /// Principais primeiro: quando a câmera está em dois recortes, vale o primeiro.
    static let catalog: [MapPack] = load(from: .main)

    static func load(from bundle: Bundle) -> [MapPack] {
        struct File: Decodable { var packs: [MapPack] }
        guard let url = bundle.url(forResource: "map-packs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            Log.data.error("mapa: map-packs.json ausente no bundle")
            return []
        }
        return file.packs
    }
}

/// `manifest.json` no R2: tamanho, sha256 e build de cada arquivo (gerado por `scripts/tiles.sh`).
struct MapPackManifest: Codable, Sendable, Equatable {
    struct Entry: Codable, Sendable, Equatable {
        var id: String
        var bytes: Int64
        var sha256: String
        var build: String
    }
    var packs: [Entry]

    subscript(id: String) -> Entry? { packs.first { $0.id == id } }
}

/// Onde os mapas baixados ficam no aparelho. Sem estado: o mapa consulta o disco quando escolhe a fonte.
enum MapPackFiles {
    /// Application Support/tiles — não é apagado pelo sistema como Caches, e fica fora do backup.
    static var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "tiles")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var url = dir
            try? url.setResourceValues(values)
        }
        return dir
    }

    static func fileURL(_ id: String) -> URL { directory.appending(path: "\(id).pmtiles") }

    static func localURL(_ id: String) -> URL? {
        let url = fileURL(id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func bytes(_ id: String) -> Int64? {
        guard let url = localURL(id),
              let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// Bucket R2 público (`MAP_TILES_URL`): `<base>/manifest.json` e `<base>/<id>.pmtiles`.
    static var remoteBase: URL? { Secrets.mapTilesURL.flatMap(URL.init(string:)) }

    /// Espaço livre pra arquivos que o usuário pediu (o sistema pode liberar caches pra isso).
    static var freeSpace: Int64? {
        (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }
}

extension Notification.Name {
    /// Um mapa offline foi baixado, atualizado ou apagado: o mapa reescolhe a fonte.
    static let mapPacksChanged = Notification.Name("mapPacksChanged")
}
