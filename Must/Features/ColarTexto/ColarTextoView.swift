import SwiftData
import SwiftUI

/// "Texto" do Adicionar (ColarTexto.png, prompt 18 · E.22): o texto recolhido com o que foi achado marcado, os
/// contadores, o dia sugerido com o selo do bairro, as dicas. Os botões ficam fixos embaixo (`ColarTextoActions`).
struct ColarTextoView: View {
    @Bindable var model: ColarTextoModel
    let env: ColarContext
    /// Itens esperando internet (todos os fluxos da fila de saída).
    let waiting: Int

    /// Recolhido: ~200 pt a partir do dia em foco; "ver tudo" abre o texto inteiro.
    @State private var textOpen = false
    private static let collapsedHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.phase {
            case .editing: editor
            case .reading: reading
            case .done: result
            }
        }
        .onAppear { TravelTextExtractor.prewarm() }
    }

    private var emptyText: Bool {
        model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Entrada

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    J9Label("cole o texto")
                    Spacer()
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        model.text = text
                    }
                    .labelStyle(.titleOnly)
                    .buttonBorderShape(.capsule)
                    .tint(Color.primary)
                }
                TextField("cola a resposta da IA, a lista do WhatsApp ou uma nota", text: $model.text, axis: .vertical)
                    .accessibilityIdentifier("colar.text")
                    .font(.body)
                    .lineLimit(6...18)
            }
            .padding(18)
            .background(V9.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            Text("Lugar, dia, dica e link aparecem marcados antes de salvar. O texto fica no aparelho.")
                .font(.footnote)
                .foregroundStyle(Color.secondary)

            J9Button("Ler texto") {
                Task { await model.analyze(model.text, env: env) }
            }
            .disabled(emptyText)
            .opacity(emptyText ? 0.4 : 1)
        }
    }

    private var reading: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Lendo o texto…").font(.footnote).foregroundStyle(Color.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 26)
    }

    // MARK: Resultado

    private var result: some View {
        VStack(alignment: .leading, spacing: 16) {
            sourceCard
            counters
            if model.queued { queuedBanner }
            ForEach(model.groups) { group in
                groupCard(group)
            }
            if !model.linkStatus.isEmpty { linksCard }
            if let draft = model.draft, !draft.tips.isEmpty { tipsCard(draft.tips) }
        }
    }

    /// O texto colado, com o que foi achado marcado. Recolhido, mostra a partir do dia em foco, com fade.
    private var sourceCard: some View {
        let start = textOpen ? nil : model.snippetStart()
        let rest = start.map { model.shown[$0...] } ?? Substring(model.shown)
        let long = rest.count > 260
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                J9Label(sourceHeader)
                Spacer()
                Button { model.edit() } label: {
                    Text("trocar")
                        .font(J9.font(13, .semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(V9.card))
                }
                .buttonStyle(.plain)
            }
            Text(ColarTextoHighlight.attributed(model.shown, from: start, spans: model.spans()))
                .font(J9.font(15))
                .lineSpacing(4)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: textOpen ? nil : Self.collapsedHeight, alignment: .top)
                .clipped()
                .mask { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fade(open: textOpen || !long)) }
                .overlay(alignment: .bottomTrailing) {
                    if long && !textOpen {
                        Button { textOpen = true } label: {
                            Text("ver tudo")
                                .font(J9.font(13, .semibold))
                                .foregroundStyle(Color.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(V9.card))
                                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
        }
        .padding(18)
        .background(V9.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// Cabeçalho: "COLADO · CHATGPT · 1.840 CAR." (a origem só quando o texto diz).
    private var sourceHeader: String {
        [ "colado", model.origin, ColarTextoModel.grouped(model.text.count) + " car." ]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Última linha esmaecida: o texto some aos poucos embaixo do card recolhido.
    private func fade(open: Bool) -> LinearGradient {
        LinearGradient(stops: open
                       ? [.init(color: .black, location: 0), .init(color: .black, location: 1)]
                       : [.init(color: .black, location: 0), .init(color: .black, location: 0.7), .init(color: .black.opacity(0.3), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// Cinco contadores; em telas estreitas a faixa rola na horizontal.
    private var counters: some View {
        let c = model.counts
        let tiles = [
            CounterTile(number: c.eat, label: "comer", fill: 0xB9F5CF, ink: 0x0B2A18),
            CounterTile(number: c.see, label: "ver", fill: 0xDCCFFF, ink: 0x2E1065),
            CounterTile(number: c.drink, label: "beber", fill: 0x9FD6FF, ink: 0x0F3B8C),
            CounterTile(number: c.links, label: "links", fill: 0x121316, ink: 0xFFFFFF),
            CounterTile(number: c.tips, label: "dicas", fill: 0xFFE3A3, ink: 0x4A2E00),
        ]
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(tiles, id: \.label) { $0.frame(maxWidth: .infinity) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tiles, id: \.label) { $0.frame(width: 84) }
                }
            }
        }
    }

    private struct CounterTile: View {
        var number: Int
        var label: String
        var fill: UInt32
        var ink: UInt32
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(number)").font(J9.font(24, .bold))
                Text(label).font(J9.font(12))
            }
            .foregroundStyle(Color(hex: ink))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .frame(height: 66)
            .background(Color(hex: fill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var queuedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(Color.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(waiting == 1 ? "Sem internet · 1 esperando internet" : "Sem internet · \(waiting) esperando internet")
                    .font(J9.font(14, .semibold))
                Text("A conferência no Places fica na fila e sai quando a rede voltar. Dá pra salvar já.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V9.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Dias

    /// Cartão do dia sugerido: selo do bairro, "<área> · dia sugerido", "virar dia N", os lugares com check.
    private func groupCard(_ group: ColarTextoModel.Group) -> some View {
        let limit = ColarTextoModel.visibleLimit
        let open = model.expanded.contains(group.id)
        let rows = open ? group.matches : Array(group.matches.prefix(limit))
        let hidden = Array(group.matches.dropFirst(limit))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if group.id >= 0 {
                    let seal = stamp(for: group)
                    // Kanji do bairro do dia; sem linha própria no catálogo, a linha pequena diz o número ("dia 2").
                    Text(seal.text).font(.footnote.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(V9.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(group.id >= 0 ? "\(group.title) · dia sugerido" : group.title)
                    .font(J9.font(17, .semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .onTapGesture { if group.id >= 0 { model.focus(group.id) } }
                Spacer(minLength: 4)
                if group.id >= 0, let number = group.number {
                    let on = model.dayOn.contains(group.id)
                    Button { model.toggleDay(group.id) } label: {
                        Text(on ? "virar dia \(number)" : "não vira dia")
                            .font(J9.font(12, .semibold))
                            .foregroundStyle(on ? Color.primary : Color.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(V9.card))
                    }
                    .buttonStyle(.plain)
                }
            }
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1).padding(.vertical, 10)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, match in
                if index > 0 { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1) }
                row(match)
            }
            if !open, !hidden.isEmpty {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1)
                Button { model.toggleExpanded(group.id) } label: {
                    HStack(spacing: 12) {
                        Circle().strokeBorder(Color(uiColor: .separator), lineWidth: 1.5).frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("+ " + hidden.map { $0.extracted.name }.joined(separator: ", "))
                                .font(J9.font(15))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                            Text("\(hidden.count) mais · toque pra ver").font(.footnote).foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(V9.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color(uiColor: .separator)))
        .shadow(color: Color(hex: 0x121316, opacity: 0.06), radius: 15, x: 0, y: 10)
    }

    /// Selo do dia: o selo do bairro no catálogo (kanji no Japão, sigla no BH); sem bairro, o número do dia.
    private func stamp(for group: ColarTextoModel.Group) -> (text: String, sub: String?) {
        let areas = AreaCatalog.areas(for: env.region)
        let parts = group.title.components(separatedBy: CharacterSet(charactersIn: ",/")).flatMap { $0.components(separatedBy: " e ") }
        for part in parts {
            let key = AreaName.key(part)
            guard !key.isEmpty else { continue }
            if let area = areas.first(where: { AreaName.key($0.name) == key || $0.aliases.contains { AreaName.key($0) == key } }) {
                return (area.seal, area.stampSub)
            }
        }
        return (group.number.map(String.init) ?? "·", "dia")
    }

    private func row(_ match: MatchedPlace) -> some View {
        let on = model.included.contains(match.id)
        return HStack(alignment: .center, spacing: 12) {
            Button { model.toggle(match.id) } label: {
                ZStack {
                    Circle().fill(on ? V9.accent : V9.fill)
                    if on { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
                }
                .frame(width: 28, height: 28)
                .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(match.extracted.name)
                        .font(J9.font(17, .semibold))
                        .foregroundStyle(Color.primary)
                        .strikethrough(model.placesChecked && !match.located)
                        .lineLimit(1)
                    if let chip = chip(for: match) {
                        Text(chip.text)
                            .font(J9.font(11, .semibold))
                            .foregroundStyle(chip.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(chip.fill))
                            .lineLimit(1)
                    }
                }
                Text(meta(match))
                    .font(J9.font(13))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .opacity(model.placesChecked && !match.located && !on ? 0.5 : 1)
    }

    /// "see · templo": a categoria em inglês (como no design) e a sub-lista, se houver.
    private func chip(for match: MatchedPlace) -> (text: String, fill: Color, ink: Color)? {
        guard let category = match.extracted.category else { return nil }
        let text = [category.rawValue, match.extracted.sub?.lowercased()].compactMap { $0 }.joined(separator: " · ")
        let (fill, ink) = Self.chipColors(category)
        return (text, fill, ink)
    }

    private func meta(_ match: MatchedPlace) -> String {
        var parts: [String] = [match.existing != nil ? "no board" : "novo"]
        if !model.placesChecked {
            parts.append("a conferir no Places")
        } else if !match.located {
            parts.append("não achei no mapa")
        }
        if let tip = model.tips(for: match).first {
            let short = tip.text.count > 48 ? String(tip.text.prefix(48)) + "…" : tip.text
            parts.append("dica: \(short)")
        }
        if match.extracted.mentions > 1 { parts.append("juntei \(match.extracted.mentions) menções") }
        return parts.joined(separator: " · ")
    }

    private static func chipColors(_ category: MustColor) -> (Color, Color) {
        switch category {
        case .eat: (Color(hex: 0xB9F5CF), Color(hex: 0x0B2A18))
        case .drink: (Color(hex: 0x9FD6FF), Color(hex: 0x0F3B8C))
        case .coffee: (Color(hex: 0xFFD2BF), Color(hex: 0x5A2200))
        case .see, .art, .photo: (Color(hex: 0xDCCFFF), Color(hex: 0x2E1065))
        case .temple: (Color(hex: 0xB8F2EA), Color(hex: 0x063F3A))
        case .listen: (Color(hex: 0xFFC6DA), Color(hex: 0x5A0F2E))
        case .shop: (Color(hex: 0xFFE3A3), Color(hex: 0x4A2E00))
        case .night: (Color(hex: 0xC9D2FF), Color(hex: 0x161C66))
        case .sport: (Color(hex: 0xDCCFFF), Color(hex: 0x2E1065))
        }
    }

    // MARK: Links e dicas

    private var linksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            J9Label("links")
            ForEach(model.linkStatus.keys.sorted(), id: \.self) { link in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(link.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                        .font(J9.font(12).monospacedDigit())
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(model.linkStatus[link] ?? "")
                        .font(J9.font(12))
                        .foregroundStyle(Color.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(V9.card))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(uiColor: .separator)))
    }

    private func tipsCard(_ tips: [TravelTip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xFFE3A3))
                    Image(systemName: "lightbulb.fill").foregroundStyle(Color(hex: 0x4A2E00))
                }
                .frame(width: 36, height: 36)
                Text("Dicas · vão pras notas").font(J9.font(17, .semibold)).foregroundStyle(Color.primary)
            }
            ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                Text("“\(tip.text)” → \(destination(tip))")
                    .font(J9.font(14))
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(V9.card))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color(uiColor: .separator)))
    }

    private func destination(_ tip: TravelTip) -> String {
        switch tip.target {
        case .wallet: "Carteira"
        case .place(let name): "nota de \(name)"
        case .general: "nota do dia"
        }
    }
}

/// Botões do Colar texto, fixos embaixo do Adicionar (`safeAreaInset`, com fade branco): "Só salvar" e
/// "Adicionar N e criar dia K" (ou "Adicionar N lugares" quando não há dia).
struct ColarTextoActions: View {
    @Bindable var model: ColarTextoModel
    let env: ColarContext
    let sync: SyncCoordinator
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        let count = model.included.count
        let days = model.dayNumbersOn
        HStack(spacing: 10) {
            Button("Só salvar") { save(withDays: false) }
                .v9Secondary()
                .disabled(count == 0)
            J9Button(title(count: count, days: days)) {
                save(withDays: !days.isEmpty)
            }
            .disabled(count == 0)
        }
        .opacity(count == 0 ? 0.5 : 1)
        .padding(V9.gutter)
        .background(.bar)
    }

    private func title(count: Int, days: [Int]) -> String {
        if count == 0 { return "Marque um lugar" }
        guard let first = days.first else { return count == 1 ? "Adicionar 1 lugar" : "Adicionar \(count) lugares" }
        return days.count == 1 ? "Adicionar \(count) e criar dia \(first)" : "Adicionar \(count) e criar \(days.count) dias"
    }

    private func save(withDays: Bool) {
        model.save(env: env, sync: sync, context: context, withDays: withDays)
        onSaved()
    }
}
