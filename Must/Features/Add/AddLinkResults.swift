import SwiftUI

/// Depois de ler o link: fonte compacta, mapa com os pinos, "Lista" e a lista de lugares (sem empilhar).
struct AddLinkResults: View {
    @Bindable var model: AddLinkModel
    let lists: [MustList]
    let region: Region

    var body: some View {
        let layout = LinkMapLayout.make(matches: model.matches, region: region, transit: TransitLoader.load(region))
        VStack(alignment: .leading, spacing: 14) {
            sourceCard
            LinkPlacesMap(layout: layout, selectedId: model.selectedId, region: region) { id in
                model.selectedId = id
            }
            listLine
            resultList(layout)
        }
    }

    // MARK: Fonte

    private var source: LinkSource { model.resolved?.source ?? .text }

    private var headline: String {
        let base = switch source {
        case .instagram: "Reel"
        case .tiktok: "TikTok"
        case .youtube: "Vídeo"
        case .maps: "Maps"
        case .web: "Link"
        case .text: "Texto"
        }
        let label = model.videoText != nil && source == .text ? "Vídeo" : base
        let raw = model.videoText != nil ? "" : (model.caption?.title ?? model.caption?.text.components(separatedBy: .newlines).first ?? "")
        let title = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        return title.isEmpty ? label : "\(label) · “\(title)”"
    }

    private var summary: String {
        let n = model.matches.count
        let base = n == 1 ? "1 lugar" : "\(n) lugares"
        guard model.placesChecked else { return "\(base) · sem conferir no Places" }
        let located = model.matches.filter(\.located).count
        return "\(base) · \(located) \(located == 1 ? "conferido" : "conferidos") no Places"
    }

    private var sourceCard: some View {
        HStack(spacing: 10) {
            if let badge = source.badge {
                Text(badge)
                    .font(J9.font(10, .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(V9.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(headline).font(J9.font(13, .semibold)).foregroundStyle(Color.primary).lineLimit(1)
                Text(summary).font(J9.font(11.5)).foregroundStyle(Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { model.reset() } label: {
                Text("Trocar")
                    .font(J9.font(13, .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(V9.card))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(V9.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Lista

    private var batchLabel: String {
        let id = model.sharedListId ?? model.includedMatches.compactMap { model.listChoice[$0.id] }.first
        guard let id, let list = lists.first(where: { $0.id == id }) else { return "escolher lista" }
        let sub = model.includedMatches.first?.extracted.sub
        return list.displayName + (sub.map { " · \($0)" } ?? "")
    }

    /// "Lista · [Must eat · Mercado] · um por lugar…": a pílula verde escolhe pra todos os marcados.
    private var listLine: some View {
        HStack(spacing: 8) {
            Text("Lista").font(J9.font(12)).foregroundStyle(Color.secondary)
            Menu {
                ForEach(lists) { list in
                    Button(list.displayName) { model.setList(list.id) }
                }
            } label: {
                J9Chip(batchLabel, prominent: true)
            }
            Button { model.perPlaceLists.toggle() } label: {
                J9Chip("um por lugar…", isOn: model.perPlaceLists)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func resultList(_ layout: LinkMapLayout) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(model.matches.enumerated()), id: \.element.id) { index, match in
                if index > 0 { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(uiColor: .separator)).frame(height: 1) }
                row(match, number: layout.number(for: match.id))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(V9.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(uiColor: .separator)))
    }

    private func row(_ match: MatchedPlace, number: Int?) -> some View {
        let on = model.included.contains(match.id)
        let selected = model.selectedId == match.id
        return HStack(alignment: .center, spacing: 12) {
            numberBadge(number, selected: selected)
            // Foto do lugar que já está no board (prompt 19). Lugar novo ainda não tem foto: gradiente até salvar e sincronizar.
            PlaceThumb(placeId: match.existing?.placeId, refs: match.existing?.photoRefs ?? [],
                       color: match.existing?.list?.color ?? .eat, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(match.existing?.name ?? match.extracted.name)
                        .font(J9.font(16, .semibold))
                        .foregroundStyle(Color.primary)
                        .strikethrough(!match.located)
                        .lineLimit(1)
                    if let local = match.extracted.nameLocal ?? match.existing?.nameLocal {
                        Text(local).font(.footnote).foregroundStyle(Color.secondary).lineLimit(1)
                    }
                }
                Text(meta(match)).font(J9.font(12)).foregroundStyle(Color.secondary).lineLimit(1)
                if model.perPlaceLists && match.existing == nil && on { listChip(match) }
            }
            Spacer(minLength: 4)
            trailing(match, on: on)
        }
        .padding(.vertical, 12)
        .opacity(!match.located && !on ? 0.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.selectedId = match.id }
    }

    private func numberBadge(_ number: Int?, selected: Bool) -> some View {
        Text(number.map(String.init) ?? "–")
            .font(J9.font(12, .semibold).monospacedDigit())
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(selected ? V9.accent : V9.fill))
    }

    @ViewBuilder private func trailing(_ match: MatchedPlace, on: Bool) -> some View {
        if match.existing != nil {
            tag("no board", fill: V9.card)
        } else if !match.located {
            Button {
                model.toggle(match.id)
            } label: {
                if on {
                    checkDisc(on: true)
                } else {
                    tag("manter", fill: V9.fill)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button { model.toggle(match.id) } label: { checkDisc(on: on) }
                .buttonStyle(.plain)
        }
    }

    private func checkDisc(on: Bool) -> some View {
        ZStack {
            Circle().fill(on ? V9.accent : V9.fill)
            if on { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white) }
        }
        .frame(width: 28, height: 28)
        .frame(minWidth: 44, minHeight: 44)
    }

    private func tag(_ text: String, fill: Color, stroke: Bool = false) -> some View {
        Text(text)
            .font(J9.font(12, .semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(stroke ? Color(uiColor: .separator) : .clear))
    }

    /// Seletor de lista da linha (só no modo "um por lugar…").
    private func listChip(_ match: MatchedPlace) -> some View {
        let current = lists.first { $0.id == model.listChoice[match.id] }
        return Menu {
            ForEach(lists) { list in
                Button(list.displayName) { model.setList(list.id, for: match.id) }
            }
        } label: {
            Text(current?.displayName ?? "escolher lista")
                .font(J9.font(11, .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(V9.card))
        }
    }

    /// "mercado · 05:00–14:00 · juntei 2 menções": categoria (ou sub), horário de hoje, preço, menções.
    private func meta(_ match: MatchedPlace) -> String {
        let e = match.extracted
        var parts: [String] = []
        if !match.located { parts.append("não achei no mapa") }
        parts.append((e.sub ?? Self.categoryLabel(e.category)).lowercased())
        if let origin = model.videoOrigins[match.id] { parts.append(origin.label) }
        if let hours = match.details?.hours?.todayText(AppClock.now, timeZone: region.timeZone) { parts.append(hours) }
        if let price = match.details?.priceFrom, let currency = match.details?.priceCurrency {
            parts.append(price.formatted(.money(currency)))
        }
        if e.mentions > 1 { parts.append("juntei \(e.mentions) menções") }
        return parts.joined(separator: " · ")
    }

    static func categoryLabel(_ color: MustColor?) -> String {
        guard let color else { return "lugar" }
        switch color {
        case .eat: return "restaurante"
        case .drink: return "bar"
        case .coffee: return "café"
        case .see: return "ver"
        case .temple: return "templo"
        case .listen: return "música"
        case .shop: return "loja"
        case .night: return "noite"
        case .photo: return "foto"
        case .art: return "arte"
        case .sport: return "esporte"
        }
    }
}
