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

/// Uma linha do board no padrão índice do corte (`ListIndexRow`): distância (ou bairro) em mono grande à esquerda, nome,
/// meta em mono/cinza, estado em mono cinza e régua de 2 pt embaixo. Sem miniatura. Feito fica a 55%.
/// Em modo edição, a bolinha de seleção.
struct BoardRow: View {
    var place: Place
    var region: Region
    var isEditing: Bool
    var isSelected: Bool
    /// Onde você está (distância até o lugar quando é perto); nil = mostra o bairro.
    var here: CLLocation?

    private var big: (value: String, unit: String)? {
        if let here, !place.approx, place.lat != 0 || place.lng != 0 {
            let meters = here.distance(from: CLLocation(latitude: place.lat, longitude: place.lng))
            if meters < 50_000 {
                let parts = CorteSplit.distanceParts(meters)
                return (parts.value, parts.unit == "m" ? "metros" : parts.unit)
            }
        }
        if let area = place.area, !area.isEmpty { return (String(area.prefix(3)).uppercased(), area) }
        return nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isEditing { SelectMark(on: isSelected) }
            VStack(alignment: .leading, spacing: 2) {
                Text(big?.value ?? "·")
                    .font(V8Font.mono(22, weight: .semibold)).foregroundStyle(V8.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text((big?.unit ?? "").uppercased())
                    .font(V8Font.mono(8.5)).tracking(0.8).foregroundStyle(V8.mute).lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(V8Font.text(17, weight: .semibold)).foregroundStyle(V8.ink).lineLimit(2)
                if !meta.isEmpty {
                    Text(meta).font(V8Font.mono(10.5)).foregroundStyle(V8.mute).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let state {
                Text(state.uppercased())
                    .font(V8Font.mono(9.5)).tracking(0.8).foregroundStyle(V8.mute).lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? V8.ink.opacity(0.08) : Color.clear)
        .overlay(alignment: .bottom) { CorteRule2() }
        .opacity(place.isDone ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isEditing ? .isButton : [])
        .accessibilityValue(isEditing ? (isSelected ? "selecionado" : "não selecionado") : "")
    }

    /// "feito" / "sem horário" / "fica pro fim": um estado só, em cinza (laranja é só pra ação e "agora").
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
        if let sub = place.sub { out.append(sub) }
        if big != nil, let area = place.area, big?.unit != area { out.append(area) }
        if let window = place.windows.first { out.append(window.label) }
        if let queue = place.queueMinutes, queue > 0 { out.append(queue >= 60 ? "fila \(queue / 60)h" : "fila \(queue) min") }
        if let kind = place.source?.kind, kind != .board, kind != .manual { out.append("veio de \(kind.label)") }
        if let price = place.price { out.append(region.money(price)) }
        return out.joined(separator: " · ")
    }
}

/// Bolinha de seleção 24 pt: preta com ✓ quando marcada.
struct SelectMark: View {
    var on: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(on ? Color.must.ink : Color.white)
                .overlay(Circle().strokeBorder(on ? Color.must.ink : Color(hex: 0xD9DCE1), lineWidth: 1.6))
            if on {
                MustIconView(.ok, size: 12).foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// Cabeçalho de grupo = uma faixa inteira (prompt 30): régua dura de 12 pt, o nome da lista gigante (Bricolage), a contagem em
/// mono, as sub-listas em mono e "editar lista" quadrado. Sem ponto de cor (a cor do Must saiu na v8).
struct BoardGroupHeader: View {
    var group: BoardGroup
    var onEditList: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CutRule()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(group.title)
                    .font(V8Font.display(40))
                    .tracking(-1.4)
                    .foregroundStyle(V8.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text("\(group.places.count)")
                    .font(V8Font.mono(22, weight: .semibold))
                    .foregroundStyle(V8.ink)
                    .accessibilityLabel("\(group.places.count) lugares")
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            HStack(alignment: .center, spacing: 8) {
                if !group.subCounts.isEmpty {
                    Text(group.subCounts.map { "\($0.name) \($0.count)" }.joined(separator: " · ").uppercased())
                        .font(V8Font.mono(9.5)).tracking(0.8)
                        .foregroundStyle(V8.mute)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let onEditList {
                    Button(action: onEditList) {
                        Text("EDITAR LISTA")
                            .font(V8Font.mono(10, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(V8.ink)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 10)
            CorteRule2()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
