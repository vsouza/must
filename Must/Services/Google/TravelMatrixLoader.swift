import CoreLocation
import Foundation

/// Busca a matriz do dia (a pé e transporte) antes do solver rodar. Máx. 10 pontos (origem + 9 candidatas),
/// cache de um dia em Caches/. Sem rede, sem chave, sem orçamento ou com erro: `nil` e o solver usa a estimativa.
enum TravelMatrixLoader {
    static let maxPoints = 10

    /// Origem primeiro, depois as candidatas (já ordenadas por proximidade). No máx. `maxPoints` pontos.
    static func points(origin: CLLocationCoordinate2D, candidates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        [origin] + candidates.filter { abs($0.latitude - origin.latitude) + abs($0.longitude - origin.longitude) > 0.00001 }
            .prefix(maxPoints - 1)
    }

    static func load(points: [CLLocationCoordinate2D], departAt: Date, day: String, apiKey: String? = Secrets.googlePlacesKey,
                     http: HTTP = HTTP()) async -> TravelMatrix? {
        guard let apiKey, DevOverrides.liveData, points.count >= 2, points.count <= maxPoints else { return nil }
        let signature = points.map { TravelMatrix.key($0, $0) }.joined(separator: "|")
        let cacheKey = "matrix-\(day)-\(fnv(signature))"
        if let cached = await DiskCache.shared.data(for: cacheKey, maxAge: 86_400),
           let matrix = try? JSONDecoder().decode(TravelMatrix.self, from: cached) {
            return matrix
        }
        var matrix = TravelMatrix()
        for mode in ["WALK", "TRANSIT"] {
            guard let cells = try? await GoogleRoutes.matrix(origins: points, destinations: points, mode: mode, departAt: departAt,
                                                            apiKey: apiKey, http: http) else { continue }
            var table: [String: Int] = [:]
            for cell in cells where cell.originIndex != cell.destinationIndex
                && cell.originIndex < points.count && cell.destinationIndex < points.count {
                table[TravelMatrix.key(points[cell.originIndex], points[cell.destinationIndex])] = cell.minutes
            }
            if mode == "WALK" { matrix.walk = table } else { matrix.transit = table }
        }
        guard !matrix.isEmpty else { return nil }
        if let encoded = try? JSONEncoder().encode(matrix) { await DiskCache.shared.store(encoded, for: cacheKey) }
        return matrix
    }

    /// Hash estável (FNV-1a) pra chave de cache.
    static func fnv(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
