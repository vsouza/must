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

/// Nova lista: prévia ao vivo do tile, nome, kanji, ícone, cor e foto.
struct NewListView: View {
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
    @State private var photos: [FlickrPhoto] = []
    @State private var selectedPhoto: FlickrPhoto?
    @State private var photoNote: String?
    /// Modelo fora do contexto só pra prévia.
    @State private var preview = MustList(id: "preview", name: "", icon: .cafe, color: .coffee)

    static let suggestedIcons: [MustIcon] = [.cafe, .chaMatcha, .doceKonbini, .izakaya, .karaoke, .parqueNatureza, .cameraFoto]

    private var cityName: String {
        trips.first?.city(on: AppClock.now, calendar: store.region.calendar)?.name ?? store.region.displayName
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.must.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        IconButton(.fechar, label: "Fechar") { dismiss() }
                        Spacer()
                        Micro("nova lista · 1 de 2")
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.top, 16)

                    ListTile(list: preview, height: 170, previewCount: 0,
                             previewSubtitle: "\(cityName) · prévia",
                             photoURL: selectedPhoto.flatMap { URL(string: $0.largeURL ?? $0.url) })
                        .overlay(alignment: .bottomTrailing) {
                            if let selectedPhoto { Credit(selectedPhoto.credit, color: color.text).padding(10) }
                        }
                        .shadow(color: Color(hex: 0x121316, opacity: 0.14), radius: 25, x: 0, y: 20)
                        .rotationEffect(.degrees(-1.2))
                        .padding(.top, 22)

                    nameSection.padding(.top, 34)
                    iconSection.padding(.top, 26)
                    colorSection.padding(.top, 26)
                    photoSection.padding(.top, 26)
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton("Criar e adicionar lugares", icon: .avancar, iconTrailing: true, style: .dark, action: create)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 8)
                .background {
                    LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .center).ignoresSafeArea()
                }
        }
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
        .task(id: "\(name)|\(cityName)") { await loadPhotos() }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("nome")
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text("Must").font(.must.archivo(17)).foregroundStyle(Color.must.secondary)
                    TextField("kissaten", text: $name)
                        .font(.must.archivo(17, .semibold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                TextField("字", text: $kanji)
                    .font(.must.kanji(24))
                    .multilineTextAlignment(.center)
                    .frame(width: 72, height: 52)
                    .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Kanji")
            }
            Text("O kanji aparece grande no card e nos pinos do mapa — opcional.").mustMeta()
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
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
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
            HStack(spacing: 0) {
                ForEach(MustColor.allCases) { c in
                    Button { color = c } label: {
                        Circle()
                            .fill(c.gradient)
                            .frame(width: 34, height: 34)
                            .padding(3)
                            .overlay(Circle().strokeBorder(Color.must.ink, lineWidth: color == c ? 2 : 0))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MustPressStyle())
                    .accessibilityLabel(c.label)
                    .accessibilityAddTraits(color == c ? .isSelected : [])
                }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Micro("foto de fundo · Flickr CC")
                Spacer()
                Text("busca “\(name.isEmpty ? "…" : name) \(cityName.lowercased())”").mustMeta().lineLimit(1)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { selectedPhoto = nil } label: {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(color.gradient)
                            .frame(width: 84, height: 64)
                            .overlay(Text("sem foto").font(.must.mono(9)).foregroundStyle(color.text))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.must.ink, lineWidth: selectedPhoto == nil ? 2 : 0))
                    }
                    ForEach(photos.prefix(4)) { photo in
                        Button { selectedPhoto = photo } label: {
                            TintedPhoto(url: URL(string: photo.url), color: color, tintOpacity: 0.35)
                                .frame(width: 84, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.must.ink, lineWidth: selectedPhoto == photo ? 2 : 0))
                        }
                        .accessibilityLabel("Foto de \(photo.owner)")
                    }
                    if photos.isEmpty {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.must.surface).frame(width: 84, height: 64)
                        }
                    }
                }
                .buttonStyle(MustPressStyle())
            }
            Text(photoNote ?? "Só fotos com licença CC · crédito fica no card · ou sem foto, só a cor.").mustMeta()
        }
    }

    private func loadPhotos() async {
        let query = name.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { photos = []; return }
        guard services.flickr.isConfigured else { photoNote = "Fotos do Flickr aparecem quando a FLICKR_KEY estiver no Secrets.plist."; return }
        try? await Task.sleep(for: .milliseconds(600)) // espera parar de digitar
        guard !Task.isCancelled else { return }
        do {
            photos = try await services.flickr.search(text: "\(query) \(cityName)")
            photoNote = photos.isEmpty ? "Nada com licença CC pra essa busca — fica só a cor." : nil
            if let selectedPhoto, !photos.contains(selectedPhoto) { self.selectedPhoto = nil }
        } catch {
            photoNote = "Sem fotos agora: \(error.localizedDescription)"
        }
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
        } else {
            let id = Self.uniqueId(for: trimmed, existing: Set(lists.map(\.id)))
            let list = MustList(id: id, name: trimmed, kanji: kanji.isEmpty ? nil : kanji, icon: icon, color: color,
                                photo: selectedPhoto?.listPhoto, order: (lists.map(\.order).max() ?? -1) + 1)
            context.insert(list)
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
                                    .background(Circle().fill(selected == icon ? Color.must.ink : Color.must.surface))
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
