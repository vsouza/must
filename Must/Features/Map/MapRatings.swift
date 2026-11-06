import Foundation

/// Nota que **já está no aparelho**, sem chamada nova (prompt 27 §2.c: "nota só se já existir sem custo extra"):
/// as dicas do Google do Lugar já aberto (`TipsCache`, até 30 dias) e o último "Por perto" (`NearbyCache`).
enum MapRatings {
    static func known(placeId: String, name: String, region: Region, googlePlaceId: String?, nearby: [NearbyPlace],
                      cache: TipsCache = .shared) async -> KnownRating? {
        let query = TipsQuery(id: placeId, name: name, nameLocal: nil, city: "", region: region, lat: 0, lng: 0,
                              googlePlaceId: googlePlaceId, fsqId: nil, sourceKind: nil, sourceCaption: nil, sourceAuthor: nil,
                              sourceSavedAt: nil, sourceURL: nil)
        if let batch = await cache.batch(query, .google, allowStale: true), let rating = batch.rating {
            return KnownRating(rating: rating, count: batch.ratingCount)
        }
        return fromNearby(googlePlaceId: googlePlaceId, nearby: nearby)
    }

    static func fromNearby(googlePlaceId: String?, nearby: [NearbyPlace]) -> KnownRating? {
        guard let googlePlaceId, let hit = nearby.first(where: { $0.googlePlaceId == googlePlaceId }), let rating = hit.rating else {
            return nil
        }
        return KnownRating(rating: rating, count: hit.ratingCount)
    }

    /// O último lote do "Por perto" na célula (só disco; vencido = vazio).
    static func nearbyBatch(lat: Double, lng: Double, region: Region, cache: NearbyCache = .shared) async -> [NearbyPlace] {
        await cache.batch(for: NearbyCell.key(lat: lat, lng: lng, region: region))?.places ?? []
    }
}
