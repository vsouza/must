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

/// Painel simples (lugar sem reserva, ingresso nem painel do tipo): cor do Must e o que o cartão de
/// informações não mostra — "o que pedir" das notas (ou o tipo do lugar), janelas do dia, fila e
/// "fica pro fim". Horário só quando é conhecido; preço e distância ficam no cartão de baixo.
struct PlainPanel: View {
    var place: Place
    var region: Region
    var now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro(caption, color: (place.list?.color ?? .drink).text)
            Text(PlacePanelChoice.headline(place))
                .font(.must.archivo(22, .semibold))
                .foregroundStyle(Color.must.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            let facts = PlacePanelChoice.facts(place, status: status)
            if !facts.isEmpty {
                Text(facts).font(.must.archivo(14)).foregroundStyle((place.list?.color ?? .drink).text).lineLimit(1)
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

    private var status: String? {
        switch place.openState(at: now, timeZone: region.timeZone) {
        case .open(let until): until.map { "fecha \($0)" } ?? "aberto agora"
        case .closed(let day, let time): time.map { t in day.map { "abre \($0) \(t)" } ?? "abre \(t)" } ?? "fechado"
        case .unknown: nil
        }
    }
}

extension PlacePanelChoice {
    /// Título do painel simples: "Pedir o uni extra" › tipo do lugar ("Mercado") › nome da lista.
    static func headline(_ place: Place) -> String {
        if let order = orderHint(notes: place.notes) { return order }
        if let sub = place.sub?.trimmingCharacters(in: .whitespaces), !sub.isEmpty {
            return sub.prefix(1).uppercased() + sub.dropFirst()
        }
        return place.list?.displayName ?? place.name
    }

    /// "fecha 18:00 · almoço e jantar · fila ~25 min · fica pro fim" (só o que existe).
    static func facts(_ place: Place, status: String?) -> String {
        var parts: [String] = []
        if let status { parts.append(status) }
        let windows = DayWindow.allCases.filter(place.windows.contains).map(\.label)
        if !windows.isEmpty { parts.append(windows.count > 1 ? windows.dropLast().joined(separator: ", ") + " e " + windows.last! : windows[0]) }
        if let q = place.queueMinutes, q > 0 { parts.append("fila ~\(q) min") }
        if place.saveForEnd { parts.append("fica pro fim") }
        return parts.joined(separator: " · ")
    }
}
