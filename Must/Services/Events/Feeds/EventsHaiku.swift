import Foundation

/// Fallback na nuvem (prompt 26 §3): lê só os títulos/resumos dos feeds que vieram sem data e devolve local, datas e preço.
/// REGRA do Vinicius: só `CloudBoost.model` (Haiku), effort `low`, sem thinking; 1×/dia por cidade; só com chave.
/// Nunca cria evento: só completa um item que já veio do feed (por índice), e a data tem de ser válida.
enum EventsHaiku {
    static let maxItems = 12
    static let maxTokens = 1_024

    static var schema: [String: Any] { [
        "type": "object", "additionalProperties": false, "required": ["events"],
        "properties": ["events": ["type": "array", "items": [
            "type": "object", "additionalProperties": false, "required": ["index", "venue", "startDate", "endDate", "price"],
            "properties": [
                "index": ["type": "integer"],
                "venue": ["type": "string"],
                "startDate": ["type": "string"],
                "endDate": ["type": "string"],
                "price": ["type": "string"],
            ],
        ]]],
    ] }

    static let instructions = """
    Você lê títulos e resumos de itens de uma agenda cultural. Para cada item que descreve um evento com data, devolva o \
    local (nome do lugar), a data de início e a de fim em AAAA-MM-DD e o preço como aparece. Use string vazia quando o texto \
    não disser. Nunca invente evento, data nem preço: só o que está escrito no item. Ignore itens que não são evento.
    """

    /// Só os sem data (até `maxItems`), numerados.
    static func candidates(_ events: [ShowEvent], items: [String: String]) -> [(index: Int, event: ShowEvent, summary: String)] {
        events.filter { $0.startsAt == nil && $0.source == .feed }.prefix(maxItems).enumerated()
            .map { ($0.offset, $0.element, items[$0.element.id] ?? "") }
    }

    static func requestBody(_ list: [(index: Int, event: ShowEvent, summary: String)]) -> [String: Any] {
        let text = list.map { "\($0.index). \($0.event.title) — \(String($0.summary.prefix(280)))" }.joined(separator: "\n")
        return CloudBoost.messages(system: instructions + " Responda em pt-BR.", user: "Itens:\n\(text)", schema: schema, maxTokens: maxTokens)
    }

    /// Resposta → eventos completados. Índice fora da lista, data impossível ou fora de ±1 ano são ignorados.
    static func apply(_ data: Data, to list: [(index: Int, event: ShowEvent, summary: String)], now: Date, calendar: Calendar) throws -> [ShowEvent] {
        let payload = try CloudBoost.payload(data)
        let rows = payload["events"] as? [[String: Any]] ?? []
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        func day(_ raw: String?) -> Date? {
            guard let raw, !raw.isEmpty, let d = f.date(from: raw), abs(d.timeIntervalSince(now)) < 366 * 86_400 else { return nil }
            return d
        }
        var out: [ShowEvent] = []
        for row in rows {
            guard let index = row["index"] as? Int, let match = list.first(where: { $0.index == index }) else { continue }
            var event = match.event
            guard let start = day(row["startDate"] as? String) else { continue }
            event.startsAt = start
            if let end = day(row["endDate"] as? String), end > start { event.runsUntil = end }
            if let venue = row["venue"] as? String, !venue.isEmpty { event.venue = venue }
            if let price = row["price"] as? String, !price.isEmpty { event.priceText = price }
            out.append(event)
        }
        return out
    }
}
