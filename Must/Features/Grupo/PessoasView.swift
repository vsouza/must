import SwiftData
import SwiftUI

/// Viagem › Grupo › Pessoas (prompt 32): os nomes de quem viaja junto. Só nomes, no aparelho. Os nomes de Presentes ("pra quem")
/// aparecem como sugestão de um toque.
struct PessoasView: View {
    @Environment(\.dismiss) private var dismiss
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
        CutPage(title: "Pessoas", corner: ["Viagem · Grupo", people.isEmpty ? "só você" : "você + \(people.count)"],
                subtitle: "Quem viaja com você. Fica só neste aparelho.", height: 200, onBack: { dismiss() }) {
            VStack(alignment: .leading, spacing: 0) {
                addField
                if !suggestions.isEmpty { suggestionsBlock }
                ForEach(people) { person in row(person) }
                if people.isEmpty {
                    Text("Ninguém ainda. Adicione quem vai com você pra votar, dividir gasto e mandar o dia.")
                        .font(V8Font.text(15)).foregroundStyle(V8.mute)
                        .padding(.horizontal, 20).padding(.top, 20)
                }
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 10) {
            TextField("Nome", text: $draft)
                .font(V8Font.text(17))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focused)
                .onSubmit(add)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            Button(action: add) {
                Text("ADICIONAR")
                    .font(V8Font.mono(11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(V8.ink)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .background(V8.orange)
                    .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    private var suggestionsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("de Presentes · toque pra adicionar", size: 10, color: V8.mute)
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { name in
                    Button { insert(name) } label: { CutChip(text: "+ \(name)") }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    private func row(_ person: Companion) -> some View {
        HStack(spacing: 12) {
            Text(String(person.name.prefix(1)).uppercased())
                .font(V8Font.mono(14, weight: .bold)).foregroundStyle(V8.paper)
                .frame(width: 36, height: 36).background(V8.ink)
                .accessibilityHidden(true)
            Text(person.name).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
            Spacer(minLength: 8)
            CutCornerButton(systemName: "trash", label: "Tirar \(person.name)") {
                context.delete(person)
                try? context.save()
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .overlay(alignment: .bottom) { IndexRule() }
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
