import Foundation

/// O que deu pra ler de um link.
struct Caption: Equatable, Sendable {
    var source: LinkSource
    var title: String?
    /// Legenda / descrição (cortada em 2.000 caracteres).
    var text: String
    /// Links do Maps já trazem nome e coordenada.
    var placeName: String?
    var lat: Double?
    var lng: Double?
    /// URL final (depois de seguir redirects).
    var url: URL?
}

enum CaptionError: LocalizedError, Equatable {
    case offline
    case empty
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .offline: "Dados ao vivo estão desligados (menu escondido)."
        case .empty: "Não consegui ler a legenda desse link."
        case .http(let code): "O site respondeu \(code)."
        }
    }
}

/// (b) Busca a legenda: og:title/og:description do HTML público (Instagram/TikTok, best-effort),
/// oEmbed + descrição (YouTube), e parse da URL do Maps (seguindo links curtos).
struct CaptionFetcher: Sendable {
    static let maxLength = 2000
    var session: URLSession = AppNetwork.session

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    func fetch(_ link: ResolvedLink) async throws -> Caption {
        guard let url = link.url else {
            return Caption(source: .text, title: nil, text: String(link.text.prefix(Self.maxLength)), url: nil)
        }
        guard DevOverrides.liveData else { throw CaptionError.offline }
        Log.network.info("legenda \(link.source.rawValue, privacy: .public) \(url.host() ?? "", privacy: .public)")

        switch link.source {
        case .maps: return try await maps(url)
        case .youtube: return try await youtube(url)
        default: return try await openGraph(url, source: link.source)
        }
    }

    // MARK: Fontes

    private func maps(_ url: URL) async throws -> Caption {
        var final = url
        var parsed = LinkResolver.parseMaps(url)
        if parsed.lat == nil || parsed.name == nil {
            // Link curto: seguir o redirect (URLSession segue sozinho).
            let (_, response) = try await get(url)
            if let resolved = response.url { final = resolved }
            parsed = LinkResolver.parseMaps(final)
        }
        let name = parsed.name
        return Caption(source: .maps, title: name, text: name ?? "", placeName: name, lat: parsed.lat, lng: parsed.lng, url: final)
    }

    private func youtube(_ url: URL) async throws -> Caption {
        var title: String?
        var author: String?
        if var comps = URLComponents(string: "https://www.youtube.com/oembed") {
            comps.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "format", value: "json")]
            if let oembed = comps.url, let (data, _) = try? await get(oembed),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                title = json["title"] as? String
                author = json["author_name"] as? String
            }
        }
        var description = ""
        if let (data, _) = try? await get(url), let html = String(data: data, encoding: .utf8) {
            description = HTMLMeta.shortDescription(in: html) ?? HTMLMeta.content(of: "og:description", in: html) ?? ""
        }
        let text = [title, author.map { "@\($0)" }, description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { throw CaptionError.empty }
        return Caption(source: .youtube, title: title, text: String(text.prefix(Self.maxLength)), url: url)
    }

    private func openGraph(_ url: URL, source: LinkSource) async throws -> Caption {
        let (data, response) = try await get(url)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) { throw CaptionError.http(http.statusCode) }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw CaptionError.empty }
        let title = HTMLMeta.content(of: "og:title", in: html) ?? HTMLMeta.title(in: html)
        let description = HTMLMeta.content(of: "og:description", in: html) ?? HTMLMeta.content(of: "description", in: html) ?? ""
        let text = [title, description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        // Página de login do Instagram não traz legenda.
        let useless = text.isEmpty || text.lowercased().contains("log in") && description.count < 40
        guard !useless else { throw CaptionError.empty }
        return Caption(source: source, title: title, text: String(text.prefix(Self.maxLength)), url: response.url ?? url)
    }

    private func get(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("pt-BR,pt;q=0.9,en;q=0.8,ja;q=0.7", forHTTPHeaderField: "Accept-Language")
        return try await session.data(for: request)
    }
}

/// Leitura mínima de `<meta>` e `<title>` (sem parser de HTML).
enum HTMLMeta {
    static func content(of property: String, in html: String) -> String? {
        let p = NSRegularExpression.escapedPattern(for: property)
        let patterns = [
            #"<meta[^>]+(?:property|name)\s*=\s*["']"# + p + #"["'][^>]*content\s*=\s*"([^"]*)""#,
            #"<meta[^>]+(?:property|name)\s*=\s*["']"# + p + #"["'][^>]*content\s*=\s*'([^']*)'"#,
            #"<meta[^>]+content\s*=\s*"([^"]*)"[^>]*(?:property|name)\s*=\s*["']"# + p + #"["']"#,
        ]
        for pattern in patterns {
            if let value = firstGroup(pattern, in: html) { return decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }

    static func title(in html: String) -> String? {
        firstGroup(#"<title[^>]*>([^<]*)</title>"#, in: html).map(decodeEntities)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// YouTube guarda a descrição completa em `"shortDescription":"…"`.
    static func shortDescription(in html: String) -> String? {
        guard let raw = firstGroup(#""shortDescription":"((?:[^"\\]|\\.)*)""#, in: html) else { return nil }
        let json = "\"\(raw)\""
        return (try? JSONDecoder().decode(String.self, from: Data(json.utf8))) ?? raw
    }

    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        let named = ["&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&amp;": "&"]
        for (k, v) in named { out = out.replacingOccurrences(of: k, with: v) }
        // &#x1F35C; e &#12345;
        while let m = out.firstMatch(of: /&#(x?)([0-9a-fA-F]+);/) {
            let value = m.1.isEmpty ? UInt32(m.2) : UInt32(m.2, radix: 16)
            let char = value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
            out.replaceSubrange(m.range, with: char)
        }
        return out
    }
}
