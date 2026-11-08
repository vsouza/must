import SwiftUI

/// Checklist do voo por fase (`design/screens/Voos.png`): marcar à mão, prazo em chip, "marcado pela Carteira" nos automáticos.
struct FlightChecklistView: View {
    let flight: Flight
    let region: Region
    let now: Date
    let onToggle: (ChecklistItem) -> Void

    private var amber: Color { Color(hex: 0xFFB020) }

    var body: some View {
        let items = flight.checklist
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Checklist · \(items.filter(\.done).count) de \(items.count)")
                    .font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                SpecLabel("modelo: \(FlightRules.templateLabel(flight.template, legs: flight.legs))").multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) { IndexRule() }
            ForEach(ChecklistPhase.allCases) { phase in
                let rows = items.filter { $0.phase == phase }
                if !rows.isEmpty {
                    HStack {
                        MonoLabel(phase.label, size: 10, color: V8.paper)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(V8.ink)
                    ForEach(rows) { item in
                        row(item)
                    }
                }
            }
        }
    }

    private func row(_ item: ChecklistItem) -> some View {
        Button { onToggle(item) } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Rectangle().fill(item.done ? V8.orange : Color.clear)
                    Rectangle().strokeBorder(V8.ink, lineWidth: 2)
                    if item.done { MustIconView(.ok, size: 14).foregroundStyle(V8.ink) }
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(V8Font.text(16, weight: .bold))
                        .foregroundStyle(item.done ? V8.mute : V8.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = noteLine(item) {
                        Text(note).font(V8Font.text(13)).foregroundStyle(V8.mute).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let due = dueChip(item) {
                    CutTag(text: due).fixedSize()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { IndexRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
