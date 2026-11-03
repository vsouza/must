import Foundation
import Network
import Observation
import Synchronization

/// Estado de rede do aparelho (prompt 18 · A.4). Um só.
/// O `NWPathMonitor` publica no main (`@Observable`, pra UI: chip "sem internet · offline ok") e espelha o
/// estado num cofre thread-safe (`current`), que o `HTTP` lê de qualquer thread antes de sair.
/// `-debugNetwork offline` força offline (simulador); `slow` fica no `HTTP` (latência e falha).
@MainActor
@Observable
final class Connectivity {
    enum Status: String, Sendable, Equatable {
        case online, constrained, offline
    }

    private(set) var status: Status
    /// Rede medida (celular, hotspot): o aparelho pode pedir pouco dado.
    private(set) var isExpensive = false

    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private let forced: Bool

    /// Espelho pro `HTTP` (fora do main). Só o monitor escreve.
    private nonisolated static let mirror = Mutex<Status>(.online)

    /// Estado atual, lido de qualquer thread (o `HTTP` checa aqui antes de cada chamada).
    nonisolated static var current: Status { mirror.withLock { $0 } }

    init() {
        forced = DebugFlags.string("debugNetwork") == "offline"
        status = forced ? .offline : .online
        if forced { Self.mirror.withLock { $0 = .offline } }
    }

    /// Liga o monitor (uma vez). No `-debugNetwork offline` não liga: o estado fica travado em offline.
    func start() {
        guard monitor == nil, !forced, !DebugFlags.isTestHost else { return }
        let path = NWPathMonitor()
        path.pathUpdateHandler = { update in
            let next: Status = update.status != .satisfied ? .offline : (update.isConstrained ? .constrained : .online)
            let expensive = update.isExpensive
            Task { @MainActor [weak self] in self?.apply(next, expensive: expensive) }
        }
        path.start(queue: DispatchQueue(label: "dev.viniso.must.path", qos: .utility))
        monitor = path
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    /// Só o caminho de atualização (e o teste) chamam isto.
    func apply(_ next: Status, expensive: Bool) {
        guard !forced else { return }
        if status != next { status = next }
        if isExpensive != expensive { isExpensive = expensive }
        Self.mirror.withLock { $0 = next }
    }

    /// Rótulo do chip da Home: "sem internet · offline ok" quando não há rede.
    var isOffline: Bool { status == .offline }
}
