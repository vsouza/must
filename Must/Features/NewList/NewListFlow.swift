import SwiftData
import SwiftUI

/// Nova lista (1 de 2) → Adicionar lugares (2 de 2), em tela cheia.
struct NewListFlow: View {
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            NewListView { listId in path.append(listId) }
                .navigationDestination(for: String.self) { id in
                    AddItemsView(listId: id)
                }
        }
    }
}

/// Editar lista (capa do Board e do hub): o mesmo formulário da Nova lista, com os valores atuais.
struct EditListFlow: View {
    var listId: String
    @Query(sort: \MustList.order) private var lists: [MustList]

    var body: some View {
        if let list = lists.first(where: { $0.id == listId }) {
            NewListView(editing: list)
        } else {
            V9.groupedBackground.ignoresSafeArea()
        }
    }
}

/// Nova lista: prévia ao vivo do tile, nome, kanji, ícone, cor e foto.
/// Com `editing`, o mesmo formulário edita a lista e mostra sub-listas, ordem e apagar.
struct NewListView: View {
    private let editing: MustList?
    var onCreated: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var trips: [TripInfo]

    @State private var name = ""
    @State private var kanji = ""
    @State private var icon: MustIcon = .cafe
    @State private var color: MustColor = .coffee
    @State private var showIcons = false
    @State private var createdId: String?
    @State private var photos: [CCPhoto] = []
    @State private var selectedPhoto: CCPhoto?
    @State private var photoNote: String?
    /// Modelo fora do contexto só pra prévia.
    @State private var preview = MustList(id: "preview", name: "", icon: .cafe, color: .coffee)
    /// Edição: a busca de fotos só roda quando o usuário pede "Trocar foto" (sem rede ao abrir).
    @State private var searchPhotos: Bool
    /// Edição: só grava a foto se o usuário escolheu uma (ou "sem foto").
    @State private var photoChanged = false
    @State private var subs: [String] = []
    @State private var newSub = ""
    @State private var confirmDelete = false
    @State private var error: String?

    static let suggestedIcons: [MustIcon] = [.cafe, .chaMatcha, .doceKonbini, .izakaya, .karaoke, .parqueNatureza, .cameraFoto]

    init(editing list: MustList? = nil, onCreated: @escaping (String) -> Void = { _ in }) {
        self.editing = list
        self.onCreated = onCreated
        _searchPhotos = State(initialValue: list == nil)
        if let list {
            _name = State(initialValue: list.name)
            _kanji = State(initialValue: list.kanji ?? "")
            _icon = State(initialValue: list.icon)
            _color = State(initialValue: list.color)
            _subs = State(initialValue: list.subs)
            _preview = State(initialValue: MustList(id: list.id, name: list.name, kanji: list.kanji, icon: list.icon, color: list.color))
        }
    }

    private var cityName: String {
        trips.first?.city(on: AppClock.now, calendar: store.region.calendar)?.name ?? store.region.displayName
    }

    /// Foto na prévia: a escolhida agora ou, editando sem trocar, a atual da lista.
    private var shownPhotoURL: URL? {
        if let selectedPhoto { return URL(string: selectedPhoto.largeURL ?? selectedPhoto.url) }
        if let editing, !photoChanged { return editing.photo?.url.flatMap(URL.init(string:)) }
        return nil
    }

    private var shownCredit: String? {
        if let selectedPhoto { return selectedPhoto.credit }
        if let editing, !photoChanged { return editing.photo?.credit }
        return nil
    }

    private var previewSubtitle: String {
        guard let editing else { return "\(cityName) · prévia" }
        let done = editing.places.filter(\.isDone).count
        return "\(editing.places.count) lugares · \(done) \(done == 1 ? "feito" : "feitos")"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.name).font(.headline).lineLimit(2)
                    Text(previewSubtitle).font(.subheadline).foregroundStyle(.secondary)
                    if let credit = shownCredit { Text("foto · \(credit)").font(.footnote).foregroundStyle(.secondary) }
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text("Prévia")
            }
            nameSection
            iconSection
            photoSection
            if editing != nil {
                subsSection
                orderSection
                deleteSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editing == nil ? "Nova lista" : "Editar lista")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? "Criar" : "Salvar", action: confirm)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("newlist.confirm")
            }
        }
        .v9Screen(grouped: true)
        .sheet(isPresented: $showIcons) {
            IconGridSheet(selected: $icon).presentationDetents([.medium, .large])
        }
        .onChange(of: name) { _, v in preview.name = v.trimmingCharacters(in: .whitespaces).isEmpty ? "…" : v }
        .onChange(of: kanji) { _, v in
            if v.count > 1 { kanji = String(v.suffix(1)) }
            preview.kanji = kanji
        }
        .onChange(of: icon) { _, v in preview.icon = v }
        .onChange(of: color) { _, v in preview.color = v }
        .onAppear { preview.name = name.isEmpty ? "…" : name }
        .task(id: "\(name)|\(cityName)|\(searchPhotos)") { await loadPhotos() }
    }

    private var nameSection: some View {
        Section {
            HStack(spacing: 8) {
                Text("Must").foregroundStyle(.secondary)
                TextField("kissaten", text: $name)
                    .accessibilityIdentifier("newlist.name")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        } header: {
            Text("Nome")
        }
    }

    private var iconSection: some View {
        Section("Ícone") {
            let suggested = Self.suggestedIcons.contains(icon) ? Self.suggestedIcons : [icon] + Self.suggestedIcons.dropLast()
            FlowLayout(spacing: 10) {
                ForEach(suggested) { item in
                    Button { icon = item } label: {
                        MustIconView(item, size: 22)
                            .foregroundStyle(icon == item ? V9.accent : Color.primary)
                            .frame(width: 44, height: 44)
                            .background(icon == item ? V9.accent.opacity(0.14) : V9.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(item.label)
                    .accessibilityAddTraits(icon == item ? .isSelected : [])
                }
                Button { showIcons = true } label: {
                    Text("+\(MustIcon.allCases.count - suggested.count)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .background(V9.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Todos os ícones")
            }
        }
    }

    @ViewBuilder private var photoSection: some View {
        if editing != nil && !searchPhotos {
            currentPhotoRow
        } else {
            photoOptions
        }
    }

    /// Edição: a foto atual, com "trocar foto" pra abrir a busca.
    private var currentPhotoRow: some View {
        Section("Foto de fundo") {
            HStack(spacing: 12) {
                Text(shownCredit.map { "foto · \($0)" } ?? "sem foto · só a cor")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Trocar foto") { searchPhotos = true }
                    .buttonStyle(.borderless)
                    .fixedSize()
            }
        }
    }

    private var photoOptions: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { selectedPhoto = nil; photoChanged = true } label: {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(V9.fill)
                            .frame(width: 84, height: 64)
                            .overlay(Text("sem foto").font(.caption).foregroundStyle(.secondary))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(V9.accent, lineWidth: selectedPhoto == nil ? 2 : 0))
                    }
                    ForEach(photos.prefix(4)) { photo in
                        Button { selectedPhoto = photo; photoChanged = true } label: {
                            TintedPhoto(url: URL(string: photo.url), color: color, tintOpacity: 0, saturation: 1)
                                .frame(width: 84, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(V9.accent, lineWidth: selectedPhoto == photo ? 2 : 0))
                        }
                        .accessibilityLabel("Foto de \(photo.owner)")
                    }
                    if photos.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(V9.fill).frame(width: 84, height: 64)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Foto de fundo · Wikimedia CC")
        } footer: {
            Text(photoNote ?? "Só fotos com licença CC, com crédito. Busca “\(name.isEmpty ? "…" : name) \(cityName.lowercased())”. Ou sem foto.")
        }
    }

    // MARK: Edição

    private var subsSection: some View {
        Section {
            ForEach(subs, id: \.self) { sub in
                HStack {
                    Text(sub)
                    Spacer()
                    Button { subs.removeAll { $0 == sub } } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Tirar \(sub)")
                }
            }
            HStack(spacing: 10) {
                TextField("nova sub-lista, ex.: ramen", text: $newSub)
                    .submitLabel(.done)
                    .onSubmit(addSub)
                if !newSub.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Adicionar", action: addSub).buttonStyle(.borderless).font(.body.weight(.semibold))
                }
            }
        } header: {
            Text("Sub-listas")
        } footer: {
            Text("Tirar uma sub-lista não apaga os lugares: eles ficam sem sub.")
        }
    }

    private var orderSection: some View {
        let position = lists.firstIndex { $0.id == editing?.id } ?? 0
        return Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Posição")
                    Text("\(position + 1) de \(lists.count) · no hub e no board").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button { moveList(-1) } label: { Image(systemName: "arrow.up").frame(width: 44, height: 44) }
                    .disabled(position == 0)
                    .accessibilityLabel("Subir")
                Button { moveList(1) } label: { Image(systemName: "arrow.down").frame(width: 44, height: 44) }
                    .disabled(position >= lists.count - 1)
                    .accessibilityLabel("Descer")
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Ordem")
        }
    }

    private var deleteSection: some View {
        let count = editing?.places.count ?? 0
        let others = lists.filter { $0.id != editing?.id }
        return Section {
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Button("Apagar lista", role: .destructive) { confirmDelete = true }
                .confirmationDialog("Apagar \(editing?.displayName ?? "lista")?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    if count == 0 {
                        Button("Apagar lista", role: .destructive) { deleteList(to: nil) }
                    } else {
                        ForEach(others) { other in
                            Button("Levar \(count) \(count == 1 ? "lugar" : "lugares") pra \(other.displayName) e apagar") {
                                deleteList(to: other)
                            }
                        }
                    }
                } message: {
                    if count == 0 {
                        Text("A lista está vazia.")
                    } else if others.isEmpty {
                        Text("Cria outra lista antes: os lugares precisam de pra onde ir.")
                    } else {
                        Text("Os lugares vão pra outra lista. Nada se perde.")
                    }
                }
        }
    }

    private func addSub() {
        let sub = newSub.trimmingCharacters(in: .whitespaces)
        newSub = ""
        guard !sub.isEmpty, !subs.contains(sub) else { return }
        subs.append(sub)
    }

    private func moveList(_ offset: Int) {
        guard let editing else { return }
        do { try BoardEdits.moveList(editing, by: offset, in: lists, context: context) } catch { self.error = error.localizedDescription }
    }

    private func deleteList(to target: MustList?) {
        guard let editing else { return }
        do {
            try BoardEdits.deleteList(editing, moveTo: target, lists: lists, context: context)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Ações

    private func confirm() {
        if editing != nil { saveEdit() } else { create() }
    }

    private func saveEdit() {
        guard let editing else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        do {
            try BoardEdits.saveList(editing, name: trimmed, kanji: kanji.isEmpty ? nil : kanji, icon: icon, color: color,
                                    photo: selectedPhoto?.listPhoto, changePhoto: photoChanged, subs: subs, context: context)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadPhotos() async {
        guard searchPhotos else { return }
        let query = name.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { photos = []; return }
        try? await Task.sleep(for: .milliseconds(600)) // espera parar de digitar
        guard !Task.isCancelled else { return }
        do {
            photos = try await searchWithFallback(query)
            photoNote = photos.isEmpty ? "Nada com licença CC pra essa busca — fica só a cor." : nil
            if let selectedPhoto, !photos.contains(selectedPhoto) { self.selectedPhoto = nil }
        } catch {
            photoNote = "Sem fotos agora: \(error.localizedDescription)"
        }
    }

    /// "kissaten Tóquio"; se vier pouco, só "kissaten".
    private func searchWithFallback(_ query: String) async throws -> [CCPhoto] {
        var photos = try await services.photos.search(text: "\(query) \(cityName)")
        if photos.count < 4 {
            let more = try await services.photos.search(text: query)
            photos += more.filter { m in !photos.contains { $0.id == m.id } }
        }
        return photos
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        if let createdId, let list = lists.first(where: { $0.id == createdId }) {
            list.name = trimmed
            list.kanji = kanji.isEmpty ? nil : kanji
            list.icon = icon
            list.color = color
            list.photo = selectedPhoto?.listPhoto
            ListCover.mark(list, chosen: selectedPhoto != nil, context: context)
        } else {
            let id = Self.uniqueId(for: trimmed, existing: Set(lists.map(\.id)))
            let list = MustList(id: id, name: trimmed, kanji: kanji.isEmpty ? nil : kanji, icon: icon, color: color,
                                photo: selectedPhoto?.listPhoto, order: (lists.map(\.order).max() ?? -1) + 1)
            context.insert(list)
            if selectedPhoto != nil { ListCover.mark(list, chosen: true, context: context) }
            createdId = id
            Log.data.info("nova lista \(id, privacy: .public)")
        }
        try? context.save()
        if let createdId { onCreated(createdId) }
    }

    static func uniqueId(for name: String, existing: Set<String>) -> String {
        let base = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        let slug = base.isEmpty ? "lista" : base
        var candidate = slug
        var n = 2
        while existing.contains(candidate) { candidate = "\(slug)-\(n)"; n += 1 }
        return candidate
    }
}

/// Grid com todos os ícones do set.
struct IconGridSheet: View {
    @Binding var selected: MustIcon
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                    ForEach(MustIcon.allCases.filter { !$0.isTextGlyph }) { icon in
                        Button {
                            selected = icon
                            dismiss()
                        } label: {
                            VStack(spacing: 5) {
                                MustIconView(icon, size: 22)
                                    .foregroundStyle(selected == icon ? V9.accent : Color.primary)
                                    .frame(width: 48, height: 48)
                                    .background(selected == icon ? V9.accent.opacity(0.14) : V9.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(icon.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.label)
                        .accessibilityAddTraits(selected == icon ? .isSelected : [])
                    }
                }
                .padding(V9.gutter)
            }
            .navigationTitle("Ícone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
        .v9Screen()
    }
}
