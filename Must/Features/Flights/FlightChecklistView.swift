import SwiftUI

/// Checklist do voo por fase: marcar à mão, prazo em texto, "marcado pela Carteira" nos automáticos. Devolve `Section`s
/// pra morar dentro da `List` do `FlightsView`.
struct FlightChecklistView: View {
    let flight: Flight
    let region: Region
    let now: Date
    let onToggle: (ChecklistItem) -> Void

    var body: some View {
        let items = flight.checklist
        Section {
            Text("modelo: \(FlightRules.templateLabel(flight.template, legs: flight.legs))")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("Checklist · \(items.filter(\.done).count) de \(items.count)").textCase(nil).font(.headline)
        }
        ForEach(ChecklistPhase.allCases) { phase in
            let rows = items.filter { $0.phase == phase }
            if !rows.isEmpty {
                Section(phase.label) {
                    ForEach(rows) { item in row(item) }
                }
            }
        }
    }

    private func row(_ item: ChecklistItem) -> some View {
        Button { onToggle(item) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.done ? V9.accent : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(item.done ? Color.secondary : Color.primary)
                        .strikethrough(item.done)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = noteLine(item) {
                        Text(note).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let due = dueChip(item) {
                    Text(due).font(.footnote).foregroundStyle(.secondary).fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(item.done ? "Feito" : "Falta")
        .accessibilityHint(item.done ? "Desmarcar" : "Marcar como feito")
    }

    private func noteLine(_ item: ChecklistItem) -> String? {
        var parts: [String] = []
        if item.auto && item.done { parts.append("marcado pela Carteira") }
        if let note = item.note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "em 7 dias" enquanto o prazo não chegou (depois, some: o lembrete já tocou).
    private func dueChip(_ item: ChecklistItem) -> String? {
        guard !item.done, let due = item.dueAt, due > now else { return nil }
        return FlightFormat.daysAway(due, now: now, region: region)
    }
}
