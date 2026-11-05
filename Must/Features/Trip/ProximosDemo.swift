#if DEBUG
import Foundation
import SwiftData

/// `-debugScreen proximos` e `museu:j28`: dados de demonstração do Japão pro print do `Proximos.png` e do `MuseuFoto.png`
/// (ingresso do teamLab dom 16 14:00, Shinkansen ter 17 09:12, voo de volta ter 24 23:55). Só cria o que falta, só no jp.
@MainActor
enum ProximosDemo {
    static func ensure(context: ModelContext, region: Region) {
        guard region == .jp else { return }
        let dates = BoardDates(timeZone: region.timeZone)
        ensureTeamLab(context: context, dates: dates)

        let events = (try? context.fetch(FetchDescriptor<TripEvent>())) ?? []
        if !events.contains(where: { $0.title.contains("Nozomi") }),
           let day = dates.day(from: "2026-11-17"), let at = dates.time("09:12", on: day) {
            context.insert(TripEvent(at: at, title: "Shinkansen Nozomi 219", kind: .train,
                                     note: "Tokyo → Kyoto · 2h15 · carro 7 · assentos 12A-12B · lado direito: Fuji"))
        }

        let flights = (try? context.fetch(FetchDescriptor<Flight>())) ?? []
        if !flights.contains(where: { $0.id == "demo-volta" }),
           let day = dates.day(from: "2026-11-24"), let at = dates.time("23:55", on: day) {
            let legs = [
                FlightSegment(id: "demo-volta-1", number: "QR 813", from: "HND", to: "DOH", departs: at, arrives: at.addingTimeInterval(12 * 3600)),
                FlightSegment(id: "demo-volta-2", number: "QR 773", from: "DOH", to: "GRU", departs: at.addingTimeInterval(15 * 3600)),
            ]
            let checklist = (0..<12).map { i in
                ChecklistItem(id: "demo-\(i)", phase: i < 4 ? .h72 : (i < 8 ? .bags : .airport), title: "item \(i + 1)", done: i < 2)
            }
            context.insert(Flight(id: "demo-volta", pnr: "QX7R2A", carrier: "LATAM", template: "intl-japan", checkedKg: 23,
                                  legs: legs, checklist: checklist))
        }
        try? context.save()
    }

    /// Ingresso do teamLab Borderless (j28): dom 16, 14:00, 2 pessoas, QR salvo.
    static func ensureTeamLab(context: ModelContext, dates: BoardDates) {
        let id = "j28"
        guard let place = try? context.fetch(FetchDescriptor<Place>(predicate: #Predicate { $0.id == id })).first,
              place.tickets.isEmpty, let day = dates.day(from: "2026-11-16"), let at = dates.time("14:00", on: day) else { return }
        place.tickets = [Ticket(id: "demo-teamlab", at: at, confirmation: "TLB-4471-2026", qrPayload: "TLB-4471-2026", paid: 11_200, people: 2)]
        try? context.save()
    }
}
#endif
