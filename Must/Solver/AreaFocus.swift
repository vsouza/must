import Foundation

/// Solver por área (prompt 18 · C.15): o bairro do foco, os vizinhos até `maxHopMinutes` (tabela curada, sem rede)
/// e a frase que explica a ordem. Puro: não toca em SwiftData, rede nem GPS.
struct AreaFocusPlan: Sendable {
    let mainId: String
    /// Bairros aceitos → minutos desde o principal (0 = o principal). Ausente = fora do foco.
    private let reach: [String: Int]
    /// Minutos de ida entre dois bairros ligados na tabela (simétrico, pela menor ida). Ausente = sem ligação direta.
    private let hops: [String: Int]
    private let assigner: AreaAssigner

    init?(focus: DayFocus, areas: [Area]) {
        guard case .area(let id, let includeNeighbors, let maxHop) = focus,
              let main = areas.first(where: { $0.id == id }) else { return nil }
        mainId = id
        var reach = [id: 0]
        if includeNeighbors {
            for n in main.neighbors where n.minutes <= maxHop {
                reach[n.areaId] = min(reach[n.areaId] ?? .max, n.minutes)
            }
        }
        self.reach = reach
        var hops: [String: Int] = [:]
        for area in areas {
            for n in area.neighbors {
                let key = Self.pairKey(area.id, n.areaId)
                hops[key] = min(hops[key] ?? .max, n.minutes)
            }
        }
        self.hops = hops
        assigner = AreaAssigner(areas: areas)
    }

    static func pairKey(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }

    /// Bairro do lugar (nome do board, cidade, centroide), `nil` se não cai em nenhum.
    func areaId(for place: SolverPlace) -> String? {
        assigner.areaId(name: place.area, cityId: place.cityId, lat: place.lat, lng: place.lng)
    }

    func allows(_ areaId: String?) -> Bool {
        guard let areaId else { return false }
        return reach[areaId] != nil
    }

    /// Minutos de ida entre dois bairros do foco (0 no mesmo bairro). `nil` = não há ligação na tabela.
    func hop(_ a: String, _ b: String) -> Int? {
        a == b ? 0 : hops[Self.pairKey(a, b)]
    }

    /// Frase da ordem (determinística, sem LLM): "Comece por Nakano, almoço Fuunji, Gyoen no golden, Golden Gai à noite.
    /// 1 troca de bairro." `areaOf` recebe o `Place.id` e devolve o bairro.
    func sentence(for stops: [ProposedStop], areaOf: (String) -> String?) -> String {
        guard let first = stops.first else { return "Nada aberto no bairro que coubesse." }
        var parts = ["Comece por \(first.place.name)"]
        for stop in stops.dropFirst() {
            let name = stop.place.name
            if stop.place.role == .photo, stop.reason.contains("golden") {
                parts.append("\(name) no golden")
            } else if stop.place.role == .eat, stop.window == .lunch {
                parts.append("almoço \(name)")
            } else if stop.window == .night {
                parts.append("\(name) à noite")
            } else {
                parts.append("depois \(name)")
            }
        }
        var switches = 0
        for (prev, next) in zip(stops, stops.dropFirst()) {
            if let a = areaOf(prev.place.id), let b = areaOf(next.place.id), a != b { switches += 1 }
        }
        let tail: String
        switch switches {
        case 0: tail = "Tudo no mesmo bairro."
        case 1: tail = "1 troca de bairro."
        default: tail = "\(switches) trocas de bairro."
        }
        return parts.joined(separator: ", ") + ". " + tail
    }
}
