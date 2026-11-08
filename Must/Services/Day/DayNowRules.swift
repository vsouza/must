import Foundation

/// Contas do "Agora" (prompt 23 §3), puras e iguais pro stub e pro motor real:
/// - a parada de agora é a primeira (não feita) cuja hora de saída ainda não passou;
/// - hora de saída de uma parada = hora de sair pra próxima = início da próxima − deslocamento − 5 min;
/// - próxima com fila e sem reserva: sai pra chegar na abertura ("chegue às"), ou 20 min antes se não há horário.
enum DayNowRules {
    /// Margem padrão do "saia às" (a mesma do `RoutesService.leaveAt`).
    static let margin = 5
    /// Fila sem horário de abertura: chegar 20 min antes.
    static let queueMargin = 20

    /// "Chegue às" de uma parada: abertura (até 3 h antes da hora marcada) ou início − 20 min. `nil` = vale a hora marcada
    /// (reserva, ingresso, micro-parada, lugar sem fila).
    static func arriveBy(_ stop: DayStop) -> Date? {
        guard stop.kind != .micro, !stop.isBooked, (stop.queueMinutes ?? 0) > 0 else { return nil }
        if let open = stop.opensAt, open <= stop.start, stop.start.timeIntervalSince(open) <= 3 * 3600 { return open }
        return stop.start.addingTimeInterval(-Double(queueMargin) * 60)
    }

    /// Hora de sair pra chegar em `stop`: (chegue às ou início) − deslocamento da perna que chega nela − margem.
    static func leaveTime(to stop: DayStop, in plan: DayPlan) -> Date {
        let travel = plan.leg(before: stop)?.minutes ?? 0
        return (arriveBy(stop) ?? stop.start).addingTimeInterval(-Double(travel + margin) * 60)
    }

    /// Hora de sair de `stops[index]`: a de ir pra próxima (nunca antes de a parada começar); a última sai no fim.
    static func departure(from index: Int, in plan: DayPlan) -> Date {
        let stops = plan.stops
        let stop = stops[index]
        guard index + 1 < stops.count else { return stop.end }
        return max(stop.start, leaveTime(to: stops[index + 1], in: plan))
    }

    /// "Agora" em `date`. `nil` antes da primeira parada começar e depois da última sair (ou com tudo feito).
    /// `dayStarted`: o dia já começou (a primeira parada do dia inteiro, feita ou não, já passou). Sem ele, vale a primeira
    /// parada de `plan`; o `DayClock` passa o do dia inteiro, pra quem já fez as primeiras não voltar a ver "o dia começa às…".
    static func now(in plan: DayPlan, at date: Date, dayStarted: Bool? = nil) -> DayNow? {
        let stops = plan.stops
        guard let first = stops.first, dayStarted ?? (date >= first.start) else { return nil }
        guard let index = stops.indices.first(where: { !stops[$0].done && departure(from: $0, in: plan) > date }) else { return nil }
        let next = index + 1 < stops.count ? stops[index + 1] : nil
        return DayNow(current: stops[index], leaveAt: departure(from: index, in: plan), next: next, arriveBy: next.flatMap(arriveBy))
    }

    /// A parada pra onde se vai agora (Live Activity, aviso "saia em 5 min"): a de agora se ainda não começou, senão a
    /// próxima; antes do dia, a primeira. Com a hora de sair pra ela.
    static func heading(in plan: DayPlan, at date: Date) -> (stop: DayStop, index: Int, leaveAt: Date)? {
        let stops = plan.stops
        guard let first = stops.first else { return nil }
        if date < first.start {
            guard let i = stops.firstIndex(where: { !$0.done }) else { return nil }
            return (stops[i], i, leaveTime(to: stops[i], in: plan))
        }
        guard let now = now(in: plan, at: date), let index = stops.firstIndex(of: now.current) else { return nil }
        if date < now.current.start { return (now.current, index, leaveTime(to: now.current, in: plan)) }
        guard let next = now.next else { return nil }
        return (next, index + 1, now.leaveAt)
    }
}
