import CoreLocation
import Foundation
import Observation
import SwiftData
import SwiftUI

/// Estado do Guia do dia (prompt 18 · C.16). Função do `PlannedDay` e da posição; recalculada nos gatilhos, não no `body`.
@MainActor
@Observable
final class GuideModel {
    enum Status: Hashable, Sendable { case done, current, later }

    /// Uma parada do dia, já sem `@Model`.
    struct GuideStop: Identifiable, Hashable, Sendable {
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
    struct GuideLeg: Hashable, Sendable {
        var minutes: Int
        var line: LineRef?
        var walk: Bool
    }

    enum Row: Identifiable, Hashable, Sendable {
        case stop(GuideStop)
        case leg(id: String, GuideLeg)
        case home(label: String, time: String)

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

    private(set) var hasDay = false
    /// "Shinjuku" e `plus` = true ("Shinjuku+"). Sem foco, o bairro que mais aparece no roteiro.
    private(set) var title = "Hoje"
    private(set) var plus = false
    private(set) var seal = "済"
    private(set) var sealSub: String?
    private(set) var rows: [Row] = []
    private(set) var stops: [GuideStop] = []
    private(set) var paths: [MapPath] = []
    /// Parada que vem agora (a primeira não feita). `nil` = dia feito ou sem dia.
    private(set) var current: GuideStop?
    /// Fotos do Google já guardadas de cada lugar (`PlaceThumb` decide o resto).
    private(set) var photoRefs: [String: [PlacePhotoRef]] = [:]
    /// Mini-mapa: papel, trilhos e o percurso com as paradas numeradas.
    private(set) var scene = MapScene(region: .jp, layers: [], pins: [], metro: .empty)

    /// Monta o guia a partir do dia aceito: paradas, deslocamentos (tabela de vizinhos, offline) e o último trem.
    func refresh(day: PlannedDay?, region: Region, location: CLLocation?) {
        guard let day else {
            hasDay = false
            rows = []
            stops = []
            paths = []
            current = nil
            photoRefs = [:]
            scene = MapScene(region: region, layers: [], pins: [], metro: TransitLoader.load(region))
            return
        }
        hasDay = true
        let areas = AreaCatalog.areas(for: region)
        let assigner = AreaAssigner(areas: areas)
        let byId = Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let placed: [(stop: Stop, place: Place)] = day.orderedStops.compactMap { stop in
            stop.place.map { (stop, $0) }
        }
        let areaIds: [String?] = placed.map { entry in
            assigner.areaId(name: entry.place.area, cityId: entry.place.cityId, lat: entry.place.lat, lng: entry.place.lng)
        }

        // Título: o foco do dia ("Shinjuku+"); sem foco, o bairro que mais aparece no roteiro.
        // Dia criado pelo Colar texto só tem o nome ("Asakusa e Ueno"): vale o primeiro bairro reconhecido.
        let first = placed.first?.place
        let focusFromName = day.focusAreaName.flatMap { name in
            GuideModel.focusParts(name).lazy.compactMap { part in
                assigner.areaId(name: part, cityId: first?.cityId ?? "", lat: first?.lat ?? 0, lng: first?.lng ?? 0)
                    .flatMap { byId[$0]?.name == nil ? nil : $0 }
            }.first
        }
        if let focusId = day.focusAreaId ?? focusFromName, let area = byId[focusId] {
            title = area.name
            plus = true
            seal = area.seal
            sealSub = area.stampSub
        } else {
            var counts: [String: Int] = [:]
            for id in areaIds.compactMap({ $0 }) { counts[id, default: 0] += 1 }
            let best = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key
            let main = best.flatMap { byId[$0] }
            title = main?.name ?? "Hoje"
            plus = false
            seal = main?.seal ?? "済"
            sealSub = main?.stampSub
        }

        // Luz do dia (golden da manhã e da tarde) no centro do primeiro lugar.
        let sun = placed.first.map { entry in
            SunService.day(entry.stop.at, CLLocationCoordinate2D(latitude: entry.place.lat, longitude: entry.place.lng),
                           timeZone: region.timeZone)
        }
        let firstOpen = placed.firstIndex { !$0.stop.done }

        var built: [Row] = []
        var builtStops: [GuideStop] = []
        var builtPaths: [MapPath] = []
        var builtRefs: [String: [PlacePhotoRef]] = [:]
        var previousPoint = location?.coordinate
        var previousArea: String?
        for (i, entry) in placed.enumerated() {
            let place = entry.place
            let point = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lng)
            let areaId = areaIds[i]
            builtRefs[place.id] = place.photoRefs
            var leg: GuideLeg?
            if let from = previousPoint {
                let l = Self.leg(fromArea: previousArea, toArea: areaId, from: from, to: point, areas: byId)
                leg = l
                builtPaths.append(MapPath(points: [Area.Coordinate(lat: from.latitude, lng: from.longitude),
                                                   Area.Coordinate(lat: point.latitude, lng: point.longitude)],
                                          color: l.walk ? nil : (l.line?.rgb ?? 0x7A7F87)))
            }
            if i > 0, let leg { built.append(.leg(id: "leg-\(i)", leg)) }

            let status: Status = entry.stop.done ? .done : (i == firstOpen ? .current : .later)
            let at = entry.stop.at
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
            let stop = GuideStop(id: entry.stop.id, placeId: place.id, name: place.name, at: at, number: i + 1,
                                 areaSeal: areaId.flatMap { byId[$0]?.seal }, detail: Self.detail(place, region: region),
                                 color: place.list?.color ?? .eat, status: status, isGolden: golden,
                                 isNight: hour >= 20 || hour < 5, lat: place.lat, lng: place.lng,
                                 legMinutes: leg?.minutes, leaveAt: leave)
            built.append(.stop(stop))
            builtStops.append(stop)
            previousPoint = point
            previousArea = areaId
        }

        // Último trem pra casa: a tabela que já existe (`LastTrains`, prompt 17) a partir da última parada.
        let lastPoint = builtStops.last.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        if let last = LastTrains.home(region: region, near: lastPoint, transit: TransitLoader.load(region)) {
            built.append(.home(label: last.label, time: last.time))
        }

        rows = built
        stops = builtStops
        paths = builtPaths
        photoRefs = builtRefs
        current = builtStops.first { $0.status == .current }
        scene = MapScene(region: region, layers: [.metro, .today], pins: builtStops.map(Self.pin),
                         metro: TransitLoader.load(region),
                         legs: builtPaths.map { path in
                             MapLegPath(coordinates: path.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) },
                                        color: path.color)
                         })
    }

    /// Enquadra o percurso no mini-mapa (uma vez, ao abrir).
    func fitCommand() -> MapCameraCommand? {
        let points = stops.map { MapCameraCommand.Coordinate(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)) }
        guard !points.isEmpty else { return nil }
        return MapCameraCommand(target: .fit(points: points, top: 28, bottom: 28, sides: 44))
    }

    // MARK: Cálculo (puro, testável)

    /// Número da parada no mini-mapa, com o estado (feito, agora, depois).
    static func pin(_ stop: GuideStop) -> MapPin {
        let status: MapPin.TodayStatus = switch stop.status {
        case .done: .done
        case .current: .next
        case .later: .future
        }
        return MapPin(id: "guide-\(stop.id)", coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng),
                      kind: .today(number: stop.number, status: status, label: nil), placeId: stop.placeId, layer: .today)
    }

    /// Deslocamento entre duas paradas: a tabela de vizinhos quando os bairros estão ligados (trem ou a pé),
    /// senão a estimativa de sempre (`DaySolver.leg`: a pé até 1,5 km, metrô depois). Sem rede em nenhum caso.
    static func leg(fromArea: String?, toArea: String?, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                    areas: [String: Area]) -> GuideLeg {
        if let fromArea, let toArea, let edge = areas[fromArea]?.neighbors.first(where: { $0.areaId == toArea }) {
            return GuideLeg(minutes: edge.minutes, line: edge.mode == .walk ? nil : edge.line, walk: edge.mode == .walk)
        }
        let estimate = DaySolver.leg(from, to, walkMax: 1.5)
        return GuideLeg(minutes: estimate.minutes, line: nil, walk: estimate.mode == .walk)
    }

    /// "Must photo · ¥500 · fila ~20 min" (a linha de detalhe do cartão).
    static func detail(_ place: Place, region: Region) -> String {
        var parts: [String] = []
        if let list = place.list { parts.append("Must \(list.name)") }
        if let price = place.price, price > 0 { parts.append(region.money(price)) }
        if let queue = place.queueMinutes, queue > 0 { parts.append("fila ~\(queue) min") }
        return parts.joined(separator: " · ")
    }

    /// "Ir pro Fuunji · saia 14:35" (nil quando o dia acabou).
    func goLabel(region: Region) -> String? {
        guard let current else { return nil }
        return "Ir pro \(current.name) · saia \(region.timeString(current.leaveAt ?? current.at))"
    }
}

extension GuideModel {
    /// Puro (sem estado): usado fora do main também.
    /// "Asakusa e Ueno", "Shibuya + Harajuku", "Gion, Higashiyama" → cada bairro, na ordem.
    nonisolated static func focusParts(_ name: String) -> [String] {
        name.replacingOccurrences(of: " e ", with: ",").replacingOccurrences(of: "+", with: ",")
            .replacingOccurrences(of: "/", with: ",").replacingOccurrences(of: "&", with: ",")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
