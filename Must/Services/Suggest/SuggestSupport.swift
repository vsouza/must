import Foundation

/// "Não me sugere isso hoje" e "já sugerido hoje" (prompt 26 §2/§4). UserDefaults por região e dia; some sozinho no dia seguinte.
struct SuggestPrefs {
    var defaults: UserDefaults = .standard

    private func key(_ name: String, region: Region, now: Date) -> String {
        "suggest.\(name).\(region.rawValue).\(BoardDates(timeZone: region.timeZone).dayString(now))"
    }

    func dismissed(region: Region, now: Date) -> Set<String> {
        Set(defaults.stringArray(forKey: key("dismissed", region: region, now: now)) ?? [])
    }

    func dismiss(_ id: String, region: Region, now: Date) {
        var set = dismissed(region: region, now: now)
        set.insert(id)
        defaults.set(Array(set), forKey: key("dismissed", region: region, now: now))
    }

    /// id → quando foi mostrado pela primeira vez hoje (epoch).
    func shown(region: Region, now: Date) -> [String: Double] {
        defaults.dictionary(forKey: key("shown", region: region, now: now)) as? [String: Double] ?? [:]
    }

    /// Registra o que está na tela (só a primeira vez de cada id).
    func markShown(_ ids: [String], region: Region, now: Date) {
        var map = shown(region: region, now: now)
        var changed = false
        for id in ids where map[id] == nil { map[id] = now.timeIntervalSince1970; changed = true }
        if changed { defaults.set(map, forKey: key("shown", region: region, now: now)) }
    }

    /// Mostrado há mais de 1 h: entra na conta como repetição (−2).
    func shownEarlier(region: Region, now: Date) -> Set<String> {
        Set(shown(region: region, now: now).filter { now.timeIntervalSince1970 - $0.value > 3600 }.keys)
    }
}

/// A linha de estado da capa e o card "Noite, pra onde?" (prompt 26 §1).
enum SuggestCopy {
    /// "18:10 · nada marcado · 2 abertos a 10 min" / "14:20 · agora: Fuunji · saia 14:35" /
    /// "14:20 · Atrasou? Ajustei: faltam 5 paradas" / "16:10 · agora: Gyoen · a 18 min daqui · saia 16:29".
    /// O número de "abertos a 10 min" é o mesmo do numeral da capa; o que não tem horário confirmado vai à parte.
    static func stateLine(region: Region, now: Date, plan: SuggestPlanStop?, openNearby: Int, unconfirmed: Int = 0,
                          adjustedRemaining: Int? = nil, awayMinutes: Int? = nil, problem: DayProblem? = nil) -> String {
        let time = region.timeString(now)
        // Chegada, troca de cidade e último dia mandam na linha principal.
        if let problem { return "\(time) · \(problem.headline)" }
        guard let plan else {
            var parts = [time, "nada marcado"]
            if openNearby > 0 { parts.append("\(openNearby) \(openNearby == 1 ? "aberto" : "abertos") a 10 min") }
            if unconfirmed > 0 { parts.append("\(unconfirmed) sem horário confirmado") }
            return parts.joined(separator: " · ")
        }
        if let left = adjustedRemaining {
            return "\(time) · Atrasou? Ajustei: \(left == 1 ? "falta 1 parada" : "faltam \(left) paradas")"
        }
        let away = awayMinutes.map { "a \($0) min daqui" }
        return [time, "agora: \(plan.label)", away ?? "", plan.action].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    struct Night: Equatable, Sendable {
        var title: String
        var line: String
    }

    /// Some depois das 22:30 (não cabe mais um dia).
    static func night(region: Region, now: Date, areas: [String]) -> Night? {
        let c = region.calendar.dateComponents([.hour, .minute], from: now)
        let t = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        guard t >= 5 * 60, t < 22 * 60 + 30 else { return nil }
        let places = areas.prefix(2).joined(separator: " e ")
        let tail = places.isEmpty ? "" : " · \(places)"
        if t >= 18 * 60 { return Night(title: "Noite, pra onde?", line: "Montar a noite\(tail)") }
        return Night(title: "Hoje, pra onde?", line: "Montar o resto do dia\(tail)")
    }

    /// Rodapé: "FONTES: board · Places · Bandsintown · previsão · sol".
    static func sources(_ cards: [Suggestion], eventSourceName: (String) -> String?) -> [String] {
        var out: [String] = []
        func add(_ s: String) { if !out.contains(s) { out.append(s) } }
        for card in cards {
            if card.placeId != nil { add("board") }
            if card.kind == .must || card.kind == .closing, card.label.contains("ABERTO") { add("Places") }
            if card.kind == .event, let id = card.eventId, let name = eventSourceName(id) { add(name) }
            if card.kind == .light { add("sol") }
            if card.reasons.contains(where: { $0.hasPrefix("chuva") }) || card.kind == .light { add("previsão") }
            if card.kind == .indicated { add("indicados") }
        }
        return out
    }
}
