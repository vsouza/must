import Foundation

/// "Ajustar" em Hoje (relatório do viajante, problema 2): o que o replano tirou ou mexeu, dito sem culpa.
/// "Tirei Fuunji pra caber a reserva das 19:00." Puro; lê só o `DayClock`.
struct ReplanSummary: Equatable, Sendable {
    /// Uma linha por parada que saiu: "Tirei X pra caber a reserva das 19:00."
    var removed: [String]
    /// Quantas paradas ainda faltam.
    var remaining: Int
    /// Quantas mudaram de hora (sem contar as que saíram).
    var moved: Int

    var isEmpty: Bool { removed.isEmpty && moved == 0 }

    /// Título do aviso: "Atrasou? Ajustei: faltam 5 paradas."
    var headline: String { DayText.adjustedLine(remaining: remaining) }

    /// Chave estável do ajuste (pra lembrar que o aviso já foi visto).
    var key: String { removed.joined(separator: "|") + "#\(moved)#\(remaining)" }

    static func make(clock: DayClock, region: Region) -> ReplanSummary? {
        guard clock.adjusted, let plan = clock.plan else { return nil }
        let removed = clock.skipped.map { stop -> String in
            let name = DayText.head(stop.label)
            switch clock.skipReasons[stop.id] {
            case .beforeAnchor(let id):
                guard let anchor = plan.stops.first(where: { $0.id == id }) else { return "Tirei \(name): não cabe mais." }
                return "Tirei \(name) pra caber \(anchorText(anchor, region: region))."
            case .tooLate:
                return "Deixei \(name) pra outro dia: passaria das 22:30."
            case .passed, nil:
                return "\(name) ficou pra depois: a hora passou."
            }
        }
        let moved = clock.shifted.filter { !clock.skippedIds.contains($0) }.count
        return ReplanSummary(removed: removed, remaining: clock.remaining, moved: moved)
    }

    /// "a reserva das 19:00", "o ingresso das 17:30", "o Golden Gai às 21:00".
    static func anchorText(_ stop: DayStop, region: Region) -> String {
        let time = region.timeString(stop.start)
        switch stop.anchor {
        case .reservation: return "a reserva das \(time)"
        case .ticket: return "o ingresso das \(time)"
        case .golden: return "a luz das \(time)"
        case .train: return "o trem das \(time)"
        default: return "\(DayText.head(stop.label)) às \(time)"
        }
    }
}
