import Foundation

/// Contas da tela Viagem (puras, testáveis). Em BH (sem viagem) vira "o mês".
struct TripStats {
    enum DayState: Equatable { case done, today, otherCity, future, past }

    struct DayCell: Identifiable, Equatable {
        var date: Date
        var number: Int
        var state: DayState
        var cityId: String?
        var id: Date { date }
    }

    /// Período da tela: a viagem, ou o mês corrente em BH.
    static func period(trip: TripInfo?, now: Date, calendar: Calendar) -> ClosedRange<Date> {
        if let start = trip?.start, let end = trip?.end, start <= end { return calendar.startOfDay(for: start)...calendar.startOfDay(for: end) }
        let comps = calendar.dateComponents([.year, .month], from: now)
        let first = calendar.date(from: comps) ?? calendar.startOfDay(for: now)
        let last = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: first) ?? first
        return first...last
    }

    static func days(in period: ClosedRange<Date>, trip: TripInfo?, now: Date, calendar: Calendar, doneDays: Set<Date>) -> [DayCell] {
        let today = calendar.startOfDay(for: now)
        let todayCity = trip?.city(on: now, calendar: calendar)
        var cells: [DayCell] = []
        var day = period.lowerBound
        while day <= period.upperBound {
            let city = trip?.city(on: day, calendar: calendar)
            let state: DayState
            if day == today { state = .today }
            else if doneDays.contains(day) { state = .done }
            else if day < today { state = .past }
            else if let city, let todayCity, city.name != todayCity.name { state = .otherCity }
            else { state = .future }
            cells.append(DayCell(date: day, number: calendar.component(.day, from: day), state: state, cityId: city?.id))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return cells
    }

    /// Dias com algo feito (parada 済 ou lugar 済 naquele dia).
    static func doneDays(places: [Place], days: [PlannedDay], calendar: Calendar) -> Set<Date> {
        var set = Set(places.compactMap { $0.done.map { calendar.startOfDay(for: $0.at) } })
        for d in days where d.stops.contains(where: \.done) { set.insert(calendar.startOfDay(for: d.date)) }
        return set
    }

    static func spent(_ expenses: [Expense], in period: ClosedRange<Date>, calendar: Calendar) -> Double {
        let end = calendar.date(byAdding: .day, value: 1, to: period.upperBound) ?? period.upperBound
        return expenses.filter { $0.at >= period.lowerBound && $0.at < end }.reduce(0) { $0 + $1.amount }
    }

    /// Dias já vividos no período (pra média), mínimo 1.
    static func elapsedDays(_ period: ClosedRange<Date>, now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        guard today >= period.lowerBound else { return 1 }
        let until = min(today, period.upperBound)
        return max(1, (calendar.dateComponents([.day], from: period.lowerBound, to: until).day ?? 0) + 1)
    }

    /// "Eat 11/23"
    static func progress(lists: [MustList]) -> [(list: MustList, done: Int, total: Int)] {
        lists.map { ($0, $0.places.filter(\.isDone).count, $0.places.count) }
    }
}
