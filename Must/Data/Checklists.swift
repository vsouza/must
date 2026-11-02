import Foundation

/// Modelos de checklist de voo (`Must/Data/checklists/*.json`, no bundle como os seeds). Cada voo recebe uma cópia;
/// depois de criado, o checklist é do voo (marcar, desmarcar, mudar o texto).
enum ChecklistTemplates {
    struct Entry: Decodable, Sendable, Equatable {
        var id: String
        var phase: ChecklistPhase
        var title: String
        var note: String?
        /// Prazo em horas em relação à partida do primeiro trecho (-48 = 48 h antes).
        var dueOffsetHours: Int?
        /// Só entra quando algum trecho passa pelo Japão.
        var onlyJapan: Bool?
        /// Só entra quando há conexão (mais de um trecho).
        var onlyConnection: Bool?
        var autoRule: String?
    }

    private struct File: Decodable {
        var id: String
        var items: [Entry]
    }

    private final class BundleAnchor {}

    /// Nome do arquivo do modelo ("domestic-br" ou "intl-japan").
    static func fileName(for template: String) -> String {
        template == "domestic-br" ? "domestic-br" : "intl-japan"
    }

    /// Itens do modelo, sem filtro. Vazio se o arquivo não estiver no bundle.
    static func entries(template: String, bundle: Bundle? = nil) -> [Entry] {
        let name = fileName(for: template)
        for candidate in [bundle ?? .main, Bundle(for: BundleAnchor.self)] {
            guard let url = candidate.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(File.self, from: data) else { continue }
            return file.items
        }
        Log.app.error("checklist \(name, privacy: .public) não está no bundle")
        return []
    }

    /// Checklist de um voo: filtra o que não vale pros trechos (Japão, conexão) e põe o prazo dos itens com `dueOffsetHours`.
    static func items(template: String, legs: [FlightSegment], bundle: Bundle? = nil) -> [ChecklistItem] {
        let japan = FlightRules.touchesJapan(legs)
        let connection = legs.count > 1
        let first = legs.first?.departsNow
        return entries(template: template, bundle: bundle)
            .filter { ($0.onlyJapan != true || japan) && ($0.onlyConnection != true || connection) }
            .map { entry in
                ChecklistItem(id: entry.id, phase: entry.phase, title: entry.title, note: entry.note, done: false,
                              dueAt: entry.dueOffsetHours.flatMap { hours in first?.addingTimeInterval(TimeInterval(hours * 3600)) },
                              auto: entry.autoRule != nil, autoRule: entry.autoRule)
            }
    }
}

/// Itens que se marcam sozinhos pela Carteira (prompt 15 · C): o documento na Carteira basta.
enum ChecklistRules {
    /// Marca os automáticos cuja regra já vale com a Carteira atual. Nunca desmarca o que o usuário marcou.
    static func applyWallet(_ items: [ChecklistItem], wallet: [WalletItem]) -> [ChecklistItem] {
        items.map { item in
            guard item.auto, !item.done, let rule = item.autoRule, satisfied(rule, wallet: wallet) else { return item }
            var marked = item
            marked.done = true
            return marked
        }
    }

    static func satisfied(_ rule: String, wallet: [WalletItem]) -> Bool {
        switch rule {
        case "entryQR": WalletRules.containsEntryQR(wallet)
        case "esim": wallet.contains { $0.kind == .esim }
        default: false
        }
    }
}
