import CoreLocation
import SwiftData
import SwiftUI

/// Buscar por nome (prompt 17 · A, `BuscarNome.png`): campo com viés da cidade, sugestões com o trecho em verde,
/// e o card do lugar escolhido (fotos do Google com crédito, ou a cor da lista; nota, preço, horário, endereço, distância).
/// Entradas: "ou um nome" do Adicionar e o "+" do Board. Apresentada como sheet (cobre a tab bar).
struct BuscarNomeView: View {
    var initialQuery = ""
    var preferredListId: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var model: BuscarNomeModel?
    @FocusState private var focused: Bool

    private var region: Region { store.region }

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            searchField(model)
                            suggestionList(model)
                            if let selected = model.selected {
                                card(model, selected: selected)
                                Text("Sugestões do Google enquanto digita · as fotos só carregam no escolhido")
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, V9.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom, spacing: 0) { footer(model) }
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Buscar por nome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .v9Screen()
        }
        .onAppear {
            guard model == nil else { return }
            let autoChoose = DebugFlags.string("debugScreen")?.hasSuffix(":escolher") == true
            let location = services.location
            let m = BuscarNomeModel(query: initialQuery.replacingOccurrences(of: ":escolher", with: ""), places: services.places,
                                    photos: services.placePhotos, autocomplete: services.autocomplete,
                                    origin: { location.current?.coordinate }, autoChooseFirst: autoChoose)
            model = m
            if !m.query.isEmpty { m.typed(m.query, near: biasCenter) }
            focused = !autoChoose
        }
    }

    // MARK: Viés, origem e distância

    /// Onde estou (GPS ou a posição simulada); sem GPS, o centro da cidade do dia.
    private var originPoint: CLLocationCoordinate2D? { services.location.current?.coordinate }

    private var biasCenter: CLLocationCoordinate2D {
        if let here = originPoint { return here }
        let city = trips.first?.city(on: AppClock.now, calendar: region.calendar)
        return city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
    }

    /// Distância de pé de uma sugestão: a do Autocomplete (com origem), senão nada.
    private func walkText(_ meters: Int?) -> String? {
        guard let meters else { return nil }
        return "\(Walk.distanceText(Double(meters))) · \(Walk.minutes(Double(meters))) min a pé"
    }

    private var areaLabel: String? {
        trips.first?.city(on: AppClock.now, calendar: region.calendar)?.name
    }

    // MARK: Partes

    private func searchField(_ model: BuscarNomeModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("nome do lugar", text: Binding(get: { model.query }, set: { model.typed($0, near: biasCenter) }))
                .accessibilityIdentifier("buscar.query")
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if let areaLabel {
                Text("perto de \(areaLabel)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder private func suggestionList(_ model: BuscarNomeModel) -> some View {
        if model.searching && model.suggestions.isEmpty {
            Text("Buscando…").font(.footnote).foregroundStyle(.secondary).padding(.leading, 6)
        } else if !model.suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 { J9Divider() }
                    suggestionRow(suggestion, model: model)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 16)
            .background(V9.card, in: RoundedRectangle(cornerRadius: V9.cornerRadius, style: .continuous))
        } else if model.query.count >= 3, !model.searching {
            Text("Nenhuma sugestão. Tenta outro nome ou o bairro.").font(.footnote).foregroundStyle(Color.secondary)
        }
    }

    private func suggestionRow(_ suggestion: PlaceSuggestion, model: BuscarNomeModel) -> some View {
        let chosen = model.selected?.placeId == suggestion.placeId
        let onBoard = BuscarNomeModel.boardMatch(for: suggestion, coordinate: nil, origin: originPoint, places: places) != nil
        let subtitle = [suggestion.subtitle, walkText(suggestion.distanceMeters)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return Button {
            Task { await model.choose(suggestion) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle().fill(chosen ? V9.accent : V9.fill)
                    .frame(width: 44, height: 44)
                    .overlay {
                        if suggestion.isCafe {
                            MustIconView(.cafe, size: 18).foregroundStyle(chosen ? .white : Color.primary)
                        } else {
                            MustIconView(.pino, size: 18).foregroundStyle(chosen ? .white : Color.primary)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(highlighted(suggestion))
                        .font(J9.font(17, .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.footnote).foregroundStyle(Color.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                if onBoard {
                    J9Tag(text: "no board")
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Trecho casado em verde (`text.matches` do Autocomplete).
    private func highlighted(_ suggestion: PlaceSuggestion) -> AttributedString {
        var out = AttributedString()
        for segment in suggestion.segments {
            var part = AttributedString(segment.text)
            if segment.highlighted { part.backgroundColor = V9.accent.opacity(0.45) }
            out += part
        }
        return out
    }

    // MARK: Card

    @ViewBuilder private func card(_ model: BuscarNomeModel, selected: PlaceSuggestion) -> some View {
        let name = model.details?.name ?? selected.name
        let listName = lists.first { $0.id == model.listId(for: selected) }?.displayName
        VStack(alignment: .leading, spacing: 12) {
            photos(model, selected: selected)
            Text(name).font(J9.font(26, .semibold)).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
            metaLine(model, selected: selected)
            if let address = model.details?.address {
                Text(addressLine(address, model: model, selected: selected)).font(.footnote).foregroundStyle(Color.secondary)
            }
            if model.loadingCard { Text("Buscando o card…").font(.footnote).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                J9Tag(text: listName ?? "escolha uma lista", filled: true)
                Menu {
                    ForEach(lists) { list in
                        Button(list.name) { model.listOverride = list.id }
                    }
                } label: {
                    J9Tag(text: "outra lista")
                }
            }
        }
        .v9Card()
    }

    /// Até três fotos (uma grande, duas menores) com o crédito; sem foto, a cor da lista (o card não some).
    @ViewBuilder private func photos(_ model: BuscarNomeModel, selected: PlaceSuggestion) -> some View {
        let listId = model.listId(for: selected)
        let color: MustColor = lists.first(where: { $0.id == listId })?.color ?? .drink
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 4) {
                photoTile(model.photos.first, color: color)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    photoTile(model.photos.dropFirst().first, color: color)
                    photoTile(model.photos.dropFirst(2).first, color: color)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            if let first = model.photos.first {
                Credit(first.credit, color: Color.primary, url: first.pageURL)
                    .padding(10)
            }
        }
    }

    @ViewBuilder private func photoTile(_ photo: CCPhoto?, color: MustColor) -> some View {
        Group {
            if let photo, let url = URL(string: photo.largeURL ?? photo.url) {
                TintedPhoto(url: url, color: color, tintOpacity: 0.1)
            } else {
                color.gradient
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// "café · 4,6 · 2,1 mil · ¥¥ · aberto até 18:00" (o horário fecha em verde).
    private func metaLine(_ model: BuscarNomeModel, selected: PlaceSuggestion) -> some View {
        let details = model.details
        let locale = Locale(identifier: "pt_BR")
        var pieces: [String] = []
        if !selected.subtitle.isEmpty, let type = selected.subtitle.split(separator: "·").first.map({ String($0).trimmingCharacters(in: .whitespaces) }) {
            pieces.append(type)
        }
        if let rating = details?.rating {
            pieces.append("\(rating.formatted(.number.precision(.fractionLength(1)).locale(locale)))")
        }
        if let count = details?.ratingCount, count > 0 {
            pieces.append(count >= 1000 ? "\((Double(count) / 1000).formatted(.number.precision(.fractionLength(1)).locale(locale))) mil" : "\(count)")
        }
        if let level = details?.priceLevel, level > 0 {
            pieces.append(String(repeating: region.currencySymbol, count: level))
        }
        let open = details?.hours?.closesAt(AppClock.now, timeZone: region.timeZone).map { "aberto até \($0)" }
        var line = Text(pieces.joined(separator: " · "))
        if let open {
            line = line + Text(pieces.isEmpty ? "" : " · ") + Text(open).foregroundStyle(MustColor.eat.text)
        }
        return line.font(.footnote).foregroundStyle(Color.secondary)
    }

    /// "Endereço · 0,9 km · 12 min a pé" (distância do Autocomplete; sem ela, a da coordenada do Details).
    private func addressLine(_ address: String, model: BuscarNomeModel, selected: PlaceSuggestion) -> String {
        if let walk = walkText(selected.distanceMeters) { return "\(address) · \(walk)" }
        guard let lat = model.details?.lat, let lng = model.details?.lng, let origin = originPoint else { return address }
        let meters = BuscarNomeModel.distance(origin, CLLocationCoordinate2D(latitude: lat, longitude: lng))
        return "\(address) · \(Walk.distanceText(meters)) · \(Walk.minutes(meters)) min a pé"
    }

    // MARK: Rodapé

    private func footer(_ model: BuscarNomeModel) -> some View {
        let selected = model.selected
        let list = selected.flatMap { model.listId(for: $0) }.flatMap { id in lists.first { $0.id == id } }
        let onBoard = selected.map { s in
            BuscarNomeModel.boardMatch(for: s, coordinate: model.details.flatMap { d in
                d.lat.flatMap { lat in d.lng.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
            }, origin: originPoint, places: places) != nil
        } ?? false
        return VStack {
            if let selected, let list, model.details != nil {
                J9Button(onBoard ? "Já está no board" : "Adicionar ao \(list.displayName)") {
                    if model.add(to: list, suggestion: selected, details: model.details, region: region, now: AppClock.now, context: context) != nil {
                        dismiss()
                    }
                }
                .disabled(onBoard)
            } else {
                J9Button("Escolha um lugar") {}.disabled(true)
            }
        }
        .padding(V9.gutter)
        .background(.bar)
    }
}
