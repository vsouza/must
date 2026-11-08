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
                    .font(.must.mono(10, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Rectangle().fill(Color.must.ink))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(headline).font(.must.archivo(13, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                Text(summary).font(.must.archivo(11.5)).foregroundStyle(Color.must.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { model.reset() } label: {
                Text("Trocar")
                    .font(.must.archivo(13, .semibold))
                    .foregroundStyle(Color.must.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Rectangle().fill(.white))
            }
            .buttonStyle(MustPressStyle())
        }
        .padding(12)
        .background(Color.must.surface, in: Rectangle())
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
            Text("Lista").font(.must.archivo(12)).foregroundStyle(Color.must.secondary)
            Menu {
                ForEach(lists) { list in
                    Button(list.displayName) { model.setList(list.id) }
                }
            } label: {
                Pill(batchLabel, style: .green)
            }
            Button { model.perPlaceLists.toggle() } label: {
                Pill("um por lugar…", style: model.perPlaceLists ? .dark : .default)
            }
            .buttonStyle(MustPressStyle())
            Spacer(minLength: 0)
        }
    }

    private func resultList(_ layout: LinkMapLayout) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(model.matches.enumerated()), id: \.element.id) { index, match in
                if index > 0 { Rectangle().fill(Color.must.line).frame(height: 1) }
                row(match, number: layout.number(for: match.id))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 2)
        .background(Rectangle().fill(Color.white))
        .overlay(Rectangle().strokeBorder(Color.must.line))
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
                        .font(.must.archivo(16, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .strikethrough(!match.located)
                        .lineLimit(1)
                    if let local = match.extracted.nameLocal ?? match.existing?.nameLocal {
                        Text(local).font(.must.kanji(11, bold: false)).foregroundStyle(Color.must.secondary).lineLimit(1)
                    }
                }
                Text(meta(match)).font(.must.archivo(12)).foregroundStyle(Color.must.secondary).lineLimit(1)
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
            .font(.must.mono(12, .semibold))
            .foregroundStyle(number == nil ? Color.must.secondary : (selected ? Color.must.greenText : .white))
            .frame(width: 28, height: 28)
            .background(Rectangle().fill(number == nil ? Color.must.surface : (selected ? Color.must.green : Color.must.ink)))
    }

    @ViewBuilder private func trailing(_ match: MatchedPlace, on: Bool) -> some View {
        if match.existing != nil {
            tag("no board", fill: Color.must.surface)
        } else if !match.located {
            Button {
                model.toggle(match.id)
            } label: {
                if on {
                    checkDisc(on: true)
                } else {
                    tag("manter", fill: .white, stroke: true)
                }
            }
            .buttonStyle(MustPressStyle())
        } else {
            Button { model.toggle(match.id) } label: { checkDisc(on: on) }
                .buttonStyle(MustPressStyle())
        }
    }

    private func checkDisc(on: Bool) -> some View {
        ZStack {
            Rectangle().fill(on ? Color.must.green : Color.white)
            Rectangle().strokeBorder(Color.must.line, lineWidth: on ? 0 : 1)
            if on { MustIconView(.ok, size: 13).foregroundStyle(Color.must.greenText) }
        }
        .frame(width: 26, height: 26)
    }

    private func tag(_ text: String, fill: Color, stroke: Bool = false) -> some View {
        Text(text)
            .font(.must.archivo(12, .semibold))
            .foregroundStyle(Color.must.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Rectangle().fill(fill))
            .overlay(Rectangle().strokeBorder(stroke ? Color.must.line : .clear))
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
                .font(.must.archivo(11, .semibold))
                .foregroundStyle(Color.must.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Rectangle().fill(Color.must.surface))
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
