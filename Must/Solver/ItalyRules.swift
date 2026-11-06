import Foundation

/// Regras de Roma no solver (prompt 24 §2). Ligadas pelo perfil do país (`data/countries/IT.json`, `rules`; as janelas
/// em `meals`). Puras, sem rede.
/// - almoço 12:30–15, jantar 19:30–23 (jantar nunca antes das 19:30);
/// - riposo 13–16 nas lojas pequenas; igrejas fecham 12:30–15:30;
/// - museus estatais fecham segunda (a Borghese não, mas só entra com reserva);
/// - domingo a Via Appia fecha pra carros: vira âncora de manhã;
/// - reserva com "turno de 2 h" (Galleria Borghese) é âncora com fim fixo.
enum ItalyRules {
    /// Lojas pequenas fecham pro almoço.
    static let riposo = (13 * 60)..<(16 * 60)
    /// Igrejas fecham no meio do dia (Bolso IT).
    static let churchBreak = (12 * 60 + 30)..<(15 * 60 + 30)
    /// Domingo na Appia: começa às 09:30 e vai até o almoço.
    static let appiaStart = 9 * 60 + 30
    static let appiaMinutes = 150

    /// Janelas italianas (minutos desde a meia-noite, [início, fim)): as do perfil do país.
    static func range(_ window: DayWindow, startEarly: Bool) -> Range<Int> {
        DaySolver.range(window, startEarly: startEarly, region: .it)
    }

    private static func text(_ p: SolverPlace) -> String {
        [p.name, p.sub ?? "", p.notes, p.reservation?.note ?? ""].joined(separator: " ").lowercased()
    }

    /// Loja pequena: sem horário do Google (ou "riposo" escrito) e sem "horário contínuo". Mercado grande e Eataly abrem direto.
    static func hasRiposo(_ p: SolverPlace) -> Bool {
        guard p.role == .shop else { return false }
        let t = text(p)
        if t.contains("sem riposo") || t.contains("contínuo") || t.contains("continuo") || t.contains("continuato") { return false }
        if t.contains("riposo") { return true }
        if t.contains("eataly") || t.contains("shopping") || t.contains("rinascente") { return false }
        return !(p.hours?.hasPeriods ?? false)
    }

    static func isChurch(_ p: SolverPlace) -> Bool {
        guard let sub = p.sub?.lowercased() else { return false }
        return sub.contains("igreja") || sub.contains("basílica") || sub.contains("basilica")
    }

    /// Faixa do meio do dia em que o lugar está fechado (riposo da loja, pausa da igreja). `nil` = abre direto.
    static func middayClosure(_ p: SolverPlace) -> Range<Int>? {
        if hasRiposo(p) { return riposo }
        if isChurch(p), !(p.hours?.hasPeriods ?? false) { return churchBreak }
        return nil
    }

    /// Museu estatal: fecha segunda. A Borghese (reserva), os Vaticanos (Santa Sé), os Capitolinos (comunais) e os
    /// palácios privados abrem; "abre segunda" nas notas também libera.
    static func isStateMuseum(_ p: SolverPlace) -> Bool {
        guard p.kind == .art, let sub = p.sub?.lowercased(), sub.contains("museu") || sub.contains("galeria") || sub.contains("galleria") else { return false }
        let t = text(p)
        let exempt = ["borghese", "vatican", "capitolin", "privad", "abre segunda", "abre na segunda", "comunal"]
        return !exempt.contains { t.contains($0) }
    }

    /// Só entra com reserva (Galleria Borghese): sem reserva no dia, fica fora.
    static func requiresReservation(_ p: SolverPlace) -> Bool {
        let t = text(p)
        return t.contains("reserva obrigatória") || t.contains("reserva obrigatoria") || t.contains("borghese") && p.kind == .art
    }

    /// "turno de 2 h" / "turno de 2h" / "só 2 horas" → 120. `nil` = sem turno.
    static func shiftMinutes(_ p: SolverPlace) -> Int? {
        let t = text(p)
        for pattern in ["turno de (\\d+) ?h", "só (\\d+) horas", "so (\\d+) horas"] {
            if let r = t.range(of: pattern, options: .regularExpression) {
                let digits = t[r].filter(\.isNumber)
                if let h = Int(digits), (1...6).contains(h) { return h * 60 }
            }
        }
        return nil
    }

    /// Via Appia Antica (domingo sem carros).
    static func isAppia(_ p: SolverPlace) -> Bool {
        p.name.lowercased().contains("appia")
    }
}
