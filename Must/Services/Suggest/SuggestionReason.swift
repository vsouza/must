import Foundation

/// O motivo de uma linha "Agora vale" em V9 (prompt 32 §2): **uma** linha curta, em português de gente, igual em Hoje e no
/// painel do Explorar. Ex.: "fecha em 40 min · seu Must · aberto até 22:00", "seu Must · ramen · horário a confirmar".
/// Sai o jargão do ranker ("perto", "no board", "hora certa", "seu gosto"): a distância já está no detalhe da linha.
/// "Local aproximado" fica no Lugar (não muda a decisão de ir agora).
enum SuggestionReason {
    private static let rankerTags: Set<String> = ["perto", "no board", "hora certa", "seu gosto"]

    static func line(_ card: Suggestion) -> String {
        var parts: [String] = []
        // O que é urgente vem primeiro ("fecha em 40 min", "chuva em 30 min · coberto", "luz boa").
        if let urgent = card.reasons.first(where: { !rankerTags.contains($0) }) { parts.append(urgent) }
        switch card.kind {
        case .must, .closing:
            parts.append("seu Must")
            let meta = card.meta == "no seu board" ? "" : card.meta
            if let first = meta.components(separatedBy: " · ").first, first.hasPrefix("fecha ") {
                parts.append("aberto até " + first.dropFirst("fecha ".count))
            } else if !meta.isEmpty {
                parts.append(meta.components(separatedBy: " · ").first ?? meta)
            }
        default:
            if !card.meta.isEmpty, !parts.contains(card.meta) { parts.append(card.meta) }
        }
        if card.trust?.contains(PlaceTrust.hoursEstimated) == true { parts.append("horário a confirmar") }
        var seen = Set<String>()
        return parts.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(3).joined(separator: " · ")
    }
}
