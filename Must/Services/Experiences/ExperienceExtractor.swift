import Foundation
import FoundationModels

// Página de experiência colada → dados de um `Place` do tipo experiência (prompt 14 · C, item 9).
// Padrão do EventExtractor: o modelo lê no aparelho; o que ele afirma só entra se aparecer no texto da página.
// Sem modelo, o fallback é regex (reaproveita TicketMoney, TicketDates e TicketExtractor da fatia 3).

@Generable
struct ExtractedExperience {
    @Guide(description: "Nome da experiência como aparece na página (aula, tour, ingresso)")
    var title: String
    @Guide(description: "Fornecedor se aparecer (Viator, Klook, Airbnb, GetYourGuide, Sympla, Peatix, e-plus), ou vazio")
    var supplier: String
    @Guide(description: "Preço a partir de, em número inteiro na moeda da página, ou 0 se não aparecer")
    var price: Int
    @Guide(description: "Moeda em ISO (JPY, BRL, USD, EUR), ou vazio")
    var currency: String
    @Guide(description: "Duração em minutos (ex.: 180 para 3 horas), ou 0")
    var durationMinutes: Int
    @Guide(description: "Ponto de encontro como aparece na página, ou vazio")
    var meetingPoint: String
    @Guide(description: "Data de uma sessão marcada no formato yyyy-MM-dd, ou vazio")
    var date: String
    @Guide(description: "Horário de início da sessão no formato HH:mm, ou vazio")
    var time: String
    @Guide(description: "Idiomas em que acontece (ex.: inglês, japonês), até 3", .maximumCount(3))
    var languages: [String]
}

/// O que a página diz da experiência. Vira `Place` (lista Must do) quando o usuário confirma.
struct ExperienceDraft: Equatable, Sendable {
    var name: String
    var info: ExperienceInfo
    /// Sessão com data e hora, se a página trouxe uma.
    var session: EventSession?
    /// De onde veio o dado: "no aparelho" ou "palavras-chave".
    var via: String
}

enum ExperienceExtractor {
    static let instructions = """
    Você lê a página de uma experiência (aula, tour, ingresso com hora marcada) e extrai os dados. \
    Use só o que está no texto; deixe vazio (ou 0) o que não aparecer. Data em yyyy-MM-dd, hora em HH:mm.
    """

    /// Teto do texto mandado ao modelo.
    static let promptLimit = 3000

    static func fullText(_ link: ExperienceLink) -> String {
        let head = [link.title, link.description.nonEmpty].compactMap { $0 }
        return String((head + [link.pageText]).joined(separator: "\n").prefix(20_000))
    }

    /// Lê o link: no aparelho quando o usuário deixou ligado e o modelo existe; senão, regex.
    static func read(_ link: ExperienceLink, region: Region, onDeviceAI: Bool) async -> ExperienceDraft {
        if onDeviceAI, OnDeviceAI.isAvailable, let draft = try? await extractOnDevice(link, region: region) {
            return draft
        }
        return parse(link, region: region)
    }

    static func extractOnDevice(_ link: ExperienceLink, region: Region) async throws -> ExperienceDraft? {
        let text = String(fullText(link).prefix(promptLimit))
        let session = LanguageModelSession(instructions: instructions)
        let generated = try await session.respond(to: "Página:\n\(text)", generating: ExtractedExperience.self).content
        return map(generated, link: link, region: region)
    }

    // MARK: Sem modelo (regex)

    static func parse(_ link: ExperienceLink, region: Region) -> ExperienceDraft {
        let text = fullText(link)
        let money = TicketMoney.first(in: text)
        var info = ExperienceInfo(supplier: link.supplier, url: link.url, imageURL: link.imageURL)
        info.priceFrom = money?.value
        info.currency = money?.currency.flatMap { $0 == region.currency ? nil : $0 }
        info.durationMinutes = duration(in: text)
        info.groupMax = groupMax(in: text)
        info.languages = languages(in: text)
        info.meetingPoint = TicketExtractor.meetingPoint(in: text).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".;,")) }
        var session: EventSession?
        if let found = TicketDates.first(in: text, region: region), found.hasTime {
            session = EventSession(at: found.date, title: link.title ?? "Sessão")
        }
        return ExperienceDraft(name: link.title ?? "Experiência", info: info, session: session, via: "palavras-chave")
    }

    /// "2h30", "3 hours", "1.5 h", "180 min", "3時間". Procura primeiro depois de um rótulo de duração.
    static func duration(in text: String) -> Int? {
        let labelled = TicketText.first(#"(?i)(?:dura[çc][aã]o|duration|length|時間)\s*:?\s*([^\n]{1,24})"#, in: text)?[1]
        let snippet = labelled ?? text
        if let m = TicketText.first(#"(?i)\b(\d{1,2})\s?h\s?(\d{2})\b"#, in: snippet), let h = Int(m[1]), let min = Int(m[2]), h < 24 {
            return h * 60 + min
        }
        if let m = TicketText.first(#"(?i)\b(\d{1,2}(?:[.,]\d)?)\s?(?:hours?|horas?|hrs?|h)\b"#, in: snippet),
           let hours = Double(m[1].replacingOccurrences(of: ",", with: ".")), (0.25...24).contains(hours) {
            return Int((hours * 60).rounded())
        }
        if let m = TicketText.first(#"(?i)\b(\d{2,3})\s?(?:min|minutes?|minutos?)\b"#, in: snippet), let minutes = Int(m[1]), (10...1440).contains(minutes) {
            return minutes
        }
        if let m = TicketText.first(#"(\d(?:\.\d)?)\s?時間"#, in: snippet), let hours = Double(m[1]) { return Int((hours * 60).rounded()) }
        return nil
    }

    /// "grupo até 8", "group size: 8", "up to 8 people". Não pega "até 2h".
    static func groupMax(in text: String) -> Int? {
        let patterns = [
            #"(?i)(?:grupo(?: at[ée])?|group(?: size)?|max(?:imum)?)\s*:?\s*(?:at[ée]\s*|up to\s*)?(\d{1,2})\b"#,
            #"(?i)(?:at[ée]|up to)\s*(\d{1,2})\s*(?:pessoas|people|guests|participantes|travell?ers)"#,
        ]
        for pattern in patterns {
            if let m = TicketText.first(pattern, in: text), let n = Int(m[1]), (1...50).contains(n) { return n }
        }
        return nil
    }

    /// "em inglês", "in English", "Language: Japanese" → nomes em português.
    static func languages(in text: String) -> [String] {
        let names = ["english": "inglês", "inglês": "inglês", "japanese": "japonês", "japonês": "japonês",
                     "portuguese": "português", "português": "português", "spanish": "espanhol", "espanhol": "espanhol"]
        var out: [String] = []
        for m in TicketText.matches(#"(?i)\b(?:in|em|language|idioma)s?\s*:?\s*(english|inglês|japanese|japonês|portuguese|português|spanish|espanhol)\b"#, in: text) {
            if let name = names[m.groups[1].lowercased()], !out.contains(name) { out.append(name) }
        }
        return out
    }

    // MARK: Junta o modelo com o que a página diz

    /// Só aceita o que aparece no texto da página: o modelo não inventa preço, horário nem ponto de encontro.
    static func map(_ g: ExtractedExperience, link: ExperienceLink, region: Region) -> ExperienceDraft? {
        let title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let text = fullText(link)
        var draft = parse(link, region: region)
        draft.via = "no aparelho"
        if TicketText.appears(title, in: text) { draft.name = title }
        if draft.info.priceFrom == nil, g.price > 0, numberAppears(g.price, in: text) {
            draft.info.priceFrom = Double(g.price)
            if draft.info.currency == nil, ["JPY", "BRL", "USD", "EUR"].contains(g.currency), g.currency != region.currency,
               TicketText.appears(g.currency, in: text) {
                draft.info.currency = g.currency
            }
        }
        if draft.info.durationMinutes == nil, (10...1440).contains(g.durationMinutes) { draft.info.durationMinutes = g.durationMinutes }
        if draft.info.meetingPoint == nil, !g.meetingPoint.isEmpty, TicketText.appears(g.meetingPoint, in: text) {
            draft.info.meetingPoint = g.meetingPoint
        }
        if draft.info.languages.isEmpty { draft.info.languages = g.languages.filter { TicketText.appears($0, in: text) } }
        if draft.session == nil, !g.date.isEmpty, g.time.count == 5, text.contains(g.time) {
            let dates = BoardDates(timeZone: region.timeZone)
            if let day = dates.day(from: g.date), let at = dates.time(g.time, on: day) {
                draft.session = EventSession(at: at, title: draft.name)
            }
        }
        return draft
    }

    /// 12000 aparece como "12000", "12.000", "12,000" ou "12 000", sem ser parte de outro número.
    static func numberAppears(_ value: Int, in text: String) -> Bool {
        let digits = Array(String(value))
        var pattern = ""
        for (i, ch) in digits.enumerated() {
            pattern.append(ch)
            let left = digits.count - i - 1
            if left > 0, left % 3 == 0 { pattern += "[.,' ]?" }
        }
        return text.range(of: "(?<![0-9])\(pattern)(?![0-9])", options: .regularExpression) != nil
    }
}
