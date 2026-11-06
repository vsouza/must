import CoreLocation
import Foundation

/// Fonte → `ShowEvent` (contrato do prompt 26 e da rodada 23). Tudo puro e testado; a rede fica no `EventsService`.
enum EventsMapping {
    // MARK: Feeds (RSS/Atom)

    /// Itens de um feed viram `ShowEvent` (source `.feed`). Feed `events`: todo item vale; `agenda`/`guide`: só o que cita data.
    /// Item mais velho que `maxAge` cai. A data vem do texto (`EventDateExtractor`); sem data, `startsAt` fica `nil`.
    static func feedEvents(_ items: [FeedItem], feed: EventsSources.Feed, region: Region, now: Date, maxAge: TimeInterval,
                           limit: Int = 30) -> [ShowEvent] {
        let calendar = region.calendar
        var out: [ShowEvent] = []
        for item in items {
            if let published = item.published, now.timeIntervalSince(published) > maxAge { continue }
            let reference = item.published ?? now
            let dates = EventDateExtractor.dates(in: item.title + ". " + item.summary, reference: reference, calendar: calendar)
            let span = EventDateExtractor.span(from: dates, now: now, calendar: calendar)
            if feed.kind != "events", span == nil { continue }
            guard let link = item.link else { continue }
            let lower = item.title.lowercased()
            let exhibition = ["exhibition", "exposição", "exposicao", "mostra", "mostre", "museum", "museu"].contains { lower.contains($0) }
            out.append(ShowEvent(id: "feed:\(feed.id):\(stableHash(link.absoluteString))", placeId: nil, kind: exhibition ? .exhibition : .other,
                                 title: item.title, venue: nil, lat: nil, lng: nil, startsAt: span?.start, runsUntil: span?.end,
                                 sessions: [], priceText: nil, url: link, source: .feed, checkedAt: now))
            if out.count >= limit { break }
        }
        return out
    }

    /// Hash estável (FNV-1a) pro id: `hashValue` muda a cada abertura do app.
    static func stableHash(_ text: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
        return String(h, radix: 36)
    }

    // MARK: Ticketmaster Discovery

    static func ticketmaster(_ data: Data, now: Date) -> [ShowEvent] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedded = json["_embedded"] as? [String: Any],
              let events = embedded["events"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return events.compactMap { e in
            guard let id = e["id"] as? String, let name = e["name"] as? String else { return nil }
            let dates = (e["dates"] as? [String: Any])?["start"] as? [String: Any]
            let start = (dates?["dateTime"] as? String).flatMap { iso.date(from: $0) }
            let venue = ((e["_embedded"] as? [String: Any])?["venues"] as? [[String: Any]])?.first
            let loc = venue?["location"] as? [String: Any]
            let segment = ((e["classifications"] as? [[String: Any]])?.first?["segment"] as? [String: Any])?["name"] as? String
            let kind: ShowKind = segment == "Sports" ? .match : (segment == "Music" || segment == "Arts & Theatre" ? .show : .other)
            var price: String?
            if let range = (e["priceRanges"] as? [[String: Any]])?.first, let min = range["min"] as? Double {
                price = "\(range["currency"] as? String ?? "") \(Int(min.rounded()))".trimmingCharacters(in: .whitespaces)
            }
            return ShowEvent(id: "ticketmaster:\(id)", placeId: nil, kind: kind, title: name, venue: venue?["name"] as? String,
                             lat: (loc?["latitude"] as? String).flatMap(Double.init), lng: (loc?["longitude"] as? String).flatMap(Double.init),
                             startsAt: start, runsUntil: nil, sessions: [], priceText: price, url: (e["url"] as? String).flatMap(URL.init),
                             source: .ticketmaster, checkedAt: now)
        }
    }

    // MARK: Bandsintown

    /// `datetime` vem local do lugar ("2026-11-05T20:00:00"); lido no fuso da região.
    static func bandsintown(_ data: Data, region: Region, now: Date) -> [ShowEvent] {
        guard let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = region.timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return events.compactMap { e in
            let id = (e["id"] as? String) ?? (e["id"] as? Int).map(String.init)
            guard let id else { return nil }
            let venue = e["venue"] as? [String: Any]
            let lineup = (e["lineup"] as? [String])?.joined(separator: ", ")
            let title = (e["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? lineup ?? "Show"
            let lat = (venue?["latitude"] as? String).flatMap(Double.init) ?? venue?["latitude"] as? Double
            let lng = (venue?["longitude"] as? String).flatMap(Double.init) ?? venue?["longitude"] as? Double
            return ShowEvent(id: "bandsintown:\(id)", placeId: nil, kind: .show, title: title, venue: venue?["name"] as? String,
                             lat: lat, lng: lng, startsAt: (e["datetime"] as? String).flatMap { f.date(from: String($0.prefix(19))) },
                             runsUntil: nil, sessions: [], priceText: nil, url: (e["url"] as? String).flatMap(URL.init),
                             source: .bandsintown, checkedAt: now)
        }
    }

    // MARK: Consultas (hoje, próximos dias)

    static func isOn(_ event: ShowEvent, day: Date, calendar: Calendar) -> Bool {
        guard let start = event.startsAt else { return false }
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: event.runsUntil ?? start)
        let d = calendar.startOfDay(for: day)
        return d >= from && d <= to
    }

    static func dedupe(_ events: [ShowEvent]) -> [ShowEvent] {
        var seen: Set<String> = []
        return events.filter { seen.insert($0.id).inserted }
    }
}
