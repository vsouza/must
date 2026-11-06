import Foundation

/// Dicas pra hoje (prompt 23 §2 · 07, `Dicas.png`): a dica do lugar de agora (laranja), a do próximo (branco), um
/// "Sabia que" do país (tinta), a do momento do dia, a da noite e a da volta. Fontes: notas do lugar, regras do país
/// (`PocketRules`) e a primeira dica de quem foi que já está no cache. Puro: nada aqui chama rede.
enum DayTips {
    enum Filter: String, CaseIterable, Sendable, Hashable {
        case now, area, country, etiquette, saved
    }

    struct Card: Identifiable, Hashable, Sendable {
        var id: String
        var tone: PocketTone
        /// Etiqueta de cima à esquerda ("FUUNJI · AGORA", "SABIA QUE").
        var tag: String
        /// Rótulo à direita ("FILA", "GOLDEN", "JAPÃO").
        var corner: String
        var title: String
        var detail: String
        var filters: Set<Filter>
        var placeId: String?
    }

    /// Um lugar do dia visto pelas Dicas.
    struct Stop: Sendable {
        var id: String
        var placeId: String?
        var name: String
        var kind: ListKind
        var sub: String?
        var notes: String
        var queueMinutes: Int?
        var at: Date
        /// "16:00" (último horário de fechamento hoje), se souber.
        var closesAt: String?
        /// Início do golden da tarde (lugar de foto).
        var golden: Date?
        var inArea: Bool
        /// Primeira dica de quem foi já no aparelho.
        var peopleTip: String?
    }

    static func build(now: Date, region: Region, current: Stop?, next: Stop?, night: Stop?, lastTrain: (line: String, time: String)?,
                      country: PocketCountry, saved: Set<String>, time: (Date) -> String) -> [Card] {
        var cards: [Card] = []

        if let current {
            cards.append(placeCard(current, tone: .orange, tag: "\(short(current.name)) · agora", region: region, time: time))
        }
        if let next, next.id != current?.id {
            cards.append(placeCard(next, tone: .white, tag: "\(short(next.name)) · \(time(next.at))", region: region, time: time))
        }
        let anytime = country.tips.filter { $0.moment == .anytime }
        if let fact = anytime.first {
            cards.append(Card(id: fact.id, tone: .ink, tag: "sabia que", corner: country.name, title: fact.title, detail: fact.detail,
                              filters: tipFilters(fact, today: true)))
        }
        let moment = PocketRules.moment(at: now, region: region)
        if let tip = country.tips.first(where: { $0.moment == moment && moment != .back }) {
            cards.append(Card(id: tip.id, tone: .white, tag: tip.moment.label, corner: country.name, title: tip.title, detail: tip.detail,
                              filters: tipFilters(tip, today: true)))
        }
        if let night, night.id != current?.id, night.id != next?.id {
            cards.append(placeCard(night, tone: .white, tag: "\(short(night.name)) · \(time(night.at))", region: region, time: time,
                                   corner: "noite"))
        } else if moment != .night, let tip = country.tips.first(where: { $0.moment == .night }) {
            cards.append(Card(id: tip.id, tone: .white, tag: "noite", corner: country.name, title: tip.title, detail: tip.detail,
                              filters: tipFilters(tip, today: true)))
        }
        let back = country.tips.first { $0.moment == .back }
        if let lastTrain {
            cards.append(Card(id: "volta", tone: .white, tag: "volta · \(lastTrain.time)", corner: "trem",
                              title: "Último \(lastTrain.line) sai \(lastTrain.time)",
                              detail: back?.detail ?? "Confira o horário antes de sair.", filters: [.now]))
        } else if let back {
            cards.append(Card(id: back.id, tone: .white, tag: "volta", corner: "trem", title: back.title, detail: back.detail,
                              filters: tipFilters(back, today: true)))
        }

        // O resto do país (filtros País e Etiqueta), sem repetir o que já entrou.
        let used = Set(cards.map(\.id))
        for tip in country.tips where !used.contains(tip.id) {
            cards.append(Card(id: tip.id, tone: tip.moment == .anytime ? .ink : .white,
                              tag: tip.moment == .anytime ? "sabia que" : tip.moment.label, corner: country.name,
                              title: tip.title, detail: tip.detail, filters: tipFilters(tip, today: false)))
        }
        return cards.map { card in
            var card = card
            if saved.contains(card.id) { card.filters.insert(.saved) }
            return card
        }
    }

    static func filtered(_ cards: [Card], by filter: Filter) -> [Card] {
        cards.filter { $0.filters.contains(filter) }
    }

    // MARK: Lugar

    static func placeCard(_ stop: Stop, tone: PocketTone, tag: String, region: Region, time: (Date) -> String,
                          corner: String? = nil) -> Card {
        let (title, detail, kindCorner) = placeTip(stop, region: region, time: time)
        var filters: Set<Filter> = [.now]
        if stop.inArea { filters.insert(.area) }
        return Card(id: "stop-\(stop.id)", tone: tone, tag: tag, corner: corner ?? kindCorner, title: title, detail: detail,
                    filters: filters, placeId: stop.placeId)
    }

    /// Título, detalhe e rótulo da dica de um lugar.
    static func placeTip(_ stop: Stop, region: Region, time: (Date) -> String) -> (String, String, String) {
        let sentences = stop.notes.split(whereSeparator: { ".\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let cash = PocketRules.cashOnly(notes: stop.notes)
        var detailParts: [String] = []
        if cash { detailParts.append("Só cash.") }
        var title: String
        var corner = stop.kind == .photo ? "golden" : (stop.queueMinutes ?? 0 > 0 ? "fila" : (cash ? "cash" : "dica"))
        let ramen = region.profile.day?.ramenTips == true && [stop.sub, stop.name, stop.notes].compactMap { $0 }.joined(separator: " ")
            .range(of: "ramen|tsukemen", options: [.caseInsensitive, .regularExpression]) != nil

        if stop.kind == .photo, let golden = stop.golden {
            title = stop.closesAt.map { "Fecha \($0), e o golden é \(time(golden))" } ?? "O golden começa \(time(golden))"
            detailParts.append(contentsOf: sentences.prefix(2).map { $0 + "." })
        } else if ramen && (stop.queueMinutes ?? 0) > 0 {
            title = "Compre o ticket na máquina antes de entrar na fila"
            detailParts.append(contentsOf: sentences.prefix(1).map { $0 + "." })
        } else if let order = PlacePanelChoice.orderHint(notes: stop.notes) {
            title = order
            corner = "pedir"
            detailParts.append(contentsOf: sentences.filter { $0 != order }.prefix(2).map { $0 + "." })
        } else if let first = sentences.first(where: { $0.count >= 14 }) {
            title = first
            detailParts.append(contentsOf: sentences.filter { $0 != first }.prefix(1).map { $0 + "." })
        } else if let q = stop.queueMinutes, q > 0 {
            title = "Fila de ~\(q) min: chegue antes de abrir"
        } else {
            title = sentences.first ?? "Chegue com tempo e veja o horário"
        }
        if let q = stop.queueMinutes, q > 0, stop.kind != .photo { detailParts.append("Fila anda em ~\(q) min.") }
        if let people = stop.peopleTip, !people.isEmpty, detailParts.count < 3 { detailParts.append("“\(people.prefix(110))”") }
        return (title, detailParts.joined(separator: " "), corner)
    }

    /// "Fuunji · tsukemen" → "Fuunji"; "Shinjuku Gyoen" → "Gyoen" (o nome do bairro não ajuda na etiqueta).
    static func short(_ name: String) -> String {
        let base = String(name.split(separator: "·").first ?? Substring(name)).trimmingCharacters(in: .whitespaces)
        let words = base.split(separator: " ")
        if words.count == 2, ["shinjuku", "shibuya", "tokyo", "kyoto", "roma"].contains(words[0].lowercased()) { return String(words[1]) }
        return base
    }

    private static func tipFilters(_ tip: CountryTip, today: Bool) -> Set<Filter> {
        var set: Set<Filter> = [.country]
        if today { set.insert(.now) }
        if tip.etiquette { set.insert(.etiquette) }
        return set
    }
}
