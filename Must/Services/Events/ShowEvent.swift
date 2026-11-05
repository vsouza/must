import Foundation
import SwiftUI

// Contrato da RODADA-23 (fase 0) + prompt 26. "Em cartaz" (exposição, show, jogo) num valor só, venha do board
// (`PlaceExtra.art/sport/experience/program`, `Ticket`), de link/texto/cartaz colado, ou do `EventsService` do
// prompt 26 (Bandsintown, Ticketmaster, feeds RSS). Não é persistido no SwiftData.
// Donos: agente A (montagem do board, colar) e agente E (EventsService); B, C e D só leem.

enum ShowKind: String, Codable, Hashable, Sendable, CaseIterable {
    case exhibition, show, match, other
}

enum ShowSource: String, Codable, Hashable, Sendable, CaseIterable {
    case board, link, poster, bandsintown, ticketmaster, feed
}

struct ShowEvent: Identifiable, Hashable, Sendable, Codable {
    var id: String
    /// Lugar do board, quando o evento é de um lugar que você já tem.
    var placeId: String?
    var kind: ShowKind
    var title: String
    /// Onde (nome do lugar), pra evento de fora do board.
    var venue: String?
    var lat: Double?
    var lng: Double?
    var startsAt: Date?
    /// Exposição em temporada: até quando.
    var runsUntil: Date?
    var sessions: [EventSession] = []
    var priceText: String?
    var url: URL?
    var source: ShowSource
    var checkedAt: Date?
}

/// Quem responde "o que está em cartaz". Leitura síncrona do que já está no aparelho (cache primeiro).
@MainActor
protocol ShowEventsProviding {
    /// Acontecendo hoje (no fuso da região).
    func today(region: Region, at date: Date) -> [ShowEvent]
    /// Próximos `days` dias (inclui exposições em temporada).
    func upcoming(region: Region, from date: Date, days: Int) -> [ShowEvent]
    /// Do lugar do board.
    func events(placeId: String, at date: Date) -> [ShowEvent]
}

/// Stub do contrato: nada em cartaz.
struct ShowEventsStub: ShowEventsProviding {
    nonisolated init() {}
    func today(region: Region, at date: Date) -> [ShowEvent] { [] }
    func upcoming(region: Region, from date: Date, days: Int) -> [ShowEvent] { [] }
    func events(placeId: String, at date: Date) -> [ShowEvent] { [] }
}

private struct ShowEventsKey: EnvironmentKey {
    static var defaultValue: any ShowEventsProviding { ShowEventsStub() }
}

extension EnvironmentValues {
    /// Em cartaz. O agente A injeta o real em `MustApp`; sem injeção, o stub (vazio).
    var showEvents: any ShowEventsProviding {
        get { self[ShowEventsKey.self] }
        set { self[ShowEventsKey.self] = newValue }
    }
}
