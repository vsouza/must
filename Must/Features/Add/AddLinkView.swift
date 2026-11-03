import CoreLocation
import SwiftData
import SwiftUI

/// "Cola o link": Reel, TikTok, YouTube, Maps ou um nome → lugares do board.
struct AddLinkView: View {
    var initialURL: String?
    var preferredListId: String?

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
    /// Link · Texto · Nome (ColarTexto.png, prompt 18 · E.21). "Nome" abre a busca por nome, sem trocar a aba.
    @State private var mode: AddMode = .link
    @State private var texto = ColarTextoModel()
    @FocusState private var fieldFocused: Bool

    private var region: Region { store.region }
    private var city: City? { trips.first?.city(on: AppClock.now, calendar: region.calendar) }
    private var knownAreas: [String] { Array(Set(places.compactMap(\.area))) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([
                Blob(cx: 385, cy: 430, rx: 70, ry: 90, rotation: 0, fill: .blue, opacity: 0.85),
                Blob(cx: 0, cy: 500, rx: 60, ry: 70, rotation: 0, fill: .green, opacity: 0.7),
            ]))

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        IconButton(.fechar, label: "Fechar") { dismiss() }
                        Spacer()
                        modePicker
                        Spacer()
                        Color.clear.frame(width: 40, height: 40)
                    }
                    .padding(.top, 16)

                    if mode == .text {
                        ColarTextoView(model: texto, env: colarContext(), waiting: waiting.count)
                            .padding(.top, 26)
                    } else if model.phase == .done {
                        AddLinkResults(model: model, lists: lists, region: region)
                            .padding(.top, 20)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Cola o link").mustTitle()
                            Text("Reel, TikTok, YouTube ou um nome — eu descubro o lugar").mustSerif(18).foregroundStyle(Color.must.secondary)
                        }
                        .padding(.top, 26)

                        inputField.padding(.top, 18)
                        // "ou um nome": busca no Google por nome (Autocomplete), sem link.
                        Button { showNameSearch = true } label: {
                            Text("ou um nome → buscar no Google").font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.ink)
                        }
                        .buttonStyle(MustPressStyle())
                        .padding(.top, 10)
                        badges.padding(.top, 14)
                        if !waiting.isEmpty {
                            Text(waiting.count == 1 ? "1 esperando internet" : "\(waiting.count) esperando internet")
                                .mustMeta()
                                .foregroundStyle(Color.must.secondary)
                                .padding(.top, 10)
                        }
                        resultArea.padding(.top, 28)
                    }

                    Text(settingsList.first?.cloudBoost == true && CloudBoost.isConfigured
                         ? "Processado no aparelho · legendas difíceis vão pro Claude Haiku (só o texto)"
                         : "Processado no aparelho · nada sai do seu iPhone sem você pedir")
                        .font(.must.meta)
                        .foregroundStyle(Color.must.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)
            // Botões do Texto fixos embaixo (com fade branco); o Link mantém o botão dele, na ZStack.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if mode == .text && texto.phase == .done {
                    ColarTextoActions(model: texto, env: colarContext(), sync: services.sync) { dismiss() }
                }
            }

            if mode == .link { mainButton }
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
            if let initialURL, model.input.isEmpty {
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
        HStack(spacing: 2) {
            ForEach(AddMode.allCases, id: \.self) { option in
                Button { mode = option } label: {
                    Text(option.label)
                        .font(.must.archivo(14, .semibold))
                        .foregroundStyle(mode == option ? Color.white : Color.must.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Capsule().fill(mode == option ? Color.must.ink : .clear))
                }
                .buttonStyle(MustPressStyle())
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.must.surface))
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
            MustIconView(.colarLink, size: 18).foregroundStyle(Color.must.ink)
            TextField("instagram.com/reel/…", text: $model.input)
                .font(.must.mono(15))
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
            .tint(Color.must.ink)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .frame(height: 58)
        .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 29, style: .continuous))
    }

    private var badges: some View {
        HStack(spacing: 8) {
            ForEach([LinkSource.instagram, .tiktok, .youtube, .maps], id: \.self) { source in
                let on = model.detectedSource == source
                Text(source.badge ?? "")
                    .font(.must.mono(12, .semibold))
                    .foregroundStyle(on ? .white : Color.must.ink)
                    .frame(minWidth: 32)
                    .padding(.horizontal, 6)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Color.must.ink : Color.must.surface))
            }
            Text("Também pelo Atalho “Compartilhar → Must”").mustMeta().padding(.leading, 4)
        }
    }

    // MARK: Resultado

    @ViewBuilder private var resultArea: some View {
        switch model.phase {
        case .idle, .done:
            EmptyView()
        case .reading:
            HStack(spacing: 10) {
                ProgressView()
                Text(model.stepLines.first?.text ?? "Lendo…").mustMeta()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(cornerRadius: 26)
        case .needsText(let message):
            pasteCard(message)
        case .failed(let message):
            Text(message).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D))
        }
    }

    private func pasteCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            stepsView
            Text(message).font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
            TextField("cola aqui o texto da legenda", text: $model.pastedText, axis: .vertical)
                .font(.must.serif(18))
                .lineLimit(3...8)
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button {
                Task { await runPasted() }
            } label: { Pill("Ler texto", style: .green) }
                .buttonStyle(MustPressStyle())
                .disabled(model.pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(20)
        .glass(cornerRadius: 26)
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(model.stepLines.enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(step.done ? Color.must.green : Color.must.surface)
                        if step.done { MustIconView(.ok, size: 12).foregroundStyle(Color.must.greenText) }
                    }
                    .frame(width: 22, height: 22)
                    Text(step.text).font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
                }
            }
        }
    }

    // MARK: Ação principal

    @ViewBuilder private var mainButton: some View {
        Group {
            if model.phase == .done {
                if model.matches.allSatisfy({ $0.existing != nil }) {
                    PrimaryButton("Já está no board · fechar", style: .dark) { dismiss() }
                } else {
                    let count = model.included.count
                    PrimaryButton(addTitle, icon: .ok, iconTrailing: true) { save() }
                        .disabled(count == 0)
                        .opacity(count == 0 ? 0.5 : 1)
                }
            } else {
                PrimaryButton("Ler o link", icon: .avancar, iconTrailing: true, style: .dark) { Task { await run() } }
                    .disabled(model.input.trimmingCharacters(in: .whitespaces).isEmpty || model.phase == .reading)
                    .opacity(model.input.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background {
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .center).ignoresSafeArea()
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
