import SwiftUI

/// Linha de parada V9 (Linha do dia e Agora): hora em dígitos tabulares, nome, nota e estado. A parada de agora leva o
/// ponto do acento; feita fica esmaecida com ✓; âncora/reserva leva a etiqueta (RES, EXP…). Sem trama, régua nem numeral.
struct V9StopRow: View {
    var stop: DayStop
    var state: LinhaStopState
    var region: Region
    var onTap: (() -> Void)?

    private var isMicro: Bool { stop.kind == .micro }

    var body: some View {
        if let onTap {
            Button(action: onTap) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private var noteText: String {
        switch state {
        case .done: stop.note.contains("feito") ? stop.note : (stop.note.isEmpty ? "feito" : stop.note + " · feito")
        case .skipped: "ficou pra depois" + (stop.note.isEmpty ? "" : " · " + stop.note)
        default: stop.note
        }
    }

    private var tagText: String? {
        if stop.kind == .anchor || (isMicro && stop.tag?.uppercased() == "EXP") { return (stop.tag ?? (isMicro ? "EXP" : "RES")).uppercased() }
        return nil
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(region.timeString(stop.start))
                .font(isMicro ? .subheadline : .body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(state == .now ? V9.accent : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if state == .now { Circle().fill(V9.accent).frame(width: 9, height: 9).accessibilityHidden(true) }
                    Text(stop.label).font(isMicro ? .subheadline : .body.weight(.semibold)).lineLimit(2)
                }
                if !noteText.isEmpty { Text(noteText).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                if state == .now { Text("agora").font(.footnote.weight(.semibold)).foregroundStyle(V9.accent) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let tagText {
                Text(tagText).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(V9.fill, in: Capsule())
            }
            if state == .done { Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true) }
            if onTap != nil { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true) }
        }
        .opacity(state == .done || state == .skipped ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region.timeString(stop.start)), \(stop.label), \(noteText)\(state == .done ? ", feito" : state == .now ? ", agora" : "")")
    }
}

/// Deslocamento entre paradas: uma linha pequena e secundária ("a pé · 8 min").
struct V9LegRow: View {
    var leg: DayLeg
    private var systemImage: String {
        switch leg.mode {
        case .walk: "figure.walk"
        case .taxi: "car"
        case .bus: "bus"
        case .train, .metro: "tram"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).accessibilityHidden(true)
            Text(DayLegRow.text(leg)).monospacedDigit().lineLimit(2)
        }
        .font(.footnote).foregroundStyle(.secondary)
        .padding(.leading, 68)
        .accessibilityElement(children: .combine)
    }
}
