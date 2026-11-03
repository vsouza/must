import Foundation

/// O que o índice de bairros precisa de um lugar. Cópia `Sendable` (sem `@Model`) pra calcular fora do `body`.
struct AreaPlace: Sendable, Hashable {
    var id: String
    var name: String
    /// `Place.area` como está no board ("Shibuya Stream", "Azabudai Hills", "Centro").
    var areaName: String?
    /// `Place.cityId` (`tokyo1`, `kyoto`, `bh`).
    var cityId: String
    var lat: Double
    var lng: Double
    /// Cor da lista do lugar: a "categoria" do bairro.
    var kind: MustColor?
    var isDone: Bool
    /// Verificado no Places (tem `placeId`): desempata a escolha da foto do bairro.
    var verified: Bool
    /// Ordem no board (menor primeiro).
    var order: Int
    /// Tem reserva marcada (ajuda a escolher o lugar que representa o bairro).
    var hasReservation: Bool
}

/// Um bairro com seus musts e o que está aberto agora.
struct AreaEntry: Sendable, Identifiable, Hashable {
    var area: Area
    /// Musts do bairro, na ordem de `AreaPlace.order` (e os verificados primeiro).
    var placeIds: [String]
    /// Quais deles estão abertos agora (`OpenNowIndex`).
    var openIds: Set<String>
    /// Quantos musts de cada categoria.
    var mix: [MustColor: Int]

    var id: String { area.id }
    var count: Int { placeIds.count }
    var openCount: Int { openIds.count }

    /// Categoria que mais aparece (empate: a que aparece primeiro na ordem do board).
    var dominant: MustColor? {
        var best: (color: MustColor, count: Int)?
        for color in mix.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let n = mix[color] ?? 0
            if best == nil || n > best!.count { best = (color, n) }
        }
        return best?.color
    }
}

/// Musts por bairro (prompt 18 · C.13). Função pura: recebe as cópias e o conjunto de abertos e devolve tudo pronto.
/// A Home monta uma vez por gatilho (minuto, posição, lugares, dia aceito) e lê daqui no `body`.
struct AreaIndex: Sendable {
    static let empty = AreaIndex(areas: [], entries: [:], assignments: [:], outros: [])

    /// Bairros da região, na ordem da tabela.
    let areas: [Area]
    private let entries: [String: AreaEntry]
    /// Lugar → bairro (ausente = "outros").
    private let assignments: [String: String]
    /// Lugares sem bairro (ordem do board).
    let outros: [String]

    private init(areas: [Area], entries: [String: AreaEntry], assignments: [String: String], outros: [String]) {
        self.areas = areas
        self.entries = entries
        self.assignments = assignments
        self.outros = outros
    }

    /// Monta o índice. `openIds` vem de `OpenNowIndex.Snapshot` (quem está aberto no instante).
    static func build(areas: [Area], places: [AreaPlace], openIds: Set<String>) -> AreaIndex {
        let assigner = AreaAssigner(areas: areas)
        var assignments: [String: String] = [:]
        var outros: [String] = []
        var grouped: [String: [AreaPlace]] = [:]
        for place in places.sorted(by: { $0.order < $1.order }) {
            let areaId = assigner.areaId(name: place.areaName, cityId: place.cityId, lat: place.lat, lng: place.lng)
            guard let areaId else { outros.append(place.id); continue }
            assignments[place.id] = areaId
            grouped[areaId, default: []].append(place)
        }
        var entries: [String: AreaEntry] = [:]
        for area in areas {
            let members = grouped[area.id] ?? []
            var mix: [MustColor: Int] = [:]
            for place in members { if let kind = place.kind { mix[kind, default: 0] += 1 } }
            let ordered = members.sorted { ($0.verified ? 0 : 1, $0.order) < ($1.verified ? 0 : 1, $1.order) }
            entries[area.id] = AreaEntry(
                area: area, placeIds: ordered.map(\.id),
                openIds: Set(ordered.map(\.id).filter(openIds.contains)), mix: mix
            )
        }
        return AreaIndex(areas: areas, entries: entries, assignments: assignments, outros: outros)
    }

    func area(_ id: String) -> Area? { entries[id]?.area }

    func entry(_ id: String) -> AreaEntry? { entries[id] }

    /// Bairro do lugar, `nil` se está em "outros".
    func areaId(forPlace id: String) -> String? { assignments[id] }

    /// Bairros com algum must, na ordem da tabela.
    var populated: [AreaEntry] { areas.compactMap { entries[$0.id] }.filter { $0.count > 0 } }

    /// "Hoje, pra onde?": os `limit` bairros com mais musts abertos agora. Empate: mais musts, depois nome.
    func openNow(limit: Int = 3) -> [AreaEntry] {
        populated
            .filter { $0.openCount > 0 }
            .sorted { x, y in
                if x.openCount != y.openCount { return x.openCount > y.openCount }
                if x.count != y.count { return x.count > y.count }
                return x.area.name < y.area.name
            }
            .prefix(limit).map { $0 }
    }

    /// "Amanhã, pra onde?": os `limit` bairros com mais musts (empate: nome).
    func mostMusts(limit: Int = 3) -> [AreaEntry] {
        populated
            .sorted { x, y in x.count != y.count ? x.count > y.count : x.area.name < y.area.name }
            .prefix(limit).map { $0 }
    }

    /// Bairro do dia: o que tem mais paradas (empate: o que aparece primeiro na ordem do roteiro).
    static func dayArea(stopPlaceIds: [String], index: AreaIndex) -> String? {
        var counts: [String: Int] = [:]
        var firstSeen: [String] = []
        for placeId in stopPlaceIds {
            guard let areaId = index.areaId(forPlace: placeId) else { continue }
            if counts[areaId] == nil { firstSeen.append(areaId) }
            counts[areaId, default: 0] += 1
        }
        // Empate: o que aparece primeiro no roteiro (`firstSeen` já está nessa ordem).
        var best: (id: String, count: Int)?
        for id in firstSeen where best == nil || counts[id, default: 0] > best!.count {
            best = (id, counts[id, default: 0])
        }
        return best?.id
    }

    /// Bairros vizinhos que aparecem no dia (ordem do roteiro, sem o bairro principal).
    static func dayNeighbors(stopPlaceIds: [String], main: String, index: AreaIndex) -> [Area] {
        var seen: [String] = []
        for placeId in stopPlaceIds {
            guard let areaId = index.areaId(forPlace: placeId), areaId != main, !seen.contains(areaId) else { continue }
            seen.append(areaId)
        }
        return seen.compactMap(index.area)
    }
}
