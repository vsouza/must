import CoreLocation
import Foundation

/// Capa de cada bairro do board, baixada no Wi-Fi (prompt 21 · fatia 2). Uma foto por bairro, escolhida pelo
/// `AreaHeroes` (a mesma da Home e da Bairros) e guardada no disco; a miniatura de 240 px sai do aparelho.
/// Mesma política do pré-download do dia (`PrefetchPolicy`): só Wi-Fi, fora do Modo de Pouco Dados.
enum AreaCoverPrefetch {
    /// Miniatura de lista: gerada no aparelho a partir da foto guardada (nunca uma segunda chamada).
    static let thumbPixels = 240

    /// Chave da miniatura no disco (a foto grande fica na chave de `PhotoLoader`).
    static func thumbKey(for url: URL) -> String { "photo-240|\(url.absoluteString)" }

    /// Devolve quantos bairros ficaram com a capa no disco. Sem a política (celular, pouco dado, offline): 0 e nada
    /// sai na rede.
    @discardableResult
    static func run(region: Region, places: [AreaPlace], network: PrefetchPolicy.Network,
                     photos: any PhotoProviding, cityName: String) async -> Int {
        guard PrefetchPolicy.allows(network) else { return 0 }
        let index = AreaIndex.build(areas: AreaCatalog.areas(for: region), places: places, openIds: [])
        let byId = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let heroes = AreaHeroes(photos: photos)
        var ready = 0
        for entry in index.populated {
            guard !Task.isCancelled else { break }
            let candidates = entry.placeIds.compactMap { id in
                byId[id].map { AreaHeroes.Candidate(name: $0.name, coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)) }
            }
            guard let photo = await heroes.photo(region: region, area: entry.area, candidates: candidates, cityName: cityName),
                  let url = URL(string: photo.url) else { continue }
            guard await PhotoLoader.prefetch(url) else { continue }
            await makeThumbnail(for: url)
            ready += 1
        }
        Log.data.info("capas de bairro no disco: \(ready)/\(index.populated.count)")
        return ready
    }

    /// Miniatura 240 px a partir da foto já no disco. Sem foto, não faz nada.
    static func makeThumbnail(for url: URL) async {
        let thumb = thumbKey(for: url)
        guard !(await DiskCache.shared.exists(thumb)),
              let data = await DiskCache.shared.stale("photo|\(url.absoluteString)"),
              let small = PlacePhotoStore.makeThumbnail(data, maxPixel: thumbPixels) else { return }
        await DiskCache.shared.store(small, for: thumb)
    }
}
