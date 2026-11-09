import CoreLocation
import SwiftData
import SwiftUI

/// 01 · Hoje, V9 (prompt 32 §2): uma resposta simples, sem cartaz. Cabeçalho pequeno (dia · bairro, tempo e pôr do sol,
/// ✦ e ⋯), faixa do GPS, campo "Pedir algo…", a próxima parada com **Ir** (ou 3 "Agora vale" + Montar o dia) e as reservas
/// e ingressos de hoje. Nenhum destino depende de gesto: tudo tem botão com nome.
/// Tudo sai de `CapaState` (relógio do dia), `CapaSuggestState` (ranker) e `TodayContextModel` (bairro estável),
/// recalculado nos gatilhos; o `body` só desenha.
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(TodayContextModel.self) private var todayContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.eventsFeed) private var events
    @Environment(\.showEvents) private var showEvents
    @Environment(\.openURL) private var openURL

    @Query private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var trips: [TripInfo]
    @Query private var gifts: [Gift]

    @State private var state = CapaState()
    /// "Agora vale" (prompt 26): o ranker local.
    @State private var suggest = CapaSuggestState()
    @State private var currentArea: Area?
    @State private var saveRefresh: Task<Void, Never>?
    @State private var showAreaPicker = false
    @State private var greetingDismissed: String?
    @State private var now = AppClock.now
    /// `hoje-chegou` (DEBUG, prints): força a faixa "Você chegou em…".
    @State private var debugProposal: Area?

    private var region: Region { store.region }
    private var today: Date { region.calendar.startOfDay(for: now) }
    private var debugScreen: String { DebugFlags.string("debugScreen") ?? "" }
    private var locationStamp: Double { services.location.current?.timestamp.timeIntervalSince1970 ?? 0 }

    private var proposal: Area? { todayContext.proposal ?? debugProposal }
    private var next: HojeNext? { state.clock.flatMap { HojeLogic.next(clock: $0) } }
    private var greeting: HojeLogic.Greeting? {
        HojeLogic.greetingCard(now: now, calendar: region.calendar, dismissedKey: greetingDismissed)
    }

    var body: some View {
        List {
            Section {
                header
                if let greeting { greetingNotice(greeting) }
                if let proposal { arrivalNotice(proposal) }
                V9AskField { router.openQuero() }
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: V9.gutter, bottom: 6, trailing: V9.gutter))

            if let next {
                nextSection(next)
            } else {
                suggestSection
            }

            let tickets = todayItems
            if !tickets.isEmpty { ticketsSection(tickets) }

            Section {
                row("Ir pra um bairro", detail: "marque os Musts e eu monto o trajeto", systemImage: "figure.walk") {
                    router.push(.irBairro(), on: .hoje)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .v9Screen(grouped: true)
        .accessibilityAction(named: "Linha do dia") { router.push(.linha(date: today), on: .hoje) }
        .accessibilityAction(named: "Assistente") { router.sheet = .assistant }
        .accessibilityAction(named: "Bolso") { router.push(.bolso, on: .hoje) }
        .sheet(isPresented: $showAreaPicker) { areaPicker }
        .onAppear {
            greetingDismissed = GreetingDismissStore(tripId: region.trip.id).value
            if debugScreen == "hoje-chegou" {
                debugProposal = AreaCatalog.areas(for: region).first { $0.id == (region.country == "BR" ? "savassi" : "nakano") }
            }
            refresh()
        }
        .task { await clock() }
        .task(id: locationStamp) {
            await resolveCurrentArea()
            await feedGPS()
            await loadIndicated()
        }
        .task(id: region) { await refreshEvents() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onChange(of: gifts.map { "\($0.id)\($0.boughtAt != nil)" }) { _, _ in recomputeSuggestions(now: AppClock.now) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleRefresh() }
    }

    // MARK: Cabeçalho

    private var contextName: String {
        let name = todayContext.context.name
        return name.isEmpty ? (state.content?.area ?? region.displayName) : name
    }

    private var dayText: String {
        "\(DayText.weekdayShort(now, region: region).capitalizedFirst), \(region.shortDay(now))"
    }

    /// "Tóquio · 18° sol · pôr do sol 16:38" (o `CapaContent` já monta o tempo e o pôr do sol).
    private var weatherLine: String {
        (state.content?.topRight ?? []).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Button { showAreaPicker = true } label: {
                    HStack(spacing: 4) {
                        Text("\(dayText) · \(contextName)").font(.title3.weight(.semibold)).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dayText), \(contextName)")
                .accessibilityHint("Escolher o bairro")
                if !weatherLine.isEmpty {
                    Text(weatherLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { router.sheet = .assistant } label: {
                Image(systemName: "sparkle").font(.title3).foregroundStyle(V9.accent).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Assistente")
            Menu {
                Button { router.push(.bolso, on: .hoje) } label: { Label("Bolso", systemImage: "bag") }
                Button { router.push(.sos, on: .hoje) } label: { Label("SOS", systemImage: "cross.case") }
                Button { router.sheet = .viagens } label: { Label("Minhas viagens", systemImage: "arrow.left.arrow.right") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(V9.accent).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Mais")
        }
        .buttonStyle(.plain)
    }

    private func greetingNotice(_ g: HojeLogic.Greeting) -> some View {
        V9Notice(systemImage: g == .bomDia ? "sun.max" : "moon.stars",
                 text: g == .bomDia ? "Bom dia · o resumo do dia" : "Boa noite · fechar o dia e olhar amanhã",
                 actionTitle: "abrir",
                 action: { router.push(g == .bomDia ? .bomDia : .boaNoite, on: .hoje) },
                 dismiss: {
                     let key = HojeLogic.dismissKey(g, now: now, calendar: region.calendar)
                     GreetingDismissStore(tripId: region.trip.id).dismiss(key)
                     greetingDismissed = key
                 })
    }

    private func arrivalNotice(_ area: Area) -> some View {
        V9Notice(systemImage: "location", text: "Você chegou em \(area.name)", actionTitle: "ver perto",
                 action: {
                     debugProposal = nil
                     if todayContext.proposal != nil { todayContext.acceptProposal(now: now) } else { todayContext.choose(area, now: now) }
                     refresh()
                 },
                 dismiss: {
                     debugProposal = nil
                     todayContext.dismissProposal(now: now)
                 })
    }

    // MARK: Com dia

    private func nextSection(_ n: HojeNext) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(n.phase == .next ? "Próxima" : "Agora").font(.subheadline).foregroundStyle(.secondary)
                Text(n.name).font(.title2.weight(.semibold)).lineLimit(2)
                Text(HojeLogic.detail(n, region: region)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                if let then = n.thenName, n.phase == .now {
                    Text("Depois: \(then)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let placeId = n.placeId {
                    Button { router.push(.ir(placeId: placeId), on: .hoje) } label: {
                        Text("Ir").frame(maxWidth: .infinity)
                    }
                    .v9Primary()
                    .accessibilityLabel("Ir pra \(n.name)")
                }
            }
            .padding(.vertical, 6)
            ForEach(following(n)) { stop in
                Button { openStop(stop) } label: {
                    V9Row(title: DayText.head(stop.label), detail: region.timeString(stop.start),
                          reason: stop.note.isEmpty ? nil : stop.note, thumbnail: thumb(stop.placeId), systemImage: stop.placeId == nil ? "clock" : nil) {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Button { router.push(.linha(date: today), on: .hoje) } label: {
                HStack { Text("ver o dia"); Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)) }
                    .contentShape(Rectangle())
            }
            .foregroundStyle(V9.accent)
        } header: {
            Text(state.clock?.adjusted == true ? "Seu dia · ajustei, faltam \(state.clock?.remaining ?? 0)" : "Seu dia")
        }
    }

    private func following(_ n: HojeNext) -> [DayStop] {
        guard let clock = state.clock else { return [] }
        return HojeLogic.following(clock: clock, after: n.stopId, limit: 3)
    }

    private func openStop(_ stop: DayStop) {
        if let id = stop.placeId { router.push(.place(id: id), on: .hoje) } else { router.push(.linha(date: today), on: .hoje) }
    }

    // MARK: Sem dia

    private var suggestSection: some View {
        Section {
            if suggest.cards.isEmpty {
                Text(suggest.emptyLine.isEmpty ? "Nada aberto por perto agora. Peça algo ou monte o dia." : suggest.emptyLine)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(suggest.cards.prefix(3)) { card in
                Button { openSuggestion(card) } label: {
                    V9Row(title: card.title, detail: card.trailing, reason: reason(card), thumbnail: thumb(card.placeId),
                          systemImage: card.placeId == nil ? icon(card) : nil) {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Button { router.push(.montar(date: today), on: .hoje) } label: {
                Text("Montar o dia").frame(maxWidth: .infinity)
            }
            .v9Primary()
            .listRowSeparator(.hidden)
        } header: {
            Text("Agora vale")
        } footer: {
            if !suggest.stateLine.isEmpty { Text(suggest.stateLine) }
        }
    }

    private func reason(_ card: Suggestion) -> String {
        // Uma linha: os 2 primeiros motivos (a distância já está no detalhe), mais o aviso de dado estimado.
        let top = card.reasons.filter { $0 != "perto" }.prefix(2).joined(separator: " · ")
        let line = top.isEmpty ? card.meta : top
        guard let trust = card.trust else { return line }
        return line.isEmpty ? trust : "\(line) · \(trust)"
    }

    private func icon(_ card: Suggestion) -> String {
        switch card.kind {
        case .event: "ticket"
        case .gift: "gift"
        case .light: "sun.horizon"
        case .rain: "cloud.rain"
        default: "mappin.and.ellipse"
        }
    }

    private func thumb(_ placeId: String?) -> AnyView? {
        guard let placeId, let p = places.first(where: { $0.id == placeId }), !p.photoRefs.isEmpty else { return nil }
        return AnyView(PlaceThumb(placeId: p.placeId, refs: p.photoRefs, color: p.list?.color ?? .eat, size: V9.thumb))
    }

    // MARK: Reservas e ingressos de hoje

    private struct TodayItem: Identifiable {
        var id: String
        var name: String
        var at: Date
        var placeId: String
        var ticketId: String?
        var hasQR: Bool
    }

    private var todayItems: [TodayItem] {
        let cal = region.calendar
        var out: [TodayItem] = []
        for p in places {
            if let r = p.reservation, cal.isDate(r.at, inSameDayAs: now) {
                out.append(TodayItem(id: "res-\(p.id)", name: p.name, at: r.at, placeId: p.id, ticketId: nil, hasQR: false))
            }
            for t in p.tickets where cal.isDate(t.at, inSameDayAs: now) {
                out.append(TodayItem(id: "tk-\(t.id)", name: p.name, at: t.at, placeId: p.id, ticketId: t.id, hasQR: t.qrPayload != nil))
            }
        }
        return out.sorted { $0.at < $1.at }
    }

    private func ticketsSection(_ items: [TodayItem]) -> some View {
        Section("Reservas e ingressos de hoje") {
            ForEach(items) { item in
                Button {
                    if let t = item.ticketId { router.push(.ticket(placeId: item.placeId, ticketId: t), on: .hoje) }
                    else { router.push(.place(id: item.placeId), on: .hoje) }
                } label: {
                    V9Row(title: item.name, detail: region.timeString(item.at), reason: item.ticketId == nil ? "reserva" : "ingresso",
                          systemImage: item.ticketId == nil ? "calendar" : "ticket") {
                        if item.hasQR { Label("QR", systemImage: "qrcode").labelStyle(.iconOnly).font(.title3).foregroundStyle(V9.accent) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(item.hasQR ? "abre o ingresso com o QR" : "abre o lugar")
            }
        }
    }

    private func row(_ title: String, detail: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            V9Row(title: title, detail: nil, reason: detail, systemImage: systemImage) {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Seletor de bairro

    private var pickerAreas: [Area] {
        let all = AreaCatalog.areas(for: region)
        let group = todayContext.context.areaId.flatMap { id in all.first { $0.id == id }?.cityId }
            ?? currentArea?.cityId
            ?? trips.first?.city(on: now, calendar: region.calendar).map { AreaCatalog.cityGroup(forCityId: $0.id) }
        let city = group.map { g in all.filter { $0.cityId == g } } ?? []
        return (city.isEmpty ? all : city).sorted { $0.name < $1.name }
    }

    private var areaPicker: some View {
        NavigationStack {
            List {
                Button {
                    todayContext.clearManual(now: now)
                    showAreaPicker = false
                    refresh()
                } label: {
                    Label("Automático", systemImage: todayContext.context.source == .manual ? "circle" : "checkmark.circle.fill")
                }
                Section("Bairros") {
                    ForEach(pickerAreas) { area in
                        Button {
                            todayContext.choose(area, now: now)
                            showAreaPicker = false
                            refresh()
                        } label: {
                            HStack {
                                Text(area.name)
                                Spacer()
                                if todayContext.context.areaId == area.id { Image(systemName: "checkmark").foregroundStyle(V9.accent) }
                            }
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Bairro de hoje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fechar") { showAreaPicker = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Gatilhos

    private func refresh() {
        let at = AppClock.now
        now = at
        let trip = trips.first
        state.refresh(.init(region: region, now: at, engine: engine, context: context, trip: trip, expenses: expenses,
                            currentArea: currentArea, nowWeather: services.sync.now(region: region, trip: trip),
                            todayWeather: services.sync.weather(on: at, region: region, trip: trip),
                            position: services.location.current?.coordinate))
        updateContext(at)
        recomputeSuggestions(now: at)
    }

    /// Alimenta o contexto estável: parada do dia, e a cidade do dia como base (o hotel ainda não tem bairro no modelo).
    private func updateContext(_ at: Date) {
        let areas = AreaCatalog.areas(for: region)
        let stopId = state.clock.flatMap { HojeLogic.dayStopAreaId(clock: $0) }
        let city = trips.first?.city(on: at, calendar: region.calendar)?.name ?? region.displayName
        todayContext.update(tripId: region.trip.id, areas: areas, dayStop: stopId.flatMap { id in areas.first { $0.id == id } },
                            baseAreaId: nil, baseName: city, now: at, calendar: region.calendar)
    }

    private func recomputeSuggestions(now: Date) {
        events.loadCached(region: region)
        suggest.recompute(.init(
            region: region, now: now, here: services.location.current?.coordinate, currentArea: currentArea, places: places,
            plan: state.plan, dayNow: state.dayNow, clock: state.clock, problem: state.problem, events: events.events, boardShows: showEvents.today(region: region, at: now),
            forecast: services.sync.weather(on: now, region: region, trip: trips.first),
            eventSourceName: { [events] in events.sourceName(forId: $0) }, gifts: gifts))
    }

    /// Cache de "por perto" da célula (só leitura, nunca chama fonte): vira o "indicado" fora do board.
    private func loadIndicated() async {
        guard let here = services.location.current else { return }
        let batch = await services.nearby.cached(lat: here.coordinate.latitude, lng: here.coordinate.longitude, region: region)
        suggest.indicated = batch?.places.filter { !$0.sources.contains(.board) } ?? []
        recomputeSuggestions(now: AppClock.now)
    }

    private func refreshEvents() async {
        recomputeSuggestions(now: AppClock.now)
        let center = services.location.current?.coordinate ?? currentArea?.centroid.clCoordinate ?? region.defaultCenter
        await events.refresh(region: region, center: center, status: services.connectivity.status, wifi: services.connectivity.isWiFi)
        recomputeSuggestions(now: AppClock.now)
    }

    private func openSuggestion(_ card: Suggestion) {
        if card.kind == .plan { router.push(.agora, on: .hoje); return }
        if card.kind == .gift, let id = card.giftId { router.push(.presente(id: id), on: .hoje); return }
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
            await feedGPS()
        }
    }

    /// O bairro do GPS só serve pra dar (ou não) a proposta; nunca troca o título (prompt 32 §3).
    private func resolveCurrentArea() async {
        guard let here = services.location.current else { return }
        let area = await services.currentArea.area(at: here, region: region)
        guard area != currentArea else { return }
        currentArea = area
        recomputeSuggestions(now: AppClock.now)
    }

    /// Cada leitura (e cada minuto parado) vai pro propositor, com o bairro dela (já resolvido fora do main).
    private func feedGPS() async {
        guard let here = services.location.current else { return }
        let area = await services.currentArea.area(at: here, region: region)
        let group = trips.first?.city(on: AppClock.now, calendar: region.calendar).map { AreaCatalog.cityGroup(forCityId: $0.id) }
        let inside = area != nil && (group == nil || group == area?.cityId)
        todayContext.feed(LocationFix(here), area: area, insideTripCity: inside)
    }
}
