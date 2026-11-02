import Foundation

/// Caixa de entrada do Share Extension (prompt 15 · A), no container do App Group.
/// A extensão só grava (`stash…`); o app lê, confere e apaga (`pending`, `fileURL`, `remove`).
/// Compilado nos dois targets (Must e MustShare): só Foundation, sem dependências.
enum ShareInbox {
    static let appGroup = "group.dev.viniso.must"
    static let scheme = "must"
    static let host = "import"

    enum Kind: String, Codable, Sendable {
        case pdf, image, pkpass, url, text
    }

    struct Item: Codable, Equatable, Sendable, Identifiable {
        /// UUID da pasta do item.
        var id: String
        var kind: Kind
        var createdAt: Date
        /// Arquivo bruto (`item.pdf`, `item.png`, `item.pkpass`). Nil pra URL e texto.
        var fileName: String?
        /// URL ou texto recebido.
        var text: String?
    }

    enum InboxError: Error {
        case noContainer
        case badID
    }

    /// `must://import?id=<uuid>`: o que a extensão abre no app.
    static func importURL(for id: String) -> URL {
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.queryItems = [URLQueryItem(name: "id", value: id)]
        return parts.url ?? URL(string: "\(scheme)://\(host)")!
    }

    /// Grava um arquivo que já está em disco (o provedor entrega numa pasta temporária que some ao fim do bloco).
    static func stash(fileAt source: URL, kind: Kind) throws -> Item {
        let id = UUID().uuidString
        let dir = try itemDirectory(id)
        let ext = source.pathExtension.isEmpty ? kind.rawValue : source.pathExtension.lowercased()
        let name = "item.\(ext)"
        try FileManager.default.copyItem(at: source, to: dir.appending(path: name))
        return try commit(Item(id: id, kind: kind, createdAt: .now, fileName: name, text: nil), in: dir)
    }

    /// URL ou texto (sem arquivo).
    static func stash(text: String, kind: Kind) throws -> Item {
        let id = UUID().uuidString
        let dir = try itemDirectory(id)
        return try commit(Item(id: id, kind: kind, createdAt: .now, fileName: nil, text: text), in: dir)
    }

    /// Itens prontos (com `meta.json`), do mais antigo pro mais novo.
    static func pending() -> [Item] {
        guard let root = try? inbox(),
              let dirs = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { dir -> Item? in
            guard let data = try? Data(contentsOf: dir.appending(path: "meta.json")) else { return nil }
            return try? JSONDecoder().decode(Item.self, from: data)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    static func item(id: String) -> Item? {
        pending().first { $0.id == id }
    }

    /// Arquivo bruto do item (nil pra URL e texto).
    static func fileURL(for item: Item) -> URL? {
        guard let name = item.fileName, let dir = try? directory(for: item.id) else { return nil }
        return dir.appending(path: name)
    }

    /// Apaga o item (depois de salvar, ou quando o usuário descarta).
    static func remove(id: String) {
        guard let dir = try? directory(for: id) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: Interno

    private static func inbox() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw InboxError.noContainer
        }
        let dir = container.appending(path: "Inbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Só aceita UUID: o id vem de uma URL e não pode sair da caixa.
    private static func directory(for id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw InboxError.badID }
        return try inbox().appending(path: id, directoryHint: .isDirectory)
    }

    private static func itemDirectory(_ id: String) throws -> URL {
        let dir = try directory(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `meta.json` é o último a ser gravado: sem ele o item não aparece em `pending`.
    private static func commit(_ item: Item, in dir: URL) throws -> Item {
        let data = try JSONEncoder().encode(item)
        try data.write(to: dir.appending(path: "meta.json"), options: .atomic)
        return item
    }
}
