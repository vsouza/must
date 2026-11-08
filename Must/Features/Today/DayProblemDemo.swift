#if DEBUG
import Foundation
import SwiftData

/// `-debugProblemDemo YES` (prints do QA): põe, uma vez, a hospedagem de Tóquio e Kyoto e os dois voos da viagem ao Japão
/// (ida pousando em NRT dia 11, volta saindo de HND dia 24) pra os dias de chegada, de trem e o último dia terem dados.
/// Só mexe no Japão; o resto fica como está.
@MainActor
enum DayProblemDemo {
    static func ensure(context: ModelContext, region: Region) {
        guard region == .jp else { return }
        let dates = BoardDates(timeZone: region.timeZone)
        func at(_ day: String, _ hhmm: String) -> Date { dates.time(hhmm, on: dates.day(from: day)!)! }

        if let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first {
            var cities = trip.cities
            for i in cities.indices where cities[i].lodging == nil {
                switch cities[i].id {
                case "tokyo1":
                    cities[i].lodging = CityLodging(name: "Hotel Gracery", neighborhood: "Shinjuku",
                                                    checkIn: at("2026-11-11", "15:00"), checkOut: at("2026-11-17", "11:00"))
                case "kyoto":
                    cities[i].lodging = CityLodging(name: "Machiya Gion", neighborhood: "Gion",
                                                    checkIn: at("2026-11-17", "15:00"), checkOut: at("2026-11-20", "10:00"))
                default: break
                }
            }
            trip.cities = cities
        }

        let flights = context.flights()
        if !flights.contains(where: { $0.id == "qa-ida" }) {
            context.insert(Flight(id: "qa-ida", pnr: "QX7R2A", carrier: "LATAM", template: "intl-japan", checkedKg: 23, cabinKg: 8,
                                  legs: [FlightSegment(id: "qa-ida-1", number: "LA 8084", from: "GRU", to: "NRT",
                                                       departs: at("2026-11-10", "20:00"), arrives: at("2026-11-11", "15:40"),
                                                       seat: "34A", terminal: "3", arrivalTerminal: "2")],
                                  order: 0))
        }
        if !flights.contains(where: { $0.id == "qa-volta" }) {
            context.insert(Flight(id: "qa-volta", pnr: "ZK4M8P", carrier: "LATAM", template: "intl-japan", checkedKg: 23, cabinKg: 8,
                                  legs: [FlightSegment(id: "qa-volta-1", number: "LA 8085", from: "HND", to: "GRU",
                                                       departs: at("2026-11-24", "18:25"), arrives: at("2026-11-24", "23:50"),
                                                       seat: "34C", terminal: "3", arrivalTerminal: "2")],
                                  order: 1))
        }
        try? context.save()
    }
}
#endif
