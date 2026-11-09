import SwiftData
import SwiftUI

/// O que o Board apresenta por cima da lista.
enum BoardSheet: Identifiable, Hashable {
    case move
    case city
    /// Marcar feito: `Place.id`.
    case done(String)

    var id: String {
        switch self {
        case .move: "move"
        case .city: "city"
        case .done(let id): "done-\(id)"
        }
    }
}

/// Barra de ações em lote (modo edição, com seleção): material do sistema, botões com nome.
struct BoardBatchBar: View {
    var count: Int
    /// "Selecionar tudo em Must eat" (nil quando não há lista de foco).
    var focusTitle: String?
    var saveForEndTitle: String
    var onSelectAll: () -> Void
    var onMove: () -> Void
    var onSaveForEnd: () -> Void
    var onCity: () -> Void
    var onResolve: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(count) \(count == 1 ? "selecionado" : "selecionados")")
                    .font(.headline)
                Spacer(minLength: 8)
                if let focusTitle {
                    Button("Selecionar tudo em \(focusTitle)", action: onSelectAll)
                        .font(.subheadline).lineLimit(1)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Mover pra lista…", action: onMove).buttonStyle(.bordered)
                    Button(saveForEndTitle, action: onSaveForEnd).buttonStyle(.bordered)
                    Button("Cidade", action: onCity).buttonStyle(.bordered)
                    Button("Resolver no Places", action: onResolve).buttonStyle(.bordered)
                    Button("Apagar", role: .destructive, action: onDelete).buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
        .padding(.horizontal, V9.gutter)
    }
}

/// Mover pra lista…: as listas e a contagem.
struct MoveListSheet: View {
    var lists: [MustList]
    var count: Int
    var onPick: (MustList) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(lists) { list in
                Button {
                    onPick(list)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        MustIconView(list.icon, size: 18).foregroundStyle(.secondary).frame(width: 28).accessibilityHidden(true)
                        Text(list.displayName).foregroundStyle(.primary)
                        Spacer()
                        Text("\(list.places.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
            }
            .navigationTitle("Mover \(count) \(count == 1 ? "lugar" : "lugares")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}

/// Um item do seletor de cidade (o título já traz "Tóquio 13–17" quando o nome se repete).
struct CityOption: Identifiable, Hashable {
    let id: String
    let title: String
}

/// Cidade…: troca a cidade dos lugares selecionados.
struct CityPickSheet: View {
    var options: [CityOption]
    var onPick: (CityOption) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(options) { option in
                Button {
                    onPick(option)
                    dismiss()
                } label: {
                    Text(option.title).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
            }
            .navigationTitle("Cidade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}

/// Marcar feito: quanto foi. Sem valor também marca como feito.
struct DoneSheet: View {
    var place: Place
    var region: Region

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Text(region.currencySymbol).foregroundStyle(.secondary)
                        TextField("0", text: $amount).keyboardType(.decimalPad).monospacedDigit()
                    }
                } header: {
                    Text("Quanto foi?")
                } footer: {
                    Text("Pode deixar em branco: marca como feito do mesmo jeito.")
                }
                Section {
                    Button("Marcar feito") { mark() }.v9Primary().frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }

    private func mark() {
        let spent = NumberInput.double(amount.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) ?? 0
        PlaceActions.markDone(place, spent: spent, context: context)
        dismiss()
    }
}
