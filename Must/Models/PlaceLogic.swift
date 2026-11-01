import CoreLocation
import Foundation
import SwiftData

// Lógica pura sobre lugares: horário (cache do Places), cidade do dia, distância, gasto do dia.

// MARK: - Horários

extension PlaceHours {
    static let weekdayShort = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
    private static let week = 7 * 1440

    /// (dia 0–6, minutos desde a meia-noite) de `date` no fuso.
    static func weekMinute(_ date: Date, in timeZone: TimeZone) -> (day: Int, minute: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        return ((c.weekday ?? 1) - 1, (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private static func index(_ p: Point) -> Int { p.day * 1440 + p.hour * 60 + p.minute }

    /// Intervalos [abre, fecha) em minutos da semana; fechamento depois da meia-noite atravessa o dia.
    private var intervals: [(open: Int, close: Int, period: Period)] {
        (periods ?? []).map { period in
            let o = Self.index(period.open)
            guard let close = period.close else { return (o, o + Self.week, period) } // 24 h
            var c = Self.index(close)
            if c <= o { c += Self.week }
            return (o, c, period)
        }
    }

    var hasPeriods: Bool { !(periods ?? []).isEmpty }

    /// Aberto em `date`? `nil` quando não há horário.
    func isOpen(at date: Date, timeZone: TimeZone) -> Bool? {
        guard hasPeriods else { return nil }
        return currentInterval(at: date, timeZone: timeZone) != nil
    }

    private func currentInterval(at date: Date, timeZone: TimeZone) -> (open: Int, close: Int, period: Period)? {
        let (day, minute) = Self.weekMinute(date, in: timeZone)
        let t = day * 1440 + minute
        return intervals.first { ($0.open..<$0.close).contains(t) || ($0.open..<$0.close).contains(t + Self.week) }
    }

    /// "21:00" — quando fecha, se estiver aberto (nil pra 24 h).
    func closesAt(_ date: Date, timeZone: TimeZone) -> String? {
        guard let interval = currentInterval(at: date, timeZone: timeZone), let close = interval.period.close else { return nil }
        return Self.hhmm(close)
    }

    /// Próxima abertura depois de `date`: ("hoje"|"seg", "18:00").
    func nextOpening(after date: Date, timeZone: TimeZone) -> (day: String?, time: String)? {
        guard hasPeriods else { return nil }
        let (day, minute) = Self.weekMinute(date, in: timeZone)
        let t = day * 1440 + minute
        let next = intervals.map { interval -> (delta: Int, open: Point) in
            var delta = interval.open - t
            while delta <= 0 { delta += Self.week }
            return (delta, interval.period.open)
        }.min { $0.delta < $1.delta }
        guard let next else { return nil }
        let sameDay = next.open.day == day && next.delta < 1440
        return (sameDay ? nil : Self.weekdayShort[next.open.day], Self.hhmm(next.open))
    }

    /// "18:00–23:00" (períodos que abrem no dia de `date`).
    func todayText(_ date: Date, timeZone: TimeZone) -> String? {
        let day = Self.weekMinute(date, in: timeZone).day
        let today = (periods ?? []).filter { $0.open.day == day }
        guard !today.isEmpty else { return hasPeriods ? "fechado hoje" : nil }
        return today.map { p in
            guard let close = p.close else { return "24 h" }
            return "\(Self.hhmm(p.open))–\(Self.hhmm(close))"
        }.joined(separator: ", ")
    }

    /// Dias sem nenhuma abertura: ["dom"].
    var closedDays: [String] {
        guard hasPeriods else { return [] }
        let openDays = Set((periods ?? []).map(\.open.day))
        return (0..<7).filter { !openDays.contains($0) }.map { Self.weekdayShort[$0] }
    }

    static func hhmm(_ p: Point) -> String { String(format: "%02d:%02d", p.hour % 24, p.minute) }
}

/// Situação de horário de um lugar agora.
enum OpenState: Equatable {
    case open(until: String?)
    case closed(opensDay: String?, opensAt: String?)
    case unknown

    var isOpen: Bool { if case .open = self { true } else { false } }
}

extension Place {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lng) }

    func openState(at date: Date, timeZone: TimeZone) -> OpenState {
        guard let hours, let open = hours.isOpen(at: date, timeZone: timeZone) else { return .unknown }
        if open { return .open(until: hours.closesAt(date, timeZone: timeZone)) }
        let next = hours.nextOpening(after: date, timeZone: timeZone)
        return .closed(opensDay: next?.day, opensAt: next?.time)
    }

    /// Reserva no mesmo dia de `date` (fuso da região).
    func hasReservation(on date: Date, calendar: Calendar) -> Bool {
        guard let at = reservation?.at else { return false }
        return calendar.isDate(at, inSameDayAs: date)
    }

    func distance(from location: CLLocation?) -> CLLocationDistance? {
        location.map { self.location.distance(from: $0) }
    }

    /// "Sushi Dai" + "寿司大" → busca simples sem acento.
    func matches(_ query: String) -> Bool {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        let haystack = [name, nameLocal ?? "", area ?? "", sub ?? "", list?.name ?? "", notes]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return haystack.contains(q)
    }
}

// MARK: - Distância e caminhada

enum Walk {
    /// ~5 km/h na calçada.
    static let metersPerMinute: Double = 80

    static func minutes(_ meters: CLLocationDistance) -> Int { max(1, Int((meters / metersPerMinute).rounded(.up))) }

    /// "350 m" / "1,2 km"
    static func distanceText(_ meters: CLLocationDistance) -> String {
        if meters < 25 { return "aqui" }
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return "\((meters / 1000).formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(1)))) km"
    }

    /// "4 min" a pé até 2 km, senão a distância.
    static func shortText(_ meters: CLLocationDistance) -> String {
        meters <= 2000 ? "\(minutes(meters)) min" : distanceText(meters)
    }
}

// MARK: - Cidade do dia

extension TripInfo {
    /// Cidade em que se está em `date`: trecho que contém o dia (no dia de troca, a cidade nova);
    /// antes da viagem, a primeira; depois, a última; sem datas (BH), a cidade de casa.
    func city(on date: Date, calendar: Calendar) -> City? {
        let day = calendar.startOfDay(for: date)
        let dated = cities.filter { $0.from != nil && $0.to != nil }
        guard !dated.isEmpty else { return cities.first }
        if let city = dated.last(where: { $0.from! <= day && day <= $0.to! }) { return city }
        if let first = dated.first, day < first.from! { return first }
        return dated.last
    }

    /// Nome legível ("Tóquio 13–17" quando o nome se repete).
    func label(for city: City, region: Region) -> String {
        let repeated = cities.filter { $0.name == city.name }.count > 1
        guard repeated, let from = city.from, let to = city.to else { return city.name }
        return "\(city.name) \(region.dayNumber(from))–\(region.dayNumber(to))"
    }
}

// MARK: - Gastos e 済

extension Region {
    /// [meia-noite, meia-noite seguinte) de `date`.
    func dayRange(_ date: Date) -> Range<Date> {
        let start = calendar.startOfDay(for: date)
        return start..<(calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400))
    }
}

@MainActor
enum PlaceActions {
    /// Marca 済 e registra o gasto (pode ser 0).
    static func markDone(_ place: Place, spent: Double, category: ExpenseCategory? = nil, method: PaymentMethod = .card,
                         at date: Date = AppClock.now, context: ModelContext) {
        place.done = DoneMark(at: date, spent: spent)
        if spent > 0 {
            context.insert(Expense(at: date, amount: spent, category: category ?? place.defaultCategory, place: place, method: method))
        }
        try? context.save()
        Log.data.info("済 \(place.id, privacy: .public) · \(spent)")
    }

    static func undoDone(_ place: Place, context: ModelContext) {
        if let mark = place.done {
            for e in place.expenses where abs(e.at.timeIntervalSince(mark.at)) < 1 { context.delete(e) }
        }
        place.done = nil
        try? context.save()
    }
}

extension Place {
    var defaultCategory: ExpenseCategory {
        switch list?.color {
        case .eat: .food
        case .drink, .coffee: sub?.lowercased().contains("café") == true || list?.color == .coffee ? .coffee : .food
        case .shop: .shop
        case .see, .temple: .ticket
        default: .other
        }
    }

    /// Rótulo curto à direita do preço (janela principal).
    var priceLabel: String? { windows.first?.label }
}
