import Foundation

/// Página de uma experiência colada (Viator, Klook, Airbnb, GetYourGuide, e-plus, Peatix, Sympla…).
/// Só o que a página publica: og:tags e o texto visível. Nada de scraping além de uma requisição.
struct ExperienceLink: Equatable, Sendable {
    var url: URL
    var title: String?
    var description: String
    var imageURL: URL?
    var siteName: String?
    /// Texto da página (og + visível, até 20 mil caracteres), pro extrator.
    var pageText: String

    var supplier: ExperienceSupplier { ExperienceSupplier.detect(url) }
}

enum ExperienceLinkError: LocalizedError, Equatable {
    case notALink
    case empty

    var errorDescription: String? {
        switch self {
        case .notALink: "Isso não parece um link (http ou https)."
        case .empty: "A página não trouxe título nem texto que eu consiga ler."
        }
    }
}

enum ExperienceLinkReader {
    /// Uma requisição HTTP (respeita "Dados ao vivo"). Não segue script nem outras páginas.
    static func read(_ url: URL, http: HTTP = HTTP()) async throws -> ExperienceLink {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw ExperienceLinkError.notALink }
        let data = try await http.get(url, headers: ["Accept-Language": "pt-BR,pt;q=0.9,en;q=0.8,ja;q=0.7"], service: "experience.page")
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let link = parse(html, url: url)
        guard link.title != nil || !link.pageText.isEmpty else { throw ExperienceLinkError.empty }
        return link
    }

    /// Lê og:title, og:description, og:image, og:site_name e o texto visível. Testado com fixture.
    static func parse(_ html: String, url: URL) -> ExperienceLink {
        let title = HTMLMeta.content(of: "og:title", in: html) ?? HTMLMeta.title(in: html)
        let description = HTMLMeta.content(of: "og:description", in: html) ?? HTMLMeta.content(of: "description", in: html) ?? ""
        let image = HTMLMeta.content(of: "og:image", in: html).flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
        return ExperienceLink(url: url, title: title?.nonEmpty.map(cleanTitle), description: description, imageURL: image,
                              siteName: HTMLMeta.content(of: "og:site_name", in: html)?.nonEmpty,
                              pageText: TicketReader.pageText(html))
    }

    /// "Aula de sushi em Tsukiji | Viator" → "Aula de sushi em Tsukiji".
    static func cleanTitle(_ raw: String) -> String {
        let first = raw.components(separatedBy: " | ").first ?? raw
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 6 ? trimmed : raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ExperienceSupplier {
    /// Pelo domínio do link. Sites sem caso próprio (Sympla, Peatix…) ficam em `.other`.
    static func detect(_ url: URL) -> ExperienceSupplier {
        let host = (url.host() ?? "").lowercased()
        if host.contains("viator.") { return .viator }
        if host.contains("getyourguide.") { return .getYourGuide }
        if host.contains("klook.") { return .klook }
        if host.contains("airbnb.") { return .airbnb }
        return .other
    }

    /// Chip do fornecedor: o nome da enum, e pra "outro" o nome do site (Sympla, Peatix, e-plus…).
    static func badge(_ supplier: ExperienceSupplier, url: URL?) -> String {
        guard supplier == .other else { return supplier.label }
        let host = (url?.host() ?? "").lowercased()
        let known: [(String, String)] = [("sympla", "Sympla"), ("eplus", "e-plus"), ("peatix", "Peatix"), ("pia.", "Pia"),
                                         ("lawson", "Lawson"), ("ingresse", "Ingresse")]
        return known.first { host.contains($0.0) }?.1 ?? supplier.label
    }
}
