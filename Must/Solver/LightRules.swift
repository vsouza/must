import CoreLocation
import Foundation

// Regras dos tipos novos (prompt 13): luz pra photo, temporada pra art, conforto pra sport.

/// Nota de uma hora pra esporte ao ar livre: 0 = ótimo … 4 = evitar.
enum SportScore {
    /// `score(hour) = f(temp ≤ max, UV ≤ max, chuva < 30%, AQI < 100)`.
    static func penalty(_ h: HourWeather, spot: SportSpot) -> Double {
        let tMax = Double(spot.tempMax), uvMax = Double(spot.uvMax)
        let temp = h.apparent.map { max($0, h.temp) } ?? h.temp
        var p = max(0, temp - tMax) / 3
        if temp > tMax - 2 && temp <= tMax { p += 0.25 }
        if let uv = h.uv {
            p += max(0, uv - uvMax) / 2
            if uv > uvMax - 1 && uv <= uvMax { p += 0.25 }
        }
        if let rain = h.precipProb { p += max(0, Double(rain) - 25) / 30 }
        if let aqi = h.aqi { p += max(0, Double(aqi) - 90) / 50 }
        return p
    }

    static func level(_ h: HourWeather, spot: SportSpot) -> Int {
        let p = penalty(h, spot: spot)
        switch p {
        case ..<0.01: return 0
        case ..<0.5: return 1
        case ..<1: return 2
        case ..<2: return 3
        default: return 4
        }
    }

    /// Verde (0–1) = entra no dia.
    static func isGood(_ h: HourWeather, spot: SportSpot) -> Bool { level(h, spot: spot) <= 1 }

    /// "corra até as 9h" — última hora verde contínua a partir de `from`. `nil` se agora já não é verde.
    static func goodUntil(_ hours: [HourWeather], from: Date, spot: SportSpot) -> Date? {
        let ahead = hours.filter { $0.time.addingTimeInterval(3600) > from }.sorted { $0.time < $1.time }
        guard let first = ahead.first, isGood(first, spot: spot) else { return nil }
        var last = first
        for h in ahead.dropFirst() {
            guard isGood(h, spot: spot) else { break }
            last = h
        }
        return last.time.addingTimeInterval(3600)
    }

    /// Próxima hora verde depois de `from` (pra quando agora está quente).
    static func nextGood(_ hours: [HourWeather], after from: Date, spot: SportSpot) -> Date? {
        hours.filter { $0.time >= from }.sorted { $0.time < $1.time }.first { isGood($0, spot: spot) }?.time
    }
}

/// Frase do card Céu pro golden de hoje.
enum SkyVerdict {
    static func phrase(cloud: Int?, rain: Int?, golden: Bool) -> String {
        guard let cloud else { return "sem previsão de nuvens pra hoje" }
        let moment = golden ? "no pôr do sol" : "agora"
        if let rain, rain >= 50 { return "chuva provável \(moment) — melhor outro dia" }
        if cloud < 30 { return "céu limpo \(moment) — vale ir hoje" }
        if cloud <= 60 { return "nuvens soltas \(moment) — pode dar céu dramático" }
        return "nublado \(moment) (\(cloud)%) — melhor outro dia"
    }
}

extension DaySolver {
    /// Faixa de luz de um slot de horário fixo.
    enum Timing: Sendable, Hashable {
        case goldenAM, sunHigh, goldenPM, blue, sport

        var light: LightKind? {
            switch self {
            case .goldenAM: .goldenAM
            case .goldenPM: .goldenPM
            case .blue: .blue
            case .sunHigh: .hard
            case .sport: nil
            }
        }
    }

    /// Minutos desde a meia-noite da faixa, no dia do pedido.
    static func range(_ timing: Timing, sun: SunDay, ctx: Context) -> Range<Int>? {
        func r(_ i: DateInterval?) -> Range<Int>? {
            guard let i else { return nil }
            let a = ctx.minute(i.start), b = ctx.minute(i.end)
            return a < b ? a..<b : nil
        }
        switch timing {
        case .goldenAM: return r(sun.goldenAM)
        case .goldenPM: return r(sun.goldenPM)
        case .blue: return r(sun.bluePM)
        case .sunHigh: return (11 * 60)..<(15 * 60)
        case .sport: return 0..<(11 * 60)
        }
    }

    /// Minutos que a parada ocupa.
    static func duration(_ p: SolverPlace) -> Int {
        switch p.kind {
        case .art: p.extra?.art?.durationMinutes ?? 90
        case .photo: 45
        case .sport: (p.extra?.sport?.estimatedMinutes).map { $0 + 15 } ?? 60
        case .experience: p.extra?.experience?.durationMinutes ?? 120
        case .place: p.role.duration
        }
    }

    /// Fechamento do dia (minutos desde a meia-noite) pelo horário do Places.
    static func closingMinute(_ p: SolverPlace, ctx: Context) -> Int? {
        guard let periods = p.hours?.periods else { return nil }
        let wd = ctx.request.weekday
        let today = periods.filter { $0.open.day == wd }.compactMap { period -> Int? in
            guard let c = period.close else { return nil }
            return (c.day == wd ? 0 : 24 * 60) + c.hour * 60 + c.minute
        }
        return today.max()
    }

    /// Dias até o fim da temporada (art).
    static func daysLeft(_ p: SolverPlace, ctx: Context) -> Int? {
        p.extra?.art?.daysLeft(from: ctx.request.date, calendar: ctx.request.calendar)
    }

    /// "termina em 4 dias" / "termina hoje" / "termina amanhã".
    static func endsText(_ days: Int) -> String {
        switch days {
        case 0: "termina hoje"
        case 1: "termina amanhã"
        default: "termina em \(days) dias"
        }
    }

    /// Ingressos do dia viram âncoras: anexados ao lugar (`Place.tickets`) e sessões compradas
    /// (art, jogo, experiência). Um lugar com a mesma hora nos dois conta uma vez.
    static func ticketAnchors(_ catalog: [SolverPlace], ctx: Context) -> [ProposedStop] {
        let req = ctx.request
        var out: [ProposedStop] = []
        for p in catalog where !p.done && req.isInCity(p.cityId) && !ctx.mustExclude.contains(p.id) {
            var seen: Set<Int> = []
            var found: [(at: Date, reason: String)] = p.tickets
                .filter { req.calendar.isDate($0.at, inSameDayAs: req.date) }
                .map { (at: $0.at, reason: "ingresso") }
            found += (p.extra?.sessions ?? [])
                .filter { $0.bought && req.calendar.isDate($0.at, inSameDayAs: req.date) }
                .map { (at: $0.at, reason: "ingresso · \($0.title)") }
            for item in found.sorted(by: { $0.at < $1.at }) {
                let minute = ctx.minute(item.at)
                guard seen.insert(minute).inserted else { continue }
                let length = p.extra?.art?.durationMinutes ?? p.extra?.experience?.durationMinutes ?? (p.kind == .sport ? 150 : 120)
                out.append(ProposedStop(place: p, at: item.at, end: ctx.date(minute + length), window: window(at: minute, region: ctx.region),
                                        reason: item.reason, isAnchor: true, isException: false, legFromPrevious: nil))
            }
        }
        return out
    }
}
