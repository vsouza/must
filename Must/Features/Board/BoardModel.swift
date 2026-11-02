import Observation

/// Estado da tela Board: busca, chips, seleção e grupos abertos. As edições ficam em `BoardEdits`.
@MainActor
@Observable
final class BoardModel {
    var query = BoardQuery()
    /// `Place.id` dos selecionados (modo edição).
    var selection: Set<String> = []
    /// Grupos com "+ N em …" abertos.
    var expanded: Set<String> = []
    /// Lista do último lugar tocado: "Selecionar tudo em <lista>".
    var focusListId: String?

    func toggle(_ place: Place) {
        if selection.contains(place.id) {
            selection.remove(place.id)
        } else {
            selection.insert(place.id)
            focusListId = place.list?.id
        }
    }

    func clearSelection() {
        selection.removeAll()
    }
}
