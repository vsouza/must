import SwiftUI

/// Linha de filtros do corte: `CutChip` quadrados que rolam na horizontal; cada um é um botão com nome.
struct CutChipRow: View {
    struct Item: Identifiable {
        var id: String
        var title: String
        var on: Bool
    }

    var items: [Item]
    var onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    Button { onTap(item.id) } label: { CutChip(text: item.title, isOn: item.on) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }
}
