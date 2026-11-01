import Foundation

/// Regras escritas nas notas do board ("Só domingo de manhã", "Fecha segunda", "Dia inteiro", "só se céu limpo").
/// Valem mesmo sem horário do Places.
struct NotesRules: Sendable, Hashable {
    /// Dias permitidos (0 = dom). `nil` = qualquer.
    var onlyDays: Set<Int>?
    /// Dias fechados.
    var closedDays: Set<Int> = []
    /// Só de manhã / só à noite.
    var onlyWindows: Set<DayWindow>?
    /// Ocupa o dia inteiro (Inhotim): só entra se pedir.
    var fullDay = false
    /// Só com céu limpo (Fuji, mirante).
    var weatherDependent = false
    /// Ao ar livre (mirante, parque): sai com chuva forte.
    var outdoor = false
    /// "domingo lota": evitar no dia.
    var crowdedDays: Set<Int> = []

    static let dayNames: [(Int, [String])] = [
        (0, ["domingo", "dom"]), (1, ["segunda", "seg"]), (2, ["terça", "terca", "ter"]), (3, ["quarta", "qua"]),
        (4, ["quinta", "qui"]), (5, ["sexta", "sex"]), (6, ["sábado", "sabado", "sáb", "sab"]),
    ]

    static let fullNames = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]

    init(notes: String) {
        let text = notes.lowercased()

        func days(after prefix: String) -> Set<Int> {
            var result: Set<Int> = []
            for (day, names) in Self.dayNames {
                for name in names where text.range(of: "\(prefix) \(name)\\b", options: .regularExpression) != nil {
                    result.insert(day)
                }
            }
            return result
        }

        let only = days(after: "só")
        if !only.isEmpty { onlyDays = only }
        closedDays = days(after: "fecha")
        var crowded: Set<Int> = []
        for (day, names) in Self.dayNames {
            for name in names where text.range(of: "\\b\(name) lota", options: .regularExpression) != nil { crowded.insert(day) }
        }
        crowdedDays = crowded

        if text.contains("só manhã") || text.contains("só de manhã") || text.contains("de manhã") && onlyDays != nil {
            onlyWindows = [.morning]
        }
        fullDay = text.contains("dia inteiro") || text.contains("dia dedicado")
        weatherDependent = text.contains("céu limpo") || text.contains("ceu limpo")
        outdoor = weatherDependent || text.contains("ao ar livre") || text.contains("pôr do sol") || text.contains("mirante")
    }

    /// Motivo pra não entrar em `weekday`, se houver.
    func blocks(weekday: Int) -> String? {
        if let onlyDays, !onlyDays.contains(weekday) {
            let names = onlyDays.sorted().map { Self.fullNames[$0] }.joined(separator: " e ")
            return "só \(names)"
        }
        if closedDays.contains(weekday) { return "fecha \(Self.fullNames[weekday])" }
        return nil
    }

    /// Só existe hoje (ex.: "Só domingo" num domingo): o solver puxa.
    func isRareToday(weekday: Int) -> Bool { onlyDays?.contains(weekday) == true }
}
