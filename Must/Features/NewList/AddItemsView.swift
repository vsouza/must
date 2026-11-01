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

    private var selectionCount: Int { selectedBoard.count + selectedSaved.count }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: 14) {
                        searchField
                        sourcePills
                        if let importNote { Text(importNote).mustMeta() }
                        results
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, -20)
                    Color.clear.frame(height: 120)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .ignoresSafeArea(edges: .top)
            bottomBar
        }
        .background(Color.must.bg.ignoresSafeArea())
        .sheet(isPresented: $showManual) {
            EditPlaceView(newInListId: listId, prefillName: query.isEmpty ? nil : query)
        }
        .sheet(isPresented: $showLink) {
            AddLinkView(initialURL: nil, preferredListId: listId)
        }
        .fileImporter(isPresented: $showSavedPicker, allowedContentTypes: [UTType(filenameExtension: "kml") ?? .xml, .json, .xml]) { result in
            loadSaved(result)
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .topLeading) {
            TintedPhoto(url: list?.photo?.url.flatMap(URL.init(string:)), color: color)
                .frame(height: 290)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.white.opacity(0), .white.opacity(0.95), .white], startPoint: .top, endPoint: .bottom)
                        .frame(height: 140)
                }
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Button { dismiss() } label: {
                        MustIconView(.voltar, size: 18).foregroundStyle(Color.must.ink)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.55)))
                    }
                    .buttonStyle(MustPressStyle())
                    .accessibilityLabel("Voltar")
                    Spacer()
                    Micro("nova lista · 2 de 2", color: color.text)
                    Spacer()
                    Button { finish(openList: false) } label: {
                        Text("Depois").font(.must.archivo(15, .semibold)).foregroundStyle(color.text)
                            .padding(.horizontal, 16).frame(height: 36)
                            .background(Capsule().fill(Color.white.opacity(0.55)))
                    }
                    .buttonStyle(MustPressStyle())
                }
                HStack(spacing: 14) {
                    MustIconView(list?.icon ?? .cafe, size: 22)
                        .foregroundStyle(color.text)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(Color.white.opacity(0.6)))
                    VStack(alignment: .leading, spacing: 2) {
                        Micro("criada agora", color: color.text)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(list?.displayName ?? "").font(.must.archivo(30, .semibold)).tracking(-0.6)
                            if let kanji = list?.kanji { Text(kanji).font(.must.kanji(20)) }
                        }
                        .foregroundStyle(Color.must.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 62)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            MustIconView(.buscar, size: 16).foregroundStyle(Color.must.secondary)
            TextField("Buscar nome ou bairro…", text: $query)
                .font(.must.archivo(16))
                .autocorrectionDisabled()
            Button { showLink = true } label: {
                Text("link").font(.must.mono(12, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).frame(height: 26)
                    .background(Capsule().fill(Color.must.ink))
            }
            Button { showManual = true } label: {
                Text("manual").font(.must.mono(12, .semibold)).foregroundStyle(Color.must.ink)
                    .padding(.horizontal, 9).frame(height: 26)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .glass(cornerRadius: 26)
    }

    private var sourcePills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { source = .places } label: { Pill("Places · \(currentCity?.name ?? region.displayName)", isOn: source == .places) }
                Button { source = .board } label: { Pill("Do board", isOn: source == .board) }
                ForEach(otherCityNames, id: \.self) { name in
                    Button { source = .city(name) } label: { Pill(name, isOn: source == .city(name)) }
                }
                Button {
                    source = .saved
                    if saved.isEmpty { showSavedPicker = true }
                } label: { Pill("Salvos no Maps", isOn: source == .saved) }
            }
            .buttonStyle(MustPressStyle())
        }
        .scrollClipDisabled()
    }

    // MARK: Resultados

    @ViewBuilder private var results: some View {
        VStack(spacing: 0) {
            switch source {
            case .places:
                Text("A busca no Google Places entra com a chave do Secrets.plist (prompt 07). Por enquanto: do board, salvos no Maps, à mão ou por link.")
                    .mustMeta()
                    .padding(.vertical, 18)
            case .board, .city:
                ForEach(Array(boardResults.enumerated()), id: \.element.id) { i, place in
                    if i > 0 { RowDivider() }
                    checkRow(selected: selectedBoard.contains(place.id),
                             title: place.name, local: place.nameLocal,
                             meta: [place.area, place.list.map { "já estava no board · \($0.displayName)" }].compactMap { $0 }.joined(separator: " · "),
                             badge: "board") {
                        toggle(&selectedBoard, place.id)
                    }
                }
            case .saved:
                if savedResults.isEmpty {
                    Button { showSavedPicker = true } label: {
                        Text("Escolher o arquivo .kml (My Maps) ou o Saved Places.json do Takeout")
                            .font(.must.meta).foregroundStyle(Color.must.ink).underline()
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.vertical, 18)
                }
                ForEach(Array(savedResults.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { RowDivider() }
                    checkRow(selected: selectedSaved.contains(item.id), title: item.name, local: nil,
                             meta: item.note ?? String(format: "%.4f, %.4f", item.lat, item.lng), badge: "Maps") {
                        toggle(&selectedSaved, item.id)
                    }
                }
            }
            RowDivider()
            Button { showManual = true } label: {
                HStack(spacing: 14) {
                    MustIconView(.adicionar, size: 18)
                        .foregroundStyle(color.text)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(color.gradient))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Adicionar à mão").font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
                        Text(query.isEmpty ? "nome, bairro, preço, janela" : "“\(query)”").mustMeta()
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
    }

    private func checkRow(selected: Bool, title: String, local: String?, meta: String, badge: String,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    if selected {
                        Circle().fill(color.strong)
                        MustIconView(.ok, size: 15).foregroundStyle(color.text)
                    } else {
                        Circle().strokeBorder(Color(hex: 0xD5D8DD), lineWidth: 1.5)
                    }
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(title).mustPlace().lineLimit(1)
                        if let local { Text(local).font(.must.kanji(12, bold: false)).foregroundStyle(Color.must.secondary).lineLimit(1) }
                    }
                    Text(meta).mustMeta().lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(badge).font(.must.mono(11, .semibold)).foregroundStyle(Color.must.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.must.surface))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { showLink = true } label: {
                MustIconView(.colarLink, size: 20).foregroundStyle(Color.must.ink)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.white))
                    .overlay(Circle().strokeBorder(Color.must.lineStrong))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Colar link")

            Button { add() } label: {
                HStack(spacing: 9) {
                    Text(selectionCount == 0 ? "Escolha lugares" : "Adicionar \(selectionCount) à lista")
                    MustIconView(.ok, size: 18)
                }
                .font(.must.archivo(15, .bold))
                .foregroundStyle(color.text)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule().fill(color.gradient))
            }
            .buttonStyle(MustPressStyle())
            .disabled(selectionCount == 0)
            .opacity(selectionCount == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .center).ignoresSafeArea()
        }
    }

    // MARK: Ações

    private func toggle(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
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
