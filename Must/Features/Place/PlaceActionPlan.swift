import Foundation

/// As ações visíveis do Lugar V9 (prompt 32 §5): **Ir · Encaixar hoje · Guardar · Dicas** (+ Feito). Puro: a tela só
/// desenha o que isto decide, então rótulo e estado ficam testáveis sem UI.
struct PlaceActionPlan: Equatable {
    var goTitle: String
    /// "Encaixar hoje" vira "Já está no dia" (desligado) quando o lugar já é parada de hoje ou foi encaixado agora.
    var fitTitle: String
    var fitEnabled: Bool
    var saveTitle: String
    var saveIsOn: Bool
    var doneTitle: String
    var doneIsUndo: Bool
    var tipsTitle: String

    static func make(travelMinutes: Int?, isAnchor: Bool, inDay: Bool, saveForEnd: Bool, isDone: Bool, tipsCount: Int) -> PlaceActionPlan {
        let go: String
        if isAnchor {
            go = "Como chegar"
        } else if let travelMinutes {
            go = "Ir · \(travelMinutes) min"
        } else {
            go = "Ir"
        }
        return PlaceActionPlan(
            goTitle: go,
            fitTitle: inDay ? "Já está no dia" : "Encaixar hoje",
            fitEnabled: !inDay,
            saveTitle: saveForEnd ? "Guardado" : "Guardar",
            saveIsOn: saveForEnd,
            doneTitle: isDone ? "Desfazer feito" : "Feito",
            doneIsUndo: isDone,
            tipsTitle: tipsCount > 0 ? "\(tipsCount) dicas" : "Dicas")
    }
}
