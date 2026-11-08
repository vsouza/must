import Foundation

// Lista fácil de Presentes: adicionar rápido numa linha ("nome pra Ana") e filtro simples. Lógica pura, sem SwiftData.

/// O que o campo "Novo presente…" entendeu de uma linha digitada ou colada.
struct GiftQuickEntry: Equatable, Sendable {
    var title: String
    /// Vazio = sem pessoa escrita (o chamador decide se herda a do último grupo).
    var person: String
    var url: String?
    /// A pessoa veio escrita na linha ("pra Ana"); senão o chamador usa a do último grupo.
    var personExplicit: Bool
}

enum GiftQuick {
    /// "Kit Kat pra Ana", "Kit Kat — Ana", "Kit Kat - Ana", "Kit Kat para Ana". Link colado vira presente com link
    /// (título = site; a pessoa pode vir depois do link: "https://… pra Ana"). Linha vazia = `nil`.
    static func parse(_ raw: String) -> GiftQuickEntry? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var person = ""
        var explicit = false
        let separators = [" — ", " – ", " - ", " pra ", " para ", " Pra ", " Para "]
        var best: Range<String.Index>?
        for sep in separators {
            if let r = text.range(of: sep, options: .backwards), best == nil || r.lowerBound > best!.lowerBound { best = r }
        }
        if let r = best {
            let who = text[r.upperBound...].trimmingCharacters(in: .whitespaces)
            let head = text[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            // Pessoa = uma ou duas palavras curtas, sem número; senão é parte do nome ("Bolsa pra notebook de couro").
            let words = who.split(separator: " ")
            if !who.isEmpty, !head.isEmpty, words.count <= 2, who.count <= 24, !who.contains(where: \.isNumber) {
                person = who.prefix(1).uppercased() + who.dropFirst()
                text = head
                explicit = true
            }
        }
        if let url = firstURL(in: text) {
            let rest = text.replacingOccurrences(of: url, with: "").trimmingCharacters(in: .whitespaces)
            let host = URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "Link"
            return GiftQuickEntry(title: rest.isEmpty ? host : rest, person: person, url: url, personExplicit: explicit)
        }
        return GiftQuickEntry(title: text, person: person, url: nil, personExplicit: explicit)
    }

    static func firstURL(in text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace).map(String.init).first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    /// Pessoa do último grupo da lista (o que o campo do fim herda); vazio quando é "sem pessoa" ou não há grupo.
    static func inheritedPerson(_ groups: [GiftGroup]) -> String {
        guard let last = groups.last, last.person != GiftLogic.noPerson else { return "" }
        return last.person
    }
}

/// Filtro do topo da lista.
enum GiftFilter: Hashable, Sendable {
    case pending, all
    case person(String)

    func apply(_ gifts: [Gift]) -> [Gift] {
        switch self {
        case .pending: gifts.filter { !$0.isBought }
        case .all: gifts
        case .person(let name): gifts.filter { $0.personName == name }
        }
    }
}

extension GiftLogic {
    /// "5 faltam" / "1 falta" / "tudo comprado".
    static func pendingText(_ gifts: [Gift]) -> String {
        let n = pendingCount(gifts)
        if gifts.isEmpty { return "nada ainda" }
        return n == 0 ? "tudo comprado" : "\(n) \(n == 1 ? "falta" : "faltam")"
    }

    /// "5 faltam de 6" (a linha da aba Viagem).
    static func pendingOfText(_ gifts: [Gift]) -> String {
        let n = pendingCount(gifts)
        if gifts.isEmpty { return "lista vazia" }
        return n == 0 ? "tudo comprado (\(gifts.count))" : "\(n) \(n == 1 ? "falta" : "faltam") de \(gifts.count)"
    }
}
