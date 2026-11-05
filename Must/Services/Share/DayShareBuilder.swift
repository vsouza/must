import Foundation
import SwiftData

/// Junta o que o Mandar precisa de um dia aceito: o `DayPlan` (do `\.dayEngine`), o cartaz e o payload do link.
/// Lê só o aparelho (SwiftData + tabelas do bundle): nenhuma rede.
@MainActor
enum DayShareBuilder {
    struct Day: Identifiable {
        var plan: DayPlan
        var poster: DayPoster
        var shared: SharedDay
        var id: Date { plan.date }
    }

    static func day(_ date: Date, region: Region, context: ModelContext, engine: any DayEngine) -> Day? {
        let start = region.calendar.startOfDay(for: date)
        guard let plan = engine.plan(for: start, region: region, context: context), !plan.stops.isEmpty else { return nil }
        return make(plan, region: region, board: Board(context: context))
    }

    /// Os dias montados da viagem (do início ao fim); sem viagem marcada (BH), os próximos 14 dias que têm plano.
    static func trip(region: Region, context: ModelContext, engine: any DayEngine) -> [Day] {
        let board = Board(context: context)
        let cal = region.calendar
        let days: [Date]
        if let trip = board.trip, trip.hasTrip, let s = trip.start, let e = trip.end {
            let first = cal.startOfDay(for: s), last = cal.startOfDay(for: e)
            let count = max(0, cal.dateComponents([.day], from: first, to: last).day ?? 0)
            days = (0...min(count, 60)).compactMap { cal.date(byAdding: .day, value: $0, to: first) }
        } else {
            let today = cal.startOfDay(for: AppClock.now)
            days = (0..<14).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        }
        return days.compactMap { date in
            guard let plan = engine.plan(for: date, region: region, context: context), !plan.stops.isEmpty else { return nil }
            return make(plan, region: region, board: board)
        }
    }

    private static func make(_ plan: DayPlan, region: Region, board: Board) -> Day {
        let areaName = plan.area.flatMap { id in AreaCatalog.areas(for: region).first { $0.id == id }?.name }
        let cityName = board.trip?.city(on: plan.date, calendar: region.calendar)?.name ?? CapaState.cityName(region)
        let ids = Set(plan.stops.compactMap(\.placeId))
        let places = board.places.filter { ids.contains($0.id) }
        let coords = Dictionary(places.map { ($0.id, ($0.lat, $0.lng)) }, uniquingKeysWith: { a, _ in a })
        let qrs = places.flatMap { place in
            place.tickets
                .filter { region.calendar.isDate($0.at, inSameDayAs: plan.date) }
                .compactMap { t in t.qrPayload.map { DayPoster.QR(label: DayText.head(place.name), payload: $0) } }
        }
        let poster = DayPoster.make(plan: plan, region: region, areaName: areaName, cityName: cityName, coordinates: coords, qrs: qrs)
        let shared = SharedDay(plan: plan, region: region, areaName: areaName ?? poster.area, cityName: cityName, coordinates: coords)
        return Day(plan: plan, poster: poster, shared: shared)
    }

    /// O que o board tem (uma busca de cada, fora do `body`).
    struct Board {
        var trip: TripInfo?
        var places: [Place]

        init(context: ModelContext) {
            trip = (try? context.fetch(FetchDescriptor<TripInfo>()))?.first
            places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        }
    }
}
