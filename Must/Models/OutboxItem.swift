import Foundation
import SwiftData

/// Tipos da fila de saída (prompt 18 · A.4).
enum OutboxKind: String, Sendable, CaseIterable {
    /// `ref` = id do voo. Passa pelo `FlightStatusUpdater`, então respeita `FlightPolicy` e a cota.
    case flightStatus
    /// `ref` = URL colada. Ao terminar, `result` guarda a legenda lida (JSON), pra Adicionar usar.
    case readLink
}

/// Pedido que depende de rede e foi feito sem rede (prompt 18 · A.4). Vive no container da região.
/// Resolver lugar no Places não entra aqui: `Place.resolveQueued` já é a fila (`SyncCoordinator.syncPlaces`).
@Model
final class OutboxItem {
    var id: String = UUID().uuidString
    var kind: String = OutboxKind.readLink.rawValue
    var ref: String = ""
    var createdAt: Date = Date()
    /// Tentativas que de fato saíram e falharam (offline não conta).
    var attempts: Int = 0
    var nextTry: Date = Date()
    var lastError: String?
    /// Legenda lida (JSON de `StoredCaption`), quando um `readLink` termina.
    var result: Data?
    var done: Bool = false

    init(kind: OutboxKind, ref: String, now: Date = AppClock.now) {
        self.kind = kind.rawValue
        self.ref = ref
        self.createdAt = now
        self.nextTry = now
    }

    var outboxKind: OutboxKind? { OutboxKind(rawValue: kind) }
}
