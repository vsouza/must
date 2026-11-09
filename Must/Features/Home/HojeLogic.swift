import Foundation

/// Lógica pura de Hoje (V9, prompt 32 §2): o cartão da próxima parada, o bairro da parada pro contexto e o cartão
/// Bom dia / Boa noite. Tudo lê o **mesmo** `DayClock` que a faixa "agora", a Linha e o Agora, então o "saia às" é um só.
struct HojeNext: Equatable, Sendable {
    enum Phase: Sendable { case now, next }
    var phase: Phase
    var stopId: String
    var placeId: String?
    /// "Fuunji" (sem a legenda depois do "·").
    var name: String
    /// Início da parada que o cartão mostra.
    var startsAt: Date
    /// O "saia às" do relógio (`DayClock.actionTime`): o mesmo número da faixa "agora".
    var actionAt: Date
    /// "saia" / "chegue".
    var verb: String
    /// Minutos do trecho que leva à parada seguinte; `nil` sem trecho.
    var legMinutes: Int?
    var legMode: DayLegMode?
    var thenName: String?
    /// Quando o relógio foi lido (pra "saia agora" depois da hora).
    var readAt: Date = .distantPast
}

enum HojeLogic {
    /// O cartão. `nil` sem dia ou com o dia concluído.
    static func next(clock: DayClock) -> HojeNext? {
        guard let plan = clock.active ?? clock.plan, let action = clock.actionTime else { return nil }
        switch clock.phase {
        case .noPlan, .finished: return nil
        case .running:
            guard let now = clock.now else { return nil }
            let target = now.next
            let leg = target.flatMap { plan.leg(before: $0) }
            return HojeNext(phase: .now, stopId: now.current.id, placeId: now.current.placeId, name: DayText.head(now.current.label),
                            startsAt: now.current.start, actionAt: action, verb: clock.actionVerb,
                            legMinutes: leg?.minutes, legMode: leg?.mode, thenName: target.map { DayText.head($0.label) },
                            readAt: clock.at)
        case .before:
            guard let up = clock.upcoming else { return nil }
            let leg = plan.leg(before: up.stop)
            let after = plan.stops.drop { $0.id != up.stop.id }.dropFirst().first
            return HojeNext(phase: .next, stopId: up.stop.id, placeId: up.stop.placeId, name: DayText.head(up.stop.label),
                            startsAt: up.stop.start, actionAt: action, verb: "saia",
                            legMinutes: leg?.minutes, legMode: leg?.mode, thenName: after.map { DayText.head($0.label) },
                            readAt: clock.at)
        }
    }

    /// "Próxima: Fuunji · 12:10 · saia às 11:55 · a pé 6 min" (antes da primeira) ou "Agora: Gyoen · saia às 15:10 · a pé 6 min".
    static func line(_ n: HojeNext, region: Region) -> String {
        var parts: [String]
        switch n.phase {
        case .next: parts = ["Próxima: \(n.name)", region.timeString(n.startsAt), action(n, region: region)]
        case .now: parts = ["Agora: \(n.name)", action(n, region: region)]
        }
        if let m = n.legMinutes, m > 0 { parts.append(legText(m, mode: n.legMode)) }
        return parts.joined(separator: " · ")
    }

    /// A mesma linha sem o nome (o cartão já tem o nome em título): "12:10 · saia às 11:55 · a pé 6 min".
    static func detail(_ n: HojeNext, region: Region) -> String {
        var parts = n.phase == .next ? [region.timeString(n.startsAt)] : []
        parts.append(action(n, region: region))
        if let m = n.legMinutes, m > 0 { parts.append(legText(m, mode: n.legMode)) }
        return parts.joined(separator: " · ")
    }

    static func action(_ n: HojeNext, region: Region) -> String {
        DayClock.actionText(verb: n.verb, at: n.actionAt, now: n.readAt, region: region)
    }

    static func legText(_ minutes: Int, mode: DayLegMode?) -> String {
        guard let mode, mode != .walk else { return "a pé \(minutes) min" }
        return "\(minutes) min de trem"
    }

    /// As próximas paradas de verdade (sem micro-parada), depois da do cartão.
    static func following(clock: DayClock, after stopId: String?, limit: Int = 3) -> [DayStop] {
        guard let stops = clock.active?.stops else { return [] }
        var tail = stops
        if let stopId, let i = stops.firstIndex(where: { $0.id == stopId }) { tail = Array(stops[(i + 1)...]) }
        return Array(tail.filter { $0.kind != .micro }.prefix(limit))
    }

    /// Bairro da parada corrente ou, antes da primeira, da próxima (alimenta `TodayContextModel.update`).
    static func dayStopAreaId(clock: DayClock) -> String? {
        switch clock.phase {
        case .running: clock.now?.current.area
        case .before: clock.upcoming?.stop.area
        default: nil
        }
    }

    // MARK: Bom dia / Boa noite

    enum Greeting: String, Sendable {
        case bomDia, boaNoite
    }

    /// Das 4h às 10h = Bom dia; das 21h às 4h = Boa noite. No fuso da região (o `calendar` dela).
    static func greeting(now: Date, calendar: Calendar) -> Greeting? {
        let hour = calendar.component(.hour, from: now)
        if (4..<10).contains(hour) { return .bomDia }
        if hour >= 21 || hour < 4 { return .boaNoite }
        return nil
    }

    /// O cartão aparece se está no horário e não foi dispensado "até amanhã".
    static func greetingCard(now: Date, calendar: Calendar, dismissedKey: String?) -> Greeting? {
        guard let g = greeting(now: now, calendar: calendar) else { return nil }
        return dismissedKey == dismissKey(g, now: now, calendar: calendar) ? nil : g
    }

    /// A madrugada (0–4h) ainda é a noite do dia anterior.
    static func dismissKey(_ g: Greeting, now: Date, calendar: Calendar) -> String {
        var day = now
        if g == .boaNoite, calendar.component(.hour, from: now) < 4 { day = calendar.date(byAdding: .day, value: -1, to: now) ?? now }
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(g.rawValue)-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
}

/// Lembra a dispensa do cartão (uma chave por viagem).
struct GreetingDismissStore {
    var tripId: String
    var defaults: UserDefaults = .standard
    private var key: String { "hoje.greeting.dismissed.\(tripId)" }
    var value: String? { defaults.string(forKey: key) }
    func dismiss(_ k: String) { defaults.set(k, forKey: key) }
}
