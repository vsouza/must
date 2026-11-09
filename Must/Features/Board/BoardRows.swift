import CoreLocation
import CoreTransferable
import SwiftUI

/// Payload do arrastar: o id do lugar. Soltar num cabeçalho de lista move o lugar pra ela.
struct PlaceDragItem: Codable, Hashable, Transferable, Sendable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Distância curta pra linha ("350 m", "2,4 km").
enum BoardDistance {
    static func text(_ meters: Double) -> String {
        if meters < 950 { return "\(Int((meters / 10).rounded()) * 10) m" }
        return meters.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "pt_BR")).scale(0.001)) + " km"
    }
}

/// Uma linha do board (V9): miniatura, nome, meta (distância, bairro, horário, preço) e o estado em texto.
/// Em modo edição, a bolinha de seleção.
struct BoardRow: View {
    var place: Place
    var region: Region
    var isEditing: Bool
    var isSelected: Bool
    /// Onde você está (distância até o lugar quando é perto); nil = só o bairro.
    var here: CLLocation?

    private var distance: String? {
        guard let here, !place.approx, place.lat != 0 || place.lng != 0 else { return nil }
        let meters = here.distance(from: CLLocation(latitude: place.lat, longitude: place.lng))
        return meters < 50_000 ? BoardDistance.text(meters) : nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isEditing { SelectMark(on: isSelected) }
            PlaceThumb(placeId: place.placeId, refs: place.photoRefs, color: place.list?.color ?? .eat, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.body.weight(.semibold)).lineLimit(2)
                if !meta.isEmpty {
                    Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if let state {
                    Text(state).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(place.isDone ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isEditing ? .isButton : [])
        .accessibilityValue(isEditing ? (isSelected ? "selecionado" : "não selecionado") : "")
    }

    /// "feito" / "sem horário" / "fica pro fim": um estado só, em cinza.
    private var state: String? {
        if place.isDone { return "feito" }
        if place.hours?.hasPeriods != true { return "sem horário" }
        if place.saveForEnd { return "fica pro fim" }
        return nil
    }

    private var meta: String {
        if let done = place.done {
            var out = ["feito \(region.shortDay(done.at))"]
            if let spent = done.spent, spent > 0 { out.append(region.money(spent)) }
            return out.joined(separator: " · ")
        }
        var out: [String] = []
        if let distance { out.append(distance) }
        if let sub = place.sub { out.append(sub) }
        if let area = place.area, !area.isEmpty { out.append(area) }
        if let window = place.windows.first { out.append(window.label) }
        if let queue = place.queueMinutes, queue > 0 { out.append(queue >= 60 ? "fila \(queue / 60)h" : "fila \(queue) min") }
        if let kind = place.source?.kind, kind != .board, kind != .manual { out.append("veio de \(kind.label)") }
        if let price = place.price { out.append(region.money(price)) }
        return out.joined(separator: " · ")
    }
}

/// Bolinha de seleção do sistema: cheia com ✓ quando marcada.
struct SelectMark: View {
    var on: Bool

    var body: some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(on ? V9.accent : Color.secondary)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

/// Cabeçalho de grupo (V9): nome da lista, contagem, sub-listas e "Editar lista" visível.
struct BoardGroupHeader: View {
    var group: BoardGroup
    var onEditList: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(group.title) · \(group.places.count)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
                    .accessibilityAddTraits(.isHeader)
                if !group.subCounts.isEmpty {
                    Text(group.subCounts.map { "\($0.name) \($0.count)" }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary).textCase(nil).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let onEditList {
                Button("Editar lista", action: onEditList).font(.subheadline).textCase(nil)
            }
        }
    }
}
