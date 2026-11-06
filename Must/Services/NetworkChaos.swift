import Foundation

/// Internet ruim de propósito (DEBUG, rodada 23 · G): `-debugNetwork slow|flaky|dropping`.
/// - `slow`: 3 s de latência e 30% de timeout por tentativa (o de antes).
/// - `flaky`: latência aleatória de 0,5 a 8 s e 40% de falha — timeout, 500, 429 (com Retry-After), resposta cortada
///   no meio e JSON inválido com 200. A tela tem que cair no cache, sem crash e sem spinner infinito.
/// - `dropping`: a rede cai e volta a cada `-debugNetworkPeriod` s (padrão 6). O `Connectivity` acompanha (chip,
///   fila de saída) e o que estava em voo quando caiu volta `networkConnectionLost`.
/// Release: tudo vira no-op (o `mode` é sempre `.off`).
enum NetworkChaos {
    enum Mode: String, Sendable { case off, slow, flaky, dropping }

    static var mode: Mode {
        #if DEBUG
        Mode(rawValue: DebugFlags.string("debugNetwork") ?? "") ?? .off
        #else
        .off
        #endif
    }

    /// Período do liga/desliga do `dropping`, em segundos (mín. 1).
    static var dropPeriod: Double {
        let value = DebugFlags.double("debugNetworkPeriod")
        return value >= 1 ? value : 6
    }

    /// No `dropping`: offline na metade ímpar de cada período (começa online, pra a abertura carregar algo).
    static func droppingIsOffline(at date: Date = Date(), period: Double = dropPeriod, since start: Date = launch) -> Bool {
        let elapsed = max(0, date.timeIntervalSince(start))
        return Int(elapsed / period) % 2 == 1
    }

    /// Hora de referência do `dropping` (primeiro acesso, perto da abertura).
    static let launch = Date()

    /// O que o `flaky` sorteou pra esta tentativa.
    enum Fault: Equatable, Sendable {
        case none, timeout, server, tooMany, truncated, invalidJSON
    }

    /// Sorteio do `flaky`: 40% de falha, dividida entre os seis jeitos de dar errado. Puro (testável com `roll`).
    static func fault(roll: Double) -> Fault {
        switch roll {
        case ..<0.10: .timeout
        case ..<0.18: .server
        case ..<0.24: .tooMany
        case ..<0.32: .truncated
        case ..<0.40: .invalidJSON
        default: .none
        }
    }

    /// Envolve uma ida à rede com o modo atual. `fetch` é a chamada de verdade.
    static func perform(_ request: URLRequest, pause: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                        fetch: () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
        switch mode {
        case .off:
            return try await fetch()
        case .slow:
            try await pause(.seconds(3))
            if Double.random(in: 0..<1) < 0.3 { throw URLError(.timedOut) }
            return try await fetch()
        case .dropping:
            if droppingIsOffline() { throw URLError(.notConnectedToInternet) }
            try await pause(.milliseconds(Int.random(in: 200...1500)))
            let result = try await fetch()
            // Caiu enquanto a resposta vinha: como no metrô.
            if droppingIsOffline() { throw URLError(.networkConnectionLost) }
            return result
        case .flaky:
            try await pause(.milliseconds(Int.random(in: 500...8000)))
            let url = request.url ?? URL(string: "about:blank")!
            switch fault(roll: Double.random(in: 0..<1)) {
            case .none:
                return try await fetch()
            case .timeout:
                throw URLError(.timedOut)
            case .server:
                return (Data("<html>502 Bad Gateway</html>".utf8), response(url, 500))
            case .tooMany:
                return (Data("{\"error\":\"rate\"}".utf8), response(url, 429, headers: ["Retry-After": "1"]))
            case .truncated:
                let (data, real) = try await fetch()
                return (data.prefix(max(0, data.count / 2)), real)
            case .invalidJSON:
                return (Data("{\"places\": [ {\"id\": \"x\", ".utf8), response(url, 200))
            }
        }
    }

    private static func response(_ url: URL, _ code: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
