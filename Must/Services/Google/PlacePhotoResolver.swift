import CoreLocation
import Foundation
import SwiftData

/// Foto de um lugar (prompt 19): Google primeiro, Wikimedia Commons só de reserva.
/// Ordem: disco (sem rede) → `/media` uma vez → se a ref expirou (400/404), refaz o Details só com `photos` uma vez
/// por lugar e por sessão. Sem `placeId`, sem foto no Google, sem cota ou com erro → Commons perto do lugar.
/// Lugar sem foto nenhuma → `nil` (a tela mostra o gradiente da cor).
@MainActor
final class PlacePhotoResolver {
    enum Purpose: Sendable {
        /// Foto principal do Lugar aberto: pode buscar as refs (Details com `photos`) e sai acima de 80% do mês.
        case hero
        /// Galeria do Lugar, ao deslizar: sob demanda, cortada em 80% do mês.
        case gallery
        /// Miniatura (Lista, Board, Mapa, Adicionar, Hoje): nunca busca refs; sem rede, só o que já está no disco.
        case thumb
        /// Pré-download (dia aceito, lote de Ajustes): pode buscar refs; cortado em 80% do mês.
        case prefetch
    }

    private let provider: any PlacePhotosProviding
    private let commons: any PhotoProviding
    /// Lugares cujo Details veio sem foto nesta sessão: não pergunta de novo.
    private var noPhotos: Set<String> = []
    /// Lugares cujas refs expiraram e já foram refeitas nesta sessão (uma vez).
    private var refreshed: Set<String> = []

    init(provider: any PlacePhotosProviding, commons: any PhotoProviding) {
        self.provider = provider
        self.commons = commons
    }

    var isGoogleConfigured: Bool { provider.isConfigured }

    /// Foto principal do Lugar, pra tela e pro pré-download. Google primeiro; Commons só se o Google não der nada.
    /// `nil` = o lugar não tem foto em lugar nenhum. Erro (rede, cota, offline) lança quando não sobrou foto de reserva.
    func hero(for place: Place, cityName: String, commonsAllowed: Bool, purpose: Purpose = .hero) async throws -> CCPhoto? {
        var failure: Error?
        if let placeId = place.placeId, provider.isConfigured {
            do {
                if let photo = try await photo(placeId: placeId, refs: place.photoRefs, index: 0, purpose: purpose, persist: Self.persist(place)) {
                    return photo
                }
            } catch {
                failure = error
            }
        }
        if commonsAllowed, commons.isConfigured {
            do {
                if let photo = try await PlaceHero.commons(coordinate: place.coordinate, area: place.area, cityName: cityName, photos: commons) {
                    return photo
                }
            } catch {
                failure = failure ?? error
            }
        }
        if let failure { throw failure }
        return nil
    }

    /// Foto `index` do lugar (galeria do Lugar). Refs vazias não buscam (a galeria só existe com refs).
    func gallery(for place: Place, index: Int) async throws -> CCPhoto? {
        guard let placeId = place.placeId else { return nil }
        return try await photo(placeId: placeId, refs: place.photoRefs, index: index, purpose: .gallery, persist: Self.persist(place))
    }

    /// Miniatura 240 px da foto principal, pra listas e cards. Disco primeiro; com rede (Modo de Pouco Dados fora), uma `/media`.
    func thumb(placeId: String?, refs: [PlacePhotoRef]) async -> URL? {
        guard let placeId, let ref = refs.first else { return nil }
        if let thumb = PlacePhotoStore.existingThumb(ref) { return thumb }
        if let thumb = await PlacePhotoStore.ensureThumb(ref) { return thumb }
        guard let photo = try? await photo(placeId: placeId, refs: refs, index: 0, purpose: .thumb, persist: nil),
              let url = URL(string: photo.url) else { return nil }
        return await PlacePhotoStore.ensureThumb(ref) ?? url
    }

    /// Só o disco, sem rede (o que a tela mostra antes de qualquer pedido).
    func cachedHeroURL(refs: [PlacePhotoRef]) -> URL? {
        refs.first.flatMap(PlacePhotoStore.existing)
    }

    // MARK: Núcleo

    /// Disco → `/media` → (400/404) refaz as refs uma vez e tenta de novo. `persist` grava as refs novas no Place.
    func photo(placeId: String, refs: [PlacePhotoRef], index: Int, purpose: Purpose,
               persist: (([PlacePhotoRef]) -> Void)?) async throws -> CCPhoto? {
        var refs = refs
        if refs.isEmpty {
            // Sem refs: só a foto principal e o pré-download buscam o Details (uma vez por sessão, lugar sem foto não repete).
            guard purpose == .hero || purpose == .prefetch, !noPhotos.contains(placeId) else { return nil }
            refs = try await provider.photoRefs(placeId: placeId)
            persist?(refs)
            if refs.isEmpty { noPhotos.insert(placeId); return nil }
        }
        guard refs.indices.contains(index) else { return nil }
        let ref = refs[index]
        if let file = PlacePhotoStore.existing(ref) { return Self.photo(ref, file: file, placeId: placeId) }
        // Miniatura só com rede boa: no Modo de Pouco Dados (ou offline), a lista mostra o gradiente.
        if purpose == .thumb, Connectivity.current != .online { return nil }
        do {
            let file = try await download(ref, placeId: placeId, purpose: purpose)
            return Self.photo(ref, file: file, placeId: placeId)
        } catch let ServiceError.http(code, _) where code == 400 || code == 404 {
            guard refreshed.insert(placeId).inserted else { throw ServiceError.http(code, "ref expirada") }
            Log.network.notice("foto \(placeId, privacy: .public): ref expirou (\(code)), refazendo o Details de fotos")
            let fresh = try await provider.photoRefs(placeId: placeId)
            persist?(fresh)
            let next = fresh.indices.contains(index) ? fresh[index] : fresh.first
            guard let next else { return nil }
            let file = try await download(next, placeId: placeId, purpose: purpose)
            return Self.photo(next, file: file, placeId: placeId)
        }
    }

    private func download(_ ref: PlacePhotoRef, placeId: String, purpose: Purpose) async throws -> URL {
        try await provider.photo(ref, placeId: placeId, hero: purpose == .hero, prefetch: purpose == .prefetch)
    }

    /// Grava as refs no Place (e salva o contexto). Só o main mexe no modelo.
    private static func persist(_ place: Place) -> ([PlacePhotoRef]) -> Void {
        { [weak place] refs in
            guard let place, place.photoRefs != refs else { return }
            place.photoRefs = refs
            try? place.modelContext?.save()
        }
    }

    /// `CCPhoto` da foto do Google: o crédito "foto · Google · autor" e o toque abre o link do autor.
    nonisolated static func photo(_ ref: PlacePhotoRef, file: URL, placeId: String) -> CCPhoto {
        CCPhoto(id: ref.name, url: file.absoluteString, largeURL: file.absoluteString,
                owner: String((ref.author ?? "Google").prefix(28)), licenseName: "Google",
                page: ref.authorURI ?? "https://www.google.com/maps/place/?q=place_id:\(placeId)", source: "Google")
    }
}
