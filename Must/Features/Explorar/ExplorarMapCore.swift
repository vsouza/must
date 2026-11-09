import CoreLocation
import Foundation
import UIKit

// Explorar = o mapa (prompt 32 §4): a lógica pura da raiz da aba. Camadas, filtro por lista, o que está na tela, a lista agrupada
// por lista do board, o "Ver no mapa", a abertura e o centro do mapa como contexto. Sem SwiftUI, sem SwiftData, sem rede.

// MARK: - Camadas

/// Camadas do mapa (menu "Camadas"): Meus Musts sempre; Hoje = rota numerada do dia aceito; Agora = aberto agora, fecha logo,
/// eventos de hoje e luz dourada; Indicados = fora do board (desligada por padrão; só com rede e cota).
enum ExplorarMapLayer: String, CaseIterable, Identifiable, Sendable {
    case musts, today, now, indicated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .musts: "Meus Musts"
        case .today: "Hoje"
        case .now: "Agora"
        case .indicated: "Indicados"
        }
    }

    var systemImage: String {
        switch self {
        case .musts: "mappin.and.ellipse"
        case .today: "point.topleft.down.to.point.bottomright.curvepath"
        case .now: "clock"
        case .indicated: "sparkle.magnifyingglass"
        }
    }

    /// O que a camada mostra, em uma linha (subtítulo do menu).
    var caption: String {
        switch self {
        case .musts: "sempre ligada"
        case .today: "rota numerada do dia aceito"
        case .now: "aberto agora, fecha logo, eventos, luz dourada"
        case .indicated: "fora do seu board · usa internet"
        }
    }

    static let defaults: Set<ExplorarMapLayer> = [.musts, .today, .now]

    /// Liga/desliga; Meus Musts não desliga.
    static func toggled(_ layers: Set<ExplorarMapLayer>, _ layer: ExplorarMapLayer) -> Set<ExplorarMapLayer> {
        guard layer != .musts else { return layers.union([.musts]) }
        var next = layers
        if next.contains(layer) { next.remove(layer) } else { next.insert(layer) }
        return next.union([.musts])
    }
}

// MARK: - Itens

/// Um ponto do mapa (Must do board, evento de hoje ou indicado de fora). Cópia barata, montada nos gatilhos (nunca no `body`).
struct ExplorarMapItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable { case must, event, indicated }

    var id: String
    var kind: Kind
    var name: String
    var lat: Double
    var lng: Double
    /// Id do Lugar no board (`nil` = evento sem lugar ou de fora).
    var placeId: String?
    var listId: String?
    /// "eat", "drink"… (rótulo da lista, sem "Must").
    var listName: String = ""
    var color: MustColor?
    var done = false
    /// Número da parada no dia aceito de hoje (1…); `nil` = não é parada.
    var stopNumber: Int?
    var isNextStop = false
    var stopTime: String?
    /// Situação de horário (só aparece com a camada Agora).
    var open: PinOpenState = .unknown
    /// Horário do Google (confirmado). Falso = estimado ou desconhecido: "aberto agora" não afirma.
    var hoursConfirmed = true
    /// Lista de fotografia na luz dourada de hoje.
    var golden = false
    /// "seu Must eat · aberto até 22h" / "fora do board · ★ 4,4" / "evento · 19:00".
    var reason: String = ""
    var googleId: String?
    var eventId: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var isOwn: Bool { placeId != nil && kind == .must }

    /// O item como o Explorar antigo via (pra reaproveitar "Encaixar hoje" e "Guardar" do pino).
    func asExplorarItem(meters: Double) -> ExplorarItem {
        ExplorarItem(id: id, placeId: kind == .must ? placeId : nil, name: name, lat: lat, lng: lng,
                     tone: kind == .must ? (open == .open ? .own : .paper) : .outside, isOpen: open == .open, done: done,
                     inPlan: stopNumber != nil, meta: reason, meters: meters, planTime: stopTime, googleId: googleId,
                     hoursConfirmed: hoursConfirmed)
    }
}

enum ExplorarMapFilter {
    /// O que o mapa mostra: com "Ver no mapa" ativo, só os itens do pedido (o resto some, filtro e camadas não valem); senão
    /// os Musts do filtro por lista, os eventos (camada Agora) e os indicados (camada Indicados).
    static func shown(_ items: [ExplorarMapItem], layers: Set<ExplorarMapLayer>, filter: MapMustFilter,
                      showcase: Set<String>? = nil) -> [ExplorarMapItem] {
        if let showcase { return items.filter { showcase.contains($0.id) } }
        return items.filter { item in
            switch item.kind {
            case .must: filter.allows(listId: item.listId)
            case .event: layers.contains(.now)
            case .indicated: layers.contains(.indicated)
            }
        }
    }

    /// O que está dentro do quadro do mapa, do mais perto do centro pro mais longe (empate: nome).
    static func visible(_ items: [ExplorarMapItem], in rect: GeoRect, center: CLLocationCoordinate2D) -> [ExplorarMapItem] {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let inside = items.filter { rect.contains(lat: $0.lat, lng: $0.lng) }
        let measured: [(item: ExplorarMapItem, meters: Double)] = inside.map { item in
            (item, here.distance(from: CLLocation(latitude: item.lat, longitude: item.lng)))
        }
        let sorted = measured.sorted { a, b in
            if a.meters != b.meters { return a.meters < b.meters }
            return a.item.name < b.item.name
        }
        return sorted.map(\.item)
    }

    /// Uma seção da lista grande: uma por lista do board (na ordem do board), depois "Eventos de hoje" e "Indicados".
    struct Section: Identifiable, Hashable, Sendable {
        var id: String
        var title: String
        var color: MustColor?
        var items: [ExplorarMapItem]
    }

    static let eventsSection = "_events"
    static let indicatedSection = "_indicated"

    /// Agrupa por lista (ordem do board); dentro do grupo os feitos vão pro fim, o resto mantém a ordem recebida.
    static func sections(_ items: [ExplorarMapItem], lists: [(id: String, name: String)]) -> [Section] {
        var byList: [String: [ExplorarMapItem]] = [:]
        var events: [ExplorarMapItem] = []
        var indicated: [ExplorarMapItem] = []
        var orphans: [ExplorarMapItem] = []
        for item in items {
            switch item.kind {
            case .event: events.append(item)
            case .indicated: indicated.append(item)
            case .must:
                if let id = item.listId { byList[id, default: []].append(item) } else { orphans.append(item) }
            }
        }
        func doneLast(_ xs: [ExplorarMapItem]) -> [ExplorarMapItem] { xs.filter { !$0.done } + xs.filter(\.done) }
        var out: [Section] = []
        var seen: Set<String> = []
        for list in lists {
            guard let group = byList[list.id], !group.isEmpty, !seen.contains(list.id) else { continue }
            seen.insert(list.id)
            out.append(Section(id: list.id, title: MapMustFilter.label(list.name), color: group.first?.color, items: doneLast(group)))
        }
        // Lista que não veio na ordem (não deveria acontecer): no fim, por nome.
        for (id, group) in byList.sorted(by: { $0.key < $1.key }) where !seen.contains(id) {
            out.append(Section(id: id, title: MapMustFilter.label(group.first?.listName ?? id), color: group.first?.color, items: doneLast(group)))
        }
        if !orphans.isEmpty { out.append(Section(id: "_none", title: "Sem lista", color: nil, items: doneLast(orphans))) }
        if !events.isEmpty { out.append(Section(id: eventsSection, title: "Eventos de hoje", color: nil, items: events)) }
        if !indicated.isEmpty { out.append(Section(id: indicatedSection, title: "Indicados", color: nil, items: indicated)) }
        return out
    }

    /// Chips do topo: Todos e as listas com lugar, na ordem do board (Eat, Drink, See, Shop, Photo…).
    static func chips(items: [ExplorarMapItem], lists: [(id: String, name: String)]) -> [MapMustFilter.Count] {
        MapMustFilter.counts(listIdsOfPlaces: items.filter { $0.kind == .must }.map(\.listId), lists: lists).lists
    }
}

// MARK: - Pinos

enum ExplorarMapPins {
    /// Pinos do mapa a partir do que está sendo mostrado. Hoje desligada = as paradas viram pino normal; Agora desligada =
    /// sem estado de horário (pino neutro) e sem eventos.
    static func pins(_ shown: [ExplorarMapItem], layers: Set<ExplorarMapLayer>, selected: String?) -> [MapPin] {
        shown.map { item in
            let style: MapPin.V9Style
            switch item.kind {
            case .event: style = .event
            case .indicated: style = .indicated
            case .must:
                if let n = item.stopNumber, layers.contains(.today) {
                    style = .stop(number: n, next: item.isNextStop, done: item.done)
                } else if item.done {
                    style = .done
                } else {
                    let state: PinOpenState
                    if layers.contains(.now) { state = item.golden ? .open : item.open } else { state = .unknown }
                    style = .must(letter: letter(item), rgb: rgb(item.color), state: state)
                }
            }
            return MapPin(id: item.id, coordinate: item.coordinate, kind: .v9(style: style, selected: item.id == selected),
                          placeId: item.placeId, layer: .search)
        }
    }

    /// Rota do dia aceito (camada Hoje): trechos já feitos e os que faltam, em linha reta entre as paradas (offline).
    static func route(_ shown: [ExplorarMapItem], layers: Set<ExplorarMapLayer>)
        -> (done: [[CLLocationCoordinate2D]], future: [[CLLocationCoordinate2D]]) {
        guard layers.contains(.today) else { return ([], []) }
        let stops = shown.filter { $0.stopNumber != nil }.sorted { ($0.stopNumber ?? 0) < ($1.stopNumber ?? 0) }
        var done: [[CLLocationCoordinate2D]] = [], future: [[CLLocationCoordinate2D]] = []
        for (a, b) in zip(stops, stops.dropFirst()) {
            if b.done { done.append([a.coordinate, b.coordinate]) } else { future.append([a.coordinate, b.coordinate]) }
        }
        return (done, future)
    }

    /// Letra latina da lista (E de eat, D de drink…): nada de kanji no pino.
    static func letter(_ item: ExplorarMapItem) -> String {
        String((item.listName.isEmpty ? item.name : item.listName).prefix(1)).uppercased()
    }

    /// Cor da lista no pino (V9: cores do sistema, calmas; o acento laranja fica só pro selecionado).
    static func rgb(_ color: MustColor?) -> UInt32 {
        switch color {
        case .eat?: 0x34A853
        case .drink?: 0x1E88E5
        case .coffee?: 0x8D6E63
        case .see?: 0x8E5CD9
        case .temple?: 0x14A3A3
        case .listen?: 0xE0457B
        case .shop?: 0xE0A100
        case .night?: 0x5856D6
        case .photo?: 0x0A9FC9
        case .art?: 0xB0569E
        case .sport?: 0x5F7A8C
        case nil: 0x6B7280
        }
    }
}

// MARK: - Centro do mapa = contexto

enum ExplorarCenter {
    /// Só recalcula o ranking quando o centro andou mais que isso (arrastar 20 m não refaz nada).
    static let minMoveMeters: Double = 80
    /// Debounce depois que a câmera para.
    static let debounce: Duration = .milliseconds(400)
    /// Largura da tela na abertura (escala de bairro).
    static let openingWidth: Double = 1_600

    static func moved(from old: CLLocationCoordinate2D?, to new: CLLocationCoordinate2D) -> Bool {
        guard let old else { return true }
        return CLLocation(latitude: old.latitude, longitude: old.longitude)
            .distance(from: CLLocation(latitude: new.latitude, longitude: new.longitude)) >= minMoveMeters
    }

    /// Onde o mapa abre: na sua posição se você está na cidade da viagem; senão no bairro do contexto de Hoje; senão no
    /// centro da cidade.
    static func opening(gps: CLLocationCoordinate2D?, cityCenter: CLLocationCoordinate2D, contextArea: Area?) -> CLLocationCoordinate2D {
        if let gps, DaySolver.streetKm(gps, cityCenter) < WantOrigin.cityKm { return gps }
        if let contextArea { return contextArea.centroid.clCoordinate }
        return cityCenter
    }

    /// O retângulo que o mapa mostra (mesma projeção do MapLibre).
    static func rect(center: CLLocationCoordinate2D, widthMeters: Double, size: CGSize) -> GeoRect {
        ExplorarProjection(center: center, widthMeters: widthMeters, size: size).rect
    }
}

// MARK: - Ver no mapa

enum ExplorarShowcaseLogic {
    /// Ids dos itens do pedido: os lugares do board que existem e um item de fora pra cada ponto (`show-<i>`).
    static func items(_ showcase: MapShowcase, board: [ExplorarMapItem]) -> (ids: Set<String>, extra: [ExplorarMapItem]) {
        let wanted = Set(showcase.placeIds)
        var ids = Set(board.filter { $0.kind == .must && $0.placeId.map(wanted.contains) == true }.map(\.id))
        var extra: [ExplorarMapItem] = []
        for (i, point) in showcase.outside.enumerated() where point.lat != 0 || point.lng != 0 {
            let item = ExplorarMapItem(id: "show-\(i)-\(point.name)", kind: .indicated, name: point.name, lat: point.lat, lng: point.lng,
                                       reason: "fora do board")
            extra.append(item)
            ids.insert(item.id)
        }
        return (ids, extra)
    }

    /// Raio do grupo enquadrado: pedido com lugares de duas cidades (Tóquio e Kyoto) enquadra só a da vez.
    static let clusterKm: Double = 25

    /// Pontos a enquadrar: os do grupo mais perto de `near` (o centro do mapa), pra não abrir num zoom de país.
    static func fitPoints(_ items: [ExplorarMapItem], near: CLLocationCoordinate2D? = nil) -> [MapCameraCommand.Coordinate] {
        let valid = items.filter { $0.lat != 0 || $0.lng != 0 }
        guard let first = valid.first else { return [] }
        let ref = near ?? first.coordinate
        let anchor = valid.min { DaySolver.streetKm(ref, $0.coordinate) < DaySolver.streetKm(ref, $1.coordinate) } ?? first
        return valid.filter { DaySolver.streetKm(anchor.coordinate, $0.coordinate) <= clusterKm * 1.25 }
            .map { MapCameraCommand.Coordinate($0.coordinate) }
    }
}

// MARK: - Altura do painel

/// O painel de baixo (três alturas, como a sheet do Mapas): recolhido, médio e grande.
enum ExplorarDetent: Int, CaseIterable, Sendable {
    case collapsed, medium, large

    /// Toque no pegador: sobe um degrau; no grande, volta pro recolhido.
    var next: ExplorarDetent {
        switch self {
        case .collapsed: .medium
        case .medium: .large
        case .large: .collapsed
        }
    }

    /// Altura de cada degrau dentro de `available` (área livre entre o topo dos controles e o pé).
    static func height(_ detent: ExplorarDetent, collapsed: CGFloat, available: CGFloat) -> CGFloat {
        switch detent {
        case .collapsed: min(collapsed, available)
        case .medium: min(max(collapsed, available * 0.5), available)
        case .large: available
        }
    }

    /// Fim do arrasto: o degrau mais perto da altura projetada (com a velocidade).
    static func settle(predicted: CGFloat, collapsed: CGFloat, available: CGFloat) -> ExplorarDetent {
        allCases.min { a, b in
            abs(Self.height(a, collapsed: collapsed, available: available) - predicted)
                < abs(Self.height(b, collapsed: collapsed, available: available) - predicted)
        } ?? .collapsed
    }
}
