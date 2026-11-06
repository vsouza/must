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
                    Micro("cole o texto")
                    Spacer()
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        model.text = text
                    }
                    .labelStyle(.titleOnly)
                    .buttonBorderShape(.capsule)
                    .tint(Color.must.ink)
                }
                TextField("cola a resposta da IA, a lista do WhatsApp ou uma nota", text: $model.text, axis: .vertical)
                    .accessibilityIdentifier("colar.text")
                    .font(.must.serif(18))
                    .lineLimit(6...18)
            }
            .padding(18)
            .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))

            Text("Lugar, dia, dica e link aparecem marcados antes de salvar. O texto fica no aparelho.")
                .font(.must.meta)
                .foregroundStyle(Color.must.secondary)

            PrimaryButton("Ler texto", icon: .avancar, iconTrailing: true, style: .dark) {
                Task { await model.analyze(model.text, env: env) }
            }
            .disabled(emptyText)
            .opacity(emptyText ? 0.4 : 1)
        }
    }

    private var reading: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Lendo o texto…").font(.must.meta).foregroundStyle(Color.must.secondary)
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
                Micro(sourceHeader)
                Spacer()
                Button { model.edit() } label: {
                    Text("trocar")
                        .font(.must.archivo(13, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                }
                .buttonStyle(MustPressStyle())
            }
            Text(ColarTextoHighlight.attributed(model.shown, from: start, spans: model.spans()))
                .font(.must.archivo(15))
                .lineSpacing(4)
                .foregroundStyle(Color.must.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(maxHeight: textOpen ? nil : Self.collapsedHeight, alignment: .top)
                .clipped()
                .mask { Rectangle().fill(fade(open: textOpen || !long)) }
                .overlay(alignment: .bottomTrailing) {
                    if long && !textOpen {
                        Button { textOpen = true } label: {
                            Text("ver tudo")
                                .font(.must.archivo(13, .semibold))
                                .foregroundStyle(Color.must.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(.white))
                                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
        }
        .padding(18)
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
                Text("\(number)").font(.must.archivo(24, .bold))
                Text(label).font(.must.archivo(12))
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
                .foregroundStyle(Color.must.ink)
            VStack(alignment: .leading, spacing: 3) {
                Text(waiting == 1 ? "Sem internet · 1 esperando internet" : "Sem internet · \(waiting) esperando internet")
                    .font(.must.archivo(14, .semibold))
                Text("A conferência no Places fica na fila e sai quando a rede voltar. Dá pra salvar já.")
                    .font(.must.meta)
                    .foregroundStyle(Color.must.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                    StationStamp(seal.text, sub: seal.sub ?? group.number.map { "dia \($0)" }, size: 52, surface: .paper, rotation: -8)
                }
                Text(group.id >= 0 ? "\(group.title) · dia sugerido" : group.title)
                    .font(.must.archivo(17, .semibold))
                    .foregroundStyle(Color.must.ink)
                    .lineLimit(2)
                    .onTapGesture { if group.id >= 0 { model.focus(group.id) } }
                Spacer(minLength: 4)
                if group.id >= 0, let number = group.number {
                    let on = model.dayOn.contains(group.id)
                    Button { model.toggleDay(group.id) } label: {
                        Text(on ? "virar dia \(number)" : "não vira dia")
                            .font(.must.archivo(12, .semibold))
                            .foregroundStyle(on ? Color.must.ink : Color.must.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.must.surface))
                    }
                    .buttonStyle(MustPressStyle())
                }
            }
            Rectangle().fill(Color.must.line).frame(height: 1).padding(.vertical, 10)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, match in
                if index > 0 { Rectangle().fill(Color.must.line).frame(height: 1) }
                row(match)
            }
            if !open, !hidden.isEmpty {
                Rectangle().fill(Color.must.line).frame(height: 1)
                Button { model.toggleExpanded(group.id) } label: {
                    HStack(spacing: 12) {
                        Circle().strokeBorder(Color.must.lineStrong, lineWidth: 1.5).frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("+ " + hidden.map { $0.extracted.name }.joined(separator: ", "))
                                .font(.must.archivo(15))
                                .foregroundStyle(Color.must.secondary)
                                .lineLimit(1)
                            Text("\(hidden.count) mais · toque pra ver").font(.must.meta).foregroundStyle(Color.must.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(MustPressStyle())
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
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
                    Circle().fill(on ? Color.must.green : Color.white)
                    Circle().strokeBorder(Color.must.lineStrong, lineWidth: on ? 0 : 1.5)
                    if on { MustIconView(.ok, size: 13).foregroundStyle(Color.must.greenText) }
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(MustPressStyle())
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(match.extracted.name)
                        .font(.must.archivo(17, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .strikethrough(model.placesChecked && !match.located)
                        .lineLimit(1)
                    if let chip = chip(for: match) {
                        Text(chip.text)
                            .font(.must.archivo(11, .semibold))
                            .foregroundStyle(chip.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(chip.fill))
                            .lineLimit(1)
                    }
                }
                Text(meta(match))
                    .font(.must.archivo(13))
                    .foregroundStyle(Color.must.secondary)
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
            Micro("links")
            ForEach(model.linkStatus.keys.sorted(), id: \.self) { link in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(link.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                        .font(.must.mono(12))
                        .foregroundStyle(Color.must.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(model.linkStatus[link] ?? "")
                        .font(.must.archivo(12))
                        .foregroundStyle(Color.must.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.must.line))
    }

    private func tipsCard(_ tips: [TravelTip]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xFFE3A3))
                    Image(systemName: "lightbulb.fill").foregroundStyle(Color(hex: 0x4A2E00))
                }
                .frame(width: 36, height: 36)
                Text("Dicas · vão pras notas").font(.must.archivo(17, .semibold)).foregroundStyle(Color.must.ink)
            }
            ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                Text("“\(tip.text)” → \(destination(tip))")
                    .font(.must.archivo(14))
                    .foregroundStyle(Color.must.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
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
            Button { save(withDays: false) } label: {
                Text("Só salvar")
                    .font(.must.archivo(15, .bold))
                    .foregroundStyle(Color.must.ink)
                    .frame(width: 116, height: 52)
                    .overlay(Capsule().strokeBorder(Color.must.lineStrong, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(MustPressStyle())
            .disabled(count == 0)
            PrimaryButton(title(count: count, days: days), style: .dark) {
                save(withDays: !days.isEmpty)
            }
            .disabled(count == 0)
        }
        .opacity(count == 0 ? 0.5 : 1)
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .center).ignoresSafeArea()
        }
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
