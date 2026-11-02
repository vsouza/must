import Foundation

enum ServiceError: LocalizedError, Equatable {
    case liveDataOff
    case missingKey(String)
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .liveDataOff: "Dados ao vivo desligados (menu escondido)."
        case .missingKey(let key): "Falta \(key) no Secrets.plist."
        case .http(let code, let body): "HTTP \(code): \(body.prefix(700))"
        case .decoding(let what): "Resposta inesperada: \(what)"
        }
    }
}

/// HTTP mínimo dos serviços: respeita "Dados ao vivo", registra no OSLog.
struct HTTP: Sendable {
    var session: URLSession = .shared

    /// URLCache de 50 MB (fotos do Commons, respostas GET).
    static func configureCache() {
        URLCache.shared = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 50 * 1024 * 1024)
    }

    func get(_ url: URL, headers: [String: String] = [:], service: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request, service: service)
    }

    func post(_ url: URL, json: [String: Any], headers: [String: String] = [:], service: String) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return try await send(request, service: service)
    }

    func send(_ request: URLRequest, service: String) async throws -> Data {
        guard DevOverrides.liveData else { throw ServiceError.liveDataOff }
        let started = Date()
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        Log.network.info("\(service, privacy: .public) \(request.httpMethod ?? "GET", privacy: .public) \(request.url?.host() ?? "", privacy: .public) → \(code) em \(ms) ms")
        guard (200..<300).contains(code) else {
            throw ServiceError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return data
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

    func store(_ data: Data, for key: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
    }

    private func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined().prefix(120)
        return directory.appending(path: "\(safe).json")
    }
}
