import Foundation
import UIKit

// Colar link, texto ou foto do cartaz → programação do lugar (RODADA-23 · A, prompt 27 §1).
// Tudo no aparelho: a página lida pelo mesmo leitor do ingresso (`TicketReader.readPage`), o cartaz por Vision (OCR),
// depois `EventExtractor` (regex; o modelo só ajuda no título). O resultado é um rascunho pra conferir antes de salvar:
// nada entra no board sem o usuário aceitar (`apply`). Sem scraping além do link que a pessoa colou.

struct ProgramDraft: Sendable, Equatable {
    var title: String?
    var venue: String?
    var kind: ShowKind
    var sessions: [EventSession]
    /// Preço, fim da temporada, link de ingresso (reaproveita o que o `EventExtractor.parse` lê).
    var art: ArtEvent
    var source: ShowSource
    var url: URL?
    /// Confiança por campo (0…1): "title", "sessions", "season", "price". Abaixo de 0,6 a UI pede conferência.
    var confidence: [String: Double]

    var isEmpty: Bool { sessions.isEmpty && art.runsUntil == nil && title == nil }
}

enum EventPaste {
    /// Texto (colado, de página ou de OCR) → rascunho. Determinístico; sem rede.
    static func draft(text: String, url: URL? = nil, source: ShowSource, timeZone: TimeZone, now: Date = AppClock.now) -> ProgramDraft {
        let art = EventExtractor.parse(text, url: url, timeZone: timeZone, now: now)
        let title = guessTitle(text)
        let sessions = EventExtractor.sessions(in: text, timeZone: timeZone, now: now, fallbackTitle: title ?? "Sessão", url: art.ticketURL)
        var confidence: [String: Double] = [:]
        if title != nil { confidence["title"] = 0.6 }
        if !sessions.isEmpty { confidence["sessions"] = 0.8 }
        if art.runsUntil != nil { confidence["season"] = 0.8 }
        if art.priceAdult != nil { confidence["price"] = 0.7 }
        return ProgramDraft(title: title, venue: nil, kind: EventExtractor.showKind(text), sessions: sessions, art: art, source: source,
                            url: url, confidence: confidence)
    }

    /// Primeira linha com cara de título (3 a 80 letras, sem preço nem data).
    static func guessTitle(_ text: String) -> String? {
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (3...80).contains(line.count), line.contains(where: \.isLetter),
                  line.range(of: #"(¥|R\$|€|\d{1,2}[/:h]\d{2})"#, options: .regularExpression) == nil else { continue }
            return line
        }
        return nil
    }

    /// Link colado: lê a página (uma requisição) e monta o rascunho. Sem rede ou página vazia, devolve `nil`.
    static func fromLink(_ url: URL, timeZone: TimeZone, now: Date = AppClock.now) async -> ProgramDraft? {
        guard let page = try? await TicketReader.readPage(url) else { return nil }
        let d = draft(text: page.text, url: url, source: .link, timeZone: timeZone, now: now)
        return d.isEmpty ? nil : d
    }

    /// Foto ou print do cartaz: Vision (OCR em pt, en e ja) e o mesmo extrator.
    static func fromPoster(_ image: Data, timeZone: TimeZone, now: Date = AppClock.now) async -> ProgramDraft? {
        guard let reading = try? await TicketReader.readImage(image) else { return nil }
        let d = draft(text: reading.text, source: .poster, timeZone: timeZone, now: now)
        return d.isEmpty ? nil : d
    }

    /// Texto colado (ou link, se o texto for só uma URL).
    static func fromText(_ raw: String, timeZone: TimeZone, now: Date = AppClock.now) async -> ProgramDraft? {
        let reading = TicketReader.readText(raw)
        if let url = reading.url, reading.text.isEmpty { return await fromLink(url, timeZone: timeZone, now: now) }
        let d = draft(text: reading.text, source: .link, timeZone: timeZone, now: now)
        return d.isEmpty ? nil : d
    }

    // MARK: Casar com o board

    /// Lugar do board que o rascunho cita (título ou local contém o nome do lugar, ou o contrário). `nil` = perguntar a qual lugar.
    static func match(_ draft: ProgramDraft, in places: [SolverPlace]) -> SolverPlace? {
        let haystack = ShowEventBuilder.norm("\(draft.title ?? "") \(draft.venue ?? "")")
        guard !haystack.isEmpty else { return nil }
        return places.filter { p in
            let name = ShowEventBuilder.norm(p.name)
            return name.count >= 3 && haystack.contains(name)
        }.sorted { ($0.name.count, $0.id) > ($1.name.count, $1.id) }.first
    }

    // MARK: Aplicar

    /// Soma o rascunho ao `extra` do lugar: sessões novas vão pra `program` (sem repetir), a temporada e o preço do rascunho
    /// completam `art` (só o que faltava), e `programSource`/`programCheckedAt` dizem de onde veio e quando.
    static func apply(_ draft: ProgramDraft, to extra: PlaceExtra?, now: Date = AppClock.now) -> PlaceExtra {
        var extra = extra ?? PlaceExtra()
        let known = Set(extra.program.map(\.id))
        extra.program += draft.sessions.filter { !known.contains($0.id) }
        extra.program.sort { ($0.at, $0.title) < ($1.at, $1.title) }
        if !draft.sessions.isEmpty { extra.programSource = draft.source }
        if var art = extra.art {
            if let until = draft.art.runsUntil { art.runsUntil = until }
            if art.priceAdult == nil { art.priceAdult = draft.art.priceAdult }
            if art.priceStudent == nil { art.priceStudent = draft.art.priceStudent }
            if art.ticketURL == nil { art.ticketURL = draft.art.ticketURL }
            extra.art = art
            if draft.art.runsUntil != nil { extra.programSource = extra.programSource ?? draft.source }
        }
        extra.programCheckedAt = now
        return extra
    }

    @MainActor
    static func apply(_ draft: ProgramDraft, to place: Place, now: Date = AppClock.now) {
        place.extra = apply(draft, to: place.extra, now: now)
    }
}
