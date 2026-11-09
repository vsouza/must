import CoreLocation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Adicionar lugares a uma lista recém-criada: do board, salvos no Maps, à mão ou por link.
/// (Busca no Google Places entra no prompt 07.)
struct AddItemsView: View {
    let listId: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query(sort: \Place.name) private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var query = ""
    @State private var source: SourceFilter = .board
    @State private var selectedBoard: Set<String> = []
    @State private var saved: [SavedPlace] = []
    @State private var selectedSaved: Set<String> = []
    @State private var showSavedPicker = false
    @State private var showManual = false
    @State private var showLink = false
    @State private var importNote: String?
    @State private var candidates: [PlaceCandidate] = []
    @State private var selectedCandidates: Set<String> = []
    @State private var placesNote: String?

    private enum SourceFilter: Hashable { case places, board, city(String), saved }

    private var region: Region { store.region }
    private var list: MustList? { lists.first { $0.id == listId } }
    private var color: MustColor { list?.color ?? .coffee }
    private var currentCity: City? { trips.first?.city(on: AppClock.now, calendar: region.calendar) }

    private var otherCityNames: [String] {
        var names: [String] = []
        for c in trips.first?.cities ?? [] where c.name != currentCity?.name && !names.contains(c.name) { names.append(c.name) }
        return names
    }

    private var boardResults: [Place] {
        places.filter { place in
            guard place.list?.id != listId, place.matches(query) else { return false }
            if case .city(let name) = source { return trips.first?.city(id: place.cityId)?.name == name }
            return true
        }
    }

    private var savedResults: [SavedPlace] {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return saved.filter { q.isEmpty || $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q) }
    }

    private var selectionCount: Int { selectedBoard.count + selectedSaved.count + selectedCandidates.count }

    var body: some View {
        List {
            Section {
                Picker("De onde", selection: $source) {
                    Text("Places · \(currentCity?.name ?? region.displayName)").tag(SourceFilter.places)
                    Text("Do board").tag(SourceFilter.board)
                    ForEach(otherCityNames, id: \.self) { Text($0).tag(SourceFilter.city($0)) }
                    Text("Salvos no Maps").tag(SourceFilter.saved)
                }
                .pickerStyle(.menu)
                if let importNote { Text(importNote).font(.footnote).foregroundStyle(.secondary) }
            }
            results
            Section {
                Button { showManual = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(V9.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adicionar à mão").font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text(query.isEmpty ? "nome, bairro, preço, janela" : "“\(query)”").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                Button { showLink = true } label: {
                    Label("Colar um link", systemImage: "link")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(list?.displayName ?? "Lista")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar nome ou bairro…")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Depois") { finish(openList: false) } }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(selectionCount == 0 ? "Escolha lugares" : "Adicionar \(selectionCount) à lista", action: add)
                .v9Primary()
                .disabled(selectionCount == 0)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, V9.gutter).padding(.vertical, 10)
                .background(.regularMaterial)
        }
        .v9Screen(grouped: true)
        .task(id: "\(query)|\(source == .places)") { await searchPlaces() }
        .sheet(isPresented: $showManual) {
            EditPlaceView(newInListId: listId, prefillName: query.isEmpty ? nil : query)
        }
        .sheet(isPresented: $showLink) {
            AddLinkView(initialURL: nil, preferredListId: listId)
        }
        .fileImporter(isPresented: $showSavedPicker, allowedContentTypes: [UTType(filenameExtension: "kml") ?? .xml, .json, .xml]) { result in
            loadSaved(result)
        }
        .onChange(of: source) { _, new in if new == .saved && saved.isEmpty { showSavedPicker = true } }
    }

    // MARK: Resultados

    @ViewBuilder private var results: some View {
        Section {
            switch source {
            case .places:
                if let placesNote {
                    Text(placesNote).font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(candidates) { c in
                    let already = places.first { $0.placeId == c.id }
                    checkRow(selected: selectedCandidates.contains(c.id), title: c.name, local: nil,
                             meta: [c.address, already.map { "já está no board · \($0.list?.displayName ?? "")" }].compactMap { $0 }.joined(separator: " · "),
                             badge: "Places") {
                        if already == nil { toggle(&selectedCandidates, c.id) }
                    }
                    .opacity(already == nil ? 1 : 0.5)
                }
            case .board, .city:
                ForEach(boardResults) { place in
                    checkRow(selected: selectedBoard.contains(place.id),
                             title: place.name, local: place.nameLocal,
                             meta: [place.area, place.list.map { "já estava no board · \($0.displayName)" }].compactMap { $0 }.joined(separator: " · "),
                             badge: "board") {
                        toggle(&selectedBoard, place.id)
                    }
                }
            case .saved:
                if savedResults.isEmpty {
                    Button("Escolher o arquivo .kml (My Maps) ou o Saved Places.json do Takeout") { showSavedPicker = true }
                }
                ForEach(savedResults) { item in
                    checkRow(selected: selectedSaved.contains(item.id), title: item.name, local: nil,
                             meta: item.note ?? String(format: "%.4f, %.4f", item.lat, item.lng), badge: "Maps") {
                        toggle(&selectedSaved, item.id)
                    }
                }
            }
        }
    }

    private func checkRow(selected: Bool, title: String, local: String?, meta: String, badge: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? V9.accent : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    if let local { Text(local).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                    if !meta.isEmpty { Text(meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 8)
                Text(badge).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(V9.fill, in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Ações

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func searchPlaces() async {
        guard source == .places else { return }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard services.places.isConfigured else { placesNote = "A busca no Google Places precisa da GOOGLE_PLACES_KEY no Secrets.plist."; return }
        guard !q.isEmpty else { candidates = []; placesNote = "Digite o nome ou o tipo (ex.: kissaten) pra buscar em \(currentCity?.name ?? region.displayName)."; return }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        let center = CLLocationCoordinate2D(latitude: currentCity?.lat ?? region.defaultCenter.latitude,
                                            longitude: currentCity?.lng ?? region.defaultCenter.longitude)
        do {
            candidates = try await services.sync.search("\(q) \(currentCity?.name ?? "")", near: center)
            placesNote = candidates.isEmpty ? "Nada no Places pra “\(q)”." : nil
        } catch {
            placesNote = error.localizedDescription
        }
    }

    private func loadSaved(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            saved = SavedPlacesImporter.parse(try Data(contentsOf: url))
            importNote = saved.isEmpty ? "Não achei lugares nesse arquivo." : "\(saved.count) lugares em \(url.lastPathComponent)"
        } catch {
            importNote = error.localizedDescription
        }
    }

    private func add() {
        guard let list else { return }
        for place in places where selectedBoard.contains(place.id) {
            place.list = list
            place.sub = nil
        }
        let cityId = currentCity?.id ?? trips.first?.cities.first?.id ?? region.rawValue
        let today = BoardDates(timeZone: region.timeZone).dayString(AppClock.now)
        for item in saved where selectedSaved.contains(item.id) {
            let place = Place(id: "m-\(UUID().uuidString.prefix(8).lowercased())", name: item.name, cityId: cityId,
                              lat: item.lat, lng: item.lng)
            place.list = list
            place.notes = item.note ?? ""
            place.source = Source(kind: .maps, url: item.url, savedAt: today)
            context.insert(place)
        }
        for c in candidates where selectedCandidates.contains(c.id) {
            let place = Place(id: "m-\(UUID().uuidString.prefix(8).lowercased())", name: c.name, cityId: cityId, lat: c.lat, lng: c.lng)
            place.list = list
            place.placeId = c.id
            place.approx = false
            place.source = Source(kind: .manual, url: nil, savedAt: today)
            context.insert(place)
            services.sync.resolveNew(place, candidate: c, region: region, context: context)
        }
        try? context.save()
        Log.data.info("adicionados \(selectionCount) a \(listId, privacy: .public)")
        finish(openList: true)
    }

    /// Fecha o fluxo; com `openList`, abre a lista no hub.
    private func finish(openList: Bool) {
        router.cover = nil
        if openList { router.push(.list(id: listId), on: .musts) }
    }
}
