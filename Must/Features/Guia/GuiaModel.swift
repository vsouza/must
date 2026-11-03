import CoreLocation
import Foundation
import Observation
import SwiftData
import SwiftUI

/// Último trem pra casa (C.16). Japão: estimativa por linha (horário típico, não o da tabela oficial); BH: o da geojson.
enum LastTrain {
    struct Entry: Hashable, Sendable {
        var code: String
        var name: String
        var time: String
    }

    /// Prefixo da estação (`jy-shinjuku` → `jy`) → linha e último trem típico.
    static let jp: [String: Entry] = [
        "jy": Entry(code: "JY", name: "Yamanote", time: "00:40"),
        "jc": Entry(code: "JC", name: "Chūō", time: "00:30"),
        "h": Entry(code: "H", name: "Hibiya", time: "23:50"),
        "g": Entry(code: "G", name: "Ginza", time: "23:50"),
        "m": Entry(code: "M", name: "Marunouchi", time: "23:50"),
        "c": Entry(code: "C", name: "Chiyoda", time: "23:50"),
        "f": Entry(code: "F", name: "Fukutoshin", time: "00:10"),
        "in": Entry(code: "IN", name: "Inokashira", time: "00:20"),
        "ty": Entry(code: "TY", name: "Tōyoko", time: "00:10"),
        "e": Entry(code: "E", name: "Ōedo", time: "23:50"),
        "a": Entry(code: "A", name: "Asakusa", time: "23:40"),
        "z": Entry(code: "Z", name: "Hanzōmon", time: "23:50"),
        "n": Entry(code: "N", name: "Namboku", time: "23:50"),
        "i": Entry(code: "I", name: "Mita", time: "23:50"),
        "s": Entry(code: "S", name: "Shinjuku", time: "23:50"),
        "t": Entry(code: "T", name: "Tōzai", time: "00:00"),
        "y": Entry(code: "Y", name: "Yūrakuchō", time: "23:50"),
    ]

    static func jpEntry(stationId: String?) -> Entry? {
        guard let prefix = stationId?.split(separator: "-").first else { return nil }
        return jp[String(prefix)]
    }
}

/// Foto de uma parada: uma vez por lugar, no disco (mesmo caminho de `AreaHeroes`, prompt 18 · A.4/A.5).
enum GuidePhotos {
    static func cacheKey(placeId: String) -> String { "guia-foto|\(placeId)" }

    static func photo(placeId: String, coordinate: CLLocationCoordinate2D, area: String?, cityName: String,
                      photos: any PhotoProviding) async -> CCPhoto? {
        if let saved = await DiskCache.shared.stale(cacheKey(placeId: placeId)),
           let photo = try? JSONDecoder().decode(CCPhoto.self, from: saved) {
            return photo
        }
        guard photos.isConfigured else { return nil }
        guard let found = try? await PlaceHero.commons(coordinate: coordinate, area: area, cityName: cityName, photos: photos),
              let encoded = try? JSONEncoder().encode(found) else { return nil }
        await DiskCache.shared.store(encoded, for: cacheKey(placeId: placeId))
        return found
    }
}

/// Estado do Guia do dia (prompt 18 · C.16). Função da data e do `PlannedDay`: recalculada nos gatilhos, não no `body`.
@MainActor
@Observable
final class GuideModel {
    enum Status: Hashable, Sendable { case done, current, later }

    /// Uma parada do dia, já sem `@Model`.
    struct Stop: Identifiable, Hashable, Sendable {
        var id: UUID
        var placeId: String
        var name: String
        var at: Date
        var number: Int
        /// Selo do bairro da parada (kanji no Japão, sigla no BH).
        var areaSeal: String?
        var detail: String
        var color: MustColor
        var status: Status
        var isGolden: Bool
        var isNight: Bool
        var lat: Double
        var lng: Double
        /// Minutos de deslocamento até esta parada (do anterior, ou da origem na primeira).
        var legMinutes: Int?
        /// Hora de sair pra chegar a tempo (só na parada atual).
        var leaveAt: Date?
    }

    /// Deslocamento entre duas paradas: trecho de trem (com a linha), a pé ou metrô sem linha conhecida.
    struct Leg: Hashable, Sendable {
        var minutes: Int
        var line: LineRef?
        var walk: Bool
    }

    enum Row: Identifiable, Hashable, Sendable {
        case stop(Stop)
        case leg(id: String, Leg)
        case home(line: String, time: String, estimate: Bool)

        var id: String {
            switch self {
            case .stop(let s): "stop-\(s.id)"
            case .leg(let id, _): id
            case .home: "home"
            }
        }
    }

    /// Trecho do mini-mapa: `color` nil = a pé (pontilhado); senão a cor oficial da linha.
    struct MapPath: Hashable, Sendable {
        var points: [Area.Coordinate]
        var color: UInt32?
    }

    /// O que a busca de foto precisa de cada parada (cópia `Sendable`).
    struct PhotoTarget: Hashable, Sendable {
        var placeId: String
        var lat: Double
        var lng: Double
        var areaName: String?
    }

    private(set) var hasDay = false
    /// "Shinjuku" e `plus` = true ("Shinjuku+"). Sem foco, o bairro que mais aparece no dia.
    private(set) var title = "Hoje"
    private(set) var plus = false
    private(set) var seal = "済"
    private(set) var sealSub: String?
    private(set) var rows: [Row] = []
    private(set) var stops: [Stop] = []
    private(set) var paths: [MapPath] = []
    private(set) var current: Stop?
    /// Foto de cada parada (URL do Commons), à medida que chega.
    private(set) var photoURLs: [String: URL] = [:]
    @ObservationIgnored private var targets: [PhotoTarget] = []
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var cityName = ""

    /// Chave do `.task` das fotos: troca quando o dia troca.
    var photoKey: String { targets.map(\.placeId).joined(separator: ",") }

    /// Monta o guia a partir do dia aceito (ou nada, sem dia). Tudo sai de `PlannedDay`, `Area` e a tabela de vizinhos.
    func refresh(day: PlannedDay?, region: Region, now: Date, location: CLLocation?) {
        cityName = region.displayName
        guard let day else {
            hasDay = false
            rows = []
            stops = []
            paths = []
            current = nil
            targets = []
            return
        }
        hasDay = true
        let areas = AreaCatalog.areas(for: region)
        let assigner = AreaAssigner(areas: areas)
        let byId = Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let placed = day.orderedStops.compactMap { stop -> (Stop: PlannedDay.Entry, placeId: String)? in
            guard let place = stop.place else { return nil }
            return (PlannedDay.Entry(stop: stop, place: place), place.id)
        }
        let sun = placed.first.map { SunService.day($0.Stop.at, areas.first?.centroid.clCoordinate ?? region.defaultCenter, timeZone: region.timeZone) }
        let firstOpen = placed.firstIndex { !$0.Stop.done }

        // Título: o foco do dia ("Shinjuku+"); sem foco, o bairro que mais aparece no roteiro.
        var areaIds: [String?] = []
        for entry in placed {
            areaIds.append(assigner.areaId(name: entry.place.area, cityId: entry.place.cityId, lat: entry.place.lat, lng: entry.place.lng))
        }
        if let focusId = day.focusAreaId, let area = byId[focusId] {
            title = area.name
            plus = true
            seal = area.seal
            sealSub = area.stampSub
        } else {
            var counts: [String: Int] = [:]
            for id in areaIds.compactMap({ $0 }) { counts[id, default: 0] += 1 }
            let main = areaIds.compactMap { $0 }.first { counts[$0] == counts.values.max() }.flatMap { byId[$0] }
            title = main?.name ?? "Hoje"
            plus = false
            seal = main?.seal ?? "済"
            sealSub = main?.stampSub
        }

        var built: [Row] = []
        var built_stops: [Stop] = []
        var builtPaths: [MapPath] = []
        var previousPoint = location?.coordinate
        var previousArea: String?
        for (i, entry) in placed.enumerated() {
            let place = entry.place
            let point = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
            let areaId = areaIds[i]
            var leg: Leg?
            if let from = previousPoint {
                leg = Self.leg(fromArea: previousArea, toArea: areaId, from: from, to: point, areas: byId)
            }
            if i > 0, let leg { built.append(.leg(id: "leg-\(i)", leg)) }
            if let from = previousPoint {
                builtPaths.append(MapPath(points: [Area.Coordinate(lat: from.latitude, lng: from.longitude),
                                                   Area.Coordinate(lat: point.latitude, lng: point.longitude)],
                                          color: leg.flatMap { $0.walk ? nil : ($0.line?.rgb ?? 0x7A7F87) }))
            }
            let status: Status = entry.Stop.done ? .done : (i == firstOpen ? .current : .later)
            let at = entry.Stop.at
            let golden = sun.map { day in
                [day.goldenAM, day.goldenPM].contains { interval in
                    guard let interval else { return false }
                    return at >= interval.start.addingTimeInterval(-5 * 60) && at <= interval.end.addingTimeInterval(5 * 60)
                }
            } ?? false
            let hour = region.calendar.component(.hour, from: at)
            var leave: Date?
            if status == .current, let minutes = leg?.minutes {
                leave = region.calendar.date(byAdding: .minute, value: -(minutes + 5), to: at)
            }
            let stop = Stop(id: entry.Stop.id, placeId: place.id, name: place.name, at: at, number: i + 1,
                            areaSeal: areaId.flatMap { byId[$0]?.seal }, detail: Self.detail(place, region: region),
                            color: place.list?.color ?? .eat, status: status, isGolden: golden,
                            isNight: hour >= 20 || hour < 5, lat: place.lat, lng: place.lng,
                            legMinutes: leg?.minutes, leaveAt: leave)
            built.append(.stop(stop))
            built_stops.append(stop)
            previousPoint = point
            previousArea = areaId
        }

        // Último trem pra casa: a linha da estação principal do último bairro (Japão) ou a linha do metrô (BH).
        if let lastArea = areaIds.compactMap({ $0 }).last.flatMap({ byId[$0] }) {
            if region == .jp, let entry = LastTrain.jpEntry(stationId: lastArea.mainStation) {
                built.append(.home(line: entry.name, time: entry.time, estimate: true))
            }
        } else if region == .bh, let line = TransitLoader.load(region).lines.first, let last = line.lastTrain {
            built.append(.home(line: line.name, time: last, estimate: true))
        }

        rows = built
        stops = built_stops
        paths = builtPaths
        current = built_stops.first { $0.status == .current }
        targets = placed.map { PhotoTarget(placeId: $0.place.id, lat: $0.place.lat, lng: $0.place.lng,
                                           areaName: $0.place.area) }
    }

    /// Busca a foto de cada parada que ainda não tem (disco primeiro; rede só sem cópia). Sem rede, nada.
    func loadPhotos(photos: any PhotoProviding) async {
        let todo = targets.filter { photoURLs[$0.placeId] == nil && !requested.contains($0.placeId) }
        guard !todo.isEmpty else { return }
        requested.formUnion(todo.map(\.placeId))
        let city = cityName
        await withTaskGroup(of: (String, URL?).self) { group in
            for target in todo {
                group.addTask {
                    let photo = await GuidePhotos.photo(placeId: target.placeId,
                                                        coordinate: CLLocationCoordinate2D(latitude: target.lat, longitude: target.lng),
                                                        area: target.areaName, cityName: city, photos: photos)
                    return (target.placeId, photo.flatMap { URL(string: $0.url) })
                }
            }
            for await (id, url) in group {
                if let url { photoURLs[id] = url }
            }
        }
    }

    // MARK: Cálculo (puro, testável)

    /// Deslocamento entre duas paradas: a tabela de vizinhos quando os bairros estão ligados (trem ou a pé),
    /// senão a estimativa de sempre (`DaySolver.leg`: a pé até 1,5 km, metrô depois).
    static func leg(fromArea: String?, toArea: String?, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                    areas: [String: Area]) -> Leg {
        if let fromArea, let toArea, let edge = areas[fromArea]?.neighbors.first(where: { $0.areaId == toArea }) {
            return Leg(minutes: edge.minutes, line: edge.mode == .walk ? nil : edge.line, walk: edge.mode == .walk)
        }
        let estimate = DaySolver.leg(from, to, walkMax: 1.5)
        return Leg(minutes: estimate.minutes, line: nil, walk: estimate.mode == .walk)
    }

    /// "Must photo · ¥500 · fila ~20 min" (a linha de detalhe do cartão).
    static func detail(_ place: Place, region: Region) -> String {
        var parts: [String] = []
        if let list = place.list { parts.append("Must \(list.name)") }
        if let price = place.price, price > 0 { parts.append(region.money(price)) }
        if let queue = place.queueMinutes, queue > 0 { parts.append("fila ~\(queue) min") }
        return parts.joined(separator: " · ")
    }
}

extension GuideModel {
    /// Frase do botão "Ir pro <próximo> · saia HH:MM" (vazia quando o dia acabou).
    func goLabel(region: Region) -> String? {
        guard let current else { return nil }
        let when = region.timeString(current.leaveAt ?? current.at)
        return "Ir pro \(current.name) · saia \(when)"
    }
}
