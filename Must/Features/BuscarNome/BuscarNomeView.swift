import CoreLocation
import SwiftData
import SwiftUI

/// Buscar por nome (prompt 17 · A, `BuscarNome.png`): campo com viés da cidade, sugestões com o trecho em verde,
/// e o card do lugar escolhido (fotos do Google com crédito, nota, preço, horário, endereço, distância a pé).
/// Entradas: "ou um nome" do Adicionar e o "+" do Board.
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
        ZStack(alignment: .bottom) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([
                Blob(cx: 380, cy: 150, rx: 74, ry: 80, rotation: 8, fill: .green, opacity: 0.6),
                Blob(cx: 10, cy: 600, rx: 60, ry: 70, rotation: 0, fill: .blue, opacity: 0.5),
            ]))
            ScrollView {
                if let model {
                    VStack(alignment: .leading, spacing: 16) {
                        topBar
                        searchField(model)
                        suggestionList(model)
                        if let selected = model.selected {
                            card(model, selected: selected)
                            Text("Sugestões do Google enquanto digita · as fotos só carregam no escolhido")
                                .font(.must.meta).foregroundStyle(Color.must.secondary)
                                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                        }
                        Color.clear.frame(height: 110)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            if let model { footer(model) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if model == nil {
                model = BuscarNomeModel(query: initialQuery.replacingOccurrences(of: ":escolher", with: ""))
                if !initialQuery.isEmpty, let model { model.typed(initialQuery, near: biasCenter, provider: services.autocomplete) }
            }
            focused = true
        }
        #if DEBUG
        // Print de QA: `buscar-nome:<texto>:escolher` já escolhe a primeira sugestão (abre o card).
        .task(id: model?.suggestions.count ?? 0) {
            guard UserDefaults.standard.string(forKey: "debugScreen")?.hasSuffix(":escolher") == true,
                  let model, model.selected == nil, let first = model.suggestions.first else { return }
            focused = false
            await model.choose(first, places: services.places, photoProvider: services.placePhotos)
        }
        #endif
    }

    // MARK: Viés e distância

    /// Onde estou (ou o centro da cidade do dia): o viés do Autocomplete e a distância a pé.
    private var biasCenter: CLLocationCoordinate2D {
        if let here = services.location.current?.coordinate { return here }
        let city = trips.first?.city(on: AppClock.now, calendar: region.calendar)
        return city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
    }

    private var areaLabel: String? {
        trips.first?.city(on: AppClock.now, calendar: region.calendar)?.name
    }

    // MARK: Partes

    private var topBar: some View {
        HStack {
            IconButton(.voltar, label: "Voltar") { dismiss() }
            Spacer()
            Micro("adicionar · por nome")
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private func searchField(_ model: BuscarNomeModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.must.ink)
            TextField("nome do lugar", text: Binding(get: { model.query }, set: { model.typed($0, near: biasCenter, provider: services.autocomplete) }))
                .font(.must.archivo(20))
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if let areaLabel {
                Text("perto de \(areaLabel)")
                    .font(.must.archivo(13))
                    .foregroundStyle(Color.must.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(Capsule().fill(Color.must.surface2))
        .overlay(Capsule().stroke(Color.must.ink, lineWidth: 2))
    }

    @ViewBuilder private func suggestionList(_ model: BuscarNomeModel) -> some View {
        if model.searching && model.suggestions.isEmpty {
            Micro("buscando…").padding(.leading, 6)
        } else if !model.suggestions.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if index > 0 { RowDivider() }
                    suggestionRow(suggestion, model: model)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.must.line, lineWidth: 1))
        } else if model.query.count >= 3, !model.searching {
            Text("Nenhuma sugestão. Tenta outro nome ou o bairro.").font(.must.meta).foregroundStyle(Color.must.secondary)
        }
    }

    private func suggestionRow(_ suggestion: PlaceSuggestion, model: BuscarNomeModel) -> some View {
        let onBoard = places.contains { $0.placeId == suggestion.placeId }
        return Button {
            Task { await model.choose(suggestion, places: services.places, photoProvider: services.placePhotos) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Circle().fill(model.selected?.placeId == suggestion.placeId ? Color.must.ink : Color.must.surface)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "mappin").font(.system(size: 15)).foregroundStyle(model.selected?.placeId == suggestion.placeId ? .white : Color.must.ink))
                VStack(alignment: .leading, spacing: 3) {
                    Text(highlighted(suggestion))
                        .font(.must.archivo(17, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .lineLimit(2)
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle).font(.must.meta).foregroundStyle(Color.must.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if onBoard {
                    Tag("no board", style: .green)
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(MustPressStyle())
    }

    /// Trecho casado em verde (`text.matches` do Autocomplete).
    private func highlighted(_ suggestion: PlaceSuggestion) -> AttributedString {
        var out = AttributedString()
        for segment in suggestion.segments {
            var part = AttributedString(segment.text)
            if segment.highlighted { part.backgroundColor = Color.must.green.opacity(0.45) }
            out += part
        }
        return out
    }

    // MARK: Card

    @ViewBuilder private func card(_ model: BuscarNomeModel, selected: PlaceSuggestion) -> some View {
        let name = model.details?.name ?? selected.name
        let listName = lists.first { $0.id == model.listId(for: selected) }?.name
        VStack(alignment: .leading, spacing: 12) {
            photos(model, selected: selected)
            Text(name).font(.must.archivo(26, .semibold)).foregroundStyle(Color.must.ink).fixedSize(horizontal: false, vertical: true)
            metaLine(model)
            if let address = model.details?.address {
                Text(addressLine(address, model: model)).font(.must.meta).foregroundStyle(Color.must.secondary)
            }
            if model.loadingCard { Micro("buscando o card…") }
            HStack(spacing: 8) {
                Tag(listName ?? "escolha uma lista", style: .dark)
                Menu {
                    ForEach(lists) { list in
                        Button(list.name) { model.listOverride = list.id }
                    }
                } label: {
                    Tag("outra lista")
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.must.surface2))
        .rotationEffect(.degrees(-0.8))
    }

    /// Três fotos (uma grande e duas menores) com o crédito "FOTOS · GOOGLE · @AUTOR"; sem foto, a cor da lista.
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
                Credit(first.credit, color: Color.must.ink, url: first.pageURL)
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

    private func metaLine(_ model: BuscarNomeModel) -> some View {
        let details = model.details
        let locale = Locale(identifier: "pt_BR")
        var pieces: [String] = []
        if let type = model.selected?.subtitle.split(separator: "·").first.map({ String($0).trimmingCharacters(in: .whitespaces) }), !type.isEmpty {
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
        return line.font(.must.meta).foregroundStyle(Color.must.secondary)
    }

    private func addressLine(_ address: String, model: BuscarNomeModel) -> String {
        guard let lat = model.details?.lat, let lng = model.details?.lng else { return address }
        let km = DaySolver.streetKm(biasCenter, CLLocationCoordinate2D(latitude: lat, longitude: lng))
        let meters = km * 1000 / 1.25
        return "\(address) · \(Walk.distanceText(meters)) · \(Walk.minutes(meters)) min a pé"
    }

    // MARK: Rodapé

    private func footer(_ model: BuscarNomeModel) -> some View {
        let selected = model.selected
        let list = selected.flatMap { model.listId(for: $0) }.flatMap { id in lists.first { $0.id == id } }
        let onBoard = selected.map { s in places.contains { $0.placeId == s.placeId } } ?? false
        return VStack {
            if let selected, let list, model.details != nil {
                PrimaryButton(onBoard ? "Já está no board" : "Adicionar ao \(list.name)", style: .green) {
                    if model.add(to: list, suggestion: selected, details: model.details, region: region, now: AppClock.now, context: context) != nil {
                        dismiss()
                    }
                }
                .disabled(onBoard)
            } else {
                PrimaryButton("Escolha um lugar", style: .green) {}.disabled(true)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 26)
        .background(Color.must.bg.opacity(0.96))
    }
}
