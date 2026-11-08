import CoreLocation
import Foundation

// Explorar (prompt 31 · 8, `design/v9/ExplorarB-*.png`): a lógica pura, sem SwiftUI e sem rede. Ordem do trilho por tempo de
// trem, marcas dos bairros (aqui, hoje, feito), as quatro camadas, a sincronização lista ↔ pinos e a projeção do recorte.

// MARK: - Trilho de estações

/// Uma estação do trilho: um bairro, os minutos de trem desde a origem e a marca ao lado.
struct ExplorarStation: Identifiable, Hashable, Sendable {
    enum Mark: Hashable, Sendable {
        /// Onde você está (quadrado laranja).
        case here
        /// Bairro de um dia montado; `time` = "19h" (nil = só "hoje").
        case today(time: String?)
        /// Todos os Musts do bairro já feitos.
        case done
        case other
    }

    var area: Area
    var minutes: Int
    var mark: Mark
    var id: String { area.id }

    /// "5 min", "aqui", "hoje 19h", "feito" (a legenda da estação, em caixa alta na tela).
    var caption: String {
        switch mark {
        case .here: "aqui"
        case .today(let time): time.map { "hoje \($0)" } ?? "hoje"
        case .done: "feito"
        case .other: minutes == 0 ? "hotel" : "\(minutes) min"
        }
    }
}

enum ExplorarRail {
    /// Minutos de trem (ou a pé/ônibus, o que a tabela diz) de `originId` até cada bairro alcançável, pelo grafo de vizinhos
    /// da tabela curada (nas duas mãos). Dijkstra simples: são poucas dezenas de bairros.
    static func minutes(from originId: String, areas: [Area]) -> [String: Int] {
        var edges: [String: [(String, Int)]] = [:]
        for area in areas {
            for n in area.neighbors {
                edges[area.id, default: []].append((n.areaId, n.minutes))
                edges[n.areaId, default: []].append((area.id, n.minutes))
            }
        }
        var best: [String: Int] = [originId: 0]
        var open: Set<String> = [originId]
        while let current = open.min(by: { best[$0]! < best[$1]! }) {
            open.remove(current)
            for (next, cost) in edges[current] ?? [] {
                let candidate = best[current]! + cost
                if best[next] == nil || candidate < best[next]! {
                    best[next] = candidate
                    open.insert(next)
                }
            }
        }
        return best
    }

    /// A estimativa quando o grafo não chega lá (bairro sem vizinhos na tabela): linha reta, 2,5 min/km + 6.
    static func fallbackMinutes(from a: Area, to b: Area) -> Int {
        let km = DaySolver.streetKm(a.centroid.clCoordinate, b.centroid.clCoordinate)
        return Int((km * 2.5 + 6).rounded(.up))
    }

    /// As estações da cidade `cityGroup`, em ordem de tempo a partir de `originId` (a origem primeiro, 0 min).
    /// Entram bairros com Musts, os de dias montados, os vizinhos desses e a origem. Empate: nome.
    static func stations(areas: [Area], cityGroup: String, originId: String?, populated: Set<String>, today: [String: String?],
                         done: Set<String>, hereId: String?) -> [ExplorarStation] {
        let city = areas.filter { AreaCatalog.cityGroup(forCityId: $0.cityId) == cityGroup }
        guard !city.isEmpty else { return [] }
        let origin = city.first { $0.id == originId } ?? city.first { populated.contains($0.id) } ?? city[0]
        let reach = minutes(from: origin.id, areas: city)
        var neighborsOfToday: Set<String> = []
        for area in city where today[area.id] != nil { neighborsOfToday.formUnion(area.neighbors.map(\.areaId)) }
        let eligible = city.filter { area in
            area.id == origin.id || populated.contains(area.id) || today[area.id] != nil || neighborsOfToday.contains(area.id)
        }
        let sorted = eligible.map { area -> (Area, Int) in
            (area, reach[area.id] ?? fallbackMinutes(from: origin, to: area))
        }
        .sorted { a, b in a.1 != b.1 ? a.1 < b.1 : a.0.name < b.0.name }
        return sorted.map { area, minutes in
            let mark: ExplorarStation.Mark
            if area.id == hereId { mark = .here }
            else if let time = today[area.id] { mark = .today(time: time) }
            else if done.contains(area.id) { mark = .done }
            else { mark = .other }
            return ExplorarStation(area: area, minutes: area.id == origin.id ? 0 : minutes, mark: mark)
        }
    }

    /// Bairro de partida: o do GPS (dentro da cidade), senão o do dia, senão o primeiro da cidade (o "hotel" da tabela).
    static func origin(hereId: String?, planAreaId: String?, areas: [Area], cityGroup: String) -> String? {
        let ids = Set(areas.filter { AreaCatalog.cityGroup(forCityId: $0.cityId) == cityGroup }.map(\.id))
        if let hereId, ids.contains(hereId) { return hereId }
        if let planAreaId, ids.contains(planAreaId) { return planAreaId }
        return areas.first { AreaCatalog.cityGroup(forCityId: $0.cityId) == cityGroup }?.id
    }

    /// Bairro anterior/próximo na ordem do trilho (deslize no bloco). Nas pontas, fica onde está.
    static func step(_ stations: [ExplorarStation], from id: String, by delta: Int) -> String? {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { return stations.first?.id }
        return stations[min(max(index + delta, 0), stations.count - 1)].id
    }

    /// Estação sob o dedo no trilho: `fraction` 0…1 de cima pra baixo.
    static func station(atFraction fraction: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(Int((fraction * Double(count)).rounded(.down)), 0), count - 1)
    }
}

// MARK: - Camadas e índice

enum ExplorarLayer: String, CaseIterable, Identifiable, Sendable {
    case openNow, own, outside, trail

    var id: String { rawValue }

    /// Rótulo da célula (duas linhas no máximo).
    var label: String {
        switch self {
        case .openNow: "aberto agora"
        case .own: "seus musts"
        case .outside: "fora do board"
        case .trail: "trilha do dia"
        }
    }

    static let standard: Set<ExplorarLayer> = [.own, .outside, .trail]
}

/// Uma linha do índice (e um pino). Sem SwiftData: cópia barata, calculada fora do `body`.
struct ExplorarItem: Identifiable, Hashable, Sendable {
    enum Tone: String, Hashable, Sendable {
        /// Seu Must aberto agora (laranja).
        case own
        /// Seu Must fechado, sem horário ou parada do plano (papel).
        case paper
        /// De fora do board (tinta).
        case outside
    }

    var id: String
    /// Id do Lugar no board (`nil` = fora do board).
    var placeId: String?
    var name: String
    var lat: Double
    var lng: Double
    var tone: Tone
    var isOpen: Bool
    var done: Bool
    /// Parada de um dia montado.
    var inPlan: Bool
    /// "seu Must eat · fila 15 min · fecha 21h" / "fora do board · ★ 4,4 · lotado".
    var meta: String
    /// Metros desde a origem da lista (GPS ou o centro do bairro).
    var meters: Double
    /// Número do pino na ordem atual (1…); `nil` = ponto de 8 pt (passou do limite de números).
    var number: Int? = nil
    /// "15:30" quando o Must já é parada do dia (o bloco do pino mostra "no dia · 15:30" em vez de "+ dia").
    var planTime: String? = nil
    /// Id do Google (fora do board) pra guardar no board sem perder o placeId.
    var googleId: String? = nil
    /// O horário vem do Google (confirmado). Falso = estimado (seed) ou desconhecido: "aberto agora" não afirma.
    var hoursConfirmed: Bool = true

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var isOwn: Bool { placeId != nil }
}

struct GeoRect: Hashable, Sendable {
    var minLat: Double, maxLat: Double, minLng: Double, maxLng: Double

    func contains(lat: Double, lng: Double) -> Bool {
        lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng
    }
}

enum ExplorarLayers {
    /// Quantos pinos levam número (os outros viram ponto de 8 pt).
    static let numberedLimit = 9

    /// O que cada camada liga. `openNow` é filtro: só o que está aberto. `trail` não tem item: é a linha.
    static func filter(_ items: [ExplorarItem], layers: Set<ExplorarLayer>) -> [ExplorarItem] {
        items.filter { item in
            if item.isOwn ? !layers.contains(.own) : !layers.contains(.outside) { return false }
            // "Aberto agora" só tira o que se sabe fechado: sem horário confirmado fica (marcado), não some.
            if layers.contains(.openNow), !item.isOpen, item.hoursConfirmed { return false }
            return true
        }
    }

    /// A ordem do índice: seus Musts abertos primeiro (mais perto antes), depois o resto seu, depois os de fora; feitos por último
    /// dentro de cada grupo. Estável (empate: nome).
    static func sorted(_ items: [ExplorarItem]) -> [ExplorarItem] {
        func rank(_ item: ExplorarItem) -> Int {
            if item.isOwn { return (item.done ? 2 : 0) + (item.isOpen ? 0 : 1) }
            return 4
        }
        return items.sorted { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            if a.meters != b.meters { return a.meters < b.meters }
            return a.name < b.name
        }
    }

    /// Numera na ordem recebida (pino = linha do índice).
    static func numbered(_ items: [ExplorarItem]) -> [ExplorarItem] {
        items.enumerated().map { index, item in
            var copy = item
            copy.number = index < numberedLimit ? index + 1 : nil
            return copy
        }
    }

    /// O que a lista mostra e os pinos desenham: filtrado pelas camadas, e (com `rect`) só o que está dentro do quadro do mapa,
    /// renumerado — o número do pino é sempre a posição na lista ("na tela · N", "pino 1 de N").
    static func listed(_ items: [ExplorarItem], layers: Set<ExplorarLayer>, in rect: GeoRect? = nil) -> [ExplorarItem] {
        var out = sorted(filter(items, layers: layers))
        if let rect { out = out.filter { rect.contains(lat: $0.lat, lng: $0.lng) } }
        return numbered(out)
    }

    /// Pino selecionado → posição na lista (0-based).
    static func index(ofPin id: String, in list: [ExplorarItem]) -> Int? { list.firstIndex { $0.id == id } }

    /// Deslizar o bloco do pino: o próximo (ou o anterior), parando nas pontas.
    static func neighbor(of id: String, in list: [ExplorarItem], by delta: Int) -> String? {
        guard let i = index(ofPin: id, in: list) else { return list.first?.id }
        return list[min(max(i + delta, 0), list.count - 1)].id
    }

    /// "14 Musts seus · 6 de fora · 11 abertos".
    static func counts(_ items: [ExplorarItem]) -> (own: Int, outside: Int, open: Int) {
        (items.filter(\.isOwn).count, items.filter { !$0.isOwn }.count, items.filter(\.isOpen).count)
    }

    /// O que a camada "aberto agora" sabe dizer: nunca um 0 seco quando falta horário confirmado.
    static func openSummary(_ items: [ExplorarItem]) -> ExplorarOpenSummary {
        ExplorarOpenSummary(confirmed: items.filter { $0.isOpen && $0.hoursConfirmed }.count,
                            estimated: items.filter { $0.isOpen && !$0.hoursConfirmed }.count,
                            unknown: items.filter { !$0.isOpen && !$0.hoursConfirmed }.count)
    }

    /// A trilha do dia: as paradas do plano dentro do bairro, em ordem (a linha laranja de 3 pt).
    static func trail(stops: [CLLocationCoordinate2D]) -> [[CLLocationCoordinate2D]] {
        stops.count >= 2 ? [stops] : []
    }
}

/// Contagem da camada "aberto agora": confirmados, abertos só por horário estimado e sem horário nenhum.
struct ExplorarOpenSummary: Equatable, Sendable {
    var confirmed: Int
    var estimated: Int
    var unknown: Int

    /// "aberto agora · 2 · 14 sem horário" / "aberto agora · 5" / "aberto agora · nenhum" (só quando tudo é confirmado e fechado).
    var label: String {
        var parts = ["aberto agora"]
        if confirmed > 0 { parts.append("\(confirmed)") }
        else if estimated == 0 && unknown == 0 { parts.append("nenhum") }
        if estimated > 0 { parts.append("\(estimated) \(estimated == 1 ? "estimado" : "estimados")") }
        if unknown > 0 { parts.append("\(unknown) sem horário") }
        return parts.joined(separator: " · ")
    }
}

/// "240 m · 3 min a pé" / "2,9 km · 5 min trem": a coluna de distância do índice.
enum ExplorarTravel {
    static let walkMaxMeters: Double = 1_500

    static func distance(_ meters: Double) -> (value: String, unit: String) {
        if meters < 1_000 { return ("\(Int((meters / 10).rounded()) * 10)", "m") }
        return (String(format: "%.1f", meters / 1_000).replacingOccurrences(of: ".", with: ","), "km")
    }

    /// Minutos e o meio: até 1,5 km a pé (80 m/min); acima, trem (a mesma estimativa do solver).
    static func minutes(_ meters: Double) -> (minutes: Int, walk: Bool) {
        let km = meters / 1_000 * 1.25
        if meters <= walkMaxMeters { return (max(1, Int((meters * 1.25 / 80).rounded(.up))), true) }
        return (Int((km * 2.5 + 6).rounded(.up)), false)
    }

    static func caption(_ meters: Double) -> String {
        let t = minutes(meters)
        return t.walk ? "\(t.minutes) min a pé" : "\(t.minutes) min trem"
    }
}

// MARK: - Projeção do recorte

/// Mercator da câmera do MapLibre (tile de 512 pt): onde cada coordenada cai num quadro `size` centrado em `center` com `zoom`.
/// O recorte é um snapshot (só a base); os pinos são desenhados por cima com esta mesma conta, então batem com o índice.
struct ExplorarProjection: Equatable, Sendable {
    var center: CLLocationCoordinate2D
    var zoom: Double
    var size: CGSize

    static func == (a: Self, b: Self) -> Bool {
        a.center.latitude == b.center.latitude && a.center.longitude == b.center.longitude && a.zoom == b.zoom && a.size == b.size
    }

    /// Zoom em que `widthMeters` cabem em `size.width`.
    static func zoom(widthMeters: Double, latitude: Double, width: CGFloat) -> Double {
        log2(78_271.517 * cos(latitude * .pi / 180) * Double(width) / widthMeters)
    }

    init(center: CLLocationCoordinate2D, widthMeters: Double, size: CGSize) {
        self.center = center
        self.size = size
        zoom = Self.zoom(widthMeters: widthMeters, latitude: center.latitude, width: size.width)
    }

    private var pointsPerDegree: Double { 512 * pow(2, zoom) / 360 }
    private static func merc(_ lat: Double) -> Double { log(tan(.pi / 4 + lat * .pi / 360)) }

    func point(_ c: CLLocationCoordinate2D) -> CGPoint {
        let x = Double(size.width) / 2 + (c.longitude - center.longitude) * pointsPerDegree
        let pointsPerRad = 512 * pow(2, zoom) / (2 * .pi)
        let y = Double(size.height) / 2 - (Self.merc(c.latitude) - Self.merc(center.latitude)) * pointsPerRad
        return CGPoint(x: x, y: y)
    }

    /// Retângulo geográfico do quadro (pra "na tela").
    var rect: GeoRect {
        let halfLng = Double(size.width) / 2 / pointsPerDegree
        let pointsPerRad = 512 * pow(2, zoom) / (2 * .pi)
        func lat(_ dy: Double) -> Double { (2 * atan(exp(Self.merc(center.latitude) + dy / pointsPerRad)) - .pi / 2) * 180 / .pi }
        return GeoRect(minLat: lat(-Double(size.height) / 2), maxLat: lat(Double(size.height) / 2),
                       minLng: center.longitude - halfLng, maxLng: center.longitude + halfLng)
    }
}
