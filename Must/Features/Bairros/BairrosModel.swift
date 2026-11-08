import CoreLocation
import Foundation
import Observation
import SwiftData
import SwiftUI

/// Geometria da tela Bairros (prompt 18 · C.14), pura e testável: raio das bolhas e projeção lat/lng → ponto da tela.
enum BairroGeometry {
    /// Diâmetro da bolha ∝ √musts (26 pt sem nada, 76 pt no teto).
    static func diameter(count: Int) -> CGFloat {
        min(76, 26 + 8 * CGFloat(Double(max(0, count)).squareRoot()))
    }

    /// Lat/lng → ponto da tela, com o centro da câmera no meio da tela. `metersPerPoint` é o do centro (chão).
    static func project(lat: Double, lng: Double, camera: MapCameraState, size: CGSize) -> CGPoint {
        let (x0, y0) = mercator(camera.center.latitude, camera.center.longitude)
        let (x, y) = mercator(lat, lng)
        let k = cos(camera.center.latitude * .pi / 180) / max(camera.metersPerPoint, 1e-9)
        return CGPoint(x: size.width / 2 + (x - x0) * k, y: size.height / 2 - (y - y0) * k)
    }

    static func mercator(_ lat: Double, _ lng: Double) -> (Double, Double) {
        let r = 6_378_137.0
        return (lng * .pi / 180 * r, log(tan(.pi / 4 + lat * .pi / 360)) * r)
    }
}

/// Uma bolha do mapa: um bairro com musts.
struct AreaBubble: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var count: Int
    var openCount: Int
    /// Categoria que mais aparece.
    var color: MustColor
    /// Kanji no maior bairro (Japão). `nil` no resto.
    var kanji: String?
    var lat: Double
    var lng: Double
    var diameter: CGFloat
}

/// Ligação entre dois bairros vizinhos com musts: tracejado e o tempo no meio.
struct AreaEdge: Identifiable, Hashable, Sendable {
    var id: String
    var aLat: Double
    var aLng: Double
    var bLat: Double
    var bLng: Double
    var minutes: Int
}

/// Uma fatia da barra de mistura do bairro.
struct MixPart: Identifiable, Hashable, Sendable {
    var color: MustColor
    var count: Int
    var id: MustColor { color }
}

/// Vizinho na sheet ("Junto, a poucos minutos").
struct NeighborChip: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var minutes: Int
    var mode: TransitMode
    var line: LineRef?
}

/// O que a sheet de um bairro mostra. Calculado ao escolher o bairro, nunca no `body`.
struct BairroSheet: Hashable, Sendable {
    var area: Area
    var count: Int
    var openCount: Int
    var mix: [MixPart]
    /// "22 min · 3,4 km" a partir de você (`nil` sem GPS).
    var travelText: String?
    var neighbors: [NeighborChip]
    /// Frase do assistente com a ordem sugerida (o solver por área, sem LLM).
    var phrase: String
}

/// Estado da tela Bairros (C.14). Recalcula só nos gatilhos (lugares, minuto, posição, escolher um bairro).
@MainActor
@Observable
final class BairrosModel {
    private(set) var region: Region
    /// Tabela de bairros da região (`AreaCatalog`).
    private(set) var areas: [Area]
    private(set) var index = AreaIndex.empty
    private(set) var bubbles: [AreaBubble] = []
    private(set) var edges: [AreaEdge] = []
    /// Cena do mapa: papel + linhas de trem + você. Só muda nos gatilhos (não no `body`).
    private(set) var scene: MapScene
    private(set) var selectedId: String?
    private(set) var sheet: BairroSheet?
    /// Câmera reportada pelo `MapLibreView`: a posição das bolhas sai daqui.
    var camera: MapCameraState?

    @ObservationIgnored private var places: [Place] = []
    @ObservationIgnored private var here: CLLocation?
    @ObservationIgnored private var now = Date()
    @ObservationIgnored private var trip: TripInfo?
    @ObservationIgnored private var settings: Settings?
    @ObservationIgnored private let openIndex = OpenNowIndex()

    init(region: Region) {
        self.region = region
        areas = AreaCatalog.areas(for: region)
        scene = MapScene(region: region, layers: [.metro], pins: [], metro: Self.mainLines(TransitLoader.load(region)))
    }

    /// A tela chama ao aparecer: a região pode ser outra que a do modelo criado (tabelas e trilhos são cache estático).
    func prepare(region: Region) {
        guard region != self.region else { return }
        self.region = region
        areas = AreaCatalog.areas(for: region)
        scene = MapScene(region: region, layers: [.metro], pins: [], metro: Self.mainLines(TransitLoader.load(region)))
        selectedId = nil
        sheet = nil
    }

    /// Só as linhas que orientam (como no design): Yamanote/Chūō em Tóquio, as de Kyoto e o metrô de BH.
    /// Com todas as linhas de Tóquio as bolhas e os nomes somem no emaranhado.
    static let mainLineIds: Set<String> = ["JY", "JC", "K", "T-Kyoto", "1", "L1", "BH1"]

    static func mainLines(_ map: TransitMap) -> TransitMap {
        let kept = map.lines.filter { mainLineIds.contains($0.id) }
        // Sem nenhuma conhecida (outra região), mantém tudo.
        guard !kept.isEmpty else { return map }
        let ids = Set(kept.map(\.id))
        return TransitMap(lines: kept, stations: map.stations.filter { !Set($0.lines).isDisjoint(with: ids) },
                          attribution: map.attribution)
    }

    /// Centro e largura da câmera de entrada: o bairro pedido, senão o centro da região (escala de bairros).
    /// Com bolhas: enquadra as bolhas da cidade (a maior e as que estão a até ~8 km dela), acima da sheet.
    func initialCommand(areaId: String?, near location: CLLocation? = nil, compact: Bool = false) -> MapCameraCommand {
        let c = areaId.flatMap { id in areas.first { $0.id == id }?.centroid.clCoordinate } ?? region.defaultCenter
        // Âncora: o bairro pedido (sheet aberta), senão o mais perto de você (até 3 km), senão o que tem mais musts.
        let nearest = location.flatMap { here in
            bubbles.min { CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: here) < CLLocation(latitude: $1.lat, longitude: $1.lng).distance(from: here) }
                .flatMap { CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: here) < 3_000 ? $0 : nil }
        }
        let picked = bubbles.first(where: { $0.id == areaId }) ?? nearest
        if let anchor = picked ?? bubbles.max(by: { $0.count < $1.count }) {
            let here = CLLocation(latitude: anchor.lat, longitude: anchor.lng)
            // Bairro escolhido ou perto de você: a vizinhança (5,5 km). Sem isso, a cidade inteira do maior bairro
            // (18 km: Tóquio de Nakano a Asakusa, sem puxar Kyoto).
            let radius: CLLocationDistance = picked == nil ? 18_000 : 5_500
            let near = bubbles.filter { CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: here) < radius }
            if near.count >= 2 {
                let points = near.map { MapCameraCommand.Coordinate(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)) }
                // Laterais com folga pro nome da bolha (o ponto é o centro; "ROPPONGI" cortava na borda).
                return MapCameraCommand(target: .fit(points: points, top: compact ? 30 : 150, bottom: compact ? 40 : (areaId == nil ? 220 : 470), sides: 72))
            }
        }
        return MapCameraCommand(target: .center(lat: c.latitude, lng: c.longitude, widthMeters: region.profile.transit?.areaMapWidth ?? 6_000))
    }

    /// Recalcula bolhas, arestas e índice. Chamado pela tela nos gatilhos (lugares, minuto, posição ≥ 50 m).
    func refresh(places: [Place], now: Date, location: CLLocation?, trip: TripInfo?, settings: Settings?) {
        self.places = places
        self.now = now
        self.here = location
        self.trip = trip
        self.settings = settings
        let snapshot = openIndex.snapshot(for: places, now: now, timeZone: region.timeZone, location: location)
        let openIds = Set(places.filter { snapshot.isOpen($0.id) }.map(\.id))
        index = AreaIndex.build(areas: areas, places: places.map(HomeState.areaPlace), openIds: openIds)

        let populated = index.populated
        let biggest = populated.max { $0.count < $1.count }?.id
        bubbles = populated.map { entry in
            AreaBubble(id: entry.id, name: entry.area.name, count: entry.count, openCount: entry.openCount,
                       color: entry.dominant ?? .eat, kanji: entry.id == biggest ? entry.area.nameLocal : nil,
                       lat: entry.area.centroid.lat, lng: entry.area.centroid.lng,
                       diameter: BairroGeometry.diameter(count: entry.count))
        }
        var seen: Set<String> = []
        edges = []
        for entry in populated {
            for n in entry.area.neighbors where n.minutes <= 15 {
                guard let other = index.entry(n.areaId), other.count > 0 else { continue }
                let key = AreaFocusPlan.pairKey(entry.id, n.areaId)
                guard seen.insert(key).inserted else { continue }
                edges.append(AreaEdge(id: key, aLat: entry.area.centroid.lat, aLng: entry.area.centroid.lng,
                                      bLat: other.area.centroid.lat, bLng: other.area.centroid.lng, minutes: n.minutes))
            }
        }
        scene = MapScene(region: region, layers: [.metro], pins: [], metro: scene.metro,
                         you: location?.coordinate)
        // A sheet acompanha o bairro escolhido (o GPS pode ter mudado o tempo até ele).
        if let selectedId { select(selectedId) }
    }

    /// Escolhe um bairro (ou tira a escolha com `nil`) e monta a sheet.
    func select(_ id: String?) {
        selectedId = id
        guard let id, let entry = index.entry(id) else { sheet = nil; return }
        let area = entry.area
        let mix = entry.mix.sorted { a, b in a.value != b.value ? a.value > b.value : a.key.rawValue < b.key.rawValue }
            .map { MixPart(color: $0.key, count: $0.value) }
        let neighbors = area.neighbors.filter { $0.minutes <= 15 }.sorted { $0.minutes < $1.minutes }.map {
            NeighborChip(id: $0.areaId, name: index.area($0.areaId)?.name ?? $0.areaId, minutes: $0.minutes, mode: $0.mode, line: $0.line)
        }
        var travelText: String?
        if let here {
            let target = CLLocation(latitude: area.centroid.lat, longitude: area.centroid.lng)
            let meters = here.distance(from: target)
            let minutes = DaySolver.leg(here.coordinate, area.centroid.clCoordinate, walkMax: 1.5).minutes
            travelText = "\(minutes) min · \(Walk.distanceText(meters))"
        }
        sheet = BairroSheet(area: area, count: entry.count, openCount: entry.openCount, mix: mix, travelText: travelText,
                            neighbors: neighbors, phrase: phrase(for: id))
    }

    /// Frase da ordem: o solver por área (bairro + vizinhos a 15 min) sem gravar nada.
    private func phrase(for areaId: String) -> String {
        let planner = DayPlanner(date: region.calendar.startOfDay(for: now), region: region, settings: settings, existing: nil)
        planner.focusArea = areaId
        let request = planner.request(trip: trip, settings: settings, location: here)
        let proposal = DaySolver.solve(request, catalog: places.solverCatalog)
        guard let plan = AreaFocusPlan(focus: .area(id: areaId, includeNeighbors: true, maxHopMinutes: 15), areas: AreaCatalog.all) else {
            return ""
        }
        let byId = Dictionary(proposal.stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return plan.sentence(for: proposal.stops) { id in byId[id].flatMap { plan.areaId(for: $0.place) } }
    }

    /// Monta o dia de hoje no bairro (com vizinhos) e grava. Devolve `false` se o solver não achou nada.
    @discardableResult
    func montar(areaId: String, context: ModelContext, flights: [DayFlight] = []) throws -> Bool {
        let planner = DayPlanner(date: region.calendar.startOfDay(for: now), region: region, settings: settings, existing: nil)
        planner.focusArea = areaId
        planner.build(catalog: places.solverCatalog, trip: trip, settings: settings, location: here, flights: flights)
        guard let proposal = planner.proposal, !proposal.stops.isEmpty else { return false }
        try planner.accept(context: context)
        return true
    }

    /// Posição de um ponto na tela (nil enquanto a câmera não reportou).
    func point(lat: Double, lng: Double, in size: CGSize) -> CGPoint? {
        guard let camera else { return nil }
        return BairroGeometry.project(lat: lat, lng: lng, camera: camera, size: size)
    }
}
