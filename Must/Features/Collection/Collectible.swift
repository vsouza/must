import Foundation

// Contrato da RODADA-23 (agente D): cada "feito" vira um colecionável, derivado dos dados que já existem
// (`Place.done`, bairro, lista). Sem modelo SwiftData novo.

enum CollectibleVariant: String, Hashable, Sendable, CaseIterable {
    /// Cor da viagem (padrão).
    case trip
    /// Tinta: âncora (ingresso, reserva) — os "raros".
    case anchor
    /// Papel com contorno: ar livre.
    case outdoor
}

struct Collectible: Identifiable, Hashable, Sendable {
    var placeId: String
    /// Ordem do feito na coleção (1 = o primeiro) e o total do board.
    var order: Int
    var total: Int
    var variant: CollectibleVariant
    var title: String
    var area: String?
    var listId: String?
    var doneAt: Date

    var id: String { placeId }

    /// Colecionável de um lugar feito; `nil` se ainda não foi feito. O agente D completa a regra da variante.
    @MainActor
    static func make(from place: Place, in all: [Place]) -> Collectible? {
        guard let done = place.done else { return nil }
        let doneOnes = all.compactMap { p in p.done.map { (p.id, $0.at) } }.sorted { $0.1 < $1.1 }
        let order = (doneOnes.firstIndex { $0.0 == place.id } ?? doneOnes.count) + 1
        let anchor = !place.tickets.isEmpty || place.reservation != nil
        return Collectible(placeId: place.id, order: order, total: all.count, variant: anchor ? .anchor : .trip,
                           title: place.name, area: place.area, listId: place.list?.id, doneAt: done.at)
    }
}

/// O momento de ganhar um colecionável ao marcar "Feito" (`ColecionavelNovo.png`). Stub do contrato; o agente D
/// mostra a celebração. Quem marca feito (Lugar, Agora) só chama `present`.
@MainActor
enum CollectibleCelebration {
    static let notification = Notification.Name("must.collectible.new")
    static func present(for placeId: String) {
        NotificationCenter.default.post(name: notification, object: nil, userInfo: ["placeId": placeId])
    }
}
