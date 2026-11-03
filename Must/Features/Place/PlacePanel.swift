import SwiftUI

/// Qual painel fica embaixo do título do Lugar (prompt 18 · D.20). Exatamente um por lugar:
/// reserva ou ingresso âncora vence; senão o painel do tipo; senão o painel simples.
enum PlacePanelChoice: Equatable, Sendable {
    case reservation
    case ticket
    case kind
    case plain

    static func choose(kind: ListKind, hasReservation: Bool, hasTicket: Bool, hasKindData: Bool) -> PlacePanelChoice {
        if hasReservation { return .reservation }
        if hasTicket { return .ticket }
        if kind != .place && hasKindData { return .kind }
        return .plain
    }

    /// "o que pedir": a primeira frase das notas que fala de pedido ("Pedir o uni extra. …").
    static func orderHint(notes: String) -> String? {
        notes
            .split(whereSeparator: { ".;\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0.range(of: "pedir", options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// "¥¥ · ~22.000" (nível de preço + gasto esperado por pessoa); nil sem preço.
    static func priceText(_ place: Place, region: Region) -> String? {
        guard let p = place.price else { return nil }
        let level = place.priceLevel.map { String(repeating: region.currencySymbol == "¥" ? "¥" : "$", count: max(1, $0)) + " · " } ?? ""
        return "\(level)~\(region.money(p, symbol: false))"
    }
}

/// Painel simples (lugar sem reserva, ingresso nem painel do tipo): cor do Must, status de horário,
/// preço e "o que pedir" das notas. Sem nada disso, mostra a área e a lista.
struct PlainPanel: View {
    var place: Place
    var region: Region
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro(caption, color: (place.list?.color ?? .drink).text)
            Text(status)
                .font(.must.archivo(22, .semibold))
                .foregroundStyle(Color.must.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let price = PlacePanelChoice.priceText(place, region: region) {
                Text(price).font(.must.mono(14)).foregroundStyle(Color.must.ink).lineLimit(1)
            }
            if let order = PlacePanelChoice.orderHint(notes: place.notes) {
                Text(order).font(.must.archivo(15)).foregroundStyle(Color.must.ink).lineLimit(2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var caption: String {
        let parts = [place.list?.displayName, place.area].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? "lugar" : parts.joined(separator: " · ")
    }

    private var status: String {
        switch place.openState(at: now, timeZone: region.timeZone) {
        case .open(let until): until.map { "fecha \($0)" } ?? "aberto agora"
        case .closed(let day, let time): time.map { t in day.map { "abre \($0) \(t)" } ?? "abre \(t)" } ?? "fechado"
        case .unknown: "sem horário"
        }
    }
}
