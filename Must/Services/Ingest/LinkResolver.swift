import Foundation

/// De onde veio o que foi colado.
enum LinkSource: String, Sendable, CaseIterable {
    case instagram, tiktok, youtube, maps, web, text

    var badge: String? {
        switch self {
        case .instagram: "IG"
        case .tiktok: "TT"
        case .youtube: "YT"
        case .maps: "Maps"
        case .web, .text: nil
        }
    }

    var sourceKind: SourceKind {
        switch self {
        case .instagram: .instagram
        case .tiktok: .tiktok
        case .youtube: .youtube
        case .maps: .maps
        case .web, .text: .manual
        }
    }
}

struct ResolvedLink: Equatable, Sendable {
    var source: LinkSource
    var url: URL?
    /// Texto colado sem o link (pode ser o próprio nome do lugar).
    var text: String
}

/// (a) Identifica a fonte de um link ou texto colado.
enum LinkResolver {
    static func resolve(_ input: String) -> ResolvedLink {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = firstURL(in: trimmed) else { return ResolvedLink(source: .text, url: nil, text: trimmed) }
        let rest = trimmed.replacingOccurrences(of: url.absoluteString, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ResolvedLink(source: source(of: url), url: url, text: rest)
    }

    static func source(of url: URL) -> LinkSource {
        var host = (url.host() ?? "").lowercased()
        for prefix in ["www.", "m.", "mobile."] where host.hasPrefix(prefix) { host.removeFirst(prefix.count) }
        let path = url.path().lowercased()
        if host.hasSuffix("instagram.com") || host == "instagr.am" { return .instagram }
        if host.hasSuffix("tiktok.com") { return .tiktok }
        if host.hasSuffix("youtube.com") || host == "youtu.be" { return .youtube }
        if host == "maps.app.goo.gl" || (host == "goo.gl" && path.hasPrefix("/maps"))
            || host.hasPrefix("maps.google.") || (host.hasPrefix("google.") && path.hasPrefix("/maps"))
            || host == "maps.apple.com" { return .maps }
        return .web
    }

    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        if let match = detector?.firstMatch(in: text, range: range), let url = match.url,
           url.scheme == "http" || url.scheme == "https" {
            return url
        }
        // "instagram.com/reel/…" sem esquema
        if let token = text.split(whereSeparator: \.isWhitespace).first(where: { $0.contains(".") && $0.contains("/") }),
           let url = URL(string: "https://\(token)"), url.host() != nil {
            return url
        }
        return nil
    }

    /// Google Maps: "/place/<nome>/@lat,lng", "!3d<lat>!4d<lng>", "?q=lat,lng", "?q=nome". Apple Maps: "ll=", "q=".
    static func parseMaps(_ url: URL) -> (name: String?, lat: Double?, lng: Double?) {
        let string = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        var name: String?
        var lat: Double?, lng: Double?

        if let range = string.range(of: #"/place/([^/@?]+)"#, options: .regularExpression) {
            name = String(string[range]).replacingOccurrences(of: "/place/", with: "").replacingOccurrences(of: "+", with: " ")
        }
        if let m = string.firstMatch(of: /!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/) {
            lat = Double(m.1); lng = Double(m.2)
        } else if let m = string.firstMatch(of: /@(-?\d+\.\d+),(-?\d+\.\d+)/) {
            lat = Double(m.1); lng = Double(m.2)
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for key in ["q", "query", "ll", "daddr"] {
            guard let value = items.first(where: { $0.name == key })?.value else { continue }
            if let m = value.firstMatch(of: /^(-?\d+\.\d+),\s*(-?\d+\.\d+)$/) {
                if lat == nil { lat = Double(m.1); lng = Double(m.2) }
            } else if name == nil, key != "ll" {
                name = value.replacingOccurrences(of: "+", with: " ")
            }
        }
        return (name?.trimmingCharacters(in: .whitespaces), lat, lng)
    }
}
