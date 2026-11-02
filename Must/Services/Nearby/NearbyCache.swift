import Foundation

/// Cache por célula (~500 m) e região: 30 min. Fica em Caches/, então o Ajustes pode apagar.
actor NearbyCache {
    static let shared = NearbyCache()
    static let maxAge: TimeInterval = 30 * 60

    private let directory: URL

    init(directory: URL = URL.cachesDirectory.appending(path: "must-nearby", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    /// Só o que tem até 30 min. Passado disso (ou sem arquivo), `nil`.
    func batch(for cell: String, now: Date = Date()) -> NearbyBatch? {
        guard let data = try? Data(contentsOf: file(cell)),
              let batch = try? JSONDecoder.tips.decode(NearbyBatch.self, from: data) else { return nil }
        let age = now.timeIntervalSince(batch.fetchedAt)
        return age >= 0 && age < Self.maxAge ? batch : nil
    }

    func store(_ batch: NearbyBatch) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder.tips.encode(batch) { try? data.write(to: file(batch.cell), options: .atomic) }
    }

    private func file(_ cell: String) -> URL {
        directory.appending(path: "\(cell).json")
    }
}

/// Cache primeiro, fontes depois. A Home usa só `cached`; a tela Descobrir usa `load` (no máximo uma rodada por célula a cada 30 min).
struct NearbyLoader: Sendable {
    var provider: any NearbyProviding
    var cache: NearbyCache

    /// Só o cache. Nunca chama fonte nenhuma (é o que a Home lê).
    func cached(lat: Double, lng: Double, region: Region, now: Date = Date()) async -> NearbyBatch? {
        await cache.batch(for: NearbyCell.key(lat: lat, lng: lng, region: region), now: now)
    }

    /// Cache de 30 min por célula; senão, uma rodada das fontes. Só resposta completa entra no cache.
    func load(lat: Double, lng: Double, region: Region, now: Date = Date()) async -> NearbyBatch {
        let cell = NearbyCell.key(lat: lat, lng: lng, region: region)
        if let hit = await cache.batch(for: cell, now: now) { return hit }
        let fetched = await provider.fetch(lat: lat, lng: lng, region: region)
        let batch = NearbyBatch(cell: cell, fetchedAt: now, places: fetched.places)
        if fetched.complete { await cache.store(batch) }
        return batch
    }
}
