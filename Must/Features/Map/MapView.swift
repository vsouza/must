import CoreLocation
import SwiftData
import SwiftUI

/// Mapa do Must: base "papel em relevo" (MapLibre + PMTiles), metrô, rota de hoje (feito em linha, por fazer em
/// contas), rota de amanhã tracejada, carimbos dos musts sem plano e a sheet "Perto de você".
struct MapView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(\.dayEngine) private var engine

    @Query private var places: [Place]
    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var days: [PlannedDay]
    @Query private var settingsList: [Settings]
    @Query private var trips: [TripInfo]

    @State private var layers: Set<MapLayer> = [.today, .tomorrow, .unplanned, .metro]
    @State private var camera: MapCameraState?
    @State private var cam = MapCameraController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var routes = RouteGeometry()
    @State private var pinsMemo = PinsMemo()
    /// Bússola → cone do "você" (prompt 18 · A.2). Fica fora do `body`: ver `CompassBridge`.
    @State private var headingSink = YouHeadingSink()
    @State private var selectedId: String?
    @State private var didCenter = false
    /// Filtro por Must (prompt 27 §2.b), salvo por região.
    @State private var mustFilter = MapMustFilter()
    @State private var filterRegion: Region?
    /// Busca "o melhor X perto de mim agora" (prompt 27 §2.c).
    @State private var search = MapSearchModel(provider: MapSearchModel.providers().plain, rated: MapSearchModel.providers().rated)
    @State private var speech = SpeechInput()
    @State private var nearbyCache: [NearbyPlace] = []
    @State private var failure: String?
    @FocusState private var searchFocused: Bool

    /// Escala de bairro: ~900 m de largura de tela (a barra mostra "300 m").
    static let neighborhoodWidth: Double = 900
    /// "Perto de você".
    static let nearRadius: CLLocationDistance = 500
    /// Altura livre embaixo com o card do pino ou dos resultados aberto (card + barra de abas).
    static let cardBottom: CGFloat = 96 + 400
    /// Topo livre com o card aberto (barra de voltar + fechar + ficha técnica).
    static let cardTop: CGFloat = 190
    /// Topo livre com a busca (campo + chips + pílulas).
    static let resultsTop: CGFloat = 240

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var transit: TransitMap { TransitLoader.load(region) }
    private var walkMaxKm: Double { settingsList.first?.walkMaxKm ?? 1.5 }
    private var here: CLLocation? { services.location.current }

    private func accepted(_ offset: Int) -> PlannedDay? {
        let start = region.calendar.startOfDay(for: now)
        guard let day = region.calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
        return days.first { $0.date == day && $0.accepted }
    }

    private var stops: [Stop] { accepted(0)?.orderedStops.filter { $0.place != nil } ?? [] }
    private var tomorrowStops: [Stop] { accepted(1)?.orderedStops.filter { $0.place != nil } ?? [] }
    private var nextStop: Stop? { stops.first { !$0.done } }

    private var currentCityName: String? { trips.first?.city(on: now, calendar: region.calendar)?.name }

    /// Musts da cidade de hoje que não estão no roteiro de hoje nem de amanhã.
    private var unplannedPlaces: [Place] {
        let planned = Set((stops + tomorrowStops).compactMap { $0.place?.id })
        return places.filter { p in
            !planned.contains(p.id) && !p.isDone
                && (currentCityName == nil || trips.first?.city(id: p.cityId)?.name == currentCityName)
        }
    }

    private var fallbackCenter: CLLocationCoordinate2D {
        if let here { return here.coordinate }
        if let next = nextStop?.place { return next.coordinate }
        if let city = trips.first?.city(on: now, calendar: region.calendar) {
            return CLLocationCoordinate2D(latitude: city.lat, longitude: city.lng)
        }
        return region.defaultCenter
    }

    var body: some View {
        ZStack {
            Color(hex: 0xE9EBEF).ignoresSafeArea()
            MapLibreView(scene: scene, command: cam.command,
                         onCamera: { camera = $0 },
                         onGesture: { cam.userGestured() },
                         onIdle: { cam.cameraIdle() },
                         onSelect: select,
                         onTapEmpty: tapEmpty,
                         headingSink: headingSink)
                .ignoresSafeArea()
            CompassBridge(compass: services.location.compass, sink: headingSink)
            StatusBarScrim()
            overlays
        }
        .onAppear(perform: appear)
        .onAppear {
            // Voz (o mesmo `SpeechInput` do Quero…): ao parar de falar, busca.
            speech.onFinal = { text in
                search.text = text
                submitSearch()
            }
        }
        .task { await debugScreen() }
        .onDisappear { speech.cancel() }
        .onChange(of: router.mapShowsOpenNow) { _, open in if open { consumeOpenNow() } }
        .onChange(of: region, initial: true) { _, r in loadFilter(r) }
        .onChange(of: mustFilter) { _, f in
            guard filterRegion == region else { return }
            f.save(region)
            if selectedId == nil, !search.isActive { reevaluate(force: true) }
        }
        .onChange(of: search.top.map(\.id)) { _, _ in fitResults() }
        .onChange(of: speech.transcript) { _, t in if speech.isListening, !t.isEmpty { search.text = t } }
        .onChange(of: (stops + tomorrowStops).map(\.id)) { _, _ in requestRoutes() }
        // Reavaliar a câmera: andou (> 100 m, o controlador filtra), camada, 済, voltou pro app com o mapa em foco.
        .onChange(of: here.map { [$0.coordinate.latitude, $0.coordinate.longitude] }) { _, _ in reevaluate(force: false) }
        .onChange(of: layers) { _, _ in reevaluate(force: true) }
        .onChange(of: stops.filter(\.done).count) { _, _ in reevaluate(force: true) }
        .onChange(of: selectedId, initial: true) { _, id in router.mapCardOpen = id != nil }
        .onDisappear { router.mapCardOpen = false }
        .onChange(of: scenePhase) { _, phase in if phase == .active && router.tab == .explorar { reevaluate(force: true) } }
    }

    // MARK: Câmera (prompt 11)

    /// Pinos das camadas ligadas que contam pro "mais perto".
    private var candidates: [MapCandidate] {
        let nextId = nextStop?.place?.id
        return mustPins.filter { pin in
            guard layers.contains(pin.layer), pin.placeId != nil else { return false }
            if case .today(_, .done, _) = pin.kind { return false }
            return true
        }
        .map { MapCandidate(placeId: $0.placeId!, coordinate: $0.coordinate, isNextStop: $0.placeId == nextId && $0.layer == .today) }
    }

    private func reevaluate(force: Bool, animated: Bool = true) {
        cam.evaluate(here: here, candidates: candidates, fallback: fallbackCenter, force: force, animated: animated)
    }

    /// O "mais perto" quando não há nada a 500 m.
    private var farTarget: (place: Place, target: MapFocus.Target)? {
        guard selectedId == nil, let target = cam.focus?.target, let place = places.first(where: { $0.id == target.placeId }) else { return nil }
        return (place, target)
    }

    /// "2,1 km · 9 min de metrô" (a pé quando < 1,2 km).
    private func distanceText(_ meters: CLLocationDistance, to place: Place) -> String {
        guard let leg = legFromHere(to: place, walkUnderKm: 1.2) else { return Self.meters(meters) }
        return "\(Self.meters(meters)) · \(leg.text)"
    }

    /// Minutos a pé pela rua (80 m/min), pro "26 a pé" do card.
    private func walkMinutes(to place: Place) -> Int? {
        guard let here else { return nil }
        return Int((DaySolver.streetKm(here.coordinate, place.coordinate) * 1000 / 80).rounded())
    }

    // MARK: Cena

    private var scene: MapScene {
        // Com a busca aberta, os números são os dos resultados (`MapaFiltro.png`): o dia (pinos e rota) sai da frente.
        let shown = search.top.isEmpty || selectedId != nil ? layers : layers.subtracting([.today, .tomorrow])
        var scene = MapScene(region: region, layers: shown.union([.search]), pins: displayPins, metro: transit)
        let legs = Array(zip(stops, stops.dropFirst()))
        for (a, b) in legs {
            guard let pa = a.place, let pb = b.place else { continue }
            let path = routes.path(from: pa, to: pb)
            if b.done { scene.routeDone.append(path) } else { scene.routeFuture.append(path) }
        }
        for (a, b) in zip(tomorrowStops, tomorrowStops.dropFirst()) {
            if let pa = a.place, let pb = b.place { scene.routeTomorrow.append(routes.path(from: pa, to: pb)) }
        }
        scene.you = here?.coordinate
        if let far = farTarget, let here {
            let target = far.target.coordinate.value
            if cam.showsDistanceLine {
                scene.distanceLine = [here.coordinate, target]
                let mid = CLLocationCoordinate2D(latitude: (here.coordinate.latitude + target.latitude) / 2,
                                                 longitude: (here.coordinate.longitude + target.longitude) / 2)
                scene.pins.append(MapPin(id: "distance-badge", coordinate: mid, kind: .badge(text: distanceText(far.target.meters, to: far.place)),
                                         placeId: nil, layer: far.target.isNextStop ? .today : .unplanned))
            }
            if !far.target.isNextStop {
                scene.pins.append(MapPin(id: "nearest-callout", coordinate: target, kind: .callout(text: "\(Self.shortName(far.place.name)) · mais perto"),
                                         placeId: far.place.id, layer: .unplanned))
            }
        }
        return scene
    }

    /// Lista de cada lugar (pro filtro por Must).
    private var listOf: [String: String] {
        Dictionary(places.compactMap { p in p.list.map { (p.id, $0.id) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Pinos depois do filtro por Must (não toca metrô, "você", distância nem busca).
    private var mustPins: [MapPin] { mustFilter.apply(pins, listOf: listOf) }

    /// O que o mapa desenha: filtro por Must, resultados da busca por cima (o mesmo lugar do board some, pra não ter dois
    /// pinos) e o selecionado/escolhido em laranja.
    private var displayPins: [MapPin] {
        var out = mustPins
        let results = search.top
        if !results.isEmpty, selectedId == nil {
            let boardIds = Set(results.compactMap(\.result.boardPlaceId))
            out.removeAll { $0.placeId.map(boardIds.contains) == true }
            let chosen = search.chosen?.id
            for (i, c) in results.enumerated() where MapSearch.valid(c.result.lat, c.result.lng) {
                out.append(MapPin(id: "result-\(c.id)", coordinate: c.result.coordinate, kind: .result(number: i + 1),
                                  placeId: c.result.boardPlaceId, layer: .search, highlighted: c.id == chosen))
            }
        }
        if let selectedId {
            for i in out.indices where out[i].placeId == selectedId && out[i].layer != .search {
                if case .callout = out[i].kind { continue }
                if case .badge = out[i].kind { continue }
                out[i].highlighted = true
            }
        }
        return out
    }

    /// Pinos memoizados (A.2): `body` lê `pins` várias vezes; só monta de novo quando a chave muda.
    private var pins: [MapPin] {
        pinsMemo.pins(for: pinsKey) { buildPins() }
    }

    private var pinsKey: PinsMemo.Key {
        PinsMemo.Key(
            revision: PlacesRevision.of(places),
            minute: Int(now.timeIntervalSinceReferenceDate / 60),
            timeZone: region.timeZone.identifier,
            today: stops.map { "\($0.id)|\($0.done)|\($0.place?.id ?? "")" },
            tomorrow: tomorrowStops.map { "\($0.id)|\($0.place?.id ?? "")" },
            focusPlaceId: cam.focus?.target?.placeId,
            hasSelection: selectedId != nil,
            cityName: currentCityName,
            here: here.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" } ?? "",
            walkMaxKm: walkMaxKm
        )
    }

    private func buildPins() -> [MapPin] {
        var pins: [MapPin] = []
        let next = nextStop
        for (i, stop) in stops.enumerated() {
            guard let place = stop.place else { continue }
            let status: MapPin.TodayStatus = stop.done ? .done : (stop.id == next?.id ? .next : .future)
            let isFarTarget = cam.focus?.target?.placeId == place.id && selectedId == nil
            let caption = status == .next ? (isFarTarget ? "\(Self.shortName(place.name)) · mais perto" : nextCaption(place)) : nil
            pins.append(MapPin(id: "today-\(place.id)", coordinate: place.coordinate,
                               kind: .today(number: i + 1, status: status, label: caption), placeId: place.id, layer: .today))
        }
        for (i, stop) in tomorrowStops.enumerated() {
            guard let place = stop.place, !stops.contains(where: { $0.place?.id == place.id }) else { continue }
            pins.append(MapPin(id: "tomorrow-\(place.id)", coordinate: place.coordinate,
                               kind: .tomorrow(number: i + 1), placeId: place.id, layer: .tomorrow))
        }
        for place in unplannedPlaces {
            pins.append(MapPin(id: "must-\(place.id)", coordinate: place.coordinate,
                               kind: .unplanned(kanji: kanji(place), color: place.list?.color ?? .eat, open: openState(place)),
                               placeId: place.id, layer: .unplanned))
        }
        let inRoute = Set(stops.compactMap { $0.place?.id })
        for place in places where place.isDone && !inRoute.contains(place.id) {
            pins.append(MapPin(id: "done-\(place.id)", coordinate: place.coordinate,
                               kind: .today(number: 0, status: .done, label: nil), placeId: place.id, layer: .done))
        }
        return pins
    }

    private func kanji(_ place: Place) -> String {
        // Letra latina da lista (E de eat, D de drink…): nada de kanji no pino.
        String((place.list?.name ?? place.name).prefix(1)).uppercased()
    }

    private func openState(_ place: Place) -> PinOpenState {
        #if DEBUG
        if DebugFlags.bool("debugPinsOpen") { // -debugPinsOpen YES: aberto / fechando / fechado
            return [PinOpenState.open, .closingSoon(remaining: 0.4), .closed][abs(place.id.hashValue) % 3]
        }
        #endif
        switch place.openState(at: now, timeZone: region.timeZone) {
        case .open(let until):
            guard let until, let close = Settings.minutes(from: until) else { return .open }
            var left = close - minutesNow
            if left < 0 { left += 1440 }
            return left <= 30 ? .closingSoon(remaining: Double(left) / 30) : .open
        case .closed: return .closed
        case .unknown: return .unknown
        }
    }

    private var minutesNow: Int {
        region.calendar.component(.hour, from: now) * 60 + region.calendar.component(.minute, from: now)
    }

    /// "Inimá · 14 min a pé"
    private func nextCaption(_ place: Place) -> String {
        guard let leg = legFromHere(to: place) else { return Self.shortName(place.name) }
        return "\(Self.shortName(place.name)) · \(leg.text)"
    }

    private func legFromHere(to place: Place, walkUnderKm: Double? = nil) -> (minutes: Int, text: String, mode: LegMode)? {
        guard let here else { return nil }
        let leg = DaySolver.leg(here.coordinate, place.coordinate, walkMax: walkUnderKm ?? walkMaxKm)
        let minutes = services.eta.minutes(from: here.coordinate, to: place.coordinate, transit: leg.mode == .metro) ?? leg.minutes
        return (minutes, leg.mode == .walk ? "\(minutes) min a pé" : "\(minutes) min de metrô", leg.mode)
    }

    /// "Museu Inimá de Paula" → "Inimá"; nomes curtos ficam inteiros.
    static func shortName(_ name: String) -> String {
        let generic: Set<String> = ["museu", "mercado", "igreja", "praça", "parque", "templo", "santuário", "restaurante", "casa", "centro"]
        let words = name.split(separator: " ").map(String.init)
        guard words.count >= 3, generic.contains(words[0].lowercased()) else { return name }
        return words[1]
    }

    // MARK: Perto de você

    private struct Near: Identifiable {
        var place: Place
        var meters: CLLocationDistance
        var id: String { place.id }
    }

    private var nearby: [Near] {
        guard let here else { return [] }
        let visible = Set(mustPins.filter { layers.contains($0.layer) }.compactMap(\.placeId))
        return places.filter { visible.contains($0.id) && !$0.isDone }
            .map { Near(place: $0, meters: $0.location.distance(from: here)) }
            .filter { $0.meters <= Self.nearRadius }
            .sorted { $0.meters < $1.meters }
    }

    private func isOpen(_ place: Place) -> Bool { place.openState(at: now, timeZone: region.timeZone).isOpen }

    private var areaName: String {
        let c = fallbackCenter
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let nearest = places.filter { $0.area != nil }.min { $0.location.distance(from: location) < $1.location.distance(from: location) }
        if let nearest, nearest.location.distance(from: location) < 2500, let area = nearest.area { return area }
        return currentCityName ?? region.displayName
    }

    // MARK: Por cima

    private var selectedPlace: Place? { selectedId.flatMap { id in places.first { $0.id == id } } }

    @ViewBuilder private var overlays: some View {
        if let place = selectedPlace {
            cardOverlay(place)
        } else {
            mainOverlay
        }
    }

    /// Card do pino aberto (`MapaPino.png`): fechar + ficha técnica em cima, o card embaixo. O mapa continua vivo no meio.
    /// Com o card aberto a barra de abas some (`AppRouter.mapCardOpen`), então o card encosta embaixo.
    private func cardOverlay(_ place: Place) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                V8CornerButton(systemName: "xmark", label: "Fechar", filled: false) { closeCard() }
                    .background(Circle().fill(V8.paper.opacity(0.92)))
                Spacer(minLength: 12)
                V8SpecStack(lines: MapCardFacts.spec(area: areaName, pin: pinPosition(place), list: place.list?.name),
                            color: V8.ink, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(V8.paper.opacity(0.88)))
                    .padding(.top, 12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer(minLength: 0)
            MapPlaceCard(place: place, region: region, now: now, here: here, walkMaxKm: walkMaxKm,
                         goMinutes: legFromHere(to: place)?.minutes, nearby: nearbyCache,
                         onClose: closeCard,
                         onOpen: { router.push(.place(id: place.id)) },
                         onGo: { router.push(.ir(placeId: place.id)) },
                         onDone: { router.sheet = .expense(placeId: place.id) })
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// "pino 2 de 9 · hoje" (parada de hoje/amanhã); `nil` pra quem não está num dia.
    private func pinPosition(_ place: Place) -> (number: Int, total: Int, day: String)? {
        if let i = stops.firstIndex(where: { $0.place?.id == place.id }) { return (i + 1, stops.count, "hoje") }
        if let i = tomorrowStops.firstIndex(where: { $0.place?.id == place.id }) { return (i + 1, tomorrowStops.count, "amanhã") }
        return nil
    }

    private var mainOverlay: some View {
        let near = nearby
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    MapSearchField(text: $search.text, placeholder: searchPlaceholder(near), listening: speech.isListening,
                                   active: search.isActive, focused: $searchFocused,
                                   onSubmit: submitSearch, onMic: { Task { await speech.toggle() } }, onClear: clearSearch)
                }
                .padding(.horizontal, 20)
                if search.isActive { MapIntentChips(chips: search.chips, onTap: tapChip) }
                MapMustPills(total: mustCounts.total, counts: mustCounts.lists, filter: mustFilter,
                             onAll: { mustFilter.showAll() }, onToggle: { mustFilter.toggle($0) })
                if !search.isActive {
                    legend
                    if let far = farTarget { farNotice(far.place, target: far.target).padding(.horizontal, 22) }
                    OfflineMapNudge(here: here?.coordinate, region: region).padding(.horizontal, 22)
                }
            }
            .padding(.top, 8)

            Spacer()

            if !search.isActive {
                HStack(alignment: .bottom) {
                    ScaleBar(metersPerPoint: camera?.metersPerPoint)
                    Spacer()
                    VStack(spacing: 10) {
                        roundButton(label: "Centralizar em mim") {
                            MustIconView(.voceGps, size: 20).foregroundStyle(Color.must.ink)
                        } action: { selectedId = nil; cam.resumeAuto(here: here, candidates: candidates, fallback: fallbackCenter) }
                        roundButton(label: "Escala de bairro") {
                            Text("300").font(.must.mono(13, .semibold)).foregroundStyle(Color.must.ink)
                        } action: { selectedId = nil; cam.forceNeighborhood(here?.coordinate ?? fallbackCenter) }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 10)
            }

            Group {
                if search.isActive { resultsCard.padding(.horizontal, 12) } else { sheet(near).padding(.horizontal, 22) }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("© OpenStreetMap · Protomaps")
                    .font(.must.archivo(9))
                    .foregroundStyle(Color.must.secondary.opacity(0.9))
                    .padding(.trailing, 26)
                    .offset(y: 14)
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: Filtro por Must

    private var mustCounts: (total: Int, lists: [MapMustFilter.Count]) {
        MapMustFilter.counts(listIdsOfPlaces: places.map { $0.list?.id }, lists: lists.map { ($0.id, $0.name) })
    }

    private func loadFilter(_ region: Region) {
        mustFilter = MapMustFilter.load(region)
        filterRegion = region
    }

    // MARK: Busca

    private func searchPlaceholder(_ near: [Near]) -> String {
        let open = near.filter { isOpen($0.place) }.count
        let summary = near.isEmpty ? "nada a 500 m" : "\(near.count) \(near.count == 1 ? "must" : "musts") a 500 m · \(open) \(open == 1 ? "aberto" : "abertos")"
        return "\(areaName) · \(summary)"
    }

    private var resultsCard: some View {
        let chosen = search.chosen
        let slot = chosen.flatMap { search.rows[$0.id]?.slot }
        let emptyText = search.output?.offline == true
            ? "Nada aberto no seu board por aqui. Sem internet: a busca no Google volta quando a rede voltar."
            : "Nada aberto até \(MapSearchModel.km(search.output?.radiusKm ?? MapSearch.fallbackRadiusKm)). Tente o Quero… ou outro raio."
        return MapResultsCard(title: search.title, countLine: search.countLine, items: search.top, chosenId: chosen?.id,
                              searching: search.phase == .searching, emptyText: failure ?? emptyText, locale: region.locale,
                              encaixarTitle: slot.map { "Encaixar \(region.timeString($0.start))" } ?? (chosen == nil ? "Encaixar" : "Não cabe hoje"),
                              canEncaixar: slot != nil,
                              onChoose: chooseResult,
                              onQuero: { router.openQuero(text: search.text) },
                              onEncaixar: encaixar)
    }

    private func searchEnv() -> MapSearchEnv {
        let quero = queroEnv()
        let tz = region.timeZone
        let byId = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let board = quero.board.map { b -> MapBoardEntry in
            let p = byId[b.id]
            let open: Bool? = switch p?.openState(at: now, timeZone: tz) {
            case .open: true
            case .closed: false
            default: nil
            }
            return MapBoardEntry(place: b, openNow: open, priceLevel: p?.priceLevel, queueMinutes: p?.queueMinutes)
        }
        return MapSearchEnv(region: region, center: quero.origin, cityGroup: quero.cityGroup,
                            online: services.connectivity.status != .offline, board: board,
                            useModel: settingsList.first?.onDeviceAI ?? true, quero: quero, enterprise: PlacesEnterpriseFlag.isOn())
    }

    /// O mesmo ambiente do Quero… (o "Encaixar hoje" do mapa e o de lá são a mesma conta).
    private func queroEnv() -> QueroEnv {
        let trip = trips.first
        let city = trip?.city(on: now, calendar: region.calendar)
        let cityCenter = city.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) } ?? region.defaultCenter
        let gps = here?.coordinate
        let origin = gps.flatMap { DaySolver.streetKm($0, cityCenter) < 60 ? $0 : nil } ?? cityCenter
        let cityId = city?.id ?? trip?.cities.first?.id ?? region.rawValue
        let group = AreaCatalog.cityGroup(forCityId: cityId)
        let today = region.calendar.startOfDay(for: now)
        return QueroEnv(region: region, now: now, plan: engine.plan(for: today, region: region, context: context), center: origin,
                        origin: origin, areaName: areaName, cityGroup: group, cityId: cityId,
                        online: services.connectivity.status != .offline,
                        board: QueroEnv.board(places, cityGroup: group, now: now, timeZone: region.timeZone),
                        useModel: settingsList.first?.onDeviceAI ?? true, walkMaxKm: walkMaxKm)
    }

    /// Enter/buscar (nunca a cada tecla). Nome de um lugar do board abre o card dele (como a busca fazia); o resto é
    /// "o melhor X perto de mim agora".
    private func submitSearch() {
        let typed = search.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        searchFocused = false
        failure = nil
        if let hit = Self.boardNameHit(typed, in: places) {
            search.clear()
            open(hit.id, show: true)
            return
        }
        selectedId = nil
        search.submit(searchEnv())
        Task { nearbyCache = await MapRatings.nearbyBatch(lat: fallbackCenter.latitude, lng: fallbackCenter.longitude, region: region) }
    }

    /// O nome de um lugar do board ("Inimá", "Fuunji"): igual, ou contido — desde que o texto não seja uma vontade
    /// conhecida ("ramen", "pão de queijo" vão pra busca, mesmo havendo um "Ramen Nagi" no board).
    static func boardNameHit(_ text: String, in places: [Place]) -> Place? {
        let q = WantCategory.fold(text)
        guard q.count >= 3 else { return nil }
        if let exact = places.first(where: { WantCategory.fold($0.name) == q }) { return exact }
        guard WantCategory.match(text) == nil, WantParser.parseLocal(text)?.quality == .qualquer,
              q.split(separator: " ").count <= 3 else { return nil }
        return places.first { WantCategory.fold($0.name).contains(q) }
    }

    private func clearSearch() {
        speech.cancel()
        search.clear()
        searchFocused = false
        failure = nil
        reevaluate(force: true)
    }

    private func tapChip(_ id: String) {
        let env = searchEnv()
        switch id {
        case "object": searchFocused = true
        case "open": search.toggleOpen(env)
        case "quality": search.cycleQuality(env)
        case "radius": search.cycleRadius(env)
        default: break
        }
    }

    private func chooseResult(_ c: MapSearchCandidate) {
        if search.chosenId == c.id, let board = c.result.boardPlaceId {
            open(board, show: false)
            return
        }
        search.chosenId = c.id
    }

    /// Você + os 3 entre a busca e o card (a câmera não fica no meio do nada).
    private func fitResults() {
        let points = search.top.map(\.result.coordinate) + [here?.coordinate].compactMap { $0 }
        guard !search.top.isEmpty else { return }
        cam.fit(points, top: Self.resultsTop, bottom: 470)
    }

    /// Encaixar hoje (a mesma conta do Quero…): grava o lugar (o do board ou um novo na lista da vontade) e a parada.
    private func encaixar() {
        guard let chosen = search.chosen, let row = search.rows[chosen.id], row.slot != nil else { return }
        let env = queroEnv()
        guard let place = QueroSave.place(for: row, intent: search.intent, text: search.text, lists: lists, cityId: env.cityId,
                                          region: region, sync: services.sync, context: context) else { return }
        do {
            _ = try QueroSave.encaixar(row, place: place, env: env, context: context)
            search.clear()
            router.push(.linha(date: region.calendar.startOfDay(for: now)), on: .hoje)
        } catch {
            failure = "não deu pra gravar o dia: \(error.localizedDescription)"
        }
    }

    /// "Nada a menos de 500 m. Abri o mapa até o mais perto: **Inimá de Paula**, parada 3 de hoje."
    private func farNotice(_ place: Place, target: MapFocus.Target) -> some View {
        let index = stops.firstIndex { $0.place?.id == place.id }
        let tail = index.map { ", parada \($0 + 1) de hoje." } ?? (place.list.map { ", \($0.displayName)." } ?? ".")
        let name = Text(Self.withoutGeneric(place.name)).font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
        return HStack(alignment: .center, spacing: 12) {
            MustIconView(.buscar, size: 16).foregroundStyle(Color.must.ink)
                .frame(width: 38, height: 38).background(Circle().fill(Color.must.surface))
            Text("Nada a menos de 500 m. Abri o mapa até o mais perto: \(name)\(tail)")
                .font(.must.serif(16.5)).foregroundStyle(Color.must.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(cornerRadius: 26)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// "Museu Inimá de Paula" → "Inimá de Paula".
    static func withoutGeneric(_ name: String) -> String {
        let words = name.split(separator: " ").map(String.init)
        guard words.count >= 3, shortName(name) != name else { return name }
        return words.dropFirst().joined(separator: " ")
    }

    private var legend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MapLayer.legend) { layer in
                    Button { toggle(layer) } label: { chip(layer) }
                        .buttonStyle(MustPressStyle())
                        .accessibilityAddTraits(layers.contains(layer) ? .isSelected : [])
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ layer: MapLayer) -> some View {
        let on = layers.contains(layer)
        return HStack(spacing: 7) {
            switch layer {
            case .today:
                Text("\(stops.filter { !$0.done }.count)").font(.must.mono(10, .semibold)).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Circle().fill(Color.must.ink))
            case .tomorrow:
                Circle().strokeBorder(Color.must.blue, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])).frame(width: 16, height: 16)
            case .unplanned:
                Text("E").font(.must.mono(12, .bold)).foregroundStyle(Color.must.ink)
            case .done:
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.must.ink)
            case .metro:
                Capsule().fill(transit.lines.first?.color ?? Color.must.blue).frame(width: 14, height: 4)
            case .search:
                MustIconView(.buscar, size: 12).foregroundStyle(Color.must.ink)
            }
            Text(layer.label).font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Capsule().fill(Color.white.opacity(on ? 0.96 : 0.6)))
        .overlay(Capsule().strokeBorder(Color.must.line))
        .shadow(color: Color(hex: 0x121316, opacity: on ? 0.08 : 0), radius: 8, y: 4)
        .opacity(on ? 1 : 0.45)
    }

    private func roundButton<Label: View>(label: String, @ViewBuilder content: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .frame(width: 52, height: 52)
                .background(Circle().fill(.white))
                .overlay(Circle().strokeBorder(Color.must.line))
                .shadow(color: Color(hex: 0x121316, opacity: 0.12), radius: 8, y: 4)
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel(label)
    }

    // MARK: Sheet

    @ViewBuilder private func sheet(_ near: [Near]) -> some View {
        // O pino tocado abre o `MapPlaceCard` (por cima de tudo, em `overlays`); aqui fica o "mais perto" e o "Perto de você".
        if let far = farTarget {
            let index = stops.firstIndex { $0.place?.id == far.place.id }
            PlaceSheetCard(place: far.place, number: index.map { $0 + 1 }, stop: index.map { stops[$0] },
                           leg: legFromHere(to: far.place, walkUnderKm: 1.2), region: region, now: now,
                           distance: far.target.meters,
                           walkMinutes: walkMinutes(to: far.place),
                           onClose: { cam.forceNeighborhood(here?.coordinate ?? fallbackCenter) },
                           onOpen: { router.push(.place(id: far.place.id)) },
                           onDay: { router.select(.hoje) })
        } else if !near.isEmpty || nextStop != nil {
            VStack(alignment: .leading, spacing: 0) {
                if !near.isEmpty {
                    HStack {
                        Micro("perto de você · 500 m")
                        Spacer()
                        let open = near.filter { isOpen($0.place) }.count
                        Text("\(open) \(open == 1 ? "aberto" : "abertos")").font(.must.archivo(13)).foregroundStyle(Color.must.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(near.prefix(3)) { item in
                                Button { selectedId = item.place.id } label: { miniCard(item) }.buttonStyle(MustPressStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                    .padding(.top, 12)
                    .padding(.bottom, nextStop == nil ? 16 : 0)
                }
                if let stop = nextStop, let place = stop.place {
                    if !near.isEmpty { RowDivider().padding(.horizontal, 20).padding(.top, 14) }
                    nextRow(stop: stop, place: place)
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(hex: 0x121316, opacity: 0.10), radius: 18, y: 8)
        } else {
            emptyCard
        }
    }

    private func miniCard(_ item: Near) -> some View {
        let place = item.place
        let state = place.openState(at: now, timeZone: region.timeZone)
        let color = place.list?.color ?? .eat
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(kanji(place)).font(.must.kanji(14)).foregroundStyle(color.strong)
                Text(place.name).font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
            }
            HStack(spacing: 4) {
                switch state {
                case .open: Text("aberto").font(.must.archivo(13, .semibold)).foregroundStyle(Color.must.greenText)
                case .closed(_, let opensAt): Text(opensAt.map { "abre \($0)" } ?? "fechado").font(.must.archivo(13)).foregroundStyle(Color.must.secondary)
                case .unknown: Text(place.list?.displayName ?? "").font(.must.archivo(13)).foregroundStyle(Color.must.secondary)
                }
                Text("· \(Self.meters(item.meters))").font(.must.archivo(13)).foregroundStyle(Color.must.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 150, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.must.line))
    }

    private func nextRow(stop: Stop, place: Place) -> some View {
        let number = (stops.firstIndex { $0.id == stop.id } ?? 0) + 1
        let leg = legFromHere(to: place)
        var parts: [String] = []
        if let leg { parts.append(leg.text) }
        if case .closed(.none, let opensAt?) = place.openState(at: now, timeZone: region.timeZone), let open = Settings.minutes(from: opensAt) {
            let delta = open - minutesNow
            if delta > 0 { parts.append(delta < 60 ? "abre em \(delta) min" : "abre em \(delta / 60)h\(String(format: "%02d", delta % 60))") }
        }
        let leave = leg.map { RoutesService.leaveAt(stop.at, travelMinutes: $0.minutes) }
        return Button { selectedId = place.id } label: {
            HStack(spacing: 14) {
                Text("\(number)").font(.must.mono(15, .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(Circle().fill(Color.must.ink))
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name).font(.must.archivo(19, .semibold)).tracking(-0.2).foregroundStyle(Color.must.ink).lineLimit(1)
                    (Text(region.timeString(stop.at)).font(.must.mono(14, .semibold)).foregroundStyle(Color.must.ink)
                        + Text(parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")))
                        .font(.must.archivo(14)).foregroundStyle(Color.must.secondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                if let leave, leave > now {
                    Text("saia \(region.timeString(leave))").font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.greenText)
                        .padding(.horizontal, 14).frame(height: 38).background(Capsule().fill(Color.must.green))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(accepted(0) == nil ? "Nenhum dia montado hoje" : "Dia feito").mustPlace()
                Text(accepted(0) == nil ? "monte o dia pra ver a rota e as paradas no mapa" : "todas as paradas de hoje estão feitas").mustMeta()
            }
            if accepted(0) == nil {
                PrimaryButton("Montar o dia", icon: .montarAjustar, style: .dark) {
                    router.push(.montar(date: region.calendar.startOfDay(for: now)), on: .hoje)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color(hex: 0x121316, opacity: 0.10), radius: 18, y: 8)
    }

    static func meters(_ m: CLLocationDistance) -> String {
        m < 1000 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Ações

    private func appear() {
        consumeOpenNow()
        requestRoutes()
        guard !didCenter else { reevaluate(force: true); return }
        didCenter = true
        #if DEBUG
        let debugWidth = DebugFlags.double("debugMapWidth") // -debugMapWidth 450 (prints)
        if debugWidth > 0 { cam.show(fallbackCenter, widthMeters: debugWidth, animated: false); return }
        #endif
        reevaluate(force: true, animated: false)
    }

    private func centerOnMe() {
        selectedId = nil
        cam.resumeAuto(here: here, candidates: candidates, fallback: fallbackCenter)
    }

    private func consumeOpenNow() {
        guard router.mapShowsOpenNow else { return }
        router.mapShowsOpenNow = false
        layers.insert(.unplanned)
        centerOnMe()
    }

    private func requestRoutes() {
        routes.request(stops: stops.compactMap(\.place), walkMaxKm: walkMaxKm)
        routes.request(stops: tomorrowStops.compactMap(\.place), walkMaxKm: walkMaxKm)
    }

    private func toggle(_ layer: MapLayer) {
        if layers.contains(layer) { layers.remove(layer) } else { layers.insert(layer) }
    }

    private func select(_ pin: MapPin) {
        searchFocused = false
        if pin.id.hasPrefix("result-") {
            let id = String(pin.id.dropFirst("result-".count))
            if let c = search.top.first(where: { $0.id == id }) { chooseResult(c) }
            return
        }
        guard let id = pin.placeId else { return }
        if selectedId == id { router.push(.place(id: id)) } else { open(id, show: false) }
    }

    /// Abre o card do pino. A câmera não pula: só desliza o pino pra cima do card (`show`: centra, vindo da busca por nome).
    private func open(_ id: String, show: Bool) {
        guard let place = places.first(where: { $0.id == id }) else { return }
        withAnimation(.spring(duration: 0.32)) { selectedId = id }
        guard show else { cam.reveal(place.coordinate, top: Self.cardTop, bottom: Self.cardBottom); return }
        cam.show(place.coordinate)
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            guard selectedId == id else { return }
            cam.reveal(place.coordinate, top: Self.cardTop, bottom: Self.cardBottom)
        }
    }

    private func closeCard() {
        withAnimation(.spring(duration: 0.3)) { selectedId = nil }
    }

    /// Toque no mapa fora dos pinos: fecha o card (e o teclado).
    private func tapEmpty() {
        searchFocused = false
        if selectedId != nil { closeCard() }
    }

    // MARK: Prints (`-debugScreen mapa-pino` / `mapa-filtro`)

    /// `mapa-pino[:<id>]` abre o card (a próxima parada de hoje, senão o lugar mais perto); `mapa-filtro[:texto]` roda a
    /// busca "o melhor … perto de mim agora" (lámen no Japão, pão de queijo em BH).
    private func debugScreen() async {
        #if DEBUG
        guard let raw = DebugFlags.string("debugScreen"), raw.hasPrefix("mapa-") else { return }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : nil
        try? await Task.sleep(for: .milliseconds(700))
        switch parts[0] {
        case "mapa-pino":
            let target = arg.flatMap { id in places.first { $0.id == id } }
                ?? nextStop?.place ?? stops.first?.place
                ?? here.flatMap { h in unplannedPlaces.min { $0.location.distance(from: h) < $1.location.distance(from: h) } }
            if let target { open(target.id, show: false) }
        case "mapa-filtro":
            search.text = arg ?? (region.profile.day?.mapSearchExample ?? "o melhor café perto de mim, agora")
            submitSearch()
        default: break
        }
        #endif
    }
}

// MARK: - Card do lugar (pino tocado / mais perto)

struct PlaceSheetCard: View {
    var place: Place
    var number: Int?
    var stop: Stop?
    var leg: (minutes: Int, text: String, mode: LegMode)?
    var region: Region
    var now: Date
    var distance: CLLocationDistance?
    var walkMinutes: Int?
    var onClose: () -> Void
    var onOpen: () -> Void
    var onDay: () -> Void

    var body: some View {
        let at = stop?.at ?? (place.hasReservation(on: now, calendar: region.calendar) ? place.reservation?.at : nil)
        let leave = at.flatMap { at in leg.map { RoutesService.leaveAt(at, travelMinutes: $0.minutes) } }
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                // Foto principal do lugar (prompt 19): miniatura de 40 pt, cantos 14.
                PlaceThumb(placeId: place.placeId, refs: place.photoRefs, color: place.list?.color ?? .eat, size: 40, opensViewer: true)
                if let number {
                    Text("\(number)").font(.must.mono(15, .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44).background(Circle().fill(stop?.done == true ? Color.must.green : Color.must.ink))
                } else {
                    Text(String((place.list?.name ?? "•").prefix(1)).uppercased()).font(.must.mono(15, .bold))
                        .foregroundStyle((place.list?.color ?? .eat).text)
                        .frame(width: 44, height: 44).background(Circle().fill((place.list?.color ?? .eat).light))
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(place.name).font(.must.archivo(19, .semibold)).tracking(-0.2).foregroundStyle(Color.must.ink).lineLimit(1)
                    }
                    meta(at: at).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                if let leave, leave > now {
                    Text("saia \(region.timeString(leave))").font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.greenText)
                        .padding(.horizontal, 14).frame(height: 38).background(Capsule().fill(Color.must.green))
                } else {
                    Button(action: onClose) {
                        MustIconView(.fechar, size: 14).foregroundStyle(Color.must.secondary).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Fechar")
                }
            }
            HStack(spacing: 10) {
                Button { MapsLinks.openApple(to: place.coordinate, name: place.name, mode: leg?.mode == .walk ? .walking : .transit) } label: {
                    Text("Apple Maps").sheetButton()
                }
                Button { MapsLinks.openGoogle(to: place.coordinate, mode: leg?.mode == .walk ? .walking : .transit) } label: {
                    Text("Google Maps").sheetButton()
                }
                Button(action: number != nil ? onDay : onOpen) {
                    Text(number != nil ? "Ver o dia" : "Abrir").font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Capsule().fill(Color.must.surface))
                }
            }
            .buttonStyle(MustPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color(hex: 0x121316, opacity: 0.10), radius: 18, y: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private func meta(at: Date?) -> Text {
        var pieces: [Text] = []
        if let distance {
            pieces.append(Text(MapView.meters(distance)).font(.must.mono(15, .semibold)).foregroundStyle(Color.must.ink))
        }
        if let leg { pieces.append(Text(leg.text)) }
        if let walkMinutes, leg?.mode == .metro { pieces.append(Text("\(walkMinutes) a pé")) }
        if let at { pieces.append(Text(region.timeString(at)).font(.must.mono(15, .semibold)).foregroundStyle(Color.must.ink)) }
        if pieces.isEmpty, let list = place.list { pieces.append(Text(list.displayName)) }
        var out = Text("")
        for (i, p) in pieces.enumerated() { out = i == 0 ? p : Text("\(out) · \(p)") }
        return out.font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
    }
}

private extension Text {
    func sheetButton() -> some View {
        font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink)
            .frame(maxWidth: .infinity).frame(height: 50)
            .overlay(Capsule().strokeBorder(Color.must.lineStrong))
    }
}

// MARK: - Escala

/// Escala no canto: escolhe 300 m (ou o valor redondo mais perto) pro zoom atual.
struct ScaleBar: View {
    var metersPerPoint: Double?

    private static let steps: [Double] = [50, 100, 200, 300, 500, 1000, 2000, 5000, 10_000, 20_000]

    var body: some View {
        if let mpp = metersPerPoint, mpp > 0 {
            let meters = Self.steps.min { abs($0 / mpp - 125) < abs($1 / mpp - 125) } ?? 300
            let width = min(140, max(24, meters / mpp))
            VStack(alignment: .leading, spacing: 2) {
                Text(meters >= 1000 ? "\(Int(meters / 1000)) km" : "\(Int(meters)) m")
                    .font(.must.mono(10, .semibold))
                    .foregroundStyle(Color.must.ink)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: 6))
                    p.addLine(to: CGPoint(x: width, y: 6)); p.addLine(to: CGPoint(x: width, y: 0))
                }
                .stroke(Color.must.ink, lineWidth: 1.4)
                .frame(width: width, height: 6)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.75)))
            .accessibilityLabel("Escala: \(Int(meters)) metros")
        }
    }
}
