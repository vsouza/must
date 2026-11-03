import Foundation

/// Disjuntor por serviço (prompt 18 · A.4): 3 falhas seguidas abrem por 2 min; depois deixa 1 tentativa passar
/// (meia-abertura). Sucesso fecha, falha reabre. Falha de conexão e 5xx/429 contam; 4xx não (o serviço respondeu).
actor CircuitBreaker {
    static let shared = CircuitBreaker()

    struct Config: Sendable {
        var threshold = 3
        var cooldown: TimeInterval = 120
    }

    private enum State: Sendable {
        case closed(failures: Int)
        case open(until: Date)
        /// `probing`: a tentativa de meia-abertura já saiu e ainda não voltou.
        case halfOpen(probing: Bool)
    }

    private var states: [String: State] = [:]
    private let config: Config
    private let now: @Sendable () -> Date

    init(config: Config = Config(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.now = now
    }

    /// Antes de sair: lança `circuitOpen` se o serviço está pausado.
    func allow(_ service: String) throws {
        switch states[service] ?? .closed(failures: 0) {
        case .closed:
            return
        case .open(let until):
            guard now() >= until else { throw ServiceError.circuitOpen(service) }
            states[service] = .halfOpen(probing: true)
        case .halfOpen(let probing):
            guard !probing else { throw ServiceError.circuitOpen(service) }
            states[service] = .halfOpen(probing: true)
        }
    }

    func success(_ service: String) {
        states[service] = .closed(failures: 0)
    }

    func failure(_ service: String) {
        switch states[service] ?? .closed(failures: 0) {
        case .closed(let failures) where failures + 1 < config.threshold:
            states[service] = .closed(failures: failures + 1)
        default:
            states[service] = .open(until: now().addingTimeInterval(config.cooldown))
        }
    }

    /// Saiu sem dizer se o serviço está bem (cancelado): libera a meia-abertura pra próxima tentativa.
    func neutral(_ service: String) {
        if case .halfOpen = states[service] { states[service] = .halfOpen(probing: false) }
    }

    /// Estado pra Ajustes/QA: "fechado", "aberto", "meia-abertura".
    func label(_ service: String) -> String {
        switch states[service] ?? .closed(failures: 0) {
        case .closed: "fechado"
        case .open: "aberto"
        case .halfOpen: "meia-abertura"
        }
    }
}

/// Deduplicação de GET em voo (prompt 18 · A.4): dois pedidos iguais ao mesmo tempo viram uma requisição só.
/// A Task é compartilhada por quem espera. Quando o último interessado sai (cancelou ou terminou), a Task é
/// cancelada e a entrada some (Rodada 21 · A.5): nada fica rodando por ninguém.
actor InFlight {
    static let shared = InFlight()

    private struct Entry {
        let id: UUID
        let task: Task<Data, Error>
        var waiters: Set<UUID>
    }

    private var entries: [String: Entry] = [:]

    func value(for key: String, _ work: @escaping @Sendable () async throws -> Data) async throws -> Data {
        var entry = entries[key] ?? Entry(id: UUID(), task: Task { try await work() }, waiters: [])
        let waiter = UUID()
        entry.waiters.insert(waiter)
        entries[key] = entry
        let (entryId, task) = (entry.id, entry.task)
        do {
            let data = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.leave(key, entryId, waiter) }
            }
            leave(key, entryId, waiter)
            return data
        } catch {
            leave(key, entryId, waiter)
            throw error
        }
    }

    /// Um interessado saiu. Se era o último, cancela a Task e tira a entrada.
    private func leave(_ key: String, _ entryId: UUID, _ waiter: UUID) {
        guard var entry = entries[key], entry.id == entryId, entry.waiters.remove(waiter) != nil else { return }
        if entry.waiters.isEmpty {
            entry.task.cancel()
            entries[key] = nil
        } else {
            entries[key] = entry
        }
    }

    /// Quantos pedidos estão em voo (teste).
    var count: Int { entries.count }
}
