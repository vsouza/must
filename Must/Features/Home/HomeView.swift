import CoreLocation
import SwiftData
import SwiftUI

/// 01 · Hoje, a capa do corte (prompt 30 §2, `CorteFluxo.png`): foto tratada em cima, régua preta puxável, papel embaixo.
/// Gestos: pra cima = Linha do dia; pra baixo (fora da régua) = Bom dia / Boa noite; pra esquerda = Dicas; pra direita
/// (ou o toque na alça da borda) = Atalhos. **Arrastar começando na régua** (ou tocar no nome do bairro) abre o "quero…".
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
    @State private var showAtalhos = false
    /// O que o toque nos Atalhos pediu: roda quando o painel termina de fechar.
    @State private var atalhoAction: AtalhosAction?
    @Environment(\.openURL) private var openURL

    private var region: Region { store.region }
    private var today: Date { region.calendar.startOfDay(for: AppClock.now) }
    private var ink: Color { theme.coverInk }

    /// `-capaFoto` (DEBUG, prints): baixa a foto do Commons uma vez pro bairro. Sem a flag, a capa só usa o que já está no disco.
    private var forcePhoto: Bool { DebugFlags.has("-capaFoto") }
    private var debugScreen: String { DebugFlags.string("debugScreen") ?? "" }
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
                CapaCorteView(content: content, areaName: currentArea?.name ?? content.area, photoURL: photoURL, suggest: suggest,
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
        .accessibilityAction(named: "Dicas") { go(.left) }
        .accessibilityAction(named: "Atalhos") { go(.right) }
        .overlay(alignment: .trailing) { if corte.stage == .rest, corte.walk == nil { atalhosHandle } }
        .fullScreenCover(isPresented: $showAtalhos, onDismiss: runAtalhoAction) {
            AtalhosPanel { action in
                atalhoAction = action
                withoutAnimation { showAtalhos = false }
            }
            .presentationBackground(.clear)
        }
        .onAppear {
            router.setQuero("capa", open: corte.stage != .rest)
            refresh()
            // `-debugScreen atalhos` (prints): abre o painel em cima da capa.
            if debugScreen == "atalhos", !showAtalhos { openAtalhos() }
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
                            todayWeather: services.sync.weather(on: now, region: region, trip: trip),
                            position: services.location.current?.coordinate))
        recomputeSuggestions(now: now)
    }

    // MARK: Agora vale (prompt 26)

    private func recomputeSuggestions(now: Date) {
        events.loadCached(region: region)
        suggest.recompute(.init(
            region: region, now: now, here: services.location.current?.coordinate, currentArea: currentArea, places: places,
            plan: state.plan, dayNow: state.dayNow, clock: state.clock, events: events.events, boardShows: showEvents.today(region: region, at: now),
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
        case .atalhos: openAtalhos()
        case .route(let route): router.push(route, on: .hoje)
        case nil: break
        }
    }

    // MARK: Atalhos (prompt 25 · D)

    /// O painel anima sozinho (entra pela direita); a apresentação em si não tem animação (abre na hora).
    private func openAtalhos() {
        atalhoAction = nil
        withoutAnimation { showAtalhos = true }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t, body)
    }

    private func runAtalhoAction() {
        guard let action = atalhoAction else { return }
        atalhoAction = nil
        switch action {
        case .route(let route): router.push(route, on: .hoje)
        case .sheet(let sheet): router.sheet = sheet
        case .selectTab(let tab): router.select(tab)
        case .url(let url): openURL(url)
        }
    }

    /// Alça na borda direita da capa: o "toque no canto" que abre os Atalhos sem deslizar.
    private var atalhosHandle: some View {
        Button(action: openAtalhos) {
            Capsule()
                .fill(ink.opacity(0.35))
                .frame(width: 5, height: 46)
                .frame(width: 28, height: 96)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Atalhos")
        .accessibilityHint("Suica, ingressos, mapa offline, SOS e linhas perto")
    }

    // MARK: O corte

    private var actions: CapaCorteView.Actions {
        .init(trips: { router.sheet = .viagens },
              dicas: { router.push(.dicas, on: .hoje) },
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
                             upcoming: QueroEnv.upcomingDays(context: context, areas: areas, today: today))
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

    /// Passo a passo (primeira vez e primeira entrada em cada viagem) e os atalhos de DEBUG dos prints (`corte-*`).
    private func startCorteExtras() async {
        let screen = debugScreen
        if screen.isEmpty {
            try? await Task.sleep(for: .milliseconds(400))
            if let content = state.content, content.lead != "Primeiro dia" { corte.startWalk(tripId: region.trip.id) }
            return
        }
        guard screen.hasPrefix("corte-") else { return }
        try? await Task.sleep(for: .milliseconds(900))
        switch screen {
        case "corte-puxando": corte.pull.drag(translation: 70)
        case "corte-quero": corte.open()
        case "corte-cafe", "corte-cafe-offline":
            corte.open()
            corte.quero.text = "café"
            corte.submit(makeEnv())
        case "corte-walk1": corte.startWalk(tripId: region.trip.id, force: true)
        case "corte-walk2":
            corte.startWalk(tripId: region.trip.id, force: true)
            corte.open()
        default: break
        }
    }
}
