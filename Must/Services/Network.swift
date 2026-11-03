import Foundation

enum ServiceError: LocalizedError, Equatable {
    case liveDataOff
    case missingKey(String)
    case http(Int, String)
    case decoding(String)
    /// Orçamento do Google (`ApiBudget`) não deixou sair: a tela cai no cache/estimativa, sem erro.
    case budget(String)
    /// Sem rede no aparelho: a chamada nem sai (prompt 18 · A.4).
    case offline
    /// Disjuntor aberto pra esse serviço depois de falhas seguidas (prompt 18 · A.4).
    case circuitOpen(String)

    var errorDescription: String? {
        switch self {
        case .budget(let why): "Google fora por enquanto: \(why)."
        case .liveDataOff: "Dados ao vivo desligados (menu escondido)."
        case .missingKey(let key): "Falta \(key) no Secrets.plist."
        case .http(let code, let body): "HTTP \(code): \(body.prefix(700))"
        case .decoding(let what): "Resposta inesperada: \(what)"
        case .offline: "Sem internet agora. Mostrando o que está salvo."
        case .circuitOpen(let service): "\(service) pausado um pouco depois de falhas seguidas."
        }
    }
}

/// Sessão do app: uma, compartilhada (prompt 18 · A.4). Timeouts curtos e nada de esperar conexão:
/// sem rede a chamada falha na hora e a tela usa o cache. O download grande de mapa tem sessão própria (`PackDownload`).
enum AppNetwork {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 4
        config.allowsConstrainedNetworkAccess = true
        config.urlCache = URLCache.shared
        return URLSession(configuration: config)
    }()
}

/// Pedido que pode ser repetido (429/5xx): leva o Retry-After pro intervalo entre as tentativas.
private struct RetryHint: Error {
    let error: ServiceError
    let retryAfter: TimeInterval?
}

/// HTTP dos serviços (prompt 18 · A.4): respeita "Dados ao vivo", falha na hora sem rede, repete só GET
/// transitório (máx. 2, backoff com jitter), disjuntor por serviço, e junta GETs iguais em voo.
/// POST nunca repete (custa cota do Google). Registra no OSLog.
struct HTTP: Sendable {
    /// `.prefetch`: pré-download (fotos, mapas) que não pode gastar dado do Modo de Pouco Dados.
    enum Kind: Sendable { case interactive, prefetch }

    var session: URLSession = AppNetwork.session
    var kind: Kind = .interactive
    /// Repetições extras (só GET). Serviços que cobram por chamada (AeroDataBox) passam 0.
    var retries = 2
    /// Disjuntor do serviço; `nil` desliga (AeroDataBox: a cota é o freio).
    var breaker: CircuitBreaker? = CircuitBreaker.shared
    /// Juntar GETs iguais em voo; `nil` desliga.
    var inFlight: InFlight? = InFlight.shared
    var connectivity: @Sendable () -> Connectivity.Status = { Connectivity.current }
    var pause: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// Multiplicador do backoff (0,8–1,2): tirável nos testes.
    var jitter: @Sendable () -> Double = { Double.random(in: 0.8...1.2) }

    /// URLCache de 50 MB (fotos do Commons, respostas GET).
    static func configureCache() {
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
    }

    private var timeout: TimeInterval { kind == .interactive ? 8 : 20 }

    func get(_ url: URL, headers: [String: String] = [:], service: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request, service: service)
    }

    /// POST nunca repete: uma tentativa, mesmo com erro transitório.
    func post(_ url: URL, json: [String: Any], headers: [String: String] = [:], service: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request, service: service)
    }

    func send(_ request: URLRequest, service: String) async throws -> Data {
        guard DevOverrides.liveData else { throw ServiceError.liveDataOff }
        // Sem rede, nada sai: erro na hora, sem esperar o timeout.
        guard connectivity() != .offline else { throw ServiceError.offline }
        var prepared = request
        if kind == .prefetch { prepared.allowsConstrainedNetworkAccess = false }
        let ready = prepared
        let method = ready.httpMethod ?? "GET"
        let idempotent = method == "GET" || method == "HEAD"
        if idempotent, let inFlight {
            let me = self
            return try await inFlight.value(for: Self.dedupeKey(ready, kind: kind)) {
                try await me.guarded(ready, service: service, retryable: true)
            }
        }
        return try await guarded(ready, service: service, retryable: idempotent)
    }

    // MARK: Disjuntor e tentativas

    private func guarded(_ request: URLRequest, service: String, retryable: Bool) async throws -> Data {
        if let breaker { try await breaker.allow(service) }
        do {
            let data = try await attempts(request, service: service, retryable: retryable)
            await breaker?.success(service)
            return data
        } catch {
            if Self.isTransient(error) {
                await breaker?.failure(service)
            } else if error is CancellationError || (error as? URLError)?.code == .cancelled {
                await breaker?.neutral(service)
            } else {
                // 4xx, chave recusada, resposta inesperada: o serviço respondeu, então está de pé.
                await breaker?.success(service)
            }
            throw error
        }
    }

    private func attempts(_ request: URLRequest, service: String, retryable: Bool) async throws -> Data {
        var retry = 0
        while true {
            do {
                return try await fetchOnce(request, service: service)
            } catch {
                let canRetry = retryable && Self.isTransient(error) && retry < retries
                guard canRetry else {
                    if let hint = error as? RetryHint { throw hint.error }
                    throw error
                }
                retry += 1
                try await pause(delay(retry, retryAfter: (error as? RetryHint)?.retryAfter))
            }
        }
    }

    /// Intervalo antes da tentativa `attempt` (1 = primeira repetição): 0,5 s, 1 s, com jitter.
    /// Um Retry-After curto (até 5 s) manda.
    func delay(_ attempt: Int, retryAfter: TimeInterval?) -> Duration {
        if let retryAfter, retryAfter <= 5 { return .milliseconds(Int(retryAfter * 1000)) }
        let base = 0.5 * pow(2.0, Double(attempt - 1))
        return .milliseconds(Int(base * jitter() * 1000))
    }

    private func fetchOnce(_ request: URLRequest, service: String) async throws -> Data {
        #if DEBUG
        // `-debugNetwork slow`: 3 s de latência e 30% de falha por tentativa (pra ver a UI sem travar).
        if DebugFlags.string("debugNetwork") == "slow" {
            try await pause(.seconds(3))
            if Double.random(in: 0..<1) < 0.3 { throw URLError(.timedOut) }
        }
        #endif
        let started = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw ServiceError.offline
        }
        let http = response as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        Log.network.info("\(service, privacy: .public) \(request.httpMethod ?? "GET", privacy: .public) \(request.url?.host() ?? "", privacy: .public) → \(code) em \(ms) ms")
        guard (200..<300).contains(code) else {
            let error = ServiceError.http(code, String(data: data, encoding: .utf8) ?? "")
            if code == 429 || code >= 500 {
                let after = http?.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw RetryHint(error: error, retryAfter: after)
            }
            throw error
        }
        return data
    }

    // MARK: Classificação

    /// Erro que vale tentar de novo (GET) e contar pro disjuntor. Offline não entra: é outra coisa.
    static func isTransient(_ error: Error) -> Bool {
        if error is RetryHint { return true }
        if let url = error as? URLError {
            return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed].contains(url.code)
        }
        if let service = error as? ServiceError, case .http(let code, _) = service {
            return code == 429 || code >= 500
        }
        return false
    }

    static func dedupeKey(_ request: URLRequest, kind: Kind) -> String {
        let headers = (request.allHTTPHeaderFields ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: "|")
        return "\(kind)|\(request.httpMethod ?? "GET")|\(request.url?.absoluteString ?? "")|\(headers)"
    }
}

/// Cache simples em disco (Caches/) pra respostas que valem por um tempo.
actor DiskCache {
    static let shared = DiskCache()
    private let directory = URL.cachesDirectory.appending(path: "must-cache", directoryHint: .isDirectory)

    func data(for key: String, maxAge: TimeInterval) -> Data? {
        let url = file(key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path()),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Ignora idade (modo "só cache").
    func stale(_ key: String) -> Data? { try? Data(contentsOf: file(key)) }

    /// Existe e tem menos de `maxAge` (sem ler o conteúdo).
    func isFresh(_ key: String, maxAge: TimeInterval) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file(key).path()),
              let modified = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(modified) < maxAge
    }

    func store(_ data: Data, for key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
    }

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined().prefix(120)
        return directory.appending(path: "\(safe).json")
    }
}
