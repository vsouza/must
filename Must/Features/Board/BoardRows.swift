import CoreTransferable
import SwiftUI

/// Payload do arrastar: o id do lugar. Soltar num cabeçalho de lista move o lugar pra ela.
struct PlaceDragItem: Codable, Hashable, Transferable, Sendable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

/// Uma linha do board: nome + nome local, meta de uma linha (sub · bairro · janela · fila · flags · preço).
/// Feito fica a 50%, com 済. Em modo edição, a bolinha de seleção.
struct BoardRow: View {
    var place: Place
    var region: Region
    var isEditing: Bool
    var isSelected: Bool

    private static let alert = Color(hex: 0xC2261D)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if isEditing { SelectMark(on: isSelected) }
            if place.isDone { KanjiSeal(done: true, size: 24, look: .soft) }
            PlaceThumb(placeId: place.placeId, refs: place.photoRefs, color: place.list?.color ?? .drink, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(place.name)
                        .font(.must.archivo(15, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .lineLimit(1)
                }
                meta
                    .font(.must.archivo(12))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, isSelected ? 10 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.must.surface2 : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottom) {
            if !isSelected { RowDivider() }
        }
        .opacity(place.isDone ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isEditing ? .isButton : [])
        .accessibilityValue(isEditing ? (isSelected ? "selecionado" : "não selecionado") : "")
    }

    private var meta: Text {
        var line = AttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                var separator = AttributedString(" · ")
                separator.foregroundColor = Color.must.secondary
                line += separator
            }
            var piece = AttributedString(part.text)
            piece.foregroundColor = part.color
            line += piece
        }
        return Text(line)
    }

    private var parts: [(text: String, color: Color)] {
        let quiet = Color.must.secondary
        if let done = place.done {
            var out: [(String, Color)] = [("feito \(region.shortDay(done.at))", quiet)]
            if let spent = done.spent, spent > 0 { out.append((region.money(spent), quiet)) }
            return out
        }
        var out: [(String, Color)] = []
        if let sub = place.sub { out.append((sub, quiet)) }
        if let area = place.area { out.append((area, quiet)) }
        if let window = place.windows.first { out.append((window.label, quiet)) }
        if let queue = place.queueMinutes, queue > 0 { out.append((queue >= 60 ? "fila \(queue / 60)h" : "fila \(queue) min", quiet)) }
        if place.hours?.hasPeriods != true { out.append(("sem horário", Self.alert)) }
        if place.saveForEnd { out.append(("fica pro fim", quiet)) }
        if let kind = place.source?.kind, kind != .board, kind != .manual { out.append(("veio de \(kind.label)", quiet)) }
        if let price = place.price { out.append((region.money(price), Color.must.ink)) }
        return out
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
