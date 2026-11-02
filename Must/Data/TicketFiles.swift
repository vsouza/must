import Foundation

/// PDFs e fotos de ingresso (e documentos da Carteira: passaporte, seguro, QR) guardados no container do app, com
/// `FileProtectionType.complete` (legíveis só com o aparelho destravado). O `Ticket` e o `WalletItem` guardam só o nome.
enum TicketFiles {
    /// Opções de gravação de todo documento: proteção completa, escrita atômica.
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]

    static func directory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Tickets", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        return dir
    }

    static func url(for name: String) throws -> URL {
        try directory().appendingPathComponent(name)
    }

    /// Grava os bytes e devolve o nome do arquivo.
    static func save(_ data: Data, ext: String) throws -> String {
        let name = "\(UUID().uuidString).\(ext.isEmpty ? "pdf" : ext.lowercased())"
        try data.write(to: url(for: name), options: writeOptions)
        return name
    }

    /// Copia um arquivo escolhido no seletor (URL com escopo de segurança) pro container.
    static func importFile(at source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        return try save(Data(contentsOf: source), ext: source.pathExtension)
    }

    static func remove(_ name: String?) {
        guard let name, let file = try? url(for: name) else { return }
        try? FileManager.default.removeItem(at: file)
    }
}
