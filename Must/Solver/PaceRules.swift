import Foundation

// Ritmo do dia v8 (prompt 23 §3) e a âncora de domingo na Appia (prompt 24 §2), como extensões puras do solver.

extension Pace {
    /// Paradas do board (âncoras + Musts) que o solver procura nesse ritmo. O resto até o ritmo são micro-paradas.
    var boardStops: Int {
        switch self {
        case .calm: 4
        case .normal: 5
        case .intense: 8
        }
    }

    /// Quantas micro-paradas o dia tenta encaixar (só nos buracos que já existem).
    var microStops: ClosedRange<Int> {
        switch self {
        case .calm: 1...2
        case .normal: 3...4
        case .intense: 4...4
        }
    }
}

extension DaySolver {
    /// Plano do tipo de dia ajustado ao ritmo: teto de paradas do board e, se faltar vaga, vagas extras opcionais com
    /// os mesmos papéis que o tipo de dia já usa naquela janela (o dia de templos continua de templos).
    static func paced(_ plan: Plan, pace: Pace, kind: DayKind) -> Plan {
        var plan = plan
        let target = kind == .rest ? min(pace.boardStops, plan.maxStops) : pace.boardStops
        plan.maxStops = target
        func freeSlots() -> Int { plan.slots.filter { $0.timing != .sport }.count }
        // Uma vaga sobrando: nem toda vaga acha lugar.
        let wanted = target + 1
        guard freeSlots() < wanted else { return plan }
        var extras: [Slot] = []
        for window in [DayWindow.morning, .afternoon, .night, .afternoon, .morning] {
            var roles: [StopRole] = []
            for role in plan.slots.filter({ $0.window == window && $0.timing == nil }).flatMap(\.roles)
            where role != .eat && role != .sport && !plan.excluded.contains(role) && !roles.contains(role) {
                roles.append(role)
            }
            if !roles.isEmpty { extras.append(Slot(window: window, roles: roles, optional: true)) }
        }
        for slot in extras where freeSlots() < wanted { plan.slots.append(slot) }
        return plan
    }

    /// Roma, domingo: a Via Appia fecha pra carros e vira âncora de manhã (09:30, 2 h 30), se não bater com outra âncora.
    static func sundayAppia(_ catalog: [SolverPlace], anchors: [ProposedStop], ctx: Context) -> ProposedStop? {
        let req = ctx.request
        guard ctx.italy, req.weekday == 0 else { return nil }
        let taken = Set(anchors.map(\.place.id))
        let options = catalog
            .filter { !$0.done && req.isInCity($0.cityId) && ItalyRules.isAppia($0) && !ctx.mustExclude.contains($0.id) && !taken.contains($0.id) }
            .filter { ctx.mode($0) != .off }
            .sorted { ($0.kind == .experience ? 1 : 0, $0.id) < ($1.kind == .experience ? 1 : 0, $1.id) }
        guard let p = options.first else { return nil }
        let start = max(ItalyRules.appiaStart, ctx.minute(req.startAt))
        guard start < 12 * 60 else { return nil }
        let end = start + max(ItalyRules.appiaMinutes, duration(p))
        if let limit = ctx.flightDeadlineMinute, end > limit { return nil }
        guard !anchors.contains(where: { ctx.minute($0.at) < end && start < ctx.minute($0.end) }) else { return nil }
        return ProposedStop(place: p, at: ctx.date(start), end: ctx.date(end), window: .morning, reason: "domingo sem carros",
                            isAnchor: true, isException: false, legFromPrevious: nil)
    }
}
