import SwiftData
import SwiftUI

/// Viagem › Grupo › Pessoas (prompt 32): os nomes de quem viaja junto. Só nomes, no aparelho. Os nomes de Presentes ("pra quem")
/// aparecem como sugestão de um toque.
struct PessoasView: View {
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store

    @Query(sort: [SortDescriptor(\Companion.order), SortDescriptor(\Companion.createdAt)]) private var people: [Companion]
    @Query private var gifts: [Gift]

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var suggestions: [String] {
        let have = Set(people.map { $0.name.lowercased() })
        return GiftLogic.people(gifts).filter { !have.contains($0.lowercased()) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("Nome", text: $draft)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(add)
                    Button("Adicionar", action: add)
                        .buttonStyle(.borderedProminent).tint(V9.accent)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                Text("Quem viaja com você. Fica só neste aparelho.")
            }
            if !suggestions.isEmpty {
                Section("Nomes dos seus Presentes") {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { name in
                            Button("+ \(name)") { insert(name) }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            Section(people.isEmpty ? "Só você" : "Você + \(people.count)") {
                ForEach(people) { person in
                    Text(person.name)
                        .swipeActions { Button("Tirar", role: .destructive) { remove(person) } }
                        .contextMenu { Button("Tirar \(person.name)", systemImage: "trash", role: .destructive) { remove(person) } }
                }
                .onDelete { offsets in offsets.map { people[$0] }.forEach(remove) }
                if people.isEmpty {
                    Text("Ninguém ainda. Adicione quem vai com você pra votar, dividir gasto e mandar o dia.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Pessoas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !people.isEmpty { ToolbarItem(placement: .primaryAction) { EditButton() } } }
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
    }

    private func remove(_ person: Companion) {
        context.delete(person)
        try? context.save()
    }

    private func add() {
        insert(draft)
        draft = ""
    }

    private func insert(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !people.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        context.insert(Companion(name: name, order: (people.map(\.order).max() ?? -1) + 1))
        try? context.save()
    }
}
