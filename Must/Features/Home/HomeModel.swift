import CoreLocation
import Foundation
import SwiftData

/// Contas "de tela" da Início que não são da view: usadas pelo `OutsideBridge` (widgets, Live Activity) e pelos
/// cenários de QA. A própria Início não monta mais isso no `body` (prompt 18 · B: `HomeState` faz o cálculo).
/// Contas da Início, separadas da view pra ficar fácil de ler.
@MainActor
struct HomeModel {
    var places: [Place]
    var expenses: [Expense]
    var days: [PlannedDay]
    var trip: TripInfo?
    var region: Region
    var now: Date
    var location: CLLocation?
    var tomorrowWeather: DayWeather?
    var nowTemp: Double?

    /// Raio do "Perto de você".
    static let nearbyRadius: Double = 1500

    var spentToday: Double {
        let range = region.dayRange(now)
        return expenses.filter { range.contains($0.at) }.reduce(0) { $0 + $1.amount }
    }

    var today: PlannedDay? {
        let start = region.calendar.startOfDay(for: now)
        return days.first { $0.date == start && $0.accepted }
    }

    var nextStop: Stop? {
        today?.orderedStops.first { !$0.done && $0.place != nil }
    }

    /// Próxima coisa do dia: a próxima parada do dia aceito ou, sem dia montado, a reserva de hoje.
    var next: (place: Place, at: Date, isReservation: Bool)? {
        if let stop = nextStop, let place = stop.place {
            return (place, stop.at, place.hasReservation(on: now, calendar: region.calendar))
        }
        let soon = now.addingTimeInterval(-3600)
        return places
            .compactMap { p in p.reservation.map { (p, $0.at) } }
            .filter { region.calendar.isDate($0.1, inSameDayAs: now) && $0.1 >= soon && !$0.0.isDone }
            .min { $0.1 < $1.1 }
            .map { ($0.0, $0.1, true) }
    }

    /// Lugares do board abertos agora a ≤ 1,5 km. Sem horário não conta.
    var openNearby: [Place] {
        guard let location else { return [] }
        return places.filter { place in
            !place.isDone
                && place.openState(at: now, timeZone: region.timeZone).isOpen
                && place.location.distance(from: location) <= Self.nearbyRadius
        }
    }

    var nearbyLine: String {
        let time = region.timeString(now)
        guard let location else { return "sem GPS · \(time)" }
        let nearest = places.filter { $0.area != nil }.min { $0.location.distance(from: location) < $1.location.distance(from: location) }
        let area = nearest.flatMap { $0.location.distance(from: location) < 3000 ? $0.area : nil }
            ?? trip?.city(on: now, calendar: region.calendar)?.name ?? region.displayName
        return [area, time, nowTemp.map { "\(Int($0.rounded()))°" }].compactMap { $0 }.joined(separator: " · ")
    }

    var tomorrowLine: String {
        let cal = region.calendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        var style = Date.FormatStyle(locale: region.locale, calendar: cal).weekday(.wide)
        style.timeZone = region.timeZone
        let weekday = tomorrow.formatted(style)
        let reservations = places.filter { $0.hasReservation(on: tomorrow, calendar: cal) }.count
        let reserved = reservations == 0 ? "nada reservado" : reservations == 1 ? "1 reserva" : "\(reservations) reservas"
        // Dia de fotografia amanhã: a hora do golden no lugar das reservas.
        let start = cal.startOfDay(for: tomorrow)
        if days.contains(where: { $0.date == start && $0.kind == .photo }) {
            let city = trip?.city(on: tomorrow, calendar: cal)
            let c = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude, longitude: city?.lng ?? region.defaultCenter.longitude)
            if let g = SunService.day(start.addingTimeInterval(12 * 3600), c, timeZone: region.timeZone).goldenPM {
                return [weekday, tomorrowWeather?.short, "golden \(region.timeString(g.start))"].compactMap { $0 }.joined(separator: " · ")
            }
        }
        return [weekday, tomorrowWeather?.short, reserved].compactMap { $0 }.joined(separator: " · ")
    }
}
