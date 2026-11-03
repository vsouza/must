import Foundation
import OSLog

/// Loggers do app (subsystem `dev.viniso.must`). Exportáveis pelo menu escondido.
enum Log {
    static let subsystem = "dev.viniso.must"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let solver = Logger(subsystem: subsystem, category: "solver")
    static let intelligence = Logger(subsystem: subsystem, category: "intelligence")
    static let guide = Logger(subsystem: subsystem, category: "guide")

    /// Entradas do app nas últimas `hours` horas, como texto.
    /// No iOS o `OSLogStore` só enxerga o processo atual (desde a última abertura).
    static func exportText(hours: Double = 24) async -> String {
        await Task.detached(priority: .utility) {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let since = store.position(date: Date().addingTimeInterval(-hours * 3600))
                let entries = try store.getEntries(at: since, matching: NSPredicate(format: "subsystem == %@", subsystem))
                let formatter = ISO8601DateFormatter()
                let lines = entries.compactMap { $0 as? OSLogEntryLog }.map { e in
                    "\(formatter.string(from: e.date)) [\(e.category)] \(Self.level(e.level)) \(e.composedMessage)"
                }
                let header = "Must · logs · \(formatter.string(from: Date())) · \(lines.count) linhas\n"
                return header + lines.joined(separator: "\n")
            } catch {
                return "Não consegui ler os logs: \(error.localizedDescription)"
            }
        }.value
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "ERRO"
        case .fault: "FALHA"
        default: "-"
        }
    }
}
