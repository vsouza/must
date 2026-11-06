import UIKit
import UniformTypeIdentifiers

/// Share Extension do Must (prompt 15 · A): recebe PDF, imagem, vídeo (prompt 29), .pkpass, URL ou texto, grava na caixa do App Group
/// (`ShareInbox`) e abre o app em `must://import?id=`. Só recebe e grava: a leitura é no app.
/// Se o app não abrir daqui, o item fica na caixa e o app o pega na próxima vez que ficar ativo.
final class ShareViewController: UIViewController {
    private let status = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.text = "Mandando pro Must…"
        status.font = .preferredFont(forTextStyle: .headline)
        status.textAlignment = .center
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        Task { await receive() }
    }

    private func receive() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        // Ordem de preferência: um .pkpass também conforma a arquivo, e o passe é o que tem mais dado.
        let candidates: [(type: String, kind: ShareInbox.Kind)] = [
            ("com.apple.pkpass", .pkpass), (UTType.pdf.identifier, .pdf), (UTType.image.identifier, .image),
            (UTType.movie.identifier, .video),
            (UTType.url.identifier, .url), (UTType.plainText.identifier, .text),
        ]
        for (type, kind) in candidates {
            guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type) }) else { continue }
            do {
                let item = try await Self.stash(provider, type: type, kind: kind)
                open(ShareInbox.importURL(for: item.id))
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                status.text = "Não consegui guardar o item."
                try? await Task.sleep(for: .seconds(2))
                extensionContext?.cancelRequest(withError: error)
            }
            return
        }
        status.text = "O Must não lê esse tipo de item."
        try? await Task.sleep(for: .seconds(2))
        extensionContext?.cancelRequest(withError: CocoaError(.fileReadUnsupportedScheme))
    }

    // MARK: Gravação

    private static func stash(_ provider: NSItemProvider, type: String, kind: ShareInbox.Kind) async throws -> ShareInbox.Item {
        switch kind {
        case .pdf, .image, .pkpass, .video:
            return try await loadFile(provider, type: type, kind: kind)
        case .url, .text:
            let value = try await loadText(provider, type: type)
            return try ShareInbox.stash(text: value, kind: kind)
        }
    }

    /// O arquivo temporário só existe dentro do bloco: copia pra caixa dentro dele.
    private static func loadFile(_ provider: NSItemProvider, type: String, kind: ShareInbox.Kind) async throws -> ShareInbox.Item {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    guard let url else { throw error ?? CocoaError(.fileReadUnknown) }
                    continuation.resume(returning: try ShareInbox.stash(fileAt: url, kind: kind))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// URL ou texto, já convertido em String dentro do bloco (o objeto do provedor não é Sendable).
    private static func loadText(_ provider: NSItemProvider, type: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let url = item as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    // MARK: Abrir o app

    /// Extensões não têm `UIApplication.shared`: sobe a cadeia de respondedores até o `openURL:` do app
    /// e, se não houver, pede ao contexto da extensão.
    private func open(_ url: URL) {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }
}
