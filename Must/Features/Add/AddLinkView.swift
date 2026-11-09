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
        NavigationStack {
        VStack(spacing: 0) {
            modePicker
                .padding(.horizontal, V9.gutter)
                .padding(.vertical, 8)
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
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(.top, 20)

                        inputField.padding(.top, 14)
                        // "ou um nome": busca no Google por nome (Autocomplete), sem link.
                        Button("Ou um nome: buscar no Google") { showNameSearch = true }
                            .padding(.top, 8)
                        // Presente (prompt 31): o mesmo link ou vídeo vira item da lista de presentes.
                        Button("Ou é um presente: guardar em Presentes") { giftSource = model.input.isEmpty ? initialURL : model.input; showGift = true }
                            .padding(.top, 4)
                        badges.padding(.top, 14)
                        if !waiting.isEmpty {
                            Text(waiting.count == 1 ? "1 esperando internet" : "\(waiting.count) esperando internet")
                                .font(J9.font(13)).foregroundStyle(Color.secondary)
                                .padding(.top, 10)
                        }
                        resultArea.padding(.top, 28)
                    }

                    Text(settingsList.first?.cloudBoost == true && CloudBoost.isConfigured
                         ? "Processado no aparelho · legendas difíceis vão pro Claude Haiku (só o texto)"
                         : "Processado no aparelho · nada sai do seu iPhone sem você pedir")
                        .font(J9.font(13))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 24)
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, V9.gutter)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if mode == .text && texto.phase == .done {
                    ColarTextoActions(model: texto, env: colarContext(), sync: services.sync) { dismiss() }
                }
            }
        }
        .navigationTitle(mode == .text ? "Colar texto" : "Guardar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
        .v9Screen()
        .modifier(AddLinkFooter(mode: mode, title: footerTitle, enabled: footerEnabled, action: footerAction))
        }
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
        Picker("Entrada", selection: $mode) {
            ForEach(AddMode.allCases, id: \.self) { option in Text(option.label).tag(option) }
        }
        .pickerStyle(.segmented)
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
        HStack(spacing: 8) {
            Image(systemName: "link").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("instagram.com/reel/…", text: $model.input)
                .accessibilityIdentifier("add.link")
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
            .buttonBorderShape(.capsule)
            .tint(V9.accent)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var badges: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach([LinkSource.instagram, .tiktok, .youtube, .maps], id: \.self) { source in
                    let on = model.detectedSource == source
                    Text(source.badge ?? "")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(on ? Color.white : Color.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(on ? V9.accent : V9.fill, in: Capsule())
                }
            }
            Text("Também pelo atalho Compartilhar → Must.").font(.footnote).foregroundStyle(.secondary)
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
                Text(model.stepLines.first?.text ?? "Lendo…").font(.footnote).foregroundStyle(.secondary)
            }
            .v9Card()
        case .needsText(let message):
            pasteCard(message)
        case .failed(let message):
            Text(message).font(.footnote).foregroundStyle(.red)
        }
    }

    private func pasteCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stepsView
            if model.offersVideo || model.videoText != nil {
                VideoReadCard(model: model) { url in Task { await runVideo(url) } }
            }
            Text(message).font(.subheadline.weight(.semibold))
            TextField("cola aqui o texto da legenda", text: $model.pastedText, axis: .vertical)
                .accessibilityIdentifier("add.caption")
                .lineLimit(3...8)
                .padding(12)
                .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            J9Button("Ler texto") { Task { await runPasted() } }
                .disabled(model.pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .v9Card()
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.stepLines.enumerated()), id: \.offset) { _, step in
                Label(step.text, systemImage: step.done ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline).foregroundStyle(step.done ? Color.primary : Color.secondary)
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
            content.j9Footer(title, enabled: enabled, action: action)
        } else {
            content
        }
    }
}
