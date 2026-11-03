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
/// A Task é independente de quem espera: cancelar um espera não cancela o pedido dos outros.
actor InFlight {
    static let shared = InFlight()

    private var tasks: [String: (id: UUID, task: Task<Data, Error>)] = [:]

    func value(for key: String, _ work: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let existing = tasks[key] { return try await existing.task.value }
        let id = UUID()
        let task = Task { try await work() }
        tasks[key] = (id, task)
        defer { if tasks[key]?.id == id { tasks[key] = nil } }
        return try await task.value
    }

    /// Quantos pedidos estão em voo (teste).
    var count: Int { tasks.count }
}
