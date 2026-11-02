import Foundation

/// Trazer ingresso (fatia 3) → Carteira (prompt 15 · B): trem vira passe de trem, QR do Visit Japan Web vira entryQR.
/// Voo continua fora (fatia 6, Voos). Função pura: quem grava é `TicketImportModel`.
enum WalletFromTicket {
    /// Tipo da Carteira pro tipo do ingresso lido. Nil quando o ingresso não é da Carteira.
    static func kind(for ticket: TicketKind) -> WalletKind? {
        switch ticket {
        case .rail: .railPass
        case .entry: .entryQR
        case .flight, .experience, .event, .other: nil
        }
    }

    /// Item novo a partir da conferência. `attachmentName` é o arquivo já guardado em `TicketFiles`, ou nil.
    static func item(from draft: TicketDraft, kind: WalletKind, attachmentName: String?, order: Int, now: Date) -> WalletItem {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? fallbackName(kind) : title
        let supplier = draft.supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = draft.confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = [supplier, code].filter { !$0.isEmpty }.joined(separator: " · ")
        let qr = draft.qrPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        return WalletItem(kind: kind, name: name, detail: detail.isEmpty ? fallbackDetail(kind) : detail,
                          validFrom: kind == .railPass ? draft.at : nil, attachmentName: attachmentName,
                          qrPayload: qr.isEmpty ? nil : qr, order: order, createdAt: now)
    }

    static func fallbackName(_ kind: WalletKind) -> String {
        kind == .entryQR ? "Visit Japan Web" : "Passe de trem"
    }

    static func fallbackDetail(_ kind: WalletKind) -> String {
        kind == .entryQR ? "QR salvo · funciona offline" : "lido do ingresso"
    }
}
