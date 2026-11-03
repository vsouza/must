import CoreLocation
import Foundation

/// Grade de ~300 m pro cache do bairro pelo GPS (prompt 21 · fatia 2). Só troca de célula faz geocoder.
enum AreaGrid {
    /// Tamanho da célula em graus: 0,0027° ≈ 300 m de latitude (de longitude é ~270 m a 35° N, sobra pro cache).
    static let step = 0.0027

    /// Índice da célula de um ponto (linha, coluna).
    static func cell(lat: Double, lng: Double) -> (row: Int, column: Int) {
        (Int((lat / step).rounded(.down)), Int((lng / step).rounded(.down)))
    }

    /// Chave de cache: uma por célula e região (o mesmo ponto pode cair em bairros diferentes de BH e do Japão).
    static func key(lat: Double, lng: Double, region: Region) -> String {
        let c = cell(lat: lat, lng: lng)
        return "area-cell|\(region.rawValue)|\(c.row)|\(c.column)"
    }
}

/// Converte nomes que o geocoder devolve no bairro do app (prompt 21 · fatia 2).
enum AreaNameMatch {
    /// Sufixos que o geocoder põe depois do nome ("Shinjuku-ku", "Shinjuku City", "Shinjuku Ward"). Só são tirados
    /// se o nome inteiro não bater: nunca quebra um bairro que termina assim de verdade.
    static let suffixes = ["ku", "city", "ward"]

    /// Primeiro nome que bate com um bairro da tabela (ordem do geocoder: do mais local pro mais amplo).
    static func area(named candidates: [String], in areas: [Area]) -> Area? {
        var table: [String: Area] = [:]
        for area in areas {
            for name in [area.name] + area.aliases where table[AreaName.key(name)] == nil {
                table[AreaName.key(name)] = area
            }
        }
        for raw in candidates {
            let key = AreaName.key(raw)
            guard !key.isEmpty else { continue }
            if let area = table[key] { return area }
            for suffix in suffixes where key.hasSuffix(suffix) && key.count > suffix.count {
                if let area = table[String(key.dropLast(suffix.count))] { return area }
            }
        }
        return nil
    }
}

/// Geocoder reverso, trocável nos testes (a rede real é só o `CLGeocoder` da Apple).
protocol AreaNameGeocoding: Sendable {
    /// Nomes do ponto, do mais local pro mais amplo (bairro, cidade). Vazio se não achou nada.
    func names(at location: CLLocation) async throws -> [String]
}

struct CLGeocoderNames: AreaNameGeocoding {
    func names(at location: CLLocation) async throws -> [String] {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let place = placemarks.first else { return [] }
        return [place.subLocality, place.locality].compactMap { $0 }
    }
}

/// Onde o mapa célula → bairro fica guardado (no real, `Caches/must-cache`; no teste, na memória).
protocol AreaCellStore: Sendable {
    /// `""` = a célula já foi pedida e não caiu em bairro nenhum.
    func value(for key: String) async -> String?
    func save(_ value: String, for key: String) async
}

struct DiskAreaCellStore: AreaCellStore {
    func value(for key: String) async -> String? {
        guard let data = await DiskCache.shared.stale(key) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func save(_ value: String, for key: String) async {
        await DiskCache.shared.store(Data(value.utf8), for: key)
    }
}

/// Bairro de um ponto do GPS (prompt 21 · fatia 2). Ordem:
/// 1. tabela curada (polígono se houver, senão o centroide mais perto a até 1,2 km): sem rede, na hora;
/// 2. mesma célula de antes: o último valor, sem pedir nada;
/// 3. célula já guardada no disco: sem rede;
/// 4. sem rede: o último valor; com rede: `CLGeocoder` **uma vez por célula**, nunca duas chamadas ao mesmo tempo.
/// Fora do main (é um `actor`). Quem chama só troca de valor quando o GPS muda de célula.
actor CurrentAreaService {
    private let geocoder: any AreaNameGeocoding
    private let store: any AreaCellStore
    private let isOnline: @Sendable () -> Bool

    private var lastCell: String?
    private var lastArea: Area?
    /// Há um geocoder rodando: outras células esperam (guardam o ponto mais recente e pegam o último valor).
    private var inFlight = false
    private var pending: CLLocation?

    init(geocoder: any AreaNameGeocoding = CLGeocoderNames(),
         store: any AreaCellStore = DiskAreaCellStore(),
         isOnline: @escaping @Sendable () -> Bool = { Connectivity.current != .offline }) {
        self.geocoder = geocoder
        self.store = store
        self.isOnline = isOnline
    }

    /// Bairro do ponto na região. `nil` se não sabe (sem tabela perto e sem geocoder).
    func area(at location: CLLocation, region: Region) async -> Area? {
        let areas = AreaCatalog.areas(for: region)
        if let curated = Self.curated(location, in: areas) { return curated }

        let cell = AreaGrid.key(lat: location.coordinate.latitude, lng: location.coordinate.longitude, region: region)
        if cell == lastCell { return lastArea }
        if let stored = await store.value(for: cell) {
            lastCell = cell
            lastArea = areas.first { $0.id == stored }
            return lastArea
        }
        guard isOnline() else { return lastArea }
        guard !inFlight else {
            pending = location
            return lastArea
        }

        inFlight = true
        defer { inFlight = false }
        var result = await resolve(location, cell: cell, areas: areas)
        // Enquanto o geocoder rodava, o GPS pode ter mudado de célula: resolve essa uma vez, sem fila.
        if let next = pending {
            pending = nil
            let nextCell = AreaGrid.key(lat: next.coordinate.latitude, lng: next.coordinate.longitude, region: region)
            if nextCell != cell, await store.value(for: nextCell) == nil {
                result = await resolve(next, cell: nextCell, areas: areas)
            }
        }
        return result
    }

    /// Geocoder reverso de uma célula. Erro de rede não é guardado: a próxima troca de célula tenta de novo.
    private func resolve(_ location: CLLocation, cell: String, areas: [Area]) async -> Area? {
        do {
            let names = try await geocoder.names(at: location)
            let area = AreaNameMatch.area(named: names, in: areas)
            await store.save(area?.id ?? "", for: cell)
            lastCell = cell
            lastArea = area
            return area
        } catch {
            Log.location.error("bairro pelo GPS: \(error.localizedDescription, privacy: .public)")
            return lastArea
        }
    }

    /// Tabela curada: o polígono que contém o ponto ganha; senão o centroide mais perto (até 1,2 km, como o solver).
    static func curated(_ location: CLLocation, in areas: [Area]) -> Area? {
        let here = location.coordinate
        if let inside = areas.first(where: { area in
            guard let polygon = area.polygon, polygon.count >= 3 else { return false }
            return contains(here, polygon: polygon)
        }) {
            return inside
        }
        var best: (area: Area, meters: CLLocationDistance)?
        for area in areas {
            let meters = location.distance(from: CLLocation(latitude: area.centroid.lat, longitude: area.centroid.lng))
            if meters <= AreaAssigner.maxDistance, best == nil || meters < best!.meters { best = (area, meters) }
        }
        return best?.area
    }

    /// Ponto dentro de polígono (regra do raio horizontal, vértice a vértice).
    static func contains(_ point: CLLocationCoordinate2D, polygon: [Area.Coordinate]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a.lat > point.latitude) != (b.lat > point.latitude),
               point.longitude < (b.lng - a.lng) * (point.latitude - a.lat) / (b.lat - a.lat) + a.lng {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
