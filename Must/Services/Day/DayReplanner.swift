import CoreLocation
import Foundation

/// Plano vivo (relatório do viajante, problema 2): passou da hora de uma parada sem "feito" → o resto do dia se refaz
/// sozinho a partir de agora e da posição. Puro e determinístico (mesma entrada → mesmo dia); sem rede, sem SwiftData.
///
/// - Âncoras (reserva, ingresso, golden, trem) nunca se mexem.
/// - A parada que já está rolando fica como está.
/// - Musts e micro-paradas que ainda vêm andam pra frente só o necessário (deslocamento + 5 min de margem, grade de 5 min).
/// - O que passou da hora sem "feito", e o que não cabe mais antes da próxima âncora (ou depois das 22:30), sai da conta
///   ("ficou pra depois"): continua no `plan.stops`, mas fora do relógio. Nunca é apagado e nunca vira culpa.
enum DayReplanner {
    struct Result: Sendable {
        /// O dia inteiro (feitos, os que ficaram pra depois e o resto já reposicionado).
        var plan: DayPlan
        /// Ficaram pra depois: passaram da hora sem "feito" ou não cabem mais.
        var skipped: [DayStop]
        /// Quais mudaram de hora.
        var shifted: [String]
        /// Por que cada um saiu (id da parada → motivo).
        var reasons: [String: SkipReason] = [:]
    }

    /// Por que uma parada ficou pra depois. Nunca é culpa: é conta de tempo.
    enum SkipReason: Equatable, Sendable {
        /// Passou da hora sem "feito".
        case passed
        /// Não cabe mais antes de uma âncora (id da âncora).
        case beforeAnchor(String)
        /// Empurrada, passaria do fim do dia.
        case tooLate
    }

    /// Margem do "saia às" (a mesma do relógio).
    static let margin = DayNowRules.margin

    /// `plan` já com os feitos aplicados (`done`). `nil` = nada a ajustar (ninguém passou da hora, ou o dia acabou).
    static func replan(_ plan: DayPlan, at now: Date, region: Region, position: CLLocationCoordinate2D? = nil,
                       walkMaxKm: Double = 1.5) -> Result? {
        let stops = plan.stops
        guard let first = stops.first, now >= first.start else { return nil }
        // A parada de agora: a primeira que falta e ainda não passou da hora de sair (o mesmo critério do relógio).
        guard let current = stops.indices.first(where: { !stops[$0].done && DayNowRules.departure(from: $0, in: plan) > now }) else { return nil }
        let overdue = stops.indices.filter { $0 < current && !stops[$0].done }
        // A parada de agora que já devia ter acabado (e ninguém marcou): conta como atraso, ela anda pra agora.
        let lateCurrent = stops[current].kind != .anchor && stops[current].end < now
        guard !overdue.isEmpty || lateCurrent else { return nil }

        let day = region.calendar.startOfDay(for: plan.date)
        let latest = day.addingTimeInterval(Double(DayFit.latestEnd.hour * 60 + DayFit.latestEnd.minute) * 60)
        func fixed(_ k: Int) -> Bool {
            let s = stops[k]
            return s.kind == .anchor || (k == current && s.start <= now)
        }
        func travel(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Int {
            DayComposer.minutes(a, b, walkMaxKm: walkMaxKm, travel: nil)
        }
        // Onde você está: o GPS, senão a última parada que ficou pra trás (feita ou não).
        let origin = position ?? stops[..<current].reversed().lazy.compactMap(DayComposer.coordinate).first

        var out: [DayStop] = []
        var skippedIds = Set(overdue.map { stops[$0].id })
        var reasons = Dictionary(uniqueKeysWithValues: overdue.map { (stops[$0].id, SkipReason.passed) })
        var shifted: [String] = []
        var prevEnd = now
        var prevCoord = origin
        for k in current..<stops.count {
            var s = stops[k]
            if s.done { continue }
            let coord = DayComposer.coordinate(s)
            if k == current, lateCurrent {
                let length = s.end.timeIntervalSince(s.start)
                s.start = MicroStops.roundDown(now, day: day)
                s.end = s.start.addingTimeInterval(length)
                shifted.append(s.id)
                out.append(s)
                prevEnd = s.end
                prevCoord = coord ?? prevCoord
                continue
            }
            if fixed(k) {
                out.append(s)
                prevEnd = max(s.end, now)
                prevCoord = coord ?? prevCoord
                continue
            }
            let original = s.start
            let earliest = MicroStops.roundUp(prevEnd.addingTimeInterval(Double(travel(prevCoord, coord) + margin) * 60), day: day)
            if s.start < earliest {
                let length = s.end.timeIntervalSince(s.start)
                s.start = earliest
                s.end = earliest.addingTimeInterval(length)
                if s.opensAt.map({ $0 > s.start }) == true { s.opensAt = nil }
            }
            // Cabe antes da próxima âncora (com o deslocamento até ela) e antes do fim do dia?
            let nextFixed = (k + 1..<stops.count).first { !stops[$0].done && fixed($0) }
            // O fim do dia (22:30) só manda em quem foi empurrado: o que já estava marcado pra depois disso fica.
            var fits = s.start == original || s.end <= latest
            if let nf = nextFixed {
                let gap = travel(coord ?? prevCoord, DayComposer.coordinate(stops[nf]))
                fits = fits && s.end.addingTimeInterval(Double(gap + margin) * 60) <= stops[nf].start
            }
            guard fits else {
                skippedIds.insert(s.id)
                if let nf = nextFixed, s.end <= latest || s.start == original { reasons[s.id] = .beforeAnchor(stops[nf].id) } else { reasons[s.id] = .tooLate }
                continue
            }
            if s.start != stops[k].start { shifted.append(s.id) }
            out.append(s)
            prevEnd = s.end
            prevCoord = coord ?? prevCoord
        }

        // O dia: tudo antes da parada de agora fica como está (feitos e os que passaram), o resto vem do reflow.
        let byId = Dictionary(out.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var newStops = stops.map { byId[$0.id] ?? $0 }
        newStops.sort { ($0.start, $0.id) < ($1.start, $1.id) }
        var result = plan
        result.stops = newStops
        // Pernas refeitas entre as paradas que continuam; as que já valiam (e as de quem ficou pra trás) ficam.
        let active = newStops.filter { !$0.done && !skippedIds.contains($0.id) }
        let fresh = DayComposer.legs(for: active, region: region, walkMaxKm: walkMaxKm, travel: nil, areas: AreaCatalog.areas(for: region))
        var legs = plan.legs.filter { leg in !fresh.contains { $0.from == leg.from && $0.to == leg.to } }
        legs += fresh.map { leg in plan.legs.first { $0.from == leg.from && $0.to == leg.to && $0.minutes == leg.minutes } ?? leg }
        result.legs = legs
        let skipped = newStops.filter { skippedIds.contains($0.id) }
        return Result(plan: result, skipped: skipped, shifted: shifted, reasons: reasons)
    }
}
