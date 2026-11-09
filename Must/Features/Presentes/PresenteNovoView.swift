import MapKit
import PhotosUI
import SwiftData
import SwiftUI

/// Novo presente (`design/v9/Presentes-Adicionar.png`): o quê, de onde veio (Nome · Link · Vídeo · Local · Foto), pra quem,
/// preço × quantidade e onde comprar. Link e vídeo são lidos no aparelho e só preenchem o que está vazio.
///
/// **Rota/folha pra o `+` e o Share Extension:** `AppRouter.Sheet.presenteNovo(source:)` (`source` = link colado ou
/// `must-video://<id da caixa>`); `Route.presentes` abre a lista e `Route.presente(id:)` o detalhe.
struct PresenteNovoView: View {
    var editing: Gift?
    /// Link ou `must-video://<id>` que já chega preenchido (conferência do Share Extension).
    var source: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var gifts: [Gift]
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]
    @Query private var trips: [TripInfo]
    @Query private var lists: [MustList]

    @State private var title = ""
    @State private var tab: GiftSource = .name
    @State private var person = ""
    @State private var extraPeople: [String] = []
    @State private var quantity = 1
    @State private var priceText = ""
    @State private var placeId: String?
    @State private var storeName = ""
    @State private var storeLat: Double?
    @State private var storeLng: Double?
    @State private var storeAddress = ""
    @State private var chain = false
    @State private var note = ""
    @State private var sourceURL: String?
    @State private var sourceLabel = ""
    @State private var clip: String?
    @State private var videoInboxId: String?
    @State private var linkInput = ""
    @State private var reading = false
    @State private var readNote: String?
    @State private var addingPerson = false
    @State private var newPerson = ""
    @State private var picking = false
    @State private var pickedVideo: PhotosPickerItem?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var loaded = false
    @FocusState private var titleFocused: Bool

    init(editing: Gift? = nil, source: String? = nil) {
        self.editing = editing
        self.source = source
    }

    private var region: Region { store.region }
    private var money: GiftMoney { GiftMoney(region: region, userRate: settingsList.first?.fxRate) }
    private var price: Double { Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var people: [String] { Array(Set(GiftLogic.people(gifts) + extraPeople)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    /// Região da busca de loja de fora: a cidade da viagem (GPS só se estiver nela).
    private var storeSearchRegion: MKCoordinateRegion {
        let city = GiftStoreSearch.cityCenter(trip: trips.first, now: AppClock.now, region: region)
        return GiftStoreSearch.searchRegion(gps: services.location.current?.coordinate, cityCenter: city.center, hasCurrentCity: city.current)
    }

    /// Loja de fora: fica no presente (nome, coordenada, endereço); "+ board" também guarda no board (lista Shop).
    private func pickOutside(_ hit: GiftStoreSearch.Hit, addToBoard: Bool) {
        chain = false
        if tab == .name { tab = .place }
        if addToBoard {
            let trip = trips.first
            let cityId = trip?.city(on: AppClock.now, calendar: region.calendar)?.id ?? trip?.cities.first?.id ?? region.rawValue
            let row = QueroRow.minimal(GiftStoreSearch.wantResult(hit))
            if let place = QueroSave.place(for: row, intent: nil, text: title, lists: lists, cityId: cityId, region: region,
                                           sync: services.sync, context: context) {
                placeId = place.id
                storeName = place.name
                storeLat = nil; storeLng = nil; storeAddress = ""
                return
            }
        }
        placeId = nil
        storeName = hit.name
        storeLat = hit.lat
        storeLng = hit.lng
        storeAddress = hit.address
    }

    private var shopStores: [GiftTextGuess.Store] { places.filter { $0.list?.id == "shop" }.map { .init(id: $0.id, name: $0.name) } }

    var body: some View {
        NavigationStack {
            Form {
                whatField
                tabs
                sourceBlock
                personBlock
                priceBlock
                whereBlock
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "Novo presente" : "Editar presente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Guardar" : "Salvar", action: save).disabled(!canSave)
                }
            }
        }
        .v9Screen(grouped: true)
        .alert("Nova pessoa", isPresented: $addingPerson) {
            TextField("Nome", text: $newPerson)
            Button("Cancelar", role: .cancel) { newPerson = "" }
            Button("Adicionar") {
                let name = newPerson.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { extraPeople.append(name); person = name }
                newPerson = ""
            }
        }
        .sheet(isPresented: $picking) {
            GiftStorePicker(places: places, searchRegion: storeSearchRegion, online: services.connectivity.status != .offline,
                            onPick: { place in
                placeId = place.id
                storeName = place.name
                storeLat = nil
                storeLng = nil
                storeAddress = ""
                chain = false
                if tab == .name { tab = .place }
            }, onPickOutside: { hit, addToBoard in pickOutside(hit, addToBoard: addToBoard) })
        }
        .onChange(of: pickedVideo) { _, item in
            guard let item else { return }
            Task {
                reading = true
                if let video = try? await item.loadTransferable(type: PickedVideo.self) {
                    apply(await GiftReader.readVideo(video.url, region: region, caption: nil, stores: shopStores), kind: .video)
                    try? FileManager.default.removeItem(at: video.url)
                } else {
                    readNote = "Não consegui abrir esse vídeo."
                }
                reading = false
                pickedVideo = nil
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                reading = true
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    apply(await GiftReader.readPhoto(image, stores: shopStores), kind: .photo)
                } else {
                    readNote = "Não consegui abrir essa foto."
                }
                reading = false
                pickedPhoto = nil
            }
        }
        .task { await load() }
    }

    // MARK: Campos

    private var whatField: some View {
        Section {
            TextField("Kit Kat de matcha", text: $title, axis: .vertical)
                .lineLimit(1...3)
                .focused($titleFocused)
                .accessibilityLabel("O quê")
        } header: {
            Text("O quê")
        } footer: {
            Text("\(region.shortName) · moeda \(MoneyFormatStyle.symbol(for: region.currency))")
        }
    }

    // MARK: Origem

    private var tabs: some View {
        Section("De onde veio") {
            Picker("De onde veio", selection: $tab) {
                ForEach(GiftSource.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder private var sourceBlock: some View {
        switch tab {
        case .name:
            Section { Text("Só o nome já basta. Dá pra completar com um link, um vídeo, uma loja ou uma foto.").font(.subheadline).foregroundStyle(.secondary) }
        case .link:
            Section {
                HStack(spacing: 10) {
                    TextField("cole o link", text: $linkInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Button(reading ? "Lendo…" : "Ler") { Task { await readLink() } }
                        .disabled(reading || linkInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } footer: {
                if let readNote { Text(readNote) }
            }
        case .video:
            videoBlock
        case .place:
            Section {
                Button { picking = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(storeName.isEmpty ? "Escolher a loja" : storeName).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text("do seu board ou do mapa da cidade").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
            }
        case .photo:
            Section {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text(reading ? "Lendo…" : "Escolher a foto")
                }
            } footer: {
                Text(readNote ?? "Etiqueta, embalagem ou um print: o nome e o preço são lidos no aparelho.")
            }
        }
    }

    private var videoBlock: some View {
        Section {
            if videoInboxId != nil || sourceURL != nil || reading || !sourceLabel.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    let origin = [sourceURL.flatMap { LinkResolver.resolve($0).source.rawValue }, sourceLabel.isEmpty ? nil : sourceLabel, clip]
                        .compactMap { $0 }.joined(separator: " · ")
                    if !origin.isEmpty { Text(origin).font(.footnote).foregroundStyle(.secondary) }
                    Text(reading ? "Lendo o vídeo no aparelho…" : "Lido no aparelho (fala e texto na tela). Confira o que foi preenchido.")
                        .font(.subheadline)
                }
            } else {
                PhotosPicker(selection: $pickedVideo, matching: .videos, preferredItemEncoding: .current) {
                    Text("Escolher a gravação")
                }
            }
        } footer: {
            if videoInboxId == nil && sourceURL == nil && !reading {
                Text(readNote ?? "Grave a tela do reel e escolha aqui, ou compartilhe o vídeo com o Must. Fala e texto da tela são lidos no aparelho.")
            }
        }
    }

    // MARK: Pra quem

    private var personBlock: some View {
        Section("Pra quem") {
            Picker("Pra quem", selection: $person) {
                Text("Ninguém ainda").tag("")
                ForEach(people, id: \.self) { Text($0).tag($0) }
            }
            Button("Nova pessoa…") { addingPerson = true }
        }
    }

    // MARK: Preço

    private var priceBlock: some View {
        Section {
            HStack(spacing: 10) {
                Text(MoneyFormatStyle.symbol(for: region.currency)).foregroundStyle(.secondary)
                TextField("0", text: $priceText)
                    .keyboardType(.decimalPad)
                    .monospacedDigit()
                    .accessibilityLabel("Preço de cada")
            }
            Stepper("Quantidade: \(quantity)", value: $quantity, in: 1...99)
        } header: {
            Text("Preço estimado · cada")
        } footer: {
            if let brl = money.brl(price * Double(quantity)), price > 0 { Text("\(brl) no total") }
        }
    }

    // MARK: Onde comprar

    private var whereBlock: some View {
        Section("Onde comprar") {
            if !storeName.isEmpty && !chain {
                storeRow(storeName, sub: chosenSub, selected: true) {}
            }
            if !storeName.isEmpty {
                storeRow("Qualquer \(storeName)", sub: "avisa perto de qualquer loja da rede", selected: chain) {
                    chain.toggle()
                    if chain { placeId = nil; storeLat = nil; storeLng = nil }
                }
            }
            storeRow("Escolher no board ou buscar no mapa", sub: "uma loja sua ou qualquer loja da cidade", selected: false, arrow: true) { picking = true }
        }
    }

    private var chosenSub: String {
        if placeId != nil { return "do board" }
        if storeLat != nil { return ["fora do board", storeAddress.isEmpty ? nil : storeAddress].compactMap { $0 }.joined(separator: " · ") }
        return tab.metaLabel ?? "loja escolhida"
    }

    private func storeRow(_ title: String, sub: String, selected: Bool, arrow: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    Text(sub).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                if arrow { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
                else if selected { Image(systemName: "checkmark").foregroundStyle(V9.accent) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Leitura

    private func readLink() async {
        reading = true
        readNote = nil
        let trimmed = linkInput.trimmingCharacters(in: .whitespaces)
        let guess = await GiftReader.readLink(trimmed, stores: shopStores)
        sourceURL = LinkResolver.resolve(trimmed).url?.absoluteString ?? sourceURL
        apply(guess, kind: .link)
        if guess == nil { readNote = "Não consegui ler esse link. Digite o nome." }
        reading = false
    }

    /// Só preenche o que está vazio; a pessoa continua dona do que digitou.
    private func apply(_ guess: GiftGuess?, kind: GiftSource) {
        guard let guess, !guess.isEmpty else {
            readNote = "Não achei nome nem preço. Digite o nome."
            return
        }
        tab = kind
        if title.trimmingCharacters(in: .whitespaces).isEmpty, let t = guess.title { title = t }
        if price == 0, let p = guess.price { priceText = p.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US"))) }
        if quantity == 1, let q = guess.quantity { quantity = q }
        if let author = guess.author, sourceLabel.isEmpty { sourceLabel = author }
        if placeId == nil, storeName.isEmpty, let s = guess.storeName {
            storeName = s
            placeId = guess.storeId
            chain = guess.chain
            if let id = guess.storeId, let p = places.first(where: { $0.id == id }) { storeLat = nil; storeLng = nil; storeAddress = ""; storeName = p.name }
        }
        readNote = nil
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        if let g = editing {
            title = g.title; person = g.person == GiftLogic.noPerson ? "" : g.person; quantity = g.quantity
            priceText = g.estimatedPrice > 0 ? g.estimatedPrice.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US"))) : ""
            placeId = g.placeId; storeName = g.storeName; storeLat = g.storeLat; storeLng = g.storeLng; storeAddress = g.storeAddress; chain = g.chain
            note = g.note; sourceURL = g.sourceURL; sourceLabel = g.sourceLabel; clip = g.videoClip; videoInboxId = g.videoInboxId
            tab = g.source; linkInput = g.sourceURL ?? ""
            if let id = g.placeId, let p = places.first(where: { $0.id == id }) { storeName = p.name }
            return
        }
        #if DEBUG
        if DebugFlags.string("debugScreen") == "presente-novo" {
            title = "Kit Kat de matcha"; person = "Ana"; quantity = 3; priceText = "1200"; tab = .video
            storeName = "Don Quijote Shinjuku"; sourceLabel = "@tokyosnacks"; clip = "0:12–0:19"; videoInboxId = "demo"
            return
        }
        #endif
        titleFocused = source == nil
        guard let source else { return }
        if source.hasPrefix(AddLinkModel.videoPrefix) {
            let id = String(source.dropFirst(AddLinkModel.videoPrefix.count))
            tab = .video
            videoInboxId = id
            guard let item = ShareInbox.item(id: id), let file = ShareInbox.fileURL(for: item) else {
                readNote = "Esse vídeo já saiu da caixa. Compartilhe de novo."
                return
            }
            reading = true
            apply(await GiftReader.readVideo(file, region: region, caption: nil, stores: shopStores), kind: .video)
            ShareInbox.remove(id: id)
            reading = false
        } else {
            linkInput = source
            tab = .link
            sourceURL = LinkResolver.resolve(source).url?.absoluteString
            await readLink()
        }
    }

    // MARK: Guardar

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let gift = editing ?? Gift(title: name, order: gifts.count)
        if editing == nil { context.insert(gift) }
        gift.title = name
        gift.person = person
        gift.quantity = quantity
        gift.estimatedPrice = price
        gift.source = tab
        gift.placeId = chain ? nil : placeId
        gift.storeName = storeName
        gift.storeLat = chain ? nil : storeLat
        gift.storeLng = chain ? nil : storeLng
        gift.storeAddress = chain || placeId != nil ? "" : storeAddress
        gift.chain = chain
        gift.note = note
        gift.sourceURL = sourceURL
        gift.sourceLabel = sourceLabel
        gift.videoClip = clip
        gift.videoInboxId = nil
        if let id = gift.placeId, let place = places.first(where: { $0.id == id }) { gift.storeName = place.name }
        try? context.save()
        dismiss()
    }
}

/// Seletor de loja: as do board em cima e, buscando, as de fora embaixo. A busca de fora é o MapKit na cidade da
/// viagem, só ao enviar; sem internet, só o board.
struct GiftStorePicker: View {
    var places: [Place]
    var searchRegion: MKCoordinateRegion
    var online: Bool
    var onPick: (Place) -> Void
    var onPickOutside: (GiftStoreSearch.Hit, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [GiftStoreSearch.Hit] = []
    @State private var searching = false
    @State private var searched = ""

    private var filtered: [Place] {
        let all = places.sorted { ($0.list?.id == "shop" ? 0 : 1, $0.name) < ($1.list?.id == "shop" ? 0 : 1, $1.name) }
        guard !query.isEmpty else { return all }
        return all.filter { $0.matches(query) }
    }

    private var outside: [GiftStoreSearch.Hit] {
        GiftStoreSearch.outside(hits, board: places.map { ($0.name, $0.lat, $0.lng) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Seu board") {
                    ForEach(filtered) { place in
                        Button { onPick(place); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                Text([place.list?.name.capitalized, place.area].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                    }
                }
                outsideSection
            }
            .navigationTitle("Escolher a loja")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Nome da loja")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        }
        .v9Screen(grouped: true)
    }

    @ViewBuilder private var outsideSection: some View {
        let typed = query.trimmingCharacters(in: .whitespaces)
        if typed.count >= 2 {
            Section("Na cidade") {
                if !online {
                    note("Sem internet · só as lojas do seu board")
                } else if searched != typed || searching {
                    Button(searching ? "Buscando no mapa…" : "Buscar “\(typed)” na cidade") { Task { await search() } }
                        .disabled(searching)
                } else if outside.isEmpty {
                    note("Nenhuma loja de fora do board com esse nome na cidade")
                }
                ForEach(outside) { hit in outsideRow(hit) }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
    }

    private func outsideRow(_ hit: GiftStoreSearch.Hit) -> some View {
        HStack(spacing: 8) {
            Button { onPickOutside(hit, false); dismiss() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    Text(["fora do board", hit.address.isEmpty ? nil : hit.address].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("+ Board") { onPickOutside(hit, true); dismiss() }
                .buttonStyle(.bordered)
                .accessibilityLabel("Guardar \(hit.name) no board")
        }
    }

    private func search() async {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard online, typed.count >= 2, !searching else { return }
        searching = true
        hits = await GiftStoreSearch.search(typed, region: searchRegion)
        searched = typed
        searching = false
    }
}
