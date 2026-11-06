import CoreLocation
import Foundation
import OSLog

/// Bairros de uma viagem criada no app (prompt 28 §3.5, aprovado): não há tabela curada pra Porto, então os bairros
/// saem **dos próprios Musts**. Agrupa por célula de ~1,5 km (grade de lat/lng, o "geohash" do prompt), dá o nome pelo
/// bairro que o board já usa (`Place.area`) ou pelo `subLocality` do geocoder do aparelho, sigla de 3 letras
/// (`AreaCode`) e vizinhos pela distância. O catálogo curado (`AreaCatalog`) fica só pras viagens de fábrica.
///
/// Puro e determinístico (testável); quem chama o geocoder e grava é o `GeneratedAreaStore`.
enum GeneratedAreas {
    /// Lado da célula, em km.
    static let cellKm = 1.5
    /// Vizinhos: no máximo 4, até 5 km.
    static let maxNeighbors = 4
    static let neighborKm = 5.0
    /// Até aqui o vizinho é "a pé" (80 m/min, como as tabelas curadas); depois, trem/metrô.
    static let walkKm = 1.6

    struct Input: Sendable, Hashable {
        var id: String
        var lat: Double
        var lng: Double
        var cityId: String
        /// `Place.area` ("Alfama", "Ribeira").
        var areaName: String?
    }

    /// Célula da grade (a mesma conta pra todo mundo: a chave não depende de quais lugares existem).
    struct Cell: Hashable, Sendable, Comparable {
        var row: Int
        var col: Int

        var id: String { "g\(row)_\(col)" }

        static func < (a: Cell, b: Cell) -> Bool { (a.row, a.col) < (b.row, b.col) }
    }

    static func cell(lat: Double, lng: Double) -> Cell {
        let latStep = cellKm / 111.32
        let row = Int((lat / latStep).rounded(.down))
        // A largura em longitude da faixa de latitude da célula (fixa por linha, então vizinhos casam).
        let bandLat = (Double(row) + 0.5) * latStep
        let lngStep = cellKm / (111.32 * max(0.1, cos(bandLat * .pi / 180)))
        return Cell(row: row, col: Int((lng / lngStep).rounded(.down)))
    }

    /// Bairros a partir dos lugares. `names`: nome do geocoder por `Cell.id` (opcional; sem ele, o nome do board ou
    /// "<cidade> · <n>").
    static func build(_ places: [Input], names: [String: String] = [:], cityNames: [String: String] = [:]) -> [Area] {
        let groups = Dictionary(grouping: places) { cell(lat: $0.lat, lng: $0.lng) }
        let cells = groups.keys.sorted()
        var areas: [Area] = []
        var usedNames: [String: Int] = [:]
        for (index, c) in cells.enumerated() {
            let members = groups[c] ?? []
            let lat = members.map(\.lat).reduce(0, +) / Double(members.count)
            let lng = members.map(\.lng).reduce(0, +) / Double(members.count)
            let cityId = mostCommon(members.map(\.cityId)) ?? ""
            let boardName = mostCommon(members.compactMap { $0.areaName?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
            var name = names[c.id] ?? boardName ?? "\(cityNames[cityId] ?? "Área") · \(index + 1)"
            // Dois bairros com o mesmo nome do geocoder: "Baixa", "Baixa 2".
            let count = usedNames[name, default: 0] + 1
            usedNames[name] = count
            if count > 1 { name += " \(count)" }
            let aliases = Array(Set(members.compactMap(\.areaName)).subtracting([name])).sorted()
            areas.append(Area(id: c.id, name: name, nameLocal: nil, cityId: AreaCatalog.cityGroup(forCityId: cityId),
                              centroid: .init(lat: lat, lng: lng), polygon: nil, stationIds: [], aliases: aliases,
                              neighbors: [], stampText: nil, stampSub: cityNames[cityId], heroPhotoRef: nil,
                              stampCode: AreaCode.derive(name)))
        }
        // Vizinhos por distância (mesma cidade).
        for i in areas.indices {
            let here = CLLocation(latitude: areas[i].centroid.lat, longitude: areas[i].centroid.lng)
            let near = areas.indices.filter { $0 != i && areas[$0].cityId == areas[i].cityId }
                .map { j -> (Int, Double) in
                    (j, here.distance(from: CLLocation(latitude: areas[j].centroid.lat, longitude: areas[j].centroid.lng)) / 1000)
                }
                .filter { $0.1 <= neighborKm }
                .sorted { ($0.1, areas[$0.0].id) < ($1.1, areas[$1.0].id) }
                .prefix(maxNeighbors)
            areas[i].neighbors = near.map { j, km in
                let street = km * 1.25
                if street <= walkKm { return .init(areaId: areas[j].id, minutes: max(3, Int((street * 1000 / 80).rounded())), mode: .walk, line: nil) }
                return .init(areaId: areas[j].id, minutes: Int((6 + street * 2.5).rounded()), mode: .train, line: nil)
            }
        }
        return areas
    }

    private static func mostCommon(_ values: [String]) -> String? {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }
}

/// Bairros gerados por viagem: em memória (leitura síncrona pelo `AreaCatalog`) e em disco
/// (`areas-<id>.json`, junto dos `.store`). Recalcula quando o board muda; o geocoder só roda pras células novas e
/// nunca em paralelo (premissa: econômico em dados).
final class GeneratedAreaStore: @unchecked Sendable {
    static let shared = GeneratedAreaStore()

    private let lock = NSLock()
    private var byTrip: [TripID: [Area]] = [:]
    /// Nomes do geocoder já pedidos, por viagem e célula (sobrevivem ao recálculo).
    private var names: [TripID: [String: String]] = [:]

    struct File: Codable { var areas: [Area]; var names: [String: String] }

    func areas(for trip: TripID, directory: URL = Region.storeDirectory) -> [Area] {
        if let cached = lock.withLock({ byTrip[trip] }) { return cached }
        let url = Self.url(trip, directory: directory)
        let file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) }
        lock.withLock {
            byTrip[trip] = file?.areas ?? []
            names[trip] = file?.names ?? [:]
        }
        return file?.areas ?? []
    }

    /// Recalcula com os lugares de agora. `geocode`: nome de um ponto (subLocality), chamado só pra célula sem nome.
    @discardableResult
    func rebuild(trip: TripID, places: [GeneratedAreas.Input], cityNames: [String: String],
                 directory: URL = Region.storeDirectory,
                 geocode: (@Sendable (CLLocationCoordinate2D) async -> String?)? = nil) async -> [Area] {
        _ = areas(for: trip, directory: directory)
        var known = lock.withLock { names[trip] ?? [:] }
        if let geocode {
            let cells = Set(places.map { GeneratedAreas.cell(lat: $0.lat, lng: $0.lng) })
            for cell in cells.sorted() where known[cell.id] == nil {
                let members = places.filter { GeneratedAreas.cell(lat: $0.lat, lng: $0.lng) == cell }
                // O board já dá nome? Não gasta geocoder.
                if members.contains(where: { !($0.areaName ?? "").isEmpty }) { continue }
                guard !members.isEmpty else { continue }
                let lat = members.map(\.lat).reduce(0, +) / Double(members.count)
                let lng = members.map(\.lng).reduce(0, +) / Double(members.count)
                if let name = await geocode(CLLocationCoordinate2D(latitude: lat, longitude: lng)), !name.isEmpty {
                    known[cell.id] = name
                }
            }
        }
        let areas = GeneratedAreas.build(places, names: known, cityNames: cityNames)
        lock.withLock {
            byTrip[trip] = areas
            names[trip] = known
        }
        if let data = try? JSONEncoder().encode(File(areas: areas, names: known)) {
            try? data.write(to: Self.url(trip, directory: directory), options: .atomic)
        }
        return areas
    }

    /// Apagar a viagem: some com os bairros dela.
    func forget(_ trip: TripID, directory: URL = Region.storeDirectory) {
        lock.withLock {
            byTrip[trip] = nil
            names[trip] = nil
        }
        try? FileManager.default.removeItem(at: Self.url(trip, directory: directory))
    }

    static func url(_ trip: TripID, directory: URL) -> URL { directory.appending(path: "areas-\(trip).json") }

    /// `subLocality` do geocoder do aparelho, em pt-BR (nome latino).
    static let deviceGeocoder: @Sendable (CLLocationCoordinate2D) async -> String? = { c in
        let geocoder = CLGeocoder()
        let marks = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude),
                                                               preferredLocale: Locale(identifier: "pt_BR"))
        return marks?.first?.subLocality ?? marks?.first?.locality
    }
}
