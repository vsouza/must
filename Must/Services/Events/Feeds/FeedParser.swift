import Foundation

/// Um item de feed RSS/Atom (prompt 26 §3). Só texto: nada de ler HTML de página.
struct FeedItem: Hashable, Sendable {
    var title: String
    var link: URL?
    /// Resumo sem tags HTML.
    var summary: String
    var published: Date?
}

/// Parser de RSS 2.0 e Atom (`XMLParser`, sem dependência). Tolerante: XML quebrado devolve o que já leu.
enum FeedParser {
    static func parse(_ data: Data) -> [FeedItem] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    /// Tira tags e entidades do resumo (`<p>`, `&#8217;`…) e junta espaços.
    static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#039;": "'", "&apos;": "'", "&nbsp;": " ",
                        "&#8217;": "’", "&#8216;": "‘", "&#8220;": "“", "&#8221;": "”", "&#8211;": "–", "&#8212;": "—", "&#038;": "&",
                        "&#124;": "|"]
        for (key, value) in entities { text = text.replacingOccurrences(of: key, with: value) }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func date(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z", "dd MMM yyyy HH:mm:ss Z"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let date = f.date(from: text) { return date }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var items: [FeedItem] = []
        private var inItem = false
        private var name = ""
        private var buffer = ""
        private var title = ""
        private var link = ""
        private var summary = ""
        private var published = ""

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String]) {
            if element == "item" || element == "entry" {
                inItem = true
                title = ""; link = ""; summary = ""; published = ""
            }
            guard inItem else { return }
            name = element
            buffer = ""
            // Atom: <link href="…"/>
            if element == "link", let href = attributes["href"], link.isEmpty, attributes["rel"] == nil || attributes["rel"] == "alternate" {
                link = href
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { if inItem { buffer += string } }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if inItem, let text = String(data: CDATABlock, encoding: .utf8) { buffer += text }
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            if element == "item" || element == "entry" {
                inItem = false
                let item = FeedItem(title: FeedParser.plain(title), link: URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
                                    summary: FeedParser.plain(summary), published: FeedParser.date(published))
                if !item.title.isEmpty { items.append(item) }
                return
            }
            guard inItem, element == name else { return }
            let text = buffer
            switch element {
            case "title": title = text
            case "link": if link.isEmpty { link = text }
            case "description", "summary": if summary.isEmpty { summary = text }
            case "content:encoded", "content": if summary.isEmpty { summary = text }
            case "pubDate", "published", "updated", "dc:date": if published.isEmpty { published = text }
            default: break
            }
        }
    }
}
