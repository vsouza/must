import Foundation
import Network
import Observation
import Synchronization

/// Estado de rede do aparelho (prompt 18 · A.4). Um só.
/// O `NWPathMonitor` publica no main (`@Observable`, pra UI: chip "sem internet · offline ok") e espelha o
/// estado num cofre thread-safe (`current`), que o `HTTP` lê de qualquer thread antes de sair.
/// `-debugNetwork offline` força offline (simulador); `slow` fica no `HTTP` (latência e falha).
/// `-debugNetwork wifi` e `celular` fingem o tipo de rede (prompt 18 · A.5: pré-download só no Wi-Fi).
/// `-debugNetwork dropping` (rodada 23 · G) alterna online/offline a cada `-debugNetworkPeriod` s (`NetworkChaos`).
@MainActor
@Observable
final class Connectivity {
    enum Status: String, Sendable, Equatable {
        case online, constrained, offline
    }

    private(set) var status: Status
    /// Rede medida (celular, hotspot): o aparelho pode pedir pouco dado.
    private(set) var isExpensive = false
    /// Wi-Fi (não celular). O pré-download do dia só roda com ele (prompt 18 · A.5).
    private(set) var isWiFi = false

    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private let forced: Bool

    /// Espelho pro `HTTP` (fora do main). Só o monitor escreve.
    private nonisolated static let mirror = Mutex<Status>(.online)
    /// Wi-Fi, espelhado pro `HTTP` (medição de dados: `DataUsage`).
    private nonisolated static let mirrorWiFi = Mutex<Bool>(false)

    /// Estado atual, lido de qualquer thread (o `HTTP` checa aqui antes de cada chamada).
    nonisolated static var current: Status { mirror.withLock { $0 } }
    nonisolated static var currentIsWiFi: Bool { mirrorWiFi.withLock { $0 } }

    init() {
        let mode = DebugFlags.string("debugNetwork")
        forced = ["offline", "wifi", "celular"].contains(mode)
        status = mode == "offline" ? .offline : .online
        isWiFi = mode == "wifi"
        isExpensive = mode == "celular"
        if mode == "offline" { Self.mirror.withLock { $0 = .offline } }
        if mode == "wifi" { Self.mirrorWiFi.withLock { $0 = true } }
        dropping = mode == "dropping" && !DebugFlags.isTestHost
    }

    /// `-debugNetwork dropping`: o estado segue o relógio do `NetworkChaos`, não o `NWPathMonitor`.
    @ObservationIgnored private let dropping: Bool
    @ObservationIgnored private var dropTask: Task<Void, Never>?

    private func startDropping() {
        guard dropTask == nil else { return }
        dropTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let next: Status = NetworkChaos.droppingIsOffline() ? .offline : .online
                self?.applyDropping(next)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func applyDropping(_ next: Status) {
        if status != next {
            Log.network.info("debugNetwork dropping → \(next.rawValue, privacy: .public)")
            status = next
        }
        isWiFi = next == .online
        Self.mirror.withLock { $0 = next }
        Self.mirrorWiFi.withLock { $0 = next == .online }
    }

    /// Liga o monitor (uma vez). Com `-debugNetwork` forçado não liga: o estado fica travado.
    func start() {
        if dropping { startDropping(); return }
        guard monitor == nil, !forced, !DebugFlags.isTestHost else { return }
        let path = NWPathMonitor()
        path.pathUpdateHandler = { update in
            let next: Status = update.status != .satisfied ? .offline : (update.isConstrained ? .constrained : .online)
            let expensive = update.isExpensive
            let wifi = update.usesInterfaceType(.wifi)
            Task { @MainActor [weak self] in self?.apply(next, expensive: expensive, wifi: wifi) }
        }
        path.start(queue: DispatchQueue(label: "dev.viniso.must.path", qos: .utility))
        monitor = path
    }

    func stop() {
        dropTask?.cancel()
        dropTask = nil
        monitor?.cancel()
        monitor = nil
    }

    /// Só o caminho de atualização (e o teste) chamam isto.
    func apply(_ next: Status, expensive: Bool, wifi: Bool) {
        guard !forced, !dropping else { return }
        if status != next { status = next }
        if isExpensive != expensive { isExpensive = expensive }
        if isWiFi != wifi { isWiFi = wifi }
        Self.mirror.withLock { $0 = next }
        Self.mirrorWiFi.withLock { $0 = wifi }
    }

    /// Rótulo do chip da Home: "sem internet · offline ok" quando não há rede.
    var isOffline: Bool { status == .offline }

    /// O que o pré-download precisa saber agora (prompt 18 · A.5).
    var prefetchNetwork: PrefetchPolicy.Network {
        PrefetchPolicy.Network(status: status, wifi: isWiFi, expensive: isExpensive)
    }
}
