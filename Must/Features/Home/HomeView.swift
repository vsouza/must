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
    /// Chave do ajuste que o "Ajustar" já confirmou (some o botão, fica a linha do que saiu).
    @State private var adjustAck: String?
    /// Foto do bairro que o app já tem no disco (nunca baixa).
    @State private var photoURL: URL?
    @State private var safeTop: CGFloat = 0
    @ScaledMetric(relativeTo: .title) private var bandScale: CGFloat = 1
    @Environment(\.tripTheme) private var theme

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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                band
                CutRule()
                HojeAskField { router.openQuero() }
                if services.connectivity.status == .offline { HojeOfflineStrip() }
                if let greeting { greetingNotice(greeting) }
                if let proposal { arrivalNotice(proposal) }
                if let special = state.special { specialSection(special) }
                if let next {
                    nextSection(next)
                } else if upcoming {
                    upcomingStrip
                } else {
                    suggestSection
                }
                let tickets = todayItems
                if !tickets.isEmpty { ticketsSection(tickets) }
                CutRow(title: "Ir pra um bairro", detail: "marque os Musts e eu monto o trajeto") { CutValue(text: "", chevron: true) }
                    .onTapGesture { router.push(.irBairro(), on: .hoje) }
                    .accessibilityAddTraits(.isButton)
                V8BarSpacer()
            }
        }
        .scrollIndicators(.hidden)
        .cutBleed($safeTop)
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .v8Legacy()
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
        .task(id: photoAreaId) { photoURL = await DayBand<EmptyView>.photo(region: region, areaId: photoAreaId, places: places) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .onChange(of: gifts.map { "\($0.id)\($0.boughtAt != nil)" }) { _, _ in recomputeSuggestions(now: AppClock.now) }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in scheduleRefresh() }
    }

    // MARK: Bloco do bairro

    /// Bairro da foto: o do contexto estável (o do título), senão o do dia.
    private var photoAreaId: String? { todayContext.context.areaId ?? state.areaId }

    private var upcoming: Bool { state.content.map { $0.lead == "Primeiro dia" && $0.agora == nil } ?? false }

    private var contextName: String {
        if upcoming, let area = state.content?.area { return area }
        let name = todayContext.context.name
        return name.isEmpty ? (state.content?.area ?? region.displayName) : name
    }

    private var dayText: String {
        "\(DayText.weekdayShort(now, region: region).capitalizedFirst), \(region.shortDay(now))"
    }

    /// Foto só quando o app já tem uma no disco: sem ela o bloco é a cor do lugar e fica mais baixo.
    private var bandHeight: CGFloat { (photoURL == nil ? 236 : 300) * min(bandScale, 1.3) + safeTop }

    private var band: some View {
        let ink = theme.coverInk
        let content = state.content
        return CutBand(photo: debugScreen == "hoje-sem-foto" ? nil : photoURL) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    SpecStack(lines: content?.topLeft ?? [dayText], color: ink.opacity(0.9))
                    Spacer(minLength: 6)
                    SpecStack(lines: content?.topRight ?? [], color: ink.opacity(0.9), alignment: .trailing)
                        .lineLimit(2)
                    CutCornerButton(systemName: "sparkle", label: "Assistente", tint: ink) { router.sheet = .assistant }
                    moreMenu(ink)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    theme.flag.frame(width: 22, height: 22)
                    SpecLabel(upcoming ? "\(content?.country ?? "") · \(content?.topLeft.first ?? "a viagem começa")"
                                       : "\(content?.country ?? region.countryName) · você está em", color: ink)
                }
                Button { showAreaPicker = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(contextName)
                            .font(V8Font.display(64)).tracking(-2).foregroundStyle(ink)
                            .lineLimit(2).minimumScaleFactor(0.5)
                        Image(systemName: "chevron.down").font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dayText), \(contextName)")
                .accessibilityHint("Escolher o bairro")
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10 + safeTop)
            .padding(.bottom, 16)
        }
        .frame(height: bandHeight)
    }

    private func moreMenu(_ ink: Color) -> some View {
        Menu {
            Button { router.push(.bolso, on: .hoje) } label: { Label("Bolso", systemImage: "bag") }
            Button { router.push(.sos, on: .hoje) } label: { Label("SOS", systemImage: "cross.case") }
            Button { router.sheet = .viagens } label: { Label("Minhas viagens", systemImage: "arrow.left.arrow.right") }
            Button { router.push(.irBairro(), on: .hoje) } label: { Label("Bairros", systemImage: "figure.walk") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(ink)
                .frame(width: 44, height: 44)
                .overlay(Rectangle().stroke(ink, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Mais: Bolso, SOS, Minhas viagens, Bairros")
    }

    // MARK: Avisos

    private func greetingNotice(_ g: HojeLogic.Greeting) -> some View {
        HojeNoticeStrip(systemImage: g == .bomDia ? "sun.max" : "moon.stars",
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
        HojeNoticeStrip(tone: .ink, systemImage: "location", text: "Você chegou em \(area.name)", actionTitle: "ver perto",
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

    private func sectionLabel(_ text: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MonoLabel(text, size: 10, color: V8.mute)
            Spacer(minLength: 8)
            if let trailing { MonoLabel(trailing, size: 10, color: V8.ink) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Com dia

    private func nextSection(_ n: HojeNext) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary = replanSummary { adjustNotice(summary) }
            sectionLabel("seu dia", trailing: state.clock?.adjusted == true ? "ajustei · faltam \(state.clock?.remaining ?? 0)" : nil)
            HojeNextBlock(next: n, region: region) {
                if let placeId = n.placeId { router.push(.ir(placeId: placeId), on: .hoje) }
            }
            ForEach(following(n)) { stop in
                HojeIndexRow(tone: .paper, big: region.timeString(stop.start), unit: DayText.caption(for: stop, isNow: false),
                             title: DayText.head(stop.label), reason: stop.note) { openStop(stop) }
            }
            Button { router.push(.linha(date: today), on: .hoje) } label: {
                CutRow(title: "Ver o dia", detail: "a linha com todas as paradas") { CutValue(text: "", chevron: true) }
            }
            .buttonStyle(.plain)
        }
    }

    private func following(_ n: HojeNext) -> [DayStop] {
        guard let clock = state.clock else { return [] }
        return HojeLogic.following(clock: clock, after: n.stopId, limit: 3)
    }

    private func openStop(_ stop: DayStop) {
        if let id = stop.placeId { router.push(.place(id: id), on: .hoje) } else { router.push(.linha(date: today), on: .hoje) }
    }

    // MARK: Atrasou? Ajustar

    private var replanSummary: ReplanSummary? {
        state.clock.flatMap { ReplanSummary.make(clock: $0, region: region) }
    }

    /// O dia já foi refeito (todas as telas leem o mesmo relógio); aqui está o que saiu e por quê, e um toque confirma.
    private func adjustNotice(_ summary: ReplanSummary) -> some View {
        let confirmed = adjustAck == summary.key
        return DayStrip(tone: .ink) {
            VStack(alignment: .leading, spacing: 8) {
                Label(confirmed ? "Dia ajustado" : summary.headline, systemImage: "arrow.triangle.2.circlepath")
                    .font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.white)
                ForEach(summary.removed, id: \.self) { line in
                    Text(line).font(V8Font.text(13)).foregroundStyle(V8.muteDark)
                }
                if !confirmed {
                    Button { adjustAck = summary.key; refresh() } label: {
                        Text("AJUSTAR").font(V8Font.mono(12, weight: .semibold)).tracking(1).foregroundStyle(V8.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(V8.orange)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajustar")
                    .accessibilityHint("confirma o dia refeito a partir de agora")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Dia especial (chegada · troca de cidade · último dia)

    private func specialSection(_ day: SpecialDay) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DayStrip(tone: .orange) {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel(day.title, size: 10, color: V8.ink)
                    Text(day.headline).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink)
                }
            }
            ForEach(day.items) { item in
                CutRow(title: item.title, detail: item.detail) {
                    if item.done { CutValue(text: "feito") }
                }
                .opacity(item.done ? 0.5 : 1)
            }
        }
    }

    // MARK: Sem dia

    private var upcomingStrip: some View {
        DayStrip {
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("a viagem", size: 10, color: V8.mute)
                Text((state.content?.midLeft ?? []).joined(separator: " · ")).font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.ink)
            }
        }
    }

    private var suggestSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("agora vale")
            if !suggest.stateLine.isEmpty {
                Text(suggest.stateLine).font(V8Font.mono(11)).foregroundStyle(V8.ink).lineLimit(3)
                    .padding(.horizontal, 20).padding(.bottom, 10)
            }
            if suggest.cards.isEmpty {
                Text(suggest.emptyLine.isEmpty ? "Nada aberto por perto agora. Peça algo ou monte o dia." : suggest.emptyLine)
                    .font(V8Font.text(14)).foregroundStyle(V8.mute)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { IndexRule() }
            }
            ForEach(suggest.cards.prefix(3)) { card in
                HojeIndexRow(card: card) { openSuggestion(card) }
            }
            HojeWideButton(title: "Montar o dia") { router.push(.montar(date: today), on: .hoje) }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("reservas e ingressos de hoje")
            ForEach(items) { item in
                HojeIndexRow(tone: .ink, big: region.timeString(item.at), unit: item.ticketId == nil ? "reserva" : "ingresso",
                             title: item.name, reason: item.hasQR ? "QR no ingresso" : "") {
                    if let t = item.ticketId { router.push(.ticket(placeId: item.placeId, ticketId: t), on: .hoje) }
                    else { router.push(.place(id: item.placeId), on: .hoje) }
                }
            }
        }
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
