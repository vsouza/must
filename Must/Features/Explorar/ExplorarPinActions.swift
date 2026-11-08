import CoreLocation
import Foundation

// Bloco do pino no recorte aberto: "+ dia" (encaixar hoje, a mesma conta do Quero…) e "+ board" (guardar o de fora). Puro: o que
// cada botão mostra e a linha do Quero que o grava. Nenhuma rede aqui.

enum ExplorarPinActions {
    /// O que a ação do dia mostra.
    enum Day: Equatable {
        /// Feito: nada a fazer.
        case none
        /// Já é parada de hoje ("no dia · 15:30").
        case inDay(time: String?)
        /// Cabe hoje neste buraco.
        case fit(DayFit.Slot)
        /// O dia não tem vaga (ou o lugar fecha antes).
        case noFit
    }

    /// O resultado do Quero equivalente ao pino (seu Must = board; de fora = Google/MapKit).
    static func wantResult(_ item: ExplorarItem) -> WantResult {
        WantResult(id: item.id, name: item.name, lat: item.lat, lng: item.lng, origin: item.isOwn ? .board : .places,
                   googlePlaceId: item.googleId, boardPlaceId: item.placeId, distance: item.meters)
    }

    static func day(for item: ExplorarItem, env: QueroEnv) -> Day {
        if item.done { return .none }
        if item.inPlan { return .inDay(time: item.planTime) }
        let slot = DayFit.slot(at: item.coordinate, plan: env.plan, now: env.now, region: env.region, origin: env.origin,
                               walkMaxKm: env.walkMaxKm)
        return slot.map(Day.fit) ?? .noFit
    }

    /// A linha pra `QueroSave.place`/`encaixar`.
    static func row(for item: ExplorarItem, slot: DayFit.Slot?, areaId: String?) -> QueroRow {
        var row = QueroRow.minimal(wantResult(item))
        row.slot = slot
        row.areaId = areaId
        row.meta = item.meta
        return row
    }

    /// "+ board" só pro que é de fora.
    static func canSave(_ item: ExplorarItem) -> Bool { !item.isOwn }
}

extension QueroRow {
    /// Linha sem encaixe calculado (guardar no board não precisa).
    static func minimal(_ result: WantResult) -> QueroRow {
        QueroRow(result: result, minutes: 1, slot: nil, meta: "", otherDay: nil, areaId: nil)
    }
}

extension GiftStoreSearch {
    /// A loja de fora como resultado de busca (pra guardar no board pelo mesmo caminho do Quero…).
    static func wantResult(_ hit: Hit) -> WantResult {
        WantResult(id: "mk-\(hit.id)", name: hit.name, lat: hit.lat, lng: hit.lng, origin: .places, address: hit.address.isEmpty ? nil : hit.address)
    }
}

// MARK: - "Fora do board" ao vivo

/// Uma busca do Google Nearby por bairro por sessão. Offline e Modo de Pouco Dados não buscam (e não gastam a vez do bairro).
struct ExplorarOutsidePolicy: Sendable {
    enum Decision: Equatable, Sendable {
        case fetch
        case alreadyThisSession
        case offline
        case lowData
    }

    private(set) var fetched: Set<String> = []

    mutating func decide(area id: String, region: Region, status: Connectivity.Status) -> Decision {
        switch status {
        case .offline: return .offline
        case .constrained: return .lowData
        case .online: break
        }
        let key = "\(region.rawValue)/\(id)"
        if fetched.contains(key) { return .alreadyThisSession }
        fetched.insert(key)
        return .fetch
    }
}

enum ExplorarOutsideState: Equatable, Sendable {
    case idle, loading, loaded, offline, lowData

    /// A nota do índice sobre a camada "fora do board".
    var note: String? {
        switch self {
        case .offline: "sem internet · só o que já estava guardado"
        case .lowData: "pouco dado · só o que já estava guardado"
        case .loading: "buscando perto daqui…"
        case .idle, .loaded: nil
        }
    }
}
