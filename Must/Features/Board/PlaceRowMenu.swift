import SwiftUI

/// O ⋯ visível de cada linha (corte): botão quadrado de 44 pt com as mesmas ações do deslizar. Nada só por gesto.
struct PlaceRowMenu: View {
    var place: Place
    var onOpen: (() -> Void)?
    var onDone: () -> Void
    var onSaveForEnd: () -> Void
    var onEdit: (() -> Void)?
    var onDelete: () -> Void

    var body: some View {
        Menu {
            if let onOpen { Button(action: onOpen) { Label("Abrir", systemImage: "arrow.up.right") } }
            if !place.isDone { Button(action: onDone) { Label("Marcar feito", systemImage: "checkmark") } }
            Button(action: onSaveForEnd) { Label(place.saveForEnd ? "Tirar do fim" : "Fica pro fim", systemImage: "clock") }
            if let onEdit { Button(action: onEdit) { Label("Editar", systemImage: "pencil") } }
            Button(role: .destructive, action: onDelete) { Label("Apagar", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(V8.ink)
                .frame(width: 40, height: 40)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Ações de \(place.name)")
    }
}
