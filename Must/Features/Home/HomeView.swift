import CoreLocation
import SwiftData
import SwiftUI

/// 01 · Hoje, a capa do corte (prompt 30 §2, `CorteFluxo.png`): foto tratada em cima, régua preta puxável, papel embaixo.
/// Gestos: pra cima = Linha do dia; pra baixo (fora da régua) = Bom dia / Boa noite; pra esquerda = Dicas; pra direita
/// (ou o toque na alça da borda) = Bolso; ← = Assistente. **Arrastar começando na régua** (ou tocar no nome do bairro) abre o "quero…".
/// Tudo sai de `CapaState` e `CapaSuggestState`, recalculado nos gatilhos; o `body` só desenha.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tripTheme) private var theme
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.eventsFeed) private var events
    @Environment(\.showEvents) private var showEvents

    @Query private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var trips: [TripInfo]
    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var settingsList: [Settings]

    @State private var state = CapaState()
    /// "Agora vale" (prompt 26): cartões, linha de estado e card da noite.
    @State private var suggest = CapaSuggestState()
    @State private var currentArea: Area?
    @State private var saveRefresh: Task<Void, Never>?
    /// O corte: régua, fenda do quero…, resultado e passo a passo.
    @State private var corte = CorteState()
    @Environment(\.openURL) private var openURL

    private var region: Region { store.region }
    private var today: Date { region.calendar.startOfDay(for: AppClock.now) }
    private var ink: Color { theme.coverInk }

    /// `-capaFoto` (DEBUG, prints): baixa a foto do Commons uma vez pro bairro. Sem a flag, a capa só usa o que já está no disco.
    private var forcePhoto: Bool { DebugFlags.has("-capaFoto") }
    private var debugScreen: String { DebugFlags.string("debugScreen") ?? "" }
    /// `quero-nakano` (DEBUG, prints): a capa sai do bairro Nakano com o GPS longe, como no uso real fora do país.
    @State private var debugArea: Area?
    private var photoURL: URL? {
        guard debugScreen != "corte-capa-sem-foto" else { return nil }
        return state.photo.flatMap { URL(string: $0.largeURL ?? $0.url) }
    }

    private var locationCell: String {
        guard let here = services.location.current else { return "" }
        return "\(Int((here.coordinate.latitude * 2000).rounded())),\(Int((here.coordinate.longitude * 2000).rounded()))"
    }

    var body: some View {
        Group {
            if let content = state.content {
                CapaCorteView(content: content, areaName: debugArea?.name ?? currentArea?.name ?? content.area, photoURL: photoURL, suggest: suggest,
                              state: corte, tripId: region.trip.id, makeEnv: makeEnv, actions: actions)
            } else {
                theme.cover.ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard corte.stage == .rest, corte.pull.phase == .closed, let swipe = CapaSwipe.from(value.translation) else { return }
            go(swipe)
        }, including: corte.stage == .rest ? .all : .subviews)
        .accessibilityAction(named: "Linha do dia") { go(.up) }
        .accessibilityAction(named: "Assistente") { go(.left) }
        .accessibilityAction(named: "Bolso") { go(.right) }
        .overlay(alignment: .trailing) { if corte.stage == .rest { bolsoHandle } }
        .onAppear {
            corte.answerer = { [context, services, store] text in
                await QueroAnswerer.answer(text, context: context, region: store.region, services: services,
                                           useModel: (try? context.fetch(FetchDescriptor<Settings>()).first?.onDeviceAI) ?? true)
            }
            router.setQuero("capa", open: corte.stage != .rest)
            refresh()
            // `-debugScreen atalhos` (prints): o Bolso (com os Atalhos no topo).
            if debugScreen == "atalhos", router.paths[.hoje]?.isEmpty ?? true { go(.right) }
        }
        .task { await clock() }
        .task { await startCorteExtras() }
        .task(id: locationCell) {
            await resolveCurrentArea()
            await loadIndicated()
        }
        .task(id: region) { await refreshEvents() }
        .task(id: state.areaId) {
            await state.loadPhoto(region: region, places: places, services: services, forced: forcePhoto)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        // O quero aberto esconde a barra de abas (ela flutuava por cima dos chips de vontade).
        .onChange(of: corte.stage) { _, stage in router.setQuero("capa", open: stage != .rest) }
        .onDisappear { router.setQuero("capa", open: false) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleRefresh() }
    }

    // MARK: Gatilhos

    private func refresh() {
        let now = AppClock.now
        let trip = trips.first
        state.refresh(.init(region: region, now: now, engine: engine, context: context, trip: trip, expenses: expenses,
                            currentArea: currentArea, nowWeather: services.sync.now(region: region, trip: trip),
                            todayWeather: services.sync.weather(on: now, region: region, trip: trip)))
        recomputeSuggestions(now: now)
    }

    // MARK: Agora vale (prompt 26)

    private func recomputeSuggestions(now: Date) {
        events.loadCached(region: region)
        suggest.recompute(.init(
            region: region, now: now, here: services.location.current?.coordinate, currentArea: currentArea, places: places,
            plan: state.plan, dayNow: state.dayNow, events: events.events, boardShows: showEvents.today(region: region, at: now),
            forecast: services.sync.weather(on: now, region: region, trip: trips.first),
            eventSourceName: { [events] in events.sourceName(forId: $0) }))
    }

    /// Cache de "por perto" da célula (só leitura, nunca chama fonte): vira o "indicado" fora do board.
    private func loadIndicated() async {
        guard let here = services.location.current else { return }
        let batch = await services.nearby.cached(lat: here.coordinate.latitude, lng: here.coordinate.longitude, region: region)
        suggest.indicated = batch?.places.filter { !$0.sources.contains(.board) } ?? []
        recomputeSuggestions(now: AppClock.now)
    }

    /// Eventos: o cache já está na tela; a rede (6 h, Wi-Fi, fora do Pouco Dados) atualiza em segundo plano.
    private func refreshEvents() async {
        recomputeSuggestions(now: AppClock.now)
        let center = services.location.current?.coordinate ?? currentArea?.centroid.clCoordinate ?? region.defaultCenter
        await events.refresh(region: region, center: center, status: services.connectivity.status, wifi: services.connectivity.isWiFi)
        recomputeSuggestions(now: AppClock.now)
    }

    private func openSuggestion(_ card: Suggestion) {
        if card.kind == .plan { router.push(.agora, on: .hoje); return }
        if let id = card.placeId { router.push(.place(id: id), on: .hoje); return }
        if let url = card.url { openURL(url); return }
        if let c = card.coordinate { MapsLinks.openApple(to: c, name: card.title) }
    }

    private func scheduleRefresh() {
        saveRefresh?.cancel()
        saveRefresh = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    private func clock() async {
        while !Task.isCancelled {
            let seconds = 60 - Int(AppClock.now.timeIntervalSince1970) % 60
            try? await Task.sleep(for: .seconds(Double(seconds) + 0.5))
            guard !Task.isCancelled else { return }
            refresh()
        }
    }

    private func resolveCurrentArea() async {
        guard let here = services.location.current else { return }
        let area = await services.currentArea.area(at: here, region: region)
        guard area != currentArea else { return }
        currentArea = area
        refresh()
    }

    private func go(_ swipe: CapaSwipe) {
        switch CapaSwipe.action(for: swipe, now: AppClock.now, region: region) {
        case .route(let route): router.push(route, on: .hoje)
        case nil: break
        }
    }

    /// Alça na borda direita da capa: o "toque no canto" que abre o Bolso sem deslizar.
    private var bolsoHandle: some View {
        Button { go(.right) } label: {
            Capsule()
                .fill(ink.opacity(0.35))
                .frame(width: 5, height: 46)
                .frame(width: 28, height: 96)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bolso")
        .accessibilityHint("Suica, ingressos, mapa offline, SOS, câmbio, frases e último trem")
    }

    // MARK: O corte

    private var actions: CapaCorteView.Actions {
        .init(trips: { router.sheet = .viagens },
              assistente: { router.sheet = .assistant },
              continueInAssistant: { text in
                  corte.close()
                  router.sheet = .assistantAsk(text: text)
              },
              openSuggestion: openSuggestion,
              openPlace: { router.push(.place(id: $0), on: .hoje) },
              route: { row in MapsLinks.openApple(to: row.row.result.coordinate, name: row.row.result.name) },
              addToBoard: addToBoard,
              fitToday: fitToday,
              openShows: { router.push(.emCartaz, on: .hoje) })
    }

    private func makeEnv() -> QueroEnv {
        let now = AppClock.now
        let areas = AreaCatalog.areas(for: region)
        return QueroEnv.make(region: region, now: now, places: places, trip: trips.first, settings: settingsList.first,
                             plan: state.plan, gps: services.location.current?.coordinate,
                             online: services.connectivity.status != .offline,
                             upcoming: QueroEnv.upcomingDays(context: context, areas: areas, today: today),
                             areaHint: capaArea(areas), shows: showEvents.today(region: region, at: now))
    }

    /// O bairro que a capa mostra (GPS por célula, senão o do dia pelo nome): de onde o quero sai quando o GPS está longe.
    private func capaArea(_ areas: [Area]) -> Area? {
        if let debugArea { return debugArea }
        if let currentArea { return currentArea }
        guard let name = state.content?.area.lowercased() else { return nil }
        return areas.first { $0.name.lowercased() == name || $0.aliases.contains { $0.lowercased() == name } }
    }

    /// "+ board": guarda o lugar de fora na lista certa (a mesma lógica do Quero…).
    private func addToBoard(_ row: CorteRow) {
        CorteSave.addToBoard(row, state: corte, env: makeEnv(), lists: lists, services: services, context: context)
    }

    /// Toque longo: "Encaixar hoje" (prompt 25), o mesmo do Quero….
    private func fitToday(_ row: CorteRow) {
        guard CorteSave.fitToday(row, state: corte, env: makeEnv(), lists: lists, services: services, context: context) else { return }
        corte.close()
        router.push(.linha(date: today), on: .hoje)
    }

    /// Os atalhos de DEBUG dos prints (`corte-*`).
    private func startCorteExtras() async {
        let screen = debugScreen
        if screen.isEmpty {
            try? await Task.sleep(for: .milliseconds(400))
            return
        }
        guard screen.hasPrefix("corte-") || screen.hasPrefix("quero-") else { return }
        if screen == "quero-nakano" { debugArea = AreaCatalog.areas(for: region).first { $0.id == "nakano" } }
        try? await Task.sleep(for: .milliseconds(900))
        switch screen {
        case "quero-pergunta":
            corte.open()
            corte.quero.text = "dá tempo do Gyoen antes do pôr do sol?"
            corte.submit(makeEnv())
        case "quero-nakano", "quero-viagem-futura":
            corte.open()
            corte.quero.text = "comer"
            corte.submit(makeEnv())
        case "corte-puxando": corte.pull.drag(translation: 70)
        case "corte-quero": corte.open()
        case "corte-cafe", "corte-cafe-offline":
            corte.open()
            corte.quero.text = "café"
            corte.submit(makeEnv())
        default: break
        }
    }
}
