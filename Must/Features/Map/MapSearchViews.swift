import SwiftUI

/// Campo do topo do mapa completo (V9): campo de busca de material do sistema, lupa, texto e microfone.
struct MapSearchField: View {
    @Binding var text: String
    var placeholder: String
    var listening: Bool
    var active: Bool
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void
    var onMic: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.secondary))
                .font(.body)
                .foregroundStyle(.primary)
                .tint(V9.accent)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .lineLimit(1)
                .onSubmit(onSubmit)
                .accessibilityLabel("Buscar no mapa")
                .accessibilityHint("por exemplo, o melhor lámen perto de mim agora")
            if active || !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Limpar a busca")
            }
            Button(action: onMic) {
                Image(systemName: listening ? "waveform" : "mic.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(listening ? V9.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(listening ? "Parar de ouvir" : "Falar")
        }
        .padding(.leading, 14)
        .padding(.trailing, 2)
        .frame(minHeight: 48)
        .background(.regularMaterial, in: Capsule())
    }
}

/// Chips do que a busca entendeu (lámen · aberto agora · melhor nota · até 1,5 km), tocáveis.
struct MapIntentChips: View {
    var chips: [(id: String, text: String)]
    var onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.id) { chip in
                    Button { onTap(chip.id) } label: {
                        Text(chip.text.lowercased()).font(.subheadline.weight(chip.id == "object" ? .semibold : .regular)).lineLimit(1)
                    }
                    .buttonStyle(.glass)
                    .tint(chip.id == "object" ? V9.accent : nil)
                    .disabled(chip.id == "offline")
                    .accessibilityHint(hint(chip.id))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 28)
        }
        .scrollClipDisabled()
        .mask {
            HStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28)
            }
        }
    }

    private func hint(_ id: String) -> String {
        switch id {
        case "object": "editar o que buscar"
        case "open": "ligar ou desligar só abertos"
        case "quality": "trocar a ordem: nota, preço, distância"
        case "radius": "trocar o raio"
        default: ""
        }
    }
}

/// Filtro por Must (Todos N, Eat N…): chips de vidro; ativo = acento.
struct MapMustPills: View {
    var total: Int
    var counts: [MapMustFilter.Count]
    var filter: MapMustFilter
    var onAll: () -> Void
    var onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                pill("Todos \(total)", on: filter.isAll, action: onAll)
                ForEach(counts) { c in
                    pill("\(c.label) \(c.count)", on: !filter.isAll && filter.listIds.contains(c.id)) { onToggle(c.id) }
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 28)
        }
        .scrollClipDisabled()
        .mask {
            HStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28)
            }
        }
    }

    @ViewBuilder
    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        let label = Text(title).font(.subheadline.weight(on ? .semibold : .regular)).lineLimit(1)
        if on {
            Button(action: action) { label }.buttonStyle(.glassProminent).tint(V9.accent).accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) { label }.buttonStyle(.glass)
        }
    }
}

/// Card de baixo dos resultados ("Melhor agora · 3 de 11 · por nota"), com **Ver no Quero…** e **Encaixar HH:MM**.
struct MapResultsCard: View {
    var title: String
    var countLine: String
    var items: [MapSearchCandidate]
    var chosenId: String?
    var searching: Bool
    var emptyText: String
    var locale: Locale
    var encaixarTitle: String
    var canEncaixar: Bool
    var onChoose: (MapSearchCandidate) -> Void
    var onQuero: () -> Void
    var onEncaixar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if searching {
                    ProgressView().controlSize(.small).tint(Color.primary)
                } else {
                    Text(countLine).font(.footnote).monospacedDigit().foregroundStyle(Color.secondary).lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 4)
            if items.isEmpty, !searching {
                Text(emptyText).font(Font.subheadline).foregroundStyle(Color.secondary).padding(.vertical, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                Button { onChoose(item) } label: { row(i + 1, item) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item.id == chosenId ? .isSelected : [])
            }
            HStack(spacing: 10) {
                Button("Ver no Quero…", action: onQuero).v9Secondary().frame(maxWidth: .infinity)
                Button(encaixarTitle, action: onEncaixar).v9Primary().frame(maxWidth: .infinity)
                    .disabled(!canEncaixar)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func row(_ index: Int, _ c: MapSearchCandidate) -> some View {
        let chosen = c.id == (chosenId ?? items.first?.id)
        return HStack(alignment: .center, spacing: 14) {
            Text("\(index)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(V9.accent)
                .frame(width: 28, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.result.name).font(Font.body.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(2)
                Text(MapSearchModel.meta(c, locale: locale)).font(Font.footnote).foregroundStyle(Color.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Walk.distanceText(c.result.distance)).font(Font.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.primary)
                if let q = c.queueMinutes, q > 0 {
                    Text("~\(q) min fila").font(Font.caption.weight(.semibold).monospacedDigit()).foregroundStyle(V9.accent)
                } else if !c.onBoard {
                    // Do board já diz na meta ("no seu board").
                    Text("fora do board").font(Font.caption.monospacedDigit()).foregroundStyle(Color.secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .frame(minHeight: 44)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(chosen && items.count > 1 ? Color.primary.opacity(0.06) : .clear))
        .overlay(alignment: .top) { Rectangle().fill(Color(.separator)).frame(height: 1).opacity(index == 1 ? 0 : 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
