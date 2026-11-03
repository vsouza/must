import Foundation

/// Quando o app sincroniza (prompt 18 · A.6): nada de rede antes do primeiro frame. A primeira sincronização
/// espera `launchDelay` (o app abre com o último estado salvo); depois, pedido vai na hora. Pedidos que chegam
/// enquanto um já está esperando ou rodando viram um só (abertura, `.active` e "voltou a rede" caem juntos).
/// `syncIfNeeded` continua limitando a sincronização real a cada 6 h.
@MainActor
final class StartupSync {
    typealias Sleep = @Sendable (Duration) async -> Void

    static let launchDelay: Duration = .seconds(2)

    private let sleep: Sleep
    private var launched = false
    private var running: Task<Void, Never>?

    init(sleep: @escaping Sleep = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Pede uma sincronização. Retorna `false` quando outro pedido já está pendente ou rodando.
    @discardableResult
    func request(_ work: @escaping @MainActor () async -> Void) -> Bool {
        guard running == nil else { return false }
        let delay: Duration = launched ? .zero : Self.launchDelay
        launched = true
        let sleep = self.sleep
        running = Task { [weak self] in
            if delay > .zero { await sleep(delay) }
            guard !Task.isCancelled else {
                self?.running = nil
                return
            }
            await work()
            self?.running = nil
        }
        return true
    }

    /// A árvore saiu (troca de região): o pedido que ainda espera não roda.
    func cancel() {
        running?.cancel()
        running = nil
    }

    /// Há um pedido esperando ou rodando (teste e QA).
    var isBusy: Bool { running != nil }
}
