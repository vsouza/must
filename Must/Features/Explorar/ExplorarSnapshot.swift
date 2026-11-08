import CoreLocation
import MapLibre
import UIKit

/// O recorte do mapa da página do bairro (prompt 31 · 8): um snapshot do MapLibre só da base (sem pinos: eles são desenhados
/// por cima, com a mesma projeção). Gerado uma vez por bairro e guardado em disco (`CutImageCache`), então a página abre
/// na hora e funciona offline; nunca há dois mapas vivos. Sem pack baixado e sem rede, devolve `nil` e a página mostra o papel
/// com a trama (estado normal, não erro).
@MainActor
enum ExplorarSnapshot {
    /// Versão do desenho (muda a chave quando o estilo do mapa muda).
    static let version = 1
    /// Largura do recorte em metros (um bairro a pé).
    static let widthMeters: Double = 900
    /// Lado do recorte quadrado (pt).
    static let side: CGFloat = 176

    /// Chave de disco: região + bairro + pack + versão.
    static func key(region: Region, areaId: String, tiles: MapTiles) -> String {
        "explorar-\(region.rawValue)-\(areaId)-\(tiles.name ?? "x")-\(tiles.isLocal ? "l" : "r")-v\(version)"
    }

    /// A projeção do recorte de um bairro (a mesma que o snapshot usou).
    static func projection(for area: Area, side: CGFloat = side) -> ExplorarProjection {
        ExplorarProjection(center: area.centroid.clCoordinate, widthMeters: widthMeters, size: CGSize(width: side, height: side))
    }

    /// Imagem guardada ou gerada agora. `online`: sem rede e com tiles remotos não tenta (sairia em branco).
    static func image(region: Region, area: Area, online: Bool, cache: CutImageCache = .shared) async -> UIImage? {
        let center = area.centroid.clCoordinate
        let tiles = MapTiles.pick(region: region, near: center)
        if case .none = tiles { return nil }
        let key = key(region: region, areaId: area.id, tiles: tiles)
        // Já em disco: nunca refaz. Senão, só gera com tiles locais ou com rede.
        if !tiles.isLocal, !online, !(await onDisk(key, cache: cache)) { return nil }
        guard let styleURL = MapStyleLoader.styleURL(region: region, tiles: tiles) else { return nil }
        let projection = projection(for: area)
        return await cache.image(key: key) {
            await render(styleURL: styleURL, projection: projection)
        }
    }

    private static func onDisk(_ key: String, cache: CutImageCache) async -> Bool {
        let file = URL.cachesDirectory.appending(path: "must-cut/\(key).jpg")
        return FileManager.default.fileExists(atPath: file.path())
    }

    /// Roda o `MLNMapSnapshotter` (no main, como o MapLibre quer) com tempo limite de 12 s.
    private static func render(styleURL: URL, projection: ExplorarProjection) async -> UIImage? {
        await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            let camera = MLNMapCamera(lookingAtCenter: projection.center, altitude: 1000, pitch: 0, heading: 0)
            let options = MLNMapSnapshotOptions(styleURL: styleURL, camera: camera, size: projection.size)
            options.zoomLevel = projection.zoom
            options.scale = 3
            let snapshotter = MLNMapSnapshotter(options: options)
            let once = Once()
            snapshotter.start { snapshot, _ in
                guard once.claim() else { return }
                let image = snapshot?.image
                continuation.resume(returning: image.flatMap { isFlat($0) ? nil : $0 })
                _ = snapshotter
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                guard once.claim() else { return }
                snapshotter.cancel()
                continuation.resume(returning: nil)
            }
        }
    }

    /// Um quadro de uma cor só (tiles que não chegaram) não vale guardar.
    nonisolated static func isFlat(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let n = 12
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        guard let context = CGContext(data: &pixels, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        context.interpolationQuality = .none
        context.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var lo = 255, hi = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
            lo = min(lo, v); hi = max(hi, v)
        }
        return hi - lo < 6
    }

    private final class Once: @unchecked Sendable {
        private var claimed = false
        func claim() -> Bool {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}

extension MapTiles {
    var isLocal: Bool { if case .local = self { true } else { false } }
}
