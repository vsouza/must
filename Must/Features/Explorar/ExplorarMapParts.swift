import CoreLocation
import SwiftUI

// Peças do Explorar = o mapa (prompt 32 §4), no visual do corte (rodada 33): chips quadrados e botões de borda 2 pt no topo,
// painel de papel com índice de linhas (numeral de distância; laranja = seu, tinta = de fora do board) e o Lugar resumido
// do pino com Ir · Encaixar · Abrir em blocos. O mapa em si (estilo, camadas, pinos) não muda.

// MARK: - Topo

/// Filtros de lista (Todos · Eat · Drink…), o menu de camadas, o ⋯ (Bairros, Mapa completo), "centralizar em mim" e, com
/// "Ver no mapa", o chip "Mostrando: … ✕".
struct ExplorarMapTop: View {
    var model: ExplorarMapModel
    var online: Bool
    var onBairros: () -> Void
    var onFullMap: () -> Void
    var onClearShowcase: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let showcase = model.showcase {
                showcaseChip(showcase)
                Spacer(minLength: 0)
            } else {
                chips
            }
            layersMenu
            moreMenu
                .padding(.trailing, 12)
        }
        .padding(.top, 6)
        .v8Legacy()
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(title: "Todos", on: model.filter.isAll) { model.showAllLists() }
                ForEach(model.chips) { c in
                    chip(title: c.label, on: model.filter.listIds.contains(c.id)) { model.toggle(list: c.id) }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CutChip(text: title, isOn: on, minHeight: 44)
                .background(on ? Color.clear : V8.paper)
        }
        .buttonStyle(.plain)
    }

    private func square(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(V8.ink)
            .frame(width: 44, height: 44)
            .background(V8.paper)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            .contentShape(Rectangle())
    }

    private var layersMenu: some View {
        Menu {
            Section("Camadas") {
                ForEach(ExplorarMapLayer.allCases) { layer in
                    let unavailable = layer == .indicated && !online && !model.layers.contains(.indicated)
                    Toggle(isOn: Binding(get: { model.layers.contains(layer) },
                                         set: { model.setLayer(layer, on: $0) })) {
                        Label(layer.label, systemImage: layer.systemImage)
                        Text(unavailable ? "precisa de internet" : layer.caption)
                    }
                    .disabled(layer == .musts || unavailable)
                }
            }
        } label: {
            square("square.3.layers.3d")
        }
        .accessibilityLabel("Camadas")
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onBairros) { Label("Bairros", systemImage: "square.grid.2x2") }
            Button(action: onFullMap) { Label("Mapa completo", systemImage: "map") }
        } label: {
            square("ellipsis")
        }
        .accessibilityLabel("Mais")
    }

    private func showcaseChip(_ showcase: MapShowcase) -> some View {
        Button(action: onClearShowcase) {
            HStack(spacing: 8) {
                Text("Mostrando: \(showcase.title)").lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .font(V8Font.mono(11, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(V8.paper)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(V8.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .accessibilityLabel("Mostrando: \(showcase.title)")
        .accessibilityHint("Toque pra ver todos os pinos de novo")
    }
}

// MARK: - Linha do índice (painel)

/// Uma linha do painel: numeral de distância, nome, motivo. **Seu = laranja** (barra e numeral); **de fora = tinta** (linha inteira).
struct ExplorarCutRow<Trailing: View>: View {
    var title: String
    var distance: (value: String, unit: String)?
    var detail: String?
    var reason: String?
    var own: Bool
    var dimmed = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let fg = own ? V8.ink : V8.white
        let soft = own ? V8.mute : V8.muteDark
        HStack(alignment: .top, spacing: 12) {
            if let distance {
                VStack(alignment: .leading, spacing: 2) {
                    Text(distance.value).font(V8Font.display(28, width: 78, weight: 800)).tracking(-1)
                        .foregroundStyle(own ? V8.orange : V8.white).lineLimit(1).minimumScaleFactor(0.7)
                    Text(distance.unit.uppercased()).font(V8Font.mono(8.5)).tracking(0.8).foregroundStyle(soft).lineLimit(2)
                }
                .frame(width: 64, alignment: .leading)
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(V8Font.text(16, weight: .bold)).foregroundStyle(fg).fixedSize(horizontal: false, vertical: true)
                if let detail, !detail.isEmpty {
                    Text(detail).font(V8Font.text(13)).foregroundStyle(soft).fixedSize(horizontal: false, vertical: true)
                }
                if let reason, !reason.isEmpty {
                    Text(reason).font(V8Font.text(13)).foregroundStyle(soft).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(own ? Color.clear : V8.ink)
        .overlay(alignment: .leading) { if own { Rectangle().fill(V8.orange).frame(width: 5) } }
        .overlay(alignment: .bottom) { own ? AnyView(IndexRule()) : AnyView(Rectangle().fill(V8.white.opacity(0.18)).frame(height: 1)) }
        .opacity(dimmed ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Agora vale (médio)

/// Os 3 cartões do ranker pro centro do mapa: nome, distância/tempo e o motivo.
struct ExplorarAgoraList: View {
    var model: ExplorarMapModel
    var onTap: (Suggestion) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if model.cards.isEmpty {
                    Text(model.ranked ? "Nada aberto perto do centro do mapa agora. Arraste o mapa ou use o Pedir algo." : "Calculando…")
                        .font(V8Font.text(14)).foregroundStyle(V8.mute)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                }
                ForEach(model.cards) { card in
                    Button { onTap(card) } label: {
                        ExplorarCutRow(title: card.title, distance: distance(card), detail: card.coordinate == nil ? card.trailing : nil,
                                       reason: reason(card), own: card.kind != .indicated) {
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(card.kind == .indicated ? V8.white : V8.ink).padding(.top, 4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 76)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func distance(_ card: Suggestion) -> (value: String, unit: String)? {
        guard let c = card.coordinate, let meters = model.meters(to: c) else { return nil }
        let d = ExplorarTravel.distance(meters)
        return (d.value, "\(d.unit) · \(ExplorarTravel.caption(meters))")
    }

    private func reason(_ card: Suggestion) -> String? {
        // O mesmo motivo de Hoje (uma linha, sem jargão do ranker).
        let line = SuggestionReason.line(card)
        return line.isEmpty ? nil : line
    }
}

// MARK: - Na tela (grande)

/// O que está visível no mapa, agrupado por lista do board.
struct ExplorarVisibleList: View {
    var model: ExplorarMapModel
    var onTap: (ExplorarMapItem) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.sections.isEmpty {
                    Text("Nada neste pedaço do mapa. Arraste o mapa ou mude os filtros.")
                        .font(V8Font.text(14)).foregroundStyle(V8.mute)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                }
                if let note = model.layers.contains(.indicated) ? model.indicatedState.note : nil {
                    Label(note, systemImage: "wifi.slash").font(V8Font.text(13)).foregroundStyle(V8.mute)
                        .padding(.horizontal, 20).padding(.vertical, 8)
                }
                ForEach(model.sections) { section in
                    HStack(alignment: .firstTextBaseline) {
                        Text(section.title.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(1)
                        Spacer(minLength: 8)
                        Text("\(section.items.count)").font(V8Font.mono(11, weight: .semibold))
                    }
                    .foregroundStyle(V8.ink)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { IndexRule() }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(section.items) { item in
                        Button { onTap(item) } label: {
                            ExplorarCutRow(title: item.name, distance: distance(item), reason: item.reason, own: item.kind != .indicated,
                                           dimmed: item.done) {
                                if item.done {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(V8.ink).padding(.top, 4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 76)
        }
    }

    private func distance(_ item: ExplorarMapItem) -> (value: String, unit: String)? {
        guard let meters = model.meters(to: item) else { return nil }
        let d = ExplorarTravel.distance(meters)
        return (d.value, "\(d.unit) · \(ExplorarTravel.caption(meters))")
    }
}

// MARK: - Lugar resumido (pino)

/// O pino tocado: nome em Bricolage, distância, motivo e as ações em blocos (Ir · Encaixar hoje · Abrir; de fora: Ir · Guardar).
struct ExplorarPlaceSummary: View {
    var item: ExplorarMapItem
    var distance: String?
    var region: Region
    var pinDay: ExplorarPinActions.Day?
    var notice: String?
    var photoRefs: [PlacePhotoRef]
    var onClose: () -> Void
    var onGo: () -> Void
    var onFit: () -> Void
    var onOpen: () -> Void
    var onSave: () -> Void

    @Environment(\.dynamicTypeSize) private var type

    private var own: Bool { item.kind != .indicated }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(V8Font.display(30)).tracking(-0.8).foregroundStyle(V8.ink)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let distance {
                        Text(distance.uppercased()).font(V8Font.mono(11, weight: .semibold)).tracking(0.8)
                            .foregroundStyle(own ? V8.orange : V8.ink)
                    }
                    if !item.reason.isEmpty {
                        Text(item.reason).font(V8Font.text(14)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
                    }
                    CutTag(text: own ? "seu Must" : "fora do board", filled: true, orange: own).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CutCornerButton(systemName: "xmark", label: "Fechar", action: onClose)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            // Ir (laranja de ponta a ponta) e, ao lado, o dia e Abrir/Guardar; no XXXL, um por linha.
            if type.isAccessibilitySize {
                VStack(spacing: 0) { goBlock; dayBlock; otherBlock }
            } else {
                VStack(spacing: 0) {
                    goBlock
                    HStack(spacing: 0) { dayBlock; otherBlock }
                }
            }
            if let notice {
                Text(notice).font(V8Font.text(13)).foregroundStyle(V8.mute).padding(.horizontal, 20).padding(.top, 10)
            } else if case .noFit(let why)? = pinDay {
                Text("Não cabe hoje: \(why).").font(V8Font.text(13)).foregroundStyle(V8.mute).padding(.horizontal, 20).padding(.top, 10)
            }
        }
    }

    private var goBlock: some View {
        Button(action: onGo) {
            HStack {
                Text("IR").font(V8Font.mono(14, weight: .semibold)).tracking(1.2)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(V8.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(V8.orange)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ir")
    }

    private func block(_ title: String, enabled: Bool = true, label: String? = nil, action: @escaping () -> Void) -> some View {
        Button { if enabled { action() } } label: {
            Text(title.uppercased()).font(V8Font.mono(12, weight: .semibold)).tracking(1)
                .foregroundStyle(V8.ink).opacity(enabled ? 1 : 0.4)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 56)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? title)
        .accessibilityAddTraits(enabled ? [] : .isStaticText)
    }

    @ViewBuilder private var otherBlock: some View {
        if item.kind == .indicated, item.placeId == nil {
            block("+ Board", label: "Guardar no board", action: onSave)
        } else if item.placeId != nil || item.eventId != nil {
            block("Abrir", action: onOpen)
        }
    }

    @ViewBuilder private var dayBlock: some View {
        if item.kind != .event {
            switch pinDay {
            case .fit(let slot)?:
                block("Encaixar \(region.timeString(slot.start))", label: "Encaixar hoje às \(region.timeString(slot.start))", action: onFit)
            case .inDay(let time)?:
                block("No dia" + (time.map { " · \($0)" } ?? ""), enabled: false) {}
            case .noFit?:
                block("Não cabe hoje", enabled: false) {}
            case .none?, nil:
                EmptyView()
            }
        }
    }
}
