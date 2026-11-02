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
            HStack(alignment: .top, spacing: 12) {
                Text("Checklist deste voo · \(items.filter(\.done).count) de \(items.count)")
                    .font(.must.archivo(22, .semibold)).foregroundStyle(Color.must.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text("modelo: \(FlightRules.templateLabel(flight.template, legs: flight.legs))")
                    .font(.must.archivo(13)).foregroundStyle(Color.must.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.must.surface))
            }
            ForEach(ChecklistPhase.allCases) { phase in
                let rows = items.filter { $0.phase == phase }
                if !rows.isEmpty {
                    Micro(phase.label).padding(.top, 20)
                    RowDivider().padding(.top, 6)
                    ForEach(rows) { item in
                        row(item)
                        if item.id != rows.last?.id { RowDivider() }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 6)
    }

    private func row(_ item: ChecklistItem) -> some View {
        Button { onToggle(item) } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.done ? Color.must.green : Color.clear)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(item.done ? Color.clear : Color.must.line, lineWidth: 1.5)
                    if item.done { MustIconView(.ok, size: 14).foregroundStyle(Color.must.greenText) }
                }
                .frame(width: 26, height: 26)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.must.archivo(16, .semibold))
                        .foregroundStyle(item.done ? Color.must.secondary : Color.must.ink)
                        .multilineTextAlignment(.leading)
                    if let note = noteLine(item) {
                        Text(note).mustMeta().multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                if let due = dueChip(item) {
                    Text(due)
                        .font(.must.archivo(13, .semibold))
                        .foregroundStyle(Color(hex: 0x0F3B8C))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Color(hex: 0xEAF2FF)))
                        .fixedSize()
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MustPressStyle())
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
