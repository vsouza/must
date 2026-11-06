import SwiftUI

/// Campo do topo do mapa (`MapaFiltro.png`): cápsula tinta com a lupa, o texto e o microfone laranja.
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
        HStack(spacing: 12) {
            MustIconView(.buscar, size: 19).foregroundStyle(V8.white).accessibilityHidden(true)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(V8.muteDark))
                .font(V8Font.text(17, weight: .semibold))
                .foregroundStyle(V8.white)
                .tint(V8.orange)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .lineLimit(1)
                .onSubmit(onSubmit)
                .accessibilityLabel("Buscar no mapa")
                .accessibilityHint("o melhor lámen perto de mim agora")
            if active || !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(V8.muteDark)
                        .frame(width: 32, height: 32).contentShape(Circle())
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Limpar a busca")
            }
            Button(action: onMic) {
                Image(systemName: listening ? "waveform" : "mic")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(V8.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(V8.orange))
                    .contentShape(Circle())
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel(listening ? "Parar de ouvir" : "Falar")
        }
        .padding(.leading, 20)
        .padding(.trailing, 6)
        .frame(minHeight: 56)
        .background(Capsule().fill(V8.ink))
        .shadow(color: V8.ink.opacity(0.18), radius: 12, y: 6)
    }
}

/// Chips do que a busca entendeu (LÁMEN · ABERTO AGORA · MELHOR NOTA · ATÉ 1,5 KM), tocáveis.
struct MapIntentChips: View {
    var chips: [(id: String, text: String)]
    var onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.id) { chip in
                    Button { onTap(chip.id) } label: {
                        Text(chip.text.uppercased())
                            .font(V8Font.mono(11, weight: .semibold))
                            .tracking(1.1)
                            .lineLimit(1)
                            .foregroundStyle(chip.id == "offline" ? V8.white : V8.ink)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(fill(chip.id)))
                    }
                    .buttonStyle(MustPressStyle())
                    .disabled(chip.id == "offline")
                    .accessibilityHint(hint(chip.id))
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private func fill(_ id: String) -> Color {
        switch id {
        case "object": V8.orange
        case "offline": V8.ink
        default: V8.paper
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

/// Pílulas do filtro por Must (`MapaFiltro.png`): **Todos N**, **Eat N**… Ativa = tinta; sobre o mapa, fundo papel.
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
            .padding(.horizontal, 20)
        }
        .scrollClipDisabled()
    }

    private func pill(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            V8FilterChip(title: title, on: on)
                .background(Capsule().fill(on ? Color.clear : V8.paper))
                .shadow(color: V8.ink.opacity(on ? 0.16 : 0.06), radius: 6, y: 3)
        }
        .buttonStyle(MustPressStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
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
            Capsule().fill(V8.ink.opacity(0.18)).frame(width: 40, height: 5).frame(maxWidth: .infinity).padding(.top, 12)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(V8Font.display(28)).tracking(-0.8).foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if searching {
                    ProgressView().controlSize(.small).tint(V8.ink)
                } else {
                    Text(countLine.uppercased()).font(V8Font.mono(11)).tracking(1.1).foregroundStyle(V8.mute).lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 4)
            if items.isEmpty, !searching {
                Text(emptyText).font(V8Font.text(15)).foregroundStyle(V8.mute).padding(.vertical, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                Button { onChoose(item) } label: { row(i + 1, item) }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(item.id == chosenId ? .isSelected : [])
            }
            HStack(spacing: 10) {
                V8Button("Ver no Quero…", .line, action: onQuero).foregroundStyle(V8.ink)
                V8Button(encaixarTitle, .orange, action: onEncaixar)
                    .disabled(!canEncaixar)
                    .opacity(canEncaixar ? 1 : 0.45)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(V8.paper))
        .overlay(RoundedRectangle(cornerRadius: 40, style: .continuous).strokeBorder(V8.ink.opacity(0.06)))
        .shadow(color: V8.ink.opacity(0.18), radius: 24, y: 10)
    }

    private func row(_ index: Int, _ c: MapSearchCandidate) -> some View {
        let chosen = c.id == (chosenId ?? items.first?.id)
        return HStack(alignment: .center, spacing: 14) {
            Text("\(index)")
                .font(Font(V8Fonts.bricolage(30, weight: 800, width: 80, opticalSize: 96)))
                .foregroundStyle(V8.orangeDeep)
                .frame(width: 30, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.result.name).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                Text(MapSearchModel.meta(c, locale: locale)).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Walk.distanceText(c.result.distance)).font(V8Font.mono(11, weight: .semibold)).foregroundStyle(V8.ink)
                if let q = c.queueMinutes, q > 0 {
                    Text("~\(q) min fila").font(V8Font.mono(11, weight: .semibold)).foregroundStyle(V8.orangeDeep)
                } else if !c.onBoard {
                    // Do board já diz na meta ("no seu board").
                    Text("fora do board").font(V8Font.mono(11)).foregroundStyle(V8.mute)
                }
            }
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(chosen && items.count > 1 ? V8.ink.opacity(0.05) : .clear))
        .overlay(alignment: .top) { Rectangle().fill(V8.ink.opacity(0.14)).frame(height: 1).opacity(index == 1 ? 0 : 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
