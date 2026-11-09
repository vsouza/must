import CoreLocation
import SwiftData
import SwiftUI

/// Pedir (Quero, prompt 32 §6, visual V9): uma vontade ("comprar um Seiko") vira lugar físico perto de hoje e termina
/// **sempre num lugar no mapa** ("Ver no mapa"). Texto ou voz; o parser no aparelho entende o verbo e o objeto; a busca é
/// só de lugar físico. Duas faixas: **seus Musts** (mesmo longe, na cidade de hoje) e **aqui perto agora** (fora do board).
/// Pergunta ("dá tempo…?", "que drink monto no 7-Eleven?") vira resposta curta + "Continuar no Assistente" + o lugar mais perto.
/// Link / Vídeo / Texto / Ingresso / Presente ficam embaixo ("ou guarde").
struct QueroView: View {
    var initialText: String?
    /// Página da aba de busca (iOS 26): "fechar" volta pra aba anterior.
    var inTab = false

    @Environment(\.dismiss) private var systemDismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dayEngine) private var engine
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(TodayContextModel.self) private var todayContext
    @Environment(\.showEvents) private var showEvents

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var gifts: [Gift]

    @State private var model = QueroModel(provider: QueroView.provider(), extras: QueroView.extras())
    @State private var speech = SpeechInput()
    @State private var secondary: AddMode?
    @State private var saved: String?
    @State private var failure: String?
    @FocusState private var focused: Bool

    private func dismiss() {
        if inTab {
            model.text = ""
            router.leaveQuero()
        } else {
            systemDismiss()
        }
    }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }

    /// Places real, o fake dos prints (`-debugPlaces fake`) ou nenhum (dados ao vivo desligados no menu de testes).
    static func provider() -> (any WantPlacesSearching)? {
        #if DEBUG
        if DebugFlags.string("debugPlaces") == "fake" || DebugFlags.string("debugAutocomplete") == "fake" { return FakeWantPlaces() }
        #endif
        return DevOverrides.liveData ? PlacesService() : nil
    }

    /// Wikipedia (sem chave) pro "ver"; fora no fake dos prints e com os dados ao vivo desligados.
    static func extras() -> WantExtras? {
        #if DEBUG
        if DebugFlags.string("debugPlaces") == "fake" || DebugFlags.string("debugAutocomplete") == "fake" { return nil }
        #endif
        return DevOverrides.liveData ? .live : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                field
                verbs
                results
                guardarSection
            }
            .padding(.horizontal, V9.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottom }
        .v9Screen()
        .sheet(item: $secondary) { mode in
            switch mode {
            case .name: BuscarNomeView(initialQuery: model.intent?.object ?? model.text, preferredListId: nil)
            default: AddLinkView(initialURL: nil, preferredListId: nil, initialMode: mode)
            }
        }
        .onAppear {
            model.answerer = { [context, services, store, engine] text in
                await QueroAnswerer.answer(text, context: context, region: store.region, services: services,
                                           useModel: (try? context.fetch(FetchDescriptor<Settings>()).first?.onDeviceAI) ?? true, engine: engine)
            }
            speech.onFinal = { text in
                model.text = text
                model.submit(env())
            }
            if let initialText, model.text.isEmpty {
                model.text = initialText
                model.submit(env())
            } else if model.text.isEmpty {
                focused = true
            }
        }
        .onDisappear { speech.cancel() }
        // A rede voltou e a lista era só do aparelho: busca de novo (a consulta tem cache, não repete chamada).
        .onChange(of: services.connectivity.status) { _, status in
            if status != .offline, model.offline { model.submit(env()) }
        }
    }

    // MARK: Topo

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pedir algo").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if !inTab {
                    Button("Fechar") { dismiss() }
                }
            }
            Text("\(areaName) · \(region.timeString(now)) · só lugares de verdade, nesta cidade")
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("", text: $model.text, prompt: Text("comprar um Seiko").foregroundStyle(.secondary))
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { model.submit(env()) }
                .accessibilityLabel("O que você quer")
            Button { Task { await speech.toggle() } } label: {
                Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(speech.isListening ? V9.accent : .secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speech.isListening ? "Parar de ouvir" : "Falar")
        }
        .padding(.leading, 12)
        .frame(minHeight: 48)
        .background(V9.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if speech.state == .denied || speech.state == .unavailable {
                Text(speech.state == .denied ? "voz desligada nos Ajustes do iPhone" : "voz indisponível agora")
                    .font(.footnote).foregroundStyle(.secondary).offset(y: 22)
            }
        }
        .padding(.bottom, speech.state == .denied || speech.state == .unavailable ? 18 : 0)
    }

    private var verbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(WantVerb.allCases, id: \.self) { verb in
                    let on = model.verb == verb
                    Button { model.choose(verb, env: env()) } label: {
                        Text(verb.label.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .background(on ? V9.accent : V9.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, V9.gutter)
        }
        .padding(.horizontal, -V9.gutter)
    }

    // MARK: Guardar

    /// Guardar (v9): Link · Vídeo · Texto · Ingresso · Presente, e "Buscar por nome" embaixo.
    enum Guardar: CaseIterable, Hashable {
        case link, video, text, ticket, gift

        var label: String {
            switch self {
            case .link: "Link"
            case .video: "Vídeo"
            case .text: "Texto"
            case .ticket: "Ingresso"
            case .gift: "Presente"
            }
        }
    }

    private var guardarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            V9SectionHeader("Ou guarde")
            CorteFlow(spacing: 8) {
                ForEach(Guardar.allCases, id: \.self) { item in
                    Button { guardar(item) } label: {
                        Text(item.label).font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(V9.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Guardar \(item.label.lowercased())")
                }
            }
            Button("Buscar por nome") { secondary = .name }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .padding(.top, 8)
    }

    private func guardar(_ item: Guardar) {
        switch item {
        case .link, .video: secondary = .link
        case .text: secondary = .text
        case .ticket: later { router.sheet = .ticketImport(inboxId: nil) }
        case .gift: later { router.sheet = .presenteNovo(source: nil) }
        }
    }

    /// Fecha o Quero e roda depois que a sheet sai (o `router` não abre sheet por cima de sheet).
    private func later(_ body: @escaping @MainActor () -> Void) {
        if inTab { body(); return }
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            body()
        }
    }

    // MARK: Resultado

    private var boardRows: [QueroRow] { model.rows.filter { $0.result.origin == .board } }
    private var nearRows: [QueroRow] { model.rows.filter { $0.result.origin != .board } }

    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let question = model.question { questionCard(question) }
            if model.offline {
                notice("sem internet · seus Musts", "wifi.slash")
            } else if let notice = model.notice {
                self.notice(notice, "info.circle")
            }
            if let understood = model.understood {
                (Text("Entendi: ").foregroundStyle(.secondary) + Text(understood.object).bold() + Text(" · \(understood.rest)").foregroundStyle(.secondary))
                    .font(.subheadline)
            }
            if !model.giftRows.isEmpty { giftSection }
            switch model.phase {
            case .idle where model.question != nil:
                EmptyView()
            case .idle:
                Text("Diga o que quer: comprar, comer, ver. Eu acho o lugar de verdade, perto de hoje, e vejo se cabe no dia.")
                    .font(.body).foregroundStyle(.secondary)
            case .searching:
                HStack(spacing: 8) { ProgressView(); Text("procurando perto de \(areaName)…").foregroundStyle(.secondary) }
                    .padding(.vertical, 8)
            case .done:
                if model.rows.isEmpty && model.giftRows.isEmpty {
                    Text(model.offline ? "Nada no aparelho pra isso ainda." : "Nenhum lugar físico por perto pra isso. Tente outra palavra.")
                        .foregroundStyle(.secondary)
                }
                if !boardRows.isEmpty { rowsSection("Seus Musts", rows: boardRows) }
                if !nearRows.isEmpty { rowsSection("Aqui perto agora", rows: nearRows) }
                if !model.rows.isEmpty || model.dropped > 0 {
                    Text(model.footer(region: region)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func notice(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(V9.fill, in: Capsule())
    }

    private func rowsSection(_ title: String, rows: [QueroRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            V9SectionHeader(title)
            ForEach(rows) { row in
                let selected = row.id == model.selected?.id
                Button { model.selectedId = row.id } label: {
                    V9Row(title: row.result.name, detail: row.meta, reason: reason(row),
                          systemImage: row.result.origin == .board ? "star.circle.fill" : "mappin.circle") {
                        Button { MapsLinks.openApple(to: row.result.coordinate, name: row.result.name) } label: {
                            Text("Ir").font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(V9.accent)
                        .accessibilityLabel("Ir até \(row.result.name)")
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(selected ? V9.fill : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    /// "\(min) min · cabe 15:10" / "hoje não cabe · sáb · Ginza".
    private func reason(_ row: QueroRow) -> String {
        let walk = "\(row.minutes) min"
        if let slot = row.slot { return "\(walk) · cabe \(region.timeString(slot.start))" }
        return [walk, row.otherDay ?? "hoje não cabe"].joined(separator: " · ")
    }

    private var giftSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            V9SectionHeader("Presentes que faltam")
            ForEach(model.giftRows) { g in
                V9Row(title: "\(g.title) · \(g.person)", detail: g.storeName,
                      reason: "\(g.minutes) min · \(g.isOpen ? "aberta" : "fechada agora")", systemImage: "gift") {
                    Button { MapsLinks.openApple(to: g.coordinate, name: g.storeName) } label: {
                        Text("Ir").font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(V9.accent)
                    .accessibilityLabel("Ir até \(g.storeName)")
                }
            }
        }
    }

    // MARK: Pergunta

    private func questionCard(_ q: QueroQuestionState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Isso é uma pergunta", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(V9.accent)
            if let answer = q.answer {
                Text(answer).font(.body)
            } else {
                HStack(spacing: 8) { ProgressView(); Text("pensando no aparelho…").foregroundStyle(.secondary) }
            }
            if let extras = q.extras {
                ForEach(extras.places) { p in
                    V9Row(title: p.name, detail: Walk.distanceText(p.distance), reason: p.note ?? p.address, systemImage: "mappin.circle.fill") {
                        Button { MapsLinks.openApple(to: p.coordinate, name: p.name) } label: {
                            Text("Ir").font(.subheadline.weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain).foregroundStyle(V9.accent)
                        .accessibilityLabel("Ir até \(p.name)")
                    }
                }
                ForEach(extras.recipes) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(.body.weight(.semibold))
                        Text(r.ingredients.joined(separator: " + ")).font(.subheadline).foregroundStyle(.secondary)
                        Text(r.step).font(.subheadline)
                        Text(r.when).font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let note = extras.note { Label(note, systemImage: "wifi.slash").font(.footnote).foregroundStyle(.secondary) }
            }
            Button {
                let text = q.text
                later { router.sheet = .assistantAsk(text: text) }
            } label: {
                Label("Continuar no Assistente", systemImage: "arrow.right").frame(maxWidth: .infinity)
            }
            .v9Secondary()
            .accessibilityHint("abre o Assistente com a sua pergunta")
        }
        .v9Card()
    }

    // MARK: Embaixo: ver no mapa, encaixe e guardar

    @ViewBuilder private var bottom: some View {
        let showcase = model.showcase()
        let row = model.phase == .done ? model.selected : nil
        if showcase != nil || row != nil || saved != nil || failure != nil {
            VStack(spacing: 10) {
                if let saved {
                    Text(saved).font(.subheadline.weight(.semibold)).foregroundStyle(V9.accent)
                } else if let failure {
                    Text(failure).font(.footnote).foregroundStyle(V9.alert)
                }
                if let row { fitCard(row) }
                HStack(spacing: 10) {
                    if let showcase {
                        Button { router.showOnMap(showcase) } label: {
                            Label("Ver no mapa", systemImage: "map").frame(maxWidth: .infinity)
                        }
                        .v9Secondary()
                        .accessibilityHint("abre o mapa só com estes lugares")
                    }
                    if let row {
                        Button(row.slot == nil ? "Não cabe hoje" : "Encaixar hoje") { encaixar(row) }
                            .v9Primary()
                            .disabled(row.slot == nil)
                    }
                }
            }
            .padding(.horizontal, V9.gutter)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
    }

    private func fitCard(_ row: QueroRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.slot.map { region.timeString($0.start) } ?? "—")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(V9.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(fitTitle(row)).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Só guardar") { guardar(row) }
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
    }

    private func fitTitle(_ row: QueroRow) -> String {
        guard let slot = row.slot else { return model.intent?.when == .amanha ? "Fica pra amanhã" : "Hoje não cabe" }
        if let after = slot.after { return "Encaixa hoje depois do \(short(after.label))" }
        if let before = slot.before { return "Encaixa hoje antes do \(short(before.label))" }
        return "Cabe agora · \(row.minutes) min até lá"
    }

    private func fitDetail(_ row: QueroRow) -> String {
        let name = short(row.result.name)
        guard let slot = row.slot else {
            return row.otherDay.map { "Só guardar deixa no board · \($0)" } ?? "o dia está cheio · Só guardar deixa no board"
        }
        var parts: [String] = []
        if let before = slot.before {
            parts.append(slot.detour <= 10 ? "\(name) fica no caminho pro \(short(before.label))" : "desvio de \(slot.detour) min antes do \(short(before.label))")
        } else if plan == nil {
            parts.append("sem dia montado: vira a parada de agora")
        }
        parts.append("\(DayFit.minutes) min lá dentro")
        return parts.joined(separator: " · ")
    }

    /// "Shinjuku Gyoen · golden" → "Shinjuku Gyoen"; "Bic Camera Shinjuku Higashi-guchi" → "Bic Camera".
    private func short(_ label: String) -> String {
        let base = label.components(separatedBy: " · ").first ?? label
        let words = base.split(separator: " ")
        return words.count > 3 ? words.prefix(2).joined(separator: " ") : base
    }

    private var listName: String {
        QueroSave.list(for: model.intent, lists: lists)?.name.capitalized ?? "Musts"
    }

    // MARK: Ações

    private func guardar(_ row: QueroRow) {
        guard let place = QueroSave.place(for: row, intent: model.intent, text: model.text, lists: lists, cityId: env().cityId,
                                          region: region, sync: services.sync, context: context) else { return }
        saved = row.result.boardPlaceId != nil ? "\(place.name) já está no board" : "Guardado em \(place.list?.name.capitalized ?? listName)"
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            saved = nil
        }
    }

    private func encaixar(_ row: QueroRow) {
        let env = env()
        guard row.slot != nil,
              let place = QueroSave.place(for: row, intent: model.intent, text: model.text, lists: lists, cityId: env.cityId,
                                          region: region, sync: services.sync, context: context) else { return }
        do {
            _ = try QueroSave.encaixar(row, place: place, env: env, context: context)
            dismiss()
            router.push(.linha(date: today), on: .hoje)
        } catch {
            failure = "não deu pra gravar o dia: \(error.localizedDescription)"
        }
    }

    // MARK: Ambiente

    private var trip: TripInfo? { trips.first }
    private var city: City? { trip?.city(on: now, calendar: region.calendar) }
    private var areas: [Area] { AreaCatalog.areas(for: region) }

    private var plan: DayPlan? { engine.plan(for: today, region: region, context: context) }

    private var planArea: Area? { plan?.area.flatMap { id in areas.first { $0.id == id } } }

    /// O bairro que a capa mostra (prompt 32 §3): serve de origem quando o GPS está fora da cidade da viagem.
    private var contextArea: Area? { todayContext.context.areaId.flatMap { id in areas.first { $0.id == id } } }

    private var gpsArea: Area? {
        guard let here = services.location.current?.coordinate else { return nil }
        let id = AreaAssigner(areas: areas).areaId(name: nil, cityId: city?.id ?? region.rawValue, lat: here.latitude, lng: here.longitude)
        return id.flatMap { id in areas.first { $0.id == id } }
    }

    private var areaName: String { contextArea?.name ?? planArea?.name ?? gpsArea?.name ?? city?.name ?? region.displayName }

    private func env() -> QueroEnv {
        var e = QueroEnv.make(region: region, now: now, places: places, trip: trip, settings: settingsList.first, plan: plan,
                              gps: services.location.current?.coordinate, online: services.connectivity.status != .offline,
                              upcoming: QueroEnv.upcomingDays(context: context, areas: areas, today: today),
                              areaHint: contextArea ?? planArea ?? gpsArea, shows: showEvents.today(region: region, at: now), gifts: gifts)
        // Seus Musts da cidade de hoje entram mesmo longe (a faixa "Seus Musts").
        e.boardAnyDistance = true
        return e
    }
}

extension AddMode: Identifiable {
    var id: Self { self }
}

/// A aba de busca da barra nativa: o Pedir como página. `token` recria a página quando alguém pede um texto novo.
struct QueroTabPage: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        QueroView(initialText: router.queroText, inTab: true)
            .id(router.queroToken)
    }
}
