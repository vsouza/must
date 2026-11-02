import Foundation

/// Trazer ingresso (fatia 3) → Voos (prompt 15 · C): o voo lido vira `Flight` com as pernas e o checklist do modelo.
/// Função pura: quem grava é `TicketImportModel`.
enum FlightFromTicket {
    /// Pernas lidas (`ExtractedTicket`) → pernas do app. A hora lida vale no fuso da região; aqui ela vai pro fuso
    /// do aeroporto de origem (o e-mail da LATAM traz a hora local de cada trecho).
    static func segments(from draft: TicketDraft, region: Region) -> [FlightSegment] {
        draft.legs.map { leg in
            let departs = leg.departs ?? draft.at
            return FlightSegment(number: leg.number, from: leg.from.uppercased(), to: leg.to.uppercased(),
                                 departs: FlightRules.inAirportZone(departs, region: region, iata: leg.from))
        }
    }

    /// `nil` sem nenhum trecho (voo sem número e sem rota não vira reserva).
    static func flight(from draft: TicketDraft, region: Region, order: Int, attachmentName: String?, now: Date) -> Flight? {
        let segments = segments(from: draft, region: region)
        guard let first = segments.first else { return nil }
        let key = FlightRules.templateKey(for: segments)
        let pnr = draft.confirmation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Flight(pnr: pnr, carrier: FlightRules.carrierName(FlightRules.carrierCode(of: first.number)), template: key,
                      legs: segments, checklist: ChecklistTemplates.items(template: key, legs: segments),
                      attachmentName: attachmentName, order: order, createdAt: now)
    }
}
