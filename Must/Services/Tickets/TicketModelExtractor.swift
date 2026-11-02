import Foundation
import FoundationModels

/// Campos que o modelo no aparelho tenta quando a regex não achou (ou achou com baixa confiança).
@Generable
struct GeneratedTicket {
    @Guide(description: "Nome da experiência, show, jogo ou viagem, como aparece no texto")
    var title: String
    @Guide(description: "Fornecedor ou site de venda (Viator, GetYourGuide, Klook, Sympla…), ou vazio")
    var supplier: String
    @Guide(description: "Ponto de encontro ou endereço, como aparece no texto, ou vazio")
    var meetingPoint: String
    @Guide(description: "Código de confirmação ou localizador exatamente como está no texto, ou vazio")
    var confirmation: String
    @Guide(description: "Número de pessoas, ou 0")
    var people: Int
    @Guide(description: "Tipo do ingresso", .anyOf(["experience", "event", "flight", "rail", "other"]))
    var kind: String
}

/// Completa o `ExtractedTicket` com o modelo do aparelho (Foundation Models), sem rede.
/// Regra: o modelo não inventa. Cada valor só entra se aparece literalmente no texto lido; o que a regex achou com
/// confiança ≥ 0,8 não é trocado. Sem Apple Intelligence, devolve o que a regex já tinha.
enum TicketModelExtractor {
    static let instructions = """
    Você lê o texto de um ingresso, reserva ou confirmação de compra e extrai os dados. \
    Use só o que está no texto; deixe vazio (ou 0) o que não aparecer. Não traduza nomes próprios.
    """

    static let modelConfidence = 0.8

    static func enrich(_ ticket: ExtractedTicket, text: String) async -> ExtractedTicket {
        guard OnDeviceAI.isAvailable, !text.isEmpty else { return ticket }
        let session = LanguageModelSession(instructions: instructions)
        guard let generated = try? await session.respond(to: "Texto do ingresso:\n\(text.prefix(4_000))", generating: GeneratedTicket.self).content else {
            return ticket
        }
        return merge(ticket, generated, text: text)
    }

    /// Junta o modelo com a regex sem trocar o que a regex já tem com confiança alta.
    static func merge(_ ticket: ExtractedTicket, _ g: GeneratedTicket, text: String) -> ExtractedTicket {
        var out = ticket
        func needsHelp(_ current: Double?) -> Bool { current.map { $0 < ExtractedTicket.reviewBelow } ?? true }

        let title = g.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsHelp(ticket.title?.confidence), !title.isEmpty, TicketText.appears(title, in: text) {
            out.title = Extracted(value: title, confidence: modelConfidence, origin: "no aparelho")
        }
        let supplier = g.supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsHelp(ticket.supplier?.confidence), !supplier.isEmpty, TicketText.appears(supplier, in: text) {
            out.supplier = Extracted(value: supplier, confidence: modelConfidence, origin: "no aparelho")
        }
        let meeting = g.meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsHelp(ticket.meetingPoint?.confidence), !meeting.isEmpty, TicketText.appears(meeting, in: text) {
            out.meetingPoint = Extracted(value: meeting, confidence: modelConfidence, origin: "no aparelho")
        }
        let code = g.confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        if needsHelp(ticket.confirmation?.confidence), TicketText.looksLikeCode(code), TicketText.appears(code, in: text) {
            out.confirmation = Extracted(value: code, confidence: modelConfidence, origin: "no aparelho")
        }
        if ticket.people == nil, (1...50).contains(g.people), TicketText.appears(String(g.people), in: text) {
            out.people = Extracted(value: g.people, confidence: 0.7, origin: "no aparelho")
        }
        if ticket.kind == .other, let kind = TicketKind(rawValue: g.kind), kind != .other, kind != .flight {
            out.kind = kind
        }
        return out
    }
}
