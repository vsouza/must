import CoreLocation
import SwiftData
import SwiftUI

/// Explorar = o mapa (prompt 32 §4): a raiz da aba. Mapa "papel em relevo" (MapLibre, PMTiles offline; um só `MLNMapView`),
/// filtros de lista e camadas no topo, e o painel de baixo com três alturas (recolhido · médio · grande). O contexto é o
/// **centro do mapa**: arrastou, parou, 400 ms depois os 3 cartões "Agora vale" são do lugar novo. As páginas de bairro
/// (conceito B, `ExplorarView`) ficam em ⋯ › Bairros.
///
/// Painel próprio (não `.sheet`): uma sheet nativa sobre uma aba cobre a barra de abas e a faixa "agora" (não dá pra trocar de
/// aba com ela recolhida) e fica por cima das outras abas e das telas empilhadas. O painel vive dentro da aba, acima da barra,
/// com as mesmas três alturas, material do sistema e controles visíveis (pegador, "Agora vale", "Ver lista").
struct ExplorarMapaView: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(TodayContextModel.self) private var todayContext
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Environment(\.eventsFeed) private var eventsFeed
    @Environment(\.showEvents) private var showEvents
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var places: [Place]
    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var days: [PlannedDay]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var model = ExplorarMapModel()
    @State private var command: MapCameraCommand?
    /// Câmera ao vivo fora do `@Observable`/`@State` de valor: arrastar o mapa não redesenha a tela a cada quadro.
    @State private var cameraBox = CameraBox()
    @State private var headingSink = YouHeadingSink()
    @State private var mapSize: CGSize = .zero
    @State private var detent: ExplorarDetent = .collapsed
    @State private var collapsedHeight: CGFloat = 132
    @State private var drag: CGFloat = 0
    /// Altura do cabeçalho do painel (pegador, chip, campo) e do conteúdo do pino: o painel do pino tem a altura justa.
    @State private var headerHeight: CGFloat = 0
    @State private var pinContentHeight: CGFloat = 0
    @State private var booted = false
    @State private var pinDay: ExplorarPinActions.Day?
    @State private var notice: String?
    @State private var indicatedTask: Task<Void, Never>?
    @State private var showcaseFitPending = false
    /// Altura livre pro painel e a margem de baixo (barra de abas + faixa "agora"), pra enquadrar o pino acima do painel.
    @State private var available: CGFloat = 600
    @State private var bottomSafe: CGFloat = 0

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var online: Bool { services.connectivity.status != .offline }
    private var debugScreen: String { DebugFlags.string("debugScreen") ?? "" }
    /// Topo reservado pros chips e menus (o painel grande para embaixo deles); medido (cresce com o Dynamic Type).
    @State private var topReserve: CGFloat = 64

    final class CameraBox {
        var state: MapCameraState?
    }

    var body: some View {
        GeometryReader { geo in
            let available = max(collapsedHeight, geo.size.height - topReserve)
            let height = fitted(panelHeight(available: available), available: available)
            ZStack(alignment: .top) {
                map(bottomInset: height)
                    .ignoresSafeArea()
                CompassBridge(compass: services.location.compass, sink: headingSink)
                ExplorarMapTop(model: model, online: online,
                               onBairros: { router.push(.guia(date: region.calendar.startOfDay(for: now)), on: .explorar) },
                               onFullMap: { router.push(.mapa, on: .explorar) },
                               onClearShowcase: { model.setShowcase(nil) })
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topReserve = $0 + 10 }
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if detent != .large, services.location.current != nil {
                        HStack {
                            Spacer()
                            Button { locate() } label: {
                                Image(systemName: "location").frame(width: 22, height: 22)
                            }
                            .buttonStyle(.glass)
                            .buttonBorderShape(.circle)
                            .accessibilityLabel("Centralizar em mim")
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 8)
                    }
                    panel(height: height, available: available)
                }
            }
            .onChange(of: geo.size, initial: true) { _, _ in
                self.available = available
                bottomSafe = geo.safeAreaInsets.bottom
            }
        }
        .v9Screen()
        .toolbar(.hidden, for: .navigationBar)
        .id(region)
        .task(id: refreshKey) { refresh() }
        .task(id: model.selectedId) { await computePinDay() }
        .onChange(of: region, initial: true) { _, r in model.loadFilter(r) }
        .onChange(of: router.mapShowcase, initial: true) { _, showcase in consume(showcase) }
        .onChange(of: model.layers.contains(.indicated)) { _, on in if on { loadIndicated() } else { model.setIndicatedState(.idle) } }
    }

    // MARK: Mapa

    private func map(bottomInset: CGFloat) -> some View {
        var scene = MapScene(region: region, layers: [.search, .today], pins: model.pins, metro: .empty)
        scene.routeDone = model.routeDone
        scene.routeFuture = model.routeFuture
        scene.you = services.location.current?.coordinate
        scene.systemYou = true
        return MapLibreView(scene: scene, command: command,
                            onCamera: { cameraBox.state = $0 },
                            onIdle: { settle() },
                            onSelect: { pin in select(pin.id) },
                            onTapEmpty: { if model.selectedId != nil { select(nil) } },
                            headingSink: headingSink)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
            .accessibilityLabel("Mapa")
    }

    /// A câmera parou: o que está na tela e o centro (contexto) mudam.
    private func settle() {
        guard let camera = cameraBox.state else { return }
        let rect = mapSize.width > 0 ? ExplorarCenter.rect(center: camera.center, widthMeters: camera.widthMeters, size: mapSize) : nil
        model.cameraIdle(center: camera.center, rect: rect)
        if model.layers.contains(.indicated) { loadIndicated() }
    }

    private func select(_ id: String?) {
        notice = nil
        model.select(id)
        guard id != nil else { return }
        if detent != .medium { setDetent(.medium) }
        // O pino escondido atrás do painel desliza pra área livre (sem mudar o zoom).
        if let item = model.selected {
            let panel = ExplorarDetent.height(.medium, collapsed: collapsedHeight, available: available)
            command = MapCameraCommand(target: .reveal(lat: item.lat, lng: item.lng, top: 150, bottom: panel + bottomSafe + 12))
        }
    }

    private func locate() {
        guard let here = services.location.current?.coordinate else { return }
        command = MapCameraCommand(target: .center(lat: here.latitude, lng: here.longitude, widthMeters: ExplorarCenter.openingWidth))
    }

    // MARK: Dados

    /// O que, se mudar, refaz os pontos: região, minuto, os Musts, o dia aceito, a posição (célula de ~50 m) e a rede.
    private var refreshKey: String {
        let cell = services.location.current.map { "\(Int(($0.coordinate.latitude * 2000).rounded())),\(Int(($0.coordinate.longitude * 2000).rounded()))" } ?? "-"
        let stops = todayStops.map { "\($0.placeId)\($0.done)" }.joined(separator: ",")
        return "\(region.rawValue)|\(Int(now.timeIntervalSinceReferenceDate / 60))|\(PlacesRevision.of(places))|\(stops)|\(cell)|\(lists.count)"
    }

    private var todayStops: [(placeId: String, at: Date, done: Bool)] {
        let today = region.calendar.startOfDay(for: now)
        guard let day = days.first(where: { $0.date == today && $0.accepted }) else { return [] }
        return day.orderedStops.compactMap { stop in stop.place.map { ($0.id, stop.at, stop.done) } }
    }

    private var cityCenter: CLLocationCoordinate2D {
        let trip = trips.first
        if let city = trip?.city(on: now, calendar: region.calendar), city.hasCoordinate {
            return CLLocationCoordinate2D(latitude: city.lat, longitude: city.lng)
        }
        if let city = trip?.cities.first(where: \.hasCoordinate) { return CLLocationCoordinate2D(latitude: city.lat, longitude: city.lng) }
        return region.defaultCenter
    }

    private func refresh() {
        eventsFeed.loadCached(region: region)
        let events = EventsMapping.dedupe(showEvents.today(region: region, at: now) + eventsFeed.today(region: region, at: now))
        model.refresh(.init(region: region, now: now, places: places, lists: lists.map { ($0.id, $0.name) }, stops: todayStops,
                            events: events, gps: services.location.current?.coordinate, cityCenter: cityCenter))
        if !booted {
            booted = true
            boot()
        }
        fitShowcase()
    }

    /// Abertura: na sua posição se está na cidade da viagem; senão no bairro do contexto de Hoje; senão no centro da cidade.
    private func boot() {
        let areas = AreaCatalog.areas(for: region)
        var contextArea = todayContext.context.areaId.flatMap { id in areas.first { $0.id == id } }
        var gps = services.location.current?.coordinate
        #if DEBUG
        if debugScreen == "v9-explorar-indicados" {
            contextArea = areas.first { $0.id == (DebugFlags.string("debugExplorarArea") ?? "naka-meguro") }
            gps = nil
        }
        #endif
        let start = ExplorarCenter.opening(gps: gps, cityCenter: cityCenter, contextArea: contextArea)
        if !showcaseFitPending, model.showcase == nil {
            command = MapCameraCommand(target: .center(lat: start.latitude, lng: start.longitude, widthMeters: ExplorarCenter.openingWidth),
                                       animated: false)
        }
        model.cameraIdle(center: start, rect: nil)
        #if DEBUG
        applyDebug()
        #endif
    }

    #if DEBUG
    /// Prints e UI tests: `v9-explorar-recolhida`, `-media`, `-grande`, `-pino` (primeiro Must perto do centro selecionado) e
    /// `-indicados` (camada Indicados ligada no bairro de `-debugExplorarArea`, primeiro de fora selecionado).
    private func applyDebug() {
        switch debugScreen {
        case "v9-explorar-media": detent = .medium
        case "v9-explorar-grande": detent = .large
        case "v9-explorar-pino":
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                let first = model.visible.first { $0.kind == .must && !$0.done } ?? model.shown.first { $0.kind == .must }
                if let first { select(first.id) }
            }
        case "v9-explorar-indicados":
            model.setLayer(.indicated, on: true)
            Task {
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(500))
                    if let first = model.visible.first(where: { $0.kind == .indicated }) ?? model.indicatedItems.first {
                        select(first.id)
                        return
                    }
                }
            }
        default: break
        }
    }
    #endif

    /// "Ver no mapa": só esses pinos, enquadrados; zera o pedido do router.
    private func consume(_ showcase: MapShowcase?) {
        guard let showcase else { return }
        router.mapShowcase = nil
        model.setShowcase(showcase)
        model.select(nil)
        detent = .collapsed
        showcaseFitPending = true
        fitShowcase()
    }

    /// Enquadra o "Ver no mapa" assim que os pontos existem (na primeira abertura, só depois do primeiro `refresh`).
    private func fitShowcase() {
        guard showcaseFitPending, model.showcase != nil, !model.items.isEmpty else { return }
        showcaseFitPending = false
        let points = ExplorarShowcaseLogic.fitPoints(model.shown, near: model.center)
        if points.count == 1 {
            command = MapCameraCommand(target: .center(lat: points[0].lat, lng: points[0].lng, widthMeters: ExplorarCenter.openingWidth))
        } else if points.count > 1 {
            command = MapCameraCommand(target: .fit(points: points, top: 150, bottom: collapsedHeight + bottomSafe + 70, sides: 48))
        }
    }

    /// Camada Indicados: cache do Por perto da célula do centro; com rede (e sem Pouco Dados), uma busca por célula por sessão.
    private func loadIndicated() {
        guard let center = model.center else { return }
        indicatedTask?.cancel()
        let region = region
        indicatedTask = Task {
            try? await Task.sleep(for: ExplorarCenter.debounce)
            guard !Task.isCancelled else { return }
            if let cached = await services.nearby.cached(lat: center.latitude, lng: center.longitude, region: region) {
                model.addIndicated(cached.places)
            }
            let cell = NearbyCell.key(lat: center.latitude, lng: center.longitude, region: region)
            switch model.indicatedPolicy.decide(area: cell, region: region, status: services.connectivity.status) {
            case .fetch:
                model.setIndicatedState(.loading)
                let batch = await services.nearby.load(lat: center.latitude, lng: center.longitude, region: region)
                model.addIndicated(batch.places)
                model.setIndicatedState(.loaded)
            case .offline: model.setIndicatedState(.offline)
            case .lowData: model.setIndicatedState(.lowData)
            case .alreadyThisSession: model.setIndicatedState(.loaded)
            }
        }
    }

    // MARK: Painel

    private func panelHeight(available: CGFloat) -> CGFloat {
        let base = ExplorarDetent.height(detent, collapsed: collapsedHeight, available: available)
        return min(max(base + drag, collapsedHeight), available)
    }

    /// Com um pino aberto, o painel cobre só o que o conteúdo precisa (sem vazio embaixo); nunca passa da altura da posição.
    /// Pino aberto: o painel mede o cartão inteiro (ações incluídas, acima da faixa "agora"), até 85% da tela.
    private func fitted(_ height: CGFloat, available: CGFloat) -> CGFloat {
        guard model.selected != nil, drag == 0, detent != .large, pinContentHeight > 0, headerHeight > 0 else { return height }
        return min(available * 0.85, max(collapsedHeight, headerHeight + pinContentHeight + 8))
    }

    private func setDetent(_ d: ExplorarDetent) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.3)) { detent = d }
    }

    private func panel(height: CGFloat, available: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                grabber(available: available)
                offlineChip
                askField
                if model.selected == nil { summaryRow }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                headerHeight = h
                if model.selected == nil, abs(h - collapsedHeight) > 1 { collapsedHeight = h }
            }
            if let item = model.selected {
                ScrollView {
                    ExplorarPlaceSummary(item: item, distance: ExplorarMapModel.distanceLine(model.meters(to: item)), region: region,
                                         pinDay: pinDay, notice: notice, photoRefs: model.photoRefs[item.id] ?? [],
                                         onClose: { select(nil) }, onGo: { go(item) }, onFit: { fit(item) },
                                         onOpen: { open(item) }, onSave: { save(item) })
                        .padding(.bottom, 76)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pinContentHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else if detent == .medium || (detent == .collapsed && drag > 20) {
                ExplorarAgoraList(model: model, onTap: tapCard)
            } else if detent == .large {
                ExplorarVisibleList(model: model, onTap: { select($0.id) })
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        // O corte: papel de ponta a ponta com régua preta grossa em cima, sem raio e sem sombra; fica no claro com o mapa escuro.
        .background(V8.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 6) }
        .v8Legacy()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Painel do mapa")
    }

    /// Pegador: toque sobe um degrau (no grande, recolhe); arrastar muda a altura (atalho, como a sheet do sistema).
    private func grabber(available: CGFloat) -> some View {
        Button { setDetent(detent.next) } label: {
            Rectangle().fill(V8.orange).frame(width: 40, height: 4)
                .frame(maxWidth: .infinity, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { drag = -$0.translation.height }
                .onEnded { value in
                    let base = ExplorarDetent.height(detent, collapsed: collapsedHeight, available: available)
                    let target = ExplorarDetent.settle(predicted: base - value.predictedEndTranslation.height,
                                                       collapsed: collapsedHeight, available: available)
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.3)) {
                        detent = target
                        drag = 0
                    }
                })
        .accessibilityLabel(detent == .large ? "Recolher o painel" : (detent == .medium ? "Ver a lista do mapa" : "Mostrar o Agora vale"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if detent != .large { setDetent(ExplorarDetent(rawValue: detent.rawValue + 1) ?? .large) }
            case .decrement: if detent != .collapsed { setDetent(ExplorarDetent(rawValue: detent.rawValue - 1) ?? .collapsed) }
            @unknown default: break
            }
        }
    }

    /// Recolhido: "Agora vale · 3 perto" (toque abre o médio). Médio/grande: o título da seção e "Ver lista"/"Agora vale".
    private var summaryRow: some View {
        HStack(spacing: 8) {
            Button { setDetent(detent == .collapsed ? .medium : .collapsed) } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((detent == .large ? "No mapa · \(model.visible.count)" : model.summaryLine).uppercased())
                            .font(V8Font.mono(11, weight: .semibold)).tracking(1).foregroundStyle(V8.ink)
                        if let area = model.centerArea?.name {
                            Text("perto de \(area)").font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: detent == .collapsed ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(V8.ink)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(detent == .collapsed ? "Mostra os 3 lugares que valem agora perto do centro do mapa" : "Recolhe o painel")
            if detent != .collapsed {
                Button { setDetent(detent == .large ? .medium : .large) } label: {
                    CutChip(text: detent == .large ? "Agora vale" : "Ver lista", minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Pedir algo…": campo visível com nome, borda de 2 pt (abre o Quero).
    private var askField: some View {
        Button { router.openQuero() } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .bold))
                Text("PEDIR ALGO…").font(V8Font.mono(12, weight: .semibold)).tracking(1).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "mic.fill").font(.system(size: 14, weight: .bold)).accessibilityHidden(true)
            }
            .foregroundStyle(V8.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pedir algo")
        .accessibilityHint("Abre o Quero")
    }

    @ViewBuilder private var offlineChip: some View {
        if services.connectivity.status == .offline {
            CutTag(text: "sem internet · offline ok", filled: true)
                .accessibilityLabel("Sem internet. O app funciona offline com o que já está no aparelho.")
        }
    }

    private func tapCard(_ card: Suggestion) {
        if let id = card.placeId, model.shown.contains(where: { $0.id == id }) {
            select(id)
            return
        }
        if let id = card.eventId, model.shown.contains(where: { $0.id == "ev-\(id)" }) {
            select("ev-\(id)")
            return
        }
        if card.kind == .gift, let id = card.giftId { router.push(.presente(id: id), on: .explorar); return }
        if let id = card.placeId { router.push(.place(id: id), on: .explorar); return }
        if let url = card.url { openURL(url); return }
        if let c = card.coordinate { MapsLinks.openApple(to: c, name: card.title) }
    }

    // MARK: Lugar resumido

    private func computePinDay() async {
        guard let item = model.selected, item.kind == .must || item.kind == .indicated else { pinDay = nil; return }
        pinDay = ExplorarPinActions.day(for: item.asExplorarItem(meters: model.meters(to: item) ?? 0), env: queroEnv())
    }

    private func go(_ item: ExplorarMapItem) {
        if item.kind == .must, let id = item.placeId { router.push(.ir(placeId: id), on: .explorar) }
        else { MapsLinks.openApple(to: item.coordinate, name: item.name) }
    }

    private func open(_ item: ExplorarMapItem) {
        if let id = item.placeId { router.push(.place(id: id), on: .explorar); return }
        if let eventId = item.eventId, let url = model.eventURL(eventId) { openURL(url) }
    }

    /// "Encaixar hoje": a mesma conta do Quero (grava o Must, se for de fora, e a parada no buraco).
    private func fit(_ item: ExplorarMapItem) {
        guard case .fit(let slot)? = pinDay else { return }
        let env = queroEnv()
        let lists = (try? context.fetch(FetchDescriptor<MustList>())) ?? []
        let row = ExplorarPinActions.row(for: item.asExplorarItem(meters: model.meters(to: item) ?? 0), slot: slot, areaId: model.centerArea?.id)
        guard let place = QueroSave.place(for: row, intent: nil, text: "", lists: lists, cityId: env.cityId, region: region,
                                          sync: services.sync, context: context),
              (try? QueroSave.encaixar(row, place: place, env: env, context: context)) != nil else {
            notice = "Não deu pra gravar no dia."
            return
        }
        let time = region.timeString(slot.start)
        pinDay = .inDay(time: time)
        notice = "Encaixado hoje às \(time)."
    }

    /// "Guardar": o de fora vira Must (e o pino vira seu).
    private func save(_ item: ExplorarMapItem) {
        let env = queroEnv()
        let lists = (try? context.fetch(FetchDescriptor<MustList>())) ?? []
        let row = ExplorarPinActions.row(for: item.asExplorarItem(meters: model.meters(to: item) ?? 0), slot: nil, areaId: model.centerArea?.id)
        guard let place = QueroSave.place(for: row, intent: nil, text: "", lists: lists, cityId: env.cityId, region: region,
                                          sync: services.sync, context: context) else {
            notice = "Não deu pra guardar agora."
            return
        }
        if (place.area ?? "").isEmpty, let area = model.centerArea {
            place.area = area.id
            try? context.save()
        }
        refresh()
        select(place.id)
        notice = "Guardado no board."
    }

    private func queroEnv() -> QueroEnv {
        let all = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let today = region.calendar.startOfDay(for: now)
        let plan = dayEngine.plan(for: today, region: region, context: context)
        return QueroEnv.make(region: region, now: now, places: all, trip: trips.first, settings: settingsList.first, plan: plan,
                             gps: services.location.current?.coordinate, online: online,
                             upcoming: QueroEnv.upcomingDays(context: context, areas: AreaCatalog.areas(for: region), today: today),
                             areaHint: model.centerArea)
    }
}
