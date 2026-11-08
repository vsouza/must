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

    @Query private var gifts: [Gift]
    @Query private var places: [Place]
    @Query private var settingsList: [Settings]

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
    private var shopStores: [GiftTextGuess.Store] { places.filter { $0.list?.id == "shop" }.map { .init(id: $0.id, name: $0.name) } }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    whatField
                    tabs
                    sourceBlock
                    personBlock
                    priceBlock
                    whereBlock
                    Color.clear.frame(height: 24)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            Button(action: save) {
                Text(editing == nil ? "Guardar presente" : "Guardar").font(V8Font.text(20, weight: .bold)).foregroundStyle(V8.ink)
                    .frame(maxWidth: .infinity, minHeight: 58).background(V8.orange.opacity(canSave ? 1 : 0.4)).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .background(V8.paper.ignoresSafeArea())
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
            GiftStorePicker(places: places) { place in
                placeId = place.id
                storeName = place.name
                storeLat = nil
                storeLng = nil
                chain = false
                if tab == .name { tab = .place }
            }
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

    // MARK: Topo e campo

    private var topBar: some View {
        HStack(spacing: 12) {
            GiftSquareButton(systemName: "xmark", label: "Fechar") { dismiss() }
            VStack(alignment: .leading, spacing: 3) {
                SpecLabel(editing == nil ? "Novo presente" : "Editar presente", color: V8.white)
                SpecLabel("\(region.shortName) · moeda \(MoneyFormatStyle.symbol(for: region.currency))", color: V8.white)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(V8.ink.ignoresSafeArea(edges: .top))
        .lightStatusBar()
    }

    private var whatField: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("o quê", size: 10, color: V8.mute)
            TextField("", text: $title, prompt: Text("Kit Kat de matcha").foregroundStyle(V8.ink.opacity(0.3)), axis: .vertical)
                .font(V8Font.display(40))
                .tracking(-1.2)
                .foregroundStyle(V8.ink)
                .tint(V8.orange)
                .lineLimit(1...3)
                .focused($titleFocused)
                .accessibilityLabel("O quê")
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 14)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    // MARK: Origem

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(GiftSource.allCases) { item in
                Button { tab = item } label: {
                    Text(item.label.uppercased())
                        .font(V8Font.mono(11, weight: .semibold)).tracking(1)
                        .foregroundStyle(tab == item ? V8.paper : V8.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(tab == item ? V8.ink : V8.paper)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
                if item != GiftSource.allCases.last { Rectangle().fill(V8.ink).frame(width: 2) }
            }
        }
        .overlay(alignment: .bottom) { IndexRule() }
    }

    @ViewBuilder private var sourceBlock: some View {
        switch tab {
        case .name:
            hint("Só o nome já basta. Dá pra completar com um link, um vídeo, uma loja ou uma foto.")
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    TextField("", text: $linkInput, prompt: Text("cole o link").foregroundStyle(V8.mute))
                        .font(V8Font.text(15)).foregroundStyle(V8.ink).tint(V8.orange)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .padding(.horizontal, 12).frame(minHeight: 46)
                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                    Button { Task { await readLink() } } label: {
                        Text(reading ? "LENDO…" : "LER").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.paper)
                            .padding(.horizontal, 14).frame(minHeight: 46).background(V8.ink).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(reading || linkInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let readNote { Text(readNote).font(V8Font.text(13)).foregroundStyle(V8.mute) }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        case .video:
            videoBlock
        case .place:
            Button { picking = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(storeName.isEmpty ? "Escolher a loja" : storeName).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink)
                        Text("do seu board (Compras e Musts)").font(V8Font.text(13)).foregroundStyle(V8.mute)
                    }
                    Spacer()
                    Text("→").foregroundStyle(V8.ink)
                }
                .padding(.horizontal, 20).padding(.vertical, 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .photo:
            VStack(alignment: .leading, spacing: 10) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Text(reading ? "LENDO…" : "ESCOLHER A FOTO").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.paper)
                        .padding(.horizontal, 14).frame(minHeight: 46).background(V8.ink)
                }
                Text(readNote ?? "Etiqueta, embalagem ou um print: o nome e o preço são lidos no aparelho.")
                    .font(V8Font.text(13)).foregroundStyle(V8.mute)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
    }

    private var videoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if videoInboxId != nil || sourceURL != nil || reading || !sourceLabel.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel([sourceURL.flatMap { LinkResolver.resolve($0).source.rawValue }, sourceLabel.isEmpty ? nil : sourceLabel, clip]
                        .compactMap { $0 }.joined(separator: " · "), size: 10, color: V8.white)
                    Text(reading ? "Lendo o vídeo no aparelho…" : "Lido no aparelho (fala e texto na tela). Confira o que foi preenchido.")
                        .font(V8Font.text(15)).foregroundStyle(V8.white)
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(V8.ink)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $pickedVideo, matching: .videos, preferredItemEncoding: .current) {
                        Text("ESCOLHER A GRAVAÇÃO").font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.paper)
                            .padding(.horizontal, 14).frame(minHeight: 46).background(V8.ink)
                    }
                    Text(readNote ?? "Grave a tela do reel e escolha aqui, ou compartilhe o vídeo com o Must. Fala e texto da tela são lidos no aparelho.")
                        .font(V8Font.text(13)).foregroundStyle(V8.mute)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
            }
        }
        .overlay(alignment: .bottom) { if videoInboxId == nil && sourceURL == nil { EmptyView() } }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(V8Font.text(13)).foregroundStyle(V8.mute)
            .padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pra quem

    private var personBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("pra quem", size: 10, color: V8.mute)
            FlowLayout(spacing: 10) {
                ForEach(people, id: \.self) { name in
                    Button { person = person == name ? "" : name } label: { CutChip(text: name, isOn: person == name) }
                        .buttonStyle(.plain)
                }
                Button { addingPerson = true } label: { CutChip(text: "+ pessoa") }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { IndexRule() }
        .overlay(alignment: .bottom) { IndexRule() }
    }

    // MARK: Preço

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("preço estimado · cada", size: 10, color: V8.mute)
            HStack(alignment: .center, spacing: 14) {
                Text(MoneyFormatStyle.symbol(for: region.currency)).font(V8Font.mono(30, weight: .semibold)).foregroundStyle(V8.ink)
                TextField("", text: $priceText, prompt: Text("0").foregroundStyle(V8.ink.opacity(0.25)))
                    .font(V8Font.mono(36, weight: .semibold)).foregroundStyle(V8.ink).tint(V8.orange)
                    .keyboardType(.decimalPad).minimumScaleFactor(0.5)
                    .frame(minWidth: 80)
                    .accessibilityLabel("Preço de cada")
                stepper
                Spacer(minLength: 0)
            }
            if let brl = money.brl(price * Double(quantity)), price > 0 {
                Text("\(brl) no total").font(V8Font.text(14)).foregroundStyle(V8.mute)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("minus", "Menos um") { quantity = max(1, quantity - 1) }
            Rectangle().fill(V8.ink).frame(width: 2)
            Text("\(quantity)").font(V8Font.mono(18, weight: .bold)).foregroundStyle(V8.ink).frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Quantidade \(quantity)")
            Rectangle().fill(V8.ink).frame(width: 2)
            stepButton("plus", "Mais um") { quantity = min(99, quantity + 1) }
        }
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
    }

    private func stepButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(V8.ink).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Onde comprar

    private var whereBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel("onde comprar", size: 10, color: V8.mute).padding(.horizontal, 20).padding(.vertical, 14)
            if !storeName.isEmpty && !chain {
                storeRow(storeName, sub: chosenSub, selected: true, orange: true) {}
            }
            if !storeName.isEmpty {
                storeRow("Qualquer \(storeName)", sub: "avisa perto de qualquer loja da rede", selected: chain, orange: chain && placeId == nil) {
                    chain.toggle()
                    if chain { placeId = nil; storeLat = nil; storeLng = nil }
                }
            }
            storeRow("Escolher no board ou no mapa", sub: "uma loja sua ou do Explorar", selected: false, orange: false, arrow: true) { picking = true }
        }
        .overlay(alignment: .top) { IndexRule() }
    }

    private var chosenSub: String {
        [tab.metaLabel, placeId != nil ? "do board" : nil].compactMap { $0 }.first ?? "loja escolhida"
    }

    private func storeRow(_ title: String, sub: String, selected: Bool, orange: Bool, arrow: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                    Text(sub).font(V8Font.text(13)).foregroundStyle(orange ? V8.ink.opacity(0.75) : V8.mute).lineLimit(1)
                }
                Spacer(minLength: 8)
                if arrow { Text("→").foregroundStyle(V8.mute) }
                else if selected { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(V8.ink)
                    .frame(width: 30, height: 30).overlay(Rectangle().stroke(V8.ink, lineWidth: 2)) }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(orange ? V8.orange : V8.paper)
            .overlay(alignment: .bottom) { IndexRule() }
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
            if let id = guess.storeId, let p = places.first(where: { $0.id == id }) { storeLat = nil; storeLng = nil; storeName = p.name }
        }
        readNote = nil
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        if let g = editing {
            title = g.title; person = g.person == GiftLogic.noPerson ? "" : g.person; quantity = g.quantity
            priceText = g.estimatedPrice > 0 ? g.estimatedPrice.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US"))) : ""
            placeId = g.placeId; storeName = g.storeName; storeLat = g.storeLat; storeLng = g.storeLng; chain = g.chain
            note = g.note; sourceURL = g.sourceURL; sourceLabel = g.sourceLabel; clip = g.videoClip; videoInboxId = g.videoInboxId
            tab = g.source; linkInput = g.sourceURL ?? ""
            if let id = g.placeId, let p = places.first(where: { $0.id == id }) { storeName = p.name }
            return
        }
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

/// Seletor de loja do board (Compras primeiro, depois o resto), com busca por nome.
struct GiftStorePicker: View {
    var places: [Place]
    var onPick: (Place) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Place] {
        let all = places.sorted { ($0.list?.id == "shop" ? 0 : 1, $0.name) < ($1.list?.id == "shop" ? 0 : 1, $1.name) }
        guard !query.isEmpty else { return all }
        return all.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                GiftSquareButton(systemName: "xmark", label: "Fechar") { dismiss() }
                MonoLabel("escolher a loja", size: 11, color: V8.white)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 10).background(V8.ink)
            CutSearchField(text: $query, placeholder: "Nome da loja") { EmptyView() }.padding(.horizontal, 20)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { place in
                        Button { onPick(place); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                                Text([place.list?.name.capitalized, place.area].compactMap { $0 }.joined(separator: " · "))
                                    .font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .overlay(alignment: .bottom) { IndexRule() }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(V8.paper.ignoresSafeArea())
    }
}
