import SwiftData
import SwiftUI

/// Nova lista (1 de 2) → Adicionar lugares (2 de 2), em tela cheia.
struct NewListFlow: View {
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            NewListView { listId in path.append(listId) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    AddItemsView(listId: id).toolbar(.hidden, for: .navigationBar)
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
            Color.must.bg.ignoresSafeArea()
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
        // Botão fixo embaixo, FORA do scroll (antes sobrepunha o último bloco: fotos, créditos, "Salvar" em cima do texto).
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        IconButton(.fechar, label: "Fechar") { dismiss() }
                        Spacer()
                        Micro(editing == nil ? "nova lista · 1 de 2" : "editar lista")
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.top, 16)

                    ListTile(list: preview, height: 170, previewCount: editing?.places.count ?? 0,
                             previewSubtitle: previewSubtitle, photoURL: shownPhotoURL)
                        .overlay(alignment: .bottomTrailing) {
                            if let credit = shownCredit { Credit(credit, color: color.text).padding(10) }
                        }
                        .rotationEffect(.degrees(-1.2))
                        .padding(.top, 22)

                    nameSection.padding(.top, 34)
                    iconSection.padding(.top, 26)
                    colorSection.padding(.top, 26)
                    photoSection.padding(.top, 26)
                    if editing != nil {
                        subsSection.padding(.top, 26)
                        orderSection.padding(.top, 26)
                        deleteSection.padding(.top, 26)
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(editing == nil ? "Criar e adicionar lugares" : "Salvar",
                          icon: editing == nil ? .avancar : nil, iconTrailing: true, style: .dark, action: confirm)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .background(Color.must.bg)
        }
        .background(Color.must.bg.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: 10) {
            Micro("nome")
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Must").font(.must.archivo(17)).foregroundStyle(Color.must.secondary)
                    TextField("kissaten", text: $name)
                        .accessibilityIdentifier("newlist.name")
                        .font(.must.archivo(17, .semibold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.must.surface, in: Rectangle())
            }
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("ícone")
            let suggested = Self.suggestedIcons.contains(icon) ? Self.suggestedIcons : [icon] + Self.suggestedIcons.dropLast()
            FlowLayout(spacing: 10) {
                ForEach(suggested) { item in
                    Button { icon = item } label: {
                        MustIconView(item, size: 22)
                            .foregroundStyle(icon == item ? .white : Color.must.ink)
                            .frame(width: 44, height: 44)
                            .background(Rectangle()
                                .fill(icon == item ? Color.must.ink : Color.must.surface))
                    }
                    .buttonStyle(MustPressStyle())
                    .accessibilityLabel(item.label)
                }
                Button { showIcons = true } label: {
                    Text("+\(MustIcon.allCases.count - suggested.count)")
                        .font(.must.archivo(13, .semibold))
                        .foregroundStyle(Color.must.ink)
                        .frame(width: 44, height: 44)
                        .overlay(Rectangle()
                            .strokeBorder(Color(hex: 0xD5D8DD), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Todos os ícones")
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Micro("cor")
            // 12 cores em linha: rolagem horizontal (sem ela o HStack exige ~480 pt e empurra a tela inteira).
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MustColor.allCases) { c in
                        Button { color = c } label: {
                            Rectangle()
                                .fill(c.gradient)
                                .frame(width: 34, height: 34)
                                .padding(3)
                                .overlay(Rectangle().strokeBorder(Color.must.ink, lineWidth: color == c ? 2 : 0))
                        }
                        .buttonStyle(MustPressStyle())
                        .accessibilityLabel(c.label)
                        .accessibilityAddTraits(color == c ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
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
        VStack(alignment: .leading, spacing: 10) {
            Micro("foto de fundo")
            HStack(spacing: 12) {
                Text(shownCredit.map { "foto · \($0)" } ?? "sem foto · só a cor")
                    .mustMeta()
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { searchPhotos = true } label: { Pill("trocar foto") }
                    .buttonStyle(MustPressStyle())
                    .fixedSize()
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var photoOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Micro("foto de fundo · Wikimedia CC")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                Text("busca “\(name.isEmpty ? "…" : name) \(cityName.lowercased())”")
                    .mustMeta()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { selectedPhoto = nil; photoChanged = true } label: {
                        Rectangle()
                            .fill(color.gradient)
                            .frame(width: 84, height: 64)
                            .overlay(Text("sem foto").font(.must.mono(9)).foregroundStyle(color.text))
                            .overlay(Rectangle().strokeBorder(Color.must.ink, lineWidth: selectedPhoto == nil ? 2 : 0))
                    }
                    ForEach(photos.prefix(4)) { photo in
                        Button { selectedPhoto = photo; photoChanged = true } label: {
                            TintedPhoto(url: URL(string: photo.url), color: color, tintOpacity: 0.35)
                                .frame(width: 84, height: 64)
                                .clipShape(Rectangle())
                                .overlay(Rectangle().strokeBorder(Color.must.ink, lineWidth: selectedPhoto == photo ? 2 : 0))
                        }
                        .accessibilityLabel("Foto de \(photo.owner)")
                    }
                    if photos.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle().fill(Color.must.surface).frame(width: 84, height: 64)
                        }
                    }
                }
                .buttonStyle(MustPressStyle())
            }
            Text(photoNote ?? "Só fotos com licença CC · crédito fica no card · ou sem foto, só a cor.").mustMeta()
        }
    }

    // MARK: Edição

    private var subsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("sub-listas")
            if !subs.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(subs, id: \.self) { sub in
                        HStack(spacing: 8) {
                            Text(sub).font(.must.archivo(13, .semibold))
                            Button { subs.removeAll { $0 == sub } } label: {
                                MustIconView(.fechar, size: 10).foregroundStyle(Color.must.secondary)
                            }
                            .accessibilityLabel("Tirar \(sub)")
                        }
                        .foregroundStyle(Color.must.ink)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 13)
                        .background(Rectangle().fill(Color.must.surface))
                    }
                }
            }
            HStack(spacing: 10) {
                TextField("nova sub-lista, ex.: ramen", text: $newSub)
                    .font(.must.archivo(16))
                    .submitLabel(.done)
                    .onSubmit(addSub)
                if !newSub.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Adicionar", action: addSub).font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.must.surface, in: Rectangle())
            Text("Tirar uma sub-lista não apaga os lugares: eles ficam sem sub.").mustMeta()
        }
    }

    private var orderSection: some View {
        let position = lists.firstIndex { $0.id == editing?.id } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            Micro("ordem")
            FormSection {
                FormRow("Posição", subtitle: "\(position + 1) de \(lists.count) · no hub e no board") {
                    HStack(spacing: 8) {
                        Button { moveList(-1) } label: { Pill("subir") }
                            .disabled(position == 0)
                        Button { moveList(1) } label: { Pill("descer") }
                            .disabled(position >= lists.count - 1)
                    }
                    .buttonStyle(MustPressStyle())
                }
            }
        }
    }

    private var deleteSection: some View {
        let count = editing?.places.count ?? 0
        let others = lists.filter { $0.id != editing?.id }
        return VStack(alignment: .leading, spacing: 10) {
            if let error {
                Text(error).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D))
            }
            Button { confirmDelete = true } label: {
                Text("Apagar lista")
                    .font(.must.archivo(15, .semibold))
                    .foregroundStyle(Color(hex: 0xC2261D))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Rectangle().fill(.white))
                    .overlay(Rectangle().strokeBorder(Color(hex: 0xF1C9C6)))
            }
            .buttonStyle(MustPressStyle())
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
        VStack(spacing: 0) {
            SheetHandle()
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                    ForEach(MustIcon.allCases.filter { !$0.isTextGlyph }) { icon in
                        Button {
                            selected = icon
                            dismiss()
                        } label: {
                            VStack(spacing: 5) {
                                MustIconView(icon, size: 22)
                                    .foregroundStyle(selected == icon ? .white : Color.must.ink)
                                    .frame(width: 48, height: 48)
                                    .background(Rectangle().fill(selected == icon ? Color.must.ink : Color.must.surface))
                                Text(icon.label).font(.must.archivo(10)).foregroundStyle(Color.must.secondary).lineLimit(1)
                            }
                        }
                        .buttonStyle(MustPressStyle())
                    }
                }
                .padding(22)
            }
        }
        .background(Color.must.bg)
    }
}
