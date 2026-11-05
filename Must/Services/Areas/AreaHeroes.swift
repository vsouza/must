import CoreLocation
import Foundation

/// Foto principal de um bairro (prompt 18 · B.11 / C.13): a do lugar mais bem colocado do bairro (verificado no
/// Places primeiro, depois a ordem do board), senão uma foto do Commons perto do centroide. Escolhida **uma vez**
/// e guardada no disco (`DiskCache`, sem prazo): depois disso o bairro nunca mais chama a rede pra escolher.
/// Sem rede e sem cópia guardada, devolve `nil` e a tela mostra o gradiente da cor (sem spinner).
struct AreaHeroes: Sendable {
    /// Um lugar candidato a representar o bairro: o nome é só pro log, a coordenada é a que a foto busca.
    struct Candidate: Sendable {
        var name: String
        var coordinate: CLLocationCoordinate2D
        /// Fotos do Google do lugar (as refs; o arquivo só existe se o Lugar já foi aberto ou baixado).
        var placeId: String? = nil
        var photoRefs: [PlacePhotoRef] = []
    }

    /// Foto do Google de um dos lugares do bairro que **já está no disco**: zero rede e bem mais viva que a do
    /// Commons (05/11). Ganha da escolha guardada do Commons; nunca baixa nada.
    static func googleOnDisk(_ candidates: [Candidate]) -> CCPhoto? {
        for candidate in candidates.prefix(6) {
            for ref in candidate.photoRefs.prefix(1) {
                if let file = PlacePhotoStore.existing(ref) {
                    return PlacePhotoResolver.photo(ref, file: file, placeId: candidate.placeId ?? "")
                }
            }
        }
        return nil
    }

    let photos: any PhotoProviding

    /// Chave do disco: uma por bairro e região (a mesma foto em todas as telas).
    static func cacheKey(region: Region, areaId: String) -> String { "area-hero|\(region.rawValue)|\(areaId)" }

    /// Foto guardada ou escolhida agora. `candidates` vêm na ordem de preferência (até 3 são tentados).
    func photo(region: Region, area: Area, candidates: [Candidate], cityName: String) async -> CCPhoto? {
        if PhotoStyle.current == .vivid, let google = Self.googleOnDisk(candidates) { return google }
        let key = Self.cacheKey(region: region, areaId: area.id)
        if let saved = await DiskCache.shared.stale(key), let photo = try? JSONDecoder().decode(CCPhoto.self, from: saved) {
            return photo
        }
        guard photos.isConfigured else { return nil }
        var chosen: CCPhoto?
        for candidate in candidates.prefix(3) {
            chosen = try? await PlaceHero.commons(coordinate: candidate.coordinate, area: area.name, cityName: cityName, photos: photos)
            if chosen != nil { break }
        }
        if chosen == nil {
            chosen = try? await photos.search(near: area.centroid.clCoordinate, radiusKm: 1).first
        }
        guard let chosen, let encoded = try? JSONEncoder().encode(chosen) else { return nil }
        await DiskCache.shared.store(encoded, for: key)
        return chosen
    }
}
