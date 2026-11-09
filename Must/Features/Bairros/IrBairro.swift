import Foundation

/// "Ir pra um bairro" (pedido de 08/11/2026): escolhe o bairro, marca os Musts que quer e o solver ordena SÓ esses
/// (mais as âncoras de hoje: reservas e ingressos). Tudo aqui é puro e testável; a tela só desenha.
enum IrBairro {
    /// Linha do seletor de bairros.
    struct AreaRow: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        /// Musts ainda não feitos no bairro.
        var count: Int
        /// Quantos deles estão abertos agora.
        var openCount: Int

        var metaLine: String {
            "\(count) \(count == 1 ? "MUST" : "MUSTS") · \(openCount) \(openCount == 1 ? "ABERTO" : "ABERTOS")"
        }
    }

    /// O que a lista precisa de um Must (cópia sem `@Model`).
    struct MustInfo: Equatable, Sendable {
        var id: String
        var name: String
        var sub: String?
        var isDone: Bool
        var state: OpenState
        var hasReservationToday: Bool
    }

    /// Linha do checklist.
    struct MustRow: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var meta: String
        var isOpen: Bool
    }

    /// Bairros com Musts não feitos, do que tem mais pro que tem menos (a mesma ordem do Montar).
    /// `index` deve ter sido montado só com Musts não feitos.
    static func areaRows(_ index: AreaIndex) -> [AreaRow] {
        MontarOptions.chips(index).map { chip in
            AreaRow(id: chip.id, name: chip.name, count: chip.count, openCount: index.entry(chip.id)?.openCount ?? 0)
        }
    }

    /// Musts do bairro: sem os feitos, abertos agora primeiro, o resto na ordem do board (ordem estável de `ids`).
    static func mustRows(ids: [String], info: [String: MustInfo]) -> [MustRow] {
        let items = ids.compactMap { info[$0] }.filter { !$0.isDone }
        let open = items.filter { $0.state.isOpen }
        let rest = items.filter { !$0.state.isOpen }
        return (open + rest).map { MustRow(id: $0.id, name: $0.name, meta: metaLine($0), isOpen: $0.state.isOpen) }
    }

    /// "ramen · aberto até 16:30", "izakaya · abre 17:00", "horário não confirmado". Só afirma "aberto" com dado de horário.
    static func metaLine(_ m: MustInfo) -> String {
        var parts: [String] = []
        if let sub = m.sub?.trimmingCharacters(in: .whitespaces), !sub.isEmpty { parts.append(sub) }
        switch m.state {
        case .open(let until): parts.append(until.map { "aberto até \($0)" } ?? "aberto")
        case .closed(let day, let at):
            if let at { parts.append(day.map { "abre \($0) \(at)" } ?? "abre \(at)") } else { parts.append("fechado agora") }
        case .unknown: parts.append("horário não confirmado")
        }
        if m.hasReservationToday { parts.append("reserva hoje") }
        return parts.joined(separator: " · ")
    }

    /// Catálogo do solver: os marcados + o que é âncora hoje (reserva, ingresso ou sessão comprada).
    static func restrictedCatalog(_ catalog: [SolverPlace], checked: Set<String>, date: Date, calendar: Calendar) -> [SolverPlace] {
        catalog.filter { checked.contains($0.id) || (!$0.done && isAnchor($0, on: date, calendar: calendar)) }
    }

    static func isAnchor(_ p: SolverPlace, on date: Date, calendar: Calendar) -> Bool {
        if let r = p.reservation, calendar.isDate(r.at, inSameDayAs: date) { return true }
        if p.tickets.contains(where: { calendar.isDate($0.at, inSameDayAs: date) }) { return true }
        return (p.extra?.sessions ?? []).contains { $0.bought && calendar.isDate($0.at, inSameDayAs: date) }
    }

    /// Nomes dos marcados, na ordem do catálogo: vão pra `DayIntent.mustInclude`.
    static func mustIncludeNames(_ catalog: [SolverPlace], checked: Set<String>) -> [String] {
        catalog.filter { checked.contains($0.id) && !$0.done }.map(\.name)
    }

    /// Marcados que a proposta não encaixou, com o motivo (`leftOut`) ou "não coube no tempo". Ordem do catálogo.
    static func missing(_ proposal: DayProposal?, asked: [SolverPlace]) -> [(name: String, reason: String)] {
        guard let proposal else { return [] }
        let placed = Set(proposal.stops.map(\.place.id))
        return asked.filter { !placed.contains($0.id) }.map { ($0.name, proposal.reason(for: $0.id) ?? "não coube no tempo") }
    }
}
