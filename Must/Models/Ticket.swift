import Foundation

/// Ingresso (ou confirmação com QR) de um lugar: âncora do dia, como a reserva (prompt 14 · C).
/// Fica no `Place` como JSON (`ticketsData`) e entra no board exportado. O PDF não vai no JSON:
/// fica no container do app (`TicketFiles`, `FileProtectionType.complete`) e o `Ticket` guarda só o nome.
struct Ticket: Codable, Hashable, Sendable, Identifiable {
    var id: String
    /// Início (a âncora do dia).
    var at: Date
    /// `EventSession.id` da sessão ligada (art, jogo ou experiência), se houver.
    var sessionId: String?
    /// Código de confirmação ("BR-7K2M-9931").
    var confirmation: String?
    /// Texto do QR (o que o leitor da entrada lê).
    var qrPayload: String?
    /// Nome do arquivo em `TicketFiles` (PDF, foto).
    var pdfName: String?
    /// Total pago, na moeda da região.
    var paid: Double?
    var people: Int?
    /// Cancelamento grátis até este instante.
    var cancelUntil: Date?
    /// `.pkpass` do fornecedor ("+ Wallet"). Sem ele, o botão some.
    var walletPassURL: URL?

    init(id: String = UUID().uuidString, at: Date, sessionId: String? = nil, confirmation: String? = nil, qrPayload: String? = nil,
         pdfName: String? = nil, paid: Double? = nil, people: Int? = nil, cancelUntil: Date? = nil, walletPassURL: URL? = nil) {
        self.id = id
        self.at = at
        self.sessionId = sessionId
        self.confirmation = confirmation
        self.qrPayload = qrPayload
        self.pdfName = pdfName
        self.paid = paid
        self.people = people
        self.cancelUntil = cancelUntil
        self.walletPassURL = walletPassURL
    }
}

extension Place {
    /// Ingressos anexados (JSON em `ticketsData`).
    var tickets: [Ticket] {
        get { ticketsData.flatMap { try? JSONDecoder.board.decode([Ticket].self, from: $0) } ?? [] }
        set { ticketsData = newValue.isEmpty ? nil : try? JSONEncoder.board(timeZone: .gmt).encode(newValue) }
    }

    /// Ingresso anexado a uma sessão marca essa sessão como comprada (vira âncora, como `bought`).
    func syncBoughtSessions() {
        var extra = self.extra ?? PlaceExtra()
        extra.markBought(Set(tickets.compactMap(\.sessionId)))
        self.extra = extra
    }
}
