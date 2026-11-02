import CryptoKit
import Foundation
import Observation

/// Mapas offline por cidade (Ajustes › Mapas offline): baixa do R2, confere tamanho e sha256, apaga pra liberar espaço.
/// Os arquivos ficam em `MapPackFiles.directory`; o mapa lê direto do disco (`MapTiles.pick`).
@MainActor
@Observable
final class OfflineMaps {
    enum Phase: Equatable, Sendable {
        case downloading(Double)
        case verifying
        case failed(String)
    }

    private(set) var manifest: MapPackManifest?
    private(set) var phases: [String: Phase] = [:]
    private(set) var isRefreshing = false
    /// Sobe quando um arquivo entra ou sai (as views releem o disco).
    private(set) var revision = 0
    private var tasks: [String: Task<Void, Never>] = [:]
    private let http = HTTP()

    private static let installedKey = "maps.installed" // id → sha256 do arquivo baixado
    private static var manifestCache: URL { MapPackFiles.directory.appending(path: "manifest.json") }

    init() {
        if let data = try? Data(contentsOf: Self.manifestCache) {
            manifest = try? JSONDecoder().decode(MapPackManifest.self, from: data)
        }
    }

    var isConfigured: Bool { MapPackFiles.remoteBase != nil }

    // MARK: Estado

    func isInstalled(_ id: String) -> Bool {
        _ = revision
        return MapPackFiles.localURL(id) != nil
    }

    /// Tamanho no disco (baixado) ou no servidor.
    func bytes(_ id: String) -> Int64? {
        _ = revision
        return MapPackFiles.bytes(id) ?? manifest?[id]?.bytes
    }

    /// Baixado, mas o servidor tem um arquivo diferente (build mais novo).
    func hasUpdate(_ id: String) -> Bool {
        guard isInstalled(id), let remote = manifest?[id] else { return false }
        return installedSHA[id] != remote.sha256
    }

    func build(_ id: String) -> String? { manifest?[id]?.build }

    var installedBytes: Int64 {
        _ = revision
        return MapPack.catalog.compactMap { MapPackFiles.bytes($0.id) }.reduce(0, +)
    }

    var installedCount: Int {
        _ = revision
        return MapPack.catalog.filter { MapPackFiles.localURL($0.id) != nil }.count
    }

    private var installedSHA: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: Self.installedKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.installedKey) }
    }

    // MARK: Manifest

    func refreshManifest() async {
        guard let base = MapPackFiles.remoteBase, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var request = URLRequest(url: base.appending(path: "manifest.json"), cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let data = try await http.send(request, service: "mapas")
            let fresh = try JSONDecoder().decode(MapPackManifest.self, from: data)
            manifest = fresh
            try? data.write(to: Self.manifestCache, options: .atomic)
        } catch {
            Log.data.error("mapas: manifest \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Baixar / apagar

    func download(_ pack: MapPack) {
        guard tasks[pack.id] == nil else { return }
        phases[pack.id] = .downloading(0)
        tasks[pack.id] = Task { [weak self] in
            let result: Result<Void, Error>
            do {
                try await self?.install(pack)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.tasks[pack.id] = nil
            switch result {
            case .success:
                self.phases[pack.id] = nil
            case .failure(let error) where error is CancellationError || (error as? URLError)?.code == .cancelled:
                self.phases[pack.id] = nil
            case .failure(let error):
                Log.data.error("mapas: \(pack.id, privacy: .public) \(error.localizedDescription, privacy: .public)")
                self.phases[pack.id] = .failed(Self.message(for: error))
            }
        }
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
    }

    func delete(_ id: String) {
        cancel(id)
        try? FileManager.default.removeItem(at: MapPackFiles.fileURL(id))
        installedSHA[id] = nil
        phases[id] = nil
        changed()
    }

    private func install(_ pack: MapPack) async throws {
        guard DevOverrides.liveData else { throw ServiceError.liveDataOff }
        guard let base = MapPackFiles.remoteBase else { throw ServiceError.missingKey("MAP_TILES_URL") }
        if manifest?[pack.id] == nil { await refreshManifest() }
        guard let entry = manifest?[pack.id] else { throw OfflineMapError.notOnServer }
        if let free = MapPackFiles.freeSpace, free < entry.bytes + 50_000_000 { throw OfflineMapError.noSpace(entry.bytes) }

        let staging = MapPackFiles.directory.appending(path: "\(pack.id).download")
        defer { try? FileManager.default.removeItem(at: staging) }
        let id = pack.id
        try await PackDownload.run(base.appending(path: "\(id).pmtiles"), to: staging, expected: entry.bytes) { fraction in
            Task { @MainActor [weak self] in
                if case .downloading = self?.phases[id] { self?.phases[id] = .downloading(fraction) }
            }
        }
        try Task.checkCancellation()
        phases[id] = .verifying
        let sha = try await Task.detached(priority: .utility) { try Self.sha256(of: staging) }.value
        let size = (try? FileManager.default.attributesOfItem(atPath: staging.path)[.size] as? NSNumber)?.int64Value
        guard size == entry.bytes, sha == entry.sha256 else { throw OfflineMapError.corrupt }
        try Task.checkCancellation()

        let final = MapPackFiles.fileURL(id)
        if FileManager.default.fileExists(atPath: final.path) {
            _ = try FileManager.default.replaceItemAt(final, withItemAt: staging)
        } else {
            try FileManager.default.moveItem(at: staging, to: final)
        }
        installedSHA[id] = sha
        changed()
    }

    private func changed() {
        revision += 1
        NotificationCenter.default.post(name: .mapPacksChanged, object: nil)
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func message(for error: Error) -> String {
        switch error {
        case let e as OfflineMapError: e.message
        case ServiceError.liveDataOff: "dados ao vivo desligados"
        case let e as URLError where e.code == .notConnectedToInternet: "sem internet"
        case let e as URLError where e.code == .timedOut: "a conexão caiu"
        default: "não deu pra baixar"
        }
    }
}

enum OfflineMapError: Error {
    case notOnServer
    case noSpace(Int64)
    case corrupt
    case http(Int)

    var message: String {
        switch self {
        case .notOnServer: "ainda não está no servidor"
        case .noSpace(let bytes): "falta espaço · precisa de \(bytes.formatted(.byteCount(style: .file)))"
        case .corrupt: "arquivo veio incompleto · tente de novo"
        case .http(let code): "servidor respondeu \(code)"
        }
    }
}

/// Um download com progresso (delegate do URLSession), cancelável pelo `Task`.
private final class PackDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let staging: URL
    private let expected: Int64
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var moveError: Error?
    private var lastPercent = -1

    private init(staging: URL, expected: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.staging = staging
        self.expected = expected
        self.onProgress = onProgress
    }

    static func run(_ url: URL, to staging: URL, expected: Int64, progress: @escaping @Sendable (Double) -> Void) async throws {
        let download = PackDownload(staging: staging, expected: expected, onProgress: progress)
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                let task = session.downloadTask(with: url)
                let wasCancelled = download.lock.withLock {
                    download.continuation = c
                    download.task = task
                    return download.cancelled
                }
                if wasCancelled { task.cancel() } else { task.resume() }
            }
        } onCancel: {
            let task = download.lock.withLock { download.cancelled = true; return download.task }
            task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        guard total > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(total))
        let percent = Int(fraction * 100)
        let changed = lock.withLock { () -> Bool in
            guard percent != lastPercent else { return false }
            lastPercent = percent
            return true
        }
        if changed { onProgress(fraction) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // O arquivo temporário some quando este método volta: mover já.
        var error: Error?
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            error = OfflineMapError.http(http.statusCode)
        } else {
            do {
                try? FileManager.default.removeItem(at: staging)
                try FileManager.default.moveItem(at: location, to: staging)
            } catch let e { error = e }
        }
        lock.withLock { moveError = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (c, moved) = lock.withLock { () -> (CheckedContinuation<Void, Error>?, Error?) in
            defer { continuation = nil }
            return (continuation, moveError)
        }
        if let error = error ?? moved { c?.resume(throwing: error) } else { c?.resume() }
    }
}
