import CoreLocation
import SwiftData
import SwiftUI

/// "Cola o link": Reel, TikTok, YouTube, Maps ou um nome → lugares do board.
struct AddLinkView: View {
    var initialURL: String?
    var preferredListId: String?
    /// Aba de entrada: o Quero… abre direto em Link ou Texto (prompt 25 · A: viraram abas secundárias dele).
    var initialMode: AddMode = .link

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    /// Leituras de link que ficaram sem rede (prompt 18 · A.4): "N esperando internet".
    @Query(filter: #Predicate<OutboxItem> { !$0.done }) private var waiting: [OutboxItem]

    @State private var model = AddLinkModel()
    @State private var showNameSearch = false
    @State private var giftSource: String?
    @State private var showGift = false
    /// Link · Texto · Nome (ColarTexto.png, prompt 18 · E.21). "Nome" abre a busca por nome, sem trocar a aba.
    @State private var mode: AddMode = .link
    @State private var texto = ColarTextoModel()
    @FocusState private var fieldFocused: Bool

    private var region: Region { store.region }
    private var city: City? { trips.first?.city(on: AppClock.now, calendar: region.calendar) }
    private var knownAreas: [String] { Array(Set(places.compactMap(\.area))) }

    var body: some View {
        VStack(spacing: 0) {
            CutScreenHeader(title: mode == .text ? "Colar texto" : "Guardar", corner: ["Link · Texto · Nome", region.shortName],
                            height: 150, onBack: { dismiss() }, backIcon: "xmark")
            modePicker
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { IndexRule() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if mode == .text {
                        ColarTextoView(model: texto, env: colarContext(), waiting: waiting.count)
                            .padding(.top, 20)
                    } else if model.phase == .done {
                        AddLinkResults(model: model, lists: lists, region: region)
                            .padding(.top, 20)
                    } else {
                        Text("Reel, TikTok, YouTube ou um nome: eu descubro o lugar.")
                            .font(V8Font.text(15)).foregroundStyle(V8.mute)
                            .padding(.top, 20)

                        inputField.padding(.top, 14)
                        // "ou um nome": busca no Google por nome (Autocomplete), sem link.
                        Button { showNameSearch = true } label: {
                            Text("ou um nome → buscar no Google").font(V8Font.text(14, weight: .semibold)).foregroundStyle(V8.ink).underline()
                        }
                        .buttonStyle(MustPressStyle())
                        .padding(.top, 10)
                        // Presente (prompt 31): o mesmo link ou vídeo vira item da lista de presentes.
                        Button { giftSource = model.input.isEmpty ? initialURL : model.input; showGift = true } label: {
                            Text("ou é um presente → guardar em Presentes").font(V8Font.text(14, weight: .semibold)).foregroundStyle(V8.ink).underline()
                        }
                        .buttonStyle(MustPressStyle())
                        .padding(.top, 8)
                        badges.padding(.top, 14)
                        if !waiting.isEmpty {
                            Text(waiting.count == 1 ? "1 esperando internet" : "\(waiting.count) esperando internet")
                                .font(V8Font.text(13)).foregroundStyle(V8.mute)
                                .padding(.top, 10)
                        }
                        resultArea.padding(.top, 28)
                    }

                    Text(settingsList.first?.cloudBoost == true && CloudBoost.isConfigured
                         ? "Processado no aparelho · legendas difíceis vão pro Claude Haiku (só o texto)"
                         : "Processado no aparelho · nada sai do seu iPhone sem você pedir")
                        .font(V8Font.text(13))
                        .foregroundStyle(V8.mute)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if mode == .text && texto.phase == .done {
                    ColarTextoActions(model: texto, env: colarContext(), sync: services.sync) { dismiss() }
                }
            }
        }
        .background(V8.paper.ignoresSafeArea())
        .modifier(AddLinkFooter(mode: mode, title: footerTitle, enabled: footerEnabled, action: footerAction))
        .sheet(isPresented: $showGift) {
            let source = (giftSource?.isEmpty == false) ? giftSource : nil
            PresenteNovoView(source: source)
        }
        .sheet(isPresented: $showNameSearch) {
            BuscarNomeView(initialQuery: model.input.trimmingCharacters(in: .whitespacesAndNewlines).contains(".") ? "" : model.input,
                           preferredListId: preferredListId)
        }
        .onChange(of: mode) { _, new in
            if new == .name {
                showNameSearch = true
                mode = .link
            }
        }
        .task {
            if initialMode == .text { mode = .text }
            if let initialURL, initialURL.hasPrefix(AddLinkModel.videoPrefix) {
                await runInboxVideo(String(initialURL.dropFirst(AddLinkModel.videoPrefix.count)))
            } else if let initialURL, model.input.isEmpty {
                model.input = initialURL
                await run()
            }
        }
        .task {
            #if DEBUG
            // -debugScreen colar-texto[:amostra] abre a aba Texto (com a amostra já lida).
            if let screen = DebugFlags.string("debugScreen"), screen.hasPrefix("colar-texto") {
                mode = .text
                if screen.hasSuffix(":amostra") {
                    texto.text = ColarTextoSample.text
                    await texto.analyze(texto.text, env: colarContext())
                }
            }
            #endif
        }
    }

    /// Seletor "Link · Texto · Nome" no topo (no lugar do rótulo "adicionar").
    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(AddMode.allCases, id: \.self) { option in
                Button { mode = option } label: {
                    Text(option.label.uppercased())
                        .font(V8Font.mono(12, weight: .semibold)).tracking(1)
                        .foregroundStyle(mode == option ? V8.paper : V8.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(mode == option ? V8.ink : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
        .accessibilityElement(children: .contain)
    }

    /// O que a aba Texto precisa: board, listas, cidade, Places, fila de saída e a configuração de IA do aparelho.
    private func colarContext() -> ColarContext {
        ColarContext(board: places, lists: lists, city: city,
                     cityId: city?.id ?? trips.first?.cities.first?.id ?? region.rawValue,
                     tripStart: trips.first?.start, region: region, knownAreas: knownAreas,
                     provider: services.places, queue: context,
                     onDevice: settingsList.first?.onDeviceAI ?? true, readLinks: true,
                     cloudBoost: settingsList.first?.cloudBoost ?? false)
    }

    // MARK: Entrada

    private var inputField: some View {
        HStack(spacing: 12) {
            MustIconView(.colarLink, size: 18).foregroundStyle(V8.ink)
            TextField("instagram.com/reel/…", text: $model.input)
                .accessibilityIdentifier("add.link")
                .font(V8Font.mono(15))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .submitLabel(.go)
                .onSubmit { Task { await run() } }
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in
                    model.input = text
                    await run()
                }
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.roundedRectangle(radius: 0))
            .tint(V8.ink)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(minHeight: 58)
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
    }

    private var badges: some View {
        HStack(spacing: 8) {
            ForEach([LinkSource.instagram, .tiktok, .youtube, .maps], id: \.self) { source in
                let on = model.detectedSource == source
                Text(source.badge ?? "")
                    .font(V8Font.mono(12, weight: .semibold))
                    .foregroundStyle(on ? V8.paper : V8.ink)
                    .frame(minWidth: 32)
                    .padding(.horizontal, 6)
                    .frame(height: 44)
                    .background(on ? V8.ink : Color.clear)
                    .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            }
            Text("Também pelo Atalho “Compartilhar → Must”").font(V8Font.text(13)).foregroundStyle(V8.mute).padding(.leading, 4)
        }
    }

    // MARK: Resultado

    @ViewBuilder private var resultArea: some View {
        switch model.phase {
        case .idle, .done:
            EmptyView()
        case .reading where model.isReadingVideo:
            VideoReadCard(model: model) { _ in }
        case .reading:
            HStack(spacing: 10) {
                ProgressView()
                Text(model.stepLines.first?.text ?? "Lendo…").font(V8Font.text(13)).foregroundStyle(V8.mute)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
        case .needsText(let message):
            pasteCard(message)
        case .failed(let message):
            Text(message).font(.must.meta).foregroundStyle(V8.orangeDeep)
        }
    }

    private func pasteCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stepsView
            if model.offersVideo || model.videoText != nil {
                VideoReadCard(model: model) { url in Task { await runVideo(url) } }
            }
            Text(message).font(V8Font.text(15, weight: .semibold)).foregroundStyle(Color.must.ink)
            TextField("cola aqui o texto da legenda", text: $model.pastedText, axis: .vertical)
                .accessibilityIdentifier("add.caption")
                .font(V8Font.text(16))
                .lineLimit(3...8)
                .padding(12)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            Button {
                Task { await runPasted() }
            } label: { Pill("Ler texto", style: .green) }
                .buttonStyle(MustPressStyle())
                .disabled(model.pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.stepLines.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Rectangle().fill(step.done ? V8.orange : Color.clear)
                        Rectangle().stroke(V8.ink, lineWidth: 1.5)
                        if step.done { MustIconView(.ok, size: 12).foregroundStyle(V8.ink) }
                    }
                    .frame(width: 22, height: 22)
                    Text(step.text).font(V8Font.text(14)).foregroundStyle(Color.must.secondary)
                }
            }
        }
    }

    // MARK: Ação principal

    private var allExisting: Bool { model.phase == .done && model.matches.allSatisfy { $0.existing != nil } }

    private var footerTitle: String {
        if model.phase == .done { return allExisting ? "Já está no board · fechar" : addTitle }
        return "Ler o link"
    }

    private var footerEnabled: Bool {
        if model.phase == .done { return allExisting || !model.included.isEmpty }
        return !model.input.trimmingCharacters(in: .whitespaces).isEmpty && model.phase != .reading
    }

    private func footerAction() {
        if model.phase == .done {
            if allExisting { dismiss() } else { save() }
        } else {
            Task { await run() }
        }
    }

    /// "Adicionar 2 ao Must eat" quando a lista é a mesma; "Adicionar 2 lugares" quando não.
    private var addTitle: String {
        let count = model.included.count
        guard count > 0 else { return "Marque um lugar" }
        if let listId = model.sharedListId, let list = lists.first(where: { $0.id == listId }) {
            return "Adicionar \(count) ao \(list.displayName)"
        }
        return count == 1 ? "Adicionar 1 lugar" : "Adicionar \(count) lugares"
    }

    private func run() async {
        fieldFocused = false
        let settings = settingsList.first
        model.extractorOptions = AIPlaceExtractor.Options(onDevice: settings?.onDeviceAI ?? true, cloudBoost: settings?.cloudBoost ?? false,
                                                          knownAreas: [], timeZone: region.timeZone)
        await model.run(board: places, lists: lists, city: city, region: region, knownAreas: knownAreas, provider: services.places,
                        queue: context)
        applyPreferredList()
    }

    /// Vídeo escolhido no cartão "Ler o vídeo": lê no aparelho e apaga a cópia temporária.
    private func runVideo(_ url: URL) async {
        configureExtractor()
        await model.runVideo(url, region: region, board: places, lists: lists, city: city, knownAreas: knownAreas, provider: services.places)
        try? FileManager.default.removeItem(at: url)
        applyPreferredList()
    }

    private func runInboxVideo(_ id: String) async {
        configureExtractor()
        await model.runInboxVideo(id: id, board: places, lists: lists, city: city, region: region, knownAreas: knownAreas,
                                  provider: services.places)
        applyPreferredList()
    }

    private func configureExtractor() {
        let settings = settingsList.first
        model.extractorOptions = AIPlaceExtractor.Options(onDevice: settings?.onDeviceAI ?? true, cloudBoost: settings?.cloudBoost ?? false,
                                                          knownAreas: [], timeZone: region.timeZone)
    }

    private func runPasted() async {
        await model.runPasted(board: places, lists: lists, city: city, region: region, knownAreas: knownAreas, provider: services.places)
        applyPreferredList()
    }

    /// Abriu de uma lista (Musts › lista › +): os novos já vêm nela.
    private func applyPreferredList() {
        guard let preferredListId else { return }
        for m in model.matches where m.existing == nil { model.listChoice[m.id] = preferredListId }
    }

    private func save() {
        let today = BoardDates(timeZone: region.timeZone).dayString(AppClock.now)
        let source = Source(kind: (model.resolved?.source ?? .text).sourceKind,
                            url: model.caption?.url?.absoluteString ?? model.resolved?.url?.absoluteString,
                            savedAt: today, caption: model.caption?.text.isEmpty == false ? model.caption?.text : nil,
                            author: model.caption?.title)
        let cityId = city?.id ?? trips.first?.cities.first?.id ?? region.rawValue
        PlaceImport.insert(model.matches, included: model.included, listChoice: model.listChoice, lists: lists, cityId: cityId,
                           region: region, source: source, sync: services.sync, context: context)
        try? context.save()
        dismiss()
    }
}

/// Abas do Adicionar (prompt 18 · E.21).
enum AddMode: CaseIterable, Hashable {
    case link, text, name

    var label: String {
        switch self {
        case .link: "Link"
        case .text: "Texto"
        case .name: "Nome"
        }
    }
}

/// O botão laranja do pé: só na aba Link (a aba Texto tem os botões dela).
private struct AddLinkFooter: ViewModifier {
    var mode: AddMode
    var title: String
    var enabled: Bool
    var action: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if mode == .link {
            content.cutFooter(title, enabled: enabled, action: action)
        } else {
            content
        }
    }
}
