import CoreLocation
import SwiftUI

// Peças do Explorar = o mapa (prompt 32 §4), no visual V9: chips e menus de vidro do sistema no topo, a lista "Agora vale",
// a lista do que está na tela agrupada por lista e o Lugar resumido do pino.

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
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(title: "Todos", color: nil, on: model.filter.isAll) { model.showAllLists() }
                ForEach(model.chips) { c in
                    chip(title: c.label, color: color(of: c.id), on: model.filter.listIds.contains(c.id)) { model.toggle(list: c.id) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func color(of listId: String) -> MustColor? {
        model.items.first { $0.listId == listId }?.color
    }

    @ViewBuilder
    private func chip(title: String, color: MustColor?, on: Bool, action: @escaping () -> Void) -> some View {
        let label = HStack(spacing: 6) {
            if let color {
                Circle().fill(Color(uiColor: UIColor(v9Hex: ExplorarMapPins.rgb(color)))).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(title).font(.subheadline.weight(on ? .semibold : .regular)).lineLimit(1)
        }
        if on {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(V9.accent)
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) { label }
                .buttonStyle(.glass)
        }
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
            Image(systemName: "square.3.layers.3d").frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Camadas")
    }

    private var moreMenu: some View {
        Menu {
            Button(action: onBairros) { Label("Bairros", systemImage: "square.grid.2x2") }
            Button(action: onFullMap) { Label("Mapa completo", systemImage: "map") }
        } label: {
            Image(systemName: "ellipsis").frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Mais")
    }

    private func showcaseChip(_ showcase: MapShowcase) -> some View {
        Button(action: onClearShowcase) {
            HStack(spacing: 6) {
                Text("Mostrando: \(showcase.title)").font(.subheadline.weight(.semibold)).lineLimit(1)
                Image(systemName: "xmark").font(.footnote.weight(.semibold))
            }
        }
        .buttonStyle(.glass)
        .padding(.leading, 12)
        .accessibilityLabel("Mostrando: \(showcase.title)")
        .accessibilityHint("Toque pra ver todos os pinos de novo")
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
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Divider() }
                    Button { onTap(card) } label: {
                        V9Row(title: card.title, detail: detail(card), reason: reason(card), systemImage: symbol(card)) {
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func detail(_ card: Suggestion) -> String? {
        if let c = card.coordinate, let line = ExplorarMapModel.distanceLine(model.meters(to: c)) { return line }
        return card.trailing
    }

    private func reason(_ card: Suggestion) -> String? {
        // O mesmo motivo de Hoje (uma linha, sem jargão do ranker).
        let line = SuggestionReason.line(card)
        return line.isEmpty ? nil : line
    }

    private func symbol(_ card: Suggestion) -> String {
        switch card.kind {
        case .event: "ticket"
        case .light: "sun.horizon"
        case .rain: "cloud.rain"
        case .indicated: "sparkle.magnifyingglass"
        case .gift: "gift"
        case .closing: "clock.badge.exclamationmark"
        case .plan, .must: "mappin"
        }
    }
}

// MARK: - Na tela (grande)

/// O que está visível no mapa, agrupado por lista do board.
struct ExplorarVisibleList: View {
    var model: ExplorarMapModel
    var onTap: (ExplorarMapItem) -> Void

    var body: some View {
        List {
            if model.sections.isEmpty {
                Text("Nada neste pedaço do mapa. Arraste o mapa ou mude os filtros.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if let note = model.layers.contains(.indicated) ? model.indicatedState.note : nil {
                Label(note, systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        Button { onTap(item) } label: {
                            V9Row(title: item.name, detail: ExplorarMapModel.distanceLine(model.meters(to: item)), reason: item.reason,
                                  thumbnail: thumbnail(item), systemImage: symbol(item), dimmed: item.done)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    HStack(spacing: 6) {
                        if let color = section.color {
                            Circle().fill(Color(uiColor: UIColor(v9Hex: ExplorarMapPins.rgb(color)))).frame(width: 8, height: 8)
                        }
                        Text(section.title)
                        Spacer()
                        Text("\(section.items.count)").monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func thumbnail(_ item: ExplorarMapItem) -> AnyView? {
        guard item.kind == .must, let refs = model.photoRefs[item.id], !refs.isEmpty else { return nil }
        return AnyView(PlaceThumb(placeId: model.googleIds[item.id], refs: refs, color: item.color ?? .eat, size: V9.thumb))
    }

    private func symbol(_ item: ExplorarMapItem) -> String {
        switch item.kind {
        case .event: "ticket"
        case .indicated: "sparkle.magnifyingglass"
        case .must: item.done ? "checkmark.circle" : "mappin"
        }
    }
}

// MARK: - Lugar resumido (pino)

/// O pino tocado: nome, distância, motivo e as ações (Ir · Encaixar hoje · Abrir; de fora: Ir · Guardar).
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if item.kind == .must, !photoRefs.isEmpty {
                    PlaceThumb(placeId: item.googleId, refs: photoRefs, color: item.color ?? .eat, size: V9.thumb)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let distance { Text(distance).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
                    if !item.reason.isEmpty {
                        Text(item.reason).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fechar")
            }
            // Três numa linha quando cabem; senão Ir + dia numa linha e Abrir/Guardar embaixo; no XXXL, um por linha.
            if type.isAccessibilitySize {
                VStack(spacing: 8) { goButton; dayButton; otherButton }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { goButton; dayButton; otherButton }
                    VStack(spacing: 8) {
                        HStack(spacing: 8) { goButton; dayButton }
                        otherButton
                    }
                    VStack(spacing: 8) { goButton; dayButton; otherButton }
                }
            }
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func label(_ title: String) -> some View {
        Text(title).lineLimit(1).fixedSize().frame(maxWidth: .infinity)
    }

    private var goButton: some View {
        Button(action: onGo) { label("Ir") }
            .buttonStyle(.borderedProminent).controlSize(.large).tint(V9.accent)
    }

    @ViewBuilder private var otherButton: some View {
        if item.kind == .indicated, item.placeId == nil {
            Button(action: onSave) { label("Guardar") }
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityLabel("Guardar no board")
        } else if item.placeId != nil || item.eventId != nil {
            Button(action: onOpen) { label("Abrir") }
                .buttonStyle(.bordered).controlSize(.large)
        }
    }

    @ViewBuilder private var dayButton: some View {
        if item.kind != .event {
            switch pinDay {
            case .fit(let slot)?:
                Button(action: onFit) { label("Encaixar \(region.timeString(slot.start))") }
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityLabel("Encaixar hoje às \(region.timeString(slot.start))")
            case .inDay(let time)?:
                Button {} label: { label("No dia" + (time.map { " · \($0)" } ?? "")) }
                    .buttonStyle(.bordered).controlSize(.large).disabled(true)
            case .noFit?:
                Button {} label: { label("Não cabe hoje") }
                    .buttonStyle(.bordered).controlSize(.large).disabled(true)
            case .none?, nil:
                EmptyView()
            }
        }
    }
}
