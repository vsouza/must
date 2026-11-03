import SwiftData
import SwiftUI

/// "Texto" do Adicionar (ColarTexto.png, prompt 18 · E.22): cola a resposta da IA, o texto marca o que achou, os lugares
/// vêm por dia sugerido e as dicas vão pras notas ou pra Carteira. Dentro do Adicionar, abaixo do seletor Link · Texto · Nome.
struct ColarTextoView: View {
    @Bindable var model: ColarTextoModel
    let env: ColarContext
    let sync: SyncCoordinator
    /// Itens esperando internet (todos os fluxos da fila de saída).
    let waiting: Int
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context

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
            actions
        }
    }

    /// O texto como foi colado, com o que foi achado marcado por cor.
    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Micro("colado · \(model.text.count) car.")
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
            Text(ColarTextoHighlight.attributed(model.shown, spans: model.spans()))
                .font(.must.archivo(16))
                .lineSpacing(5)
                .foregroundStyle(Color.must.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var counters: some View {
        let c = model.counts
        return HStack(spacing: 8) {
            counterTile("\(c.eat)", "comer", fill: 0xB9F5CF, ink: 0x0B2A18)
            counterTile("\(c.see)", "ver", fill: 0xDCCFFF, ink: 0x2E1065)
            counterTile("\(c.drink)", "beber", fill: 0x9FD6FF, ink: 0x0F3B8C)
            counterTile("\(c.links)", "links", fill: 0x121316, ink: 0xFFFFFF)
            counterTile("\(c.tips)", "dicas", fill: 0xFFE3A3, ink: 0x4A2E00)
        }
    }

    private func counterTile(_ number: String, _ label: String, fill: UInt32, ink: UInt32) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(number).font(.must.archivo(24, .bold))
            Text(label).font(.must.archivo(12))
        }
        .foregroundStyle(Color(hex: ink))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(height: 66)
        .background(Color(hex: fill), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func groupCard(_ group: ColarTextoModel.Group) -> some View {
        let limit = ColarTextoModel.visibleLimit
        let open = model.expanded.contains(group.id)
        let rows = open ? group.matches : Array(group.matches.prefix(limit))
        let hidden = Array(group.matches.dropFirst(limit))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Text(group.id >= 0 ? "\(group.title) · dia sugerido" : group.title)
                    .font(.must.archivo(16, .semibold))
                    .foregroundStyle(Color.must.ink)
                    .lineLimit(2)
                Spacer(minLength: 6)
                if group.id >= 0, let number = group.number {
                    let on = model.dayOn.contains(group.id)
                    Button { model.toggleDay(group.id) } label: {
                        Text(on ? "virar dia \(number)" : "não vira dia")
                            .font(.must.archivo(12, .semibold))
                            .foregroundStyle(on ? Color.white : Color.must.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(on ? Color.must.ink : Color.must.surface))
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
                                .lineLimit(2)
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
                        .font(.must.archivo(16, .semibold))
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
                    .font(.must.archivo(12.5))
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
                Text("Dicas · vão pras notas").font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
            }
            ForEach(Array(tips.enumerated()), id: \.offset) { _, tip in
                Text("“\(tip.text)” → \(destination(tip))")
                    .font(.must.archivo(13.5))
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

    // MARK: Ações

    private var actions: some View {
        let count = model.included.count
        let days = model.dayNumbersOn
        let title: String = {
            if count == 0 { return "Marque um lugar" }
            guard let first = days.first else { return count == 1 ? "Adicionar 1 lugar" : "Adicionar \(count) lugares" }
            return days.count == 1 ? "Adicionar \(count) e criar dia \(first)" : "Adicionar \(count) e criar \(days.count) dias"
        }()
        return VStack(spacing: 10) {
            PrimaryButton(title, icon: .ok, iconTrailing: true, style: .dark) {
                save(withDays: !days.isEmpty)
            }
            .disabled(count == 0)
            .opacity(count == 0 ? 0.5 : 1)
            Button { save(withDays: false) } label: {
                Text("Só salvar")
                    .font(.must.archivo(15, .bold))
                    .foregroundStyle(Color.must.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .overlay(Capsule().strokeBorder(Color.must.lineStrong, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(MustPressStyle())
            .disabled(count == 0)
            .opacity(count == 0 ? 0.5 : 1)
        }
    }

    private func save(withDays: Bool) {
        model.save(env: env, sync: sync, context: context, withDays: withDays)
        onSaved()
    }
}
