import CoreLocation
import SwiftData
import SwiftUI

/// Explorar (prompt 31 · 8, `design/v9/ExplorarB-*.png`): cada bairro é uma página. Bloco da foto (já no disco; sem ela, a cor do
/// lugar com a trama), recorte do mapa (snapshot em cache), trilho de estações na borda direita (ordem por tempo de trem),
/// régua "↓ quero em <bairro>" e o índice duro. Toque no recorte abre o mapa vivo (`ExplorarMapOpen`). Substitui a aba Mapa e o
/// Guia do bairro; o mapa completo (busca, packs offline, Em cartaz) continua na rota `.mapa`.
struct ExplorarView: View {
    var initialArea: String? = nil
    var showsBack = false

    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Environment(\.tripTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var type
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var model = ExplorarModel()
    @State private var corte = CorteState()
    @State private var openIndex = OpenNowIndex()
    @State private var photo: URL?
    @State private var snapshot: UIImage?
    @State private var outside: [NearbyPlace] = []
    @State private var mapOpen = false
    @State private var railPreview: Int?
    @State private var railActive = false
    @State private var booted = false
    @State private var showsPhotoOverride = true

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var debugScreen: String { DebugFlags.string("debugScreen") ?? "" }
    private var online: Bool { services.connectivity.status != .offline }

    var body: some View {
        ZStack(alignment: .topLeading) {
            V8.paper.ignoresSafeArea()
            page
            if railActive, let preview = railPreview { railPanel(preview) }
            if mapOpen, let area = model.area {
                ExplorarMapOpen(model: model, area: area, region: region, photoURL: photo, quero: { openQuero() }, onClose: { close() },
                                makeEnv: { queroEnv(area) }, onFit: { fitToday($0, slot: $1, area: area) }, onSave: { saveToBoard($0, area: area) })
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
            }
            if corte.stage != .rest, let area = model.area {
                CorteQueroOverlay(state: corte, photo: photo, subject: area.name, originName: area.name,
                                  makeEnv: { queroEnv(area) }, actions: queroActions(area))
                    .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .id(region)
        .task(id: refreshKey) { await refresh() }
        .task(id: model.areaId) { await loadVisuals() }
        .task(id: "\(mapOpen)|\(model.areaId ?? "-")|\(online)") { await loadOutsideLive() }
        .onChange(of: corte.stage) { _, stage in router.setQuero("explorar", open: stage != .rest) }
        .onChange(of: corte.quero.phase) { _, _ in corte.resultArrived() }
        .onDisappear { router.setQuero("explorar", open: false) }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.25), value: mapOpen)
        .sensoryFeedback(.selection, trigger: railPreview)
    }

    // MARK: Dados

    /// O que, se mudar, refaz o modelo: região, minuto, os Musts, a posição (célula de ~50 m) e o bairro inicial.
    private var refreshKey: String {
        let cell = services.location.current.map { "\(Int(($0.coordinate.latitude * 2000).rounded())),\(Int(($0.coordinate.longitude * 2000).rounded()))" } ?? "-"
        return "\(region.rawValue)|\(Int(now.timeIntervalSinceReferenceDate / 60))|\(PlacesRevision.of(places))|\(cell)|\(online)"
    }

    private func inputs(snapshotOf plan: DayPlan?) -> ExplorarModel.Inputs {
        let today = region.calendar.startOfDay(for: now)
        let areas = AreaCatalog.areas(for: region)
        let snapshot = openIndex.snapshot(for: places, now: now, timeZone: region.timeZone, location: services.location.current)
        var cities: [(group: String, name: String)] = []
        for city in trips.first?.cities ?? [] {
            let group = AreaCatalog.cityGroup(forCityId: city.id)
            if !cities.contains(where: { $0.group == group }) { cities.append((group, Self.cityName(city.name, group: group))) }
        }
        return ExplorarModel.Inputs(
            region: region, now: now, places: places, gps: services.location.current?.coordinate, plan: plan,
            upcoming: QueroEnv.upcomingDays(context: context, areas: areas, today: today), cities: cities, outside: outside,
            openIds: Set(places.filter { snapshot.isOpen($0.id) }.map(\.id)), distances: snapshot.distances)
    }

    /// "Tokyo 2" → "Tóquio"; o resto como está.
    static func cityName(_ name: String, group: String) -> String {
        if group == "tokyo" { return "Tóquio" }
        if group == "kyoto" { return "Kyoto" }
        return name.replacingOccurrences(of: #"\s+\d+$"#, with: "", options: .regularExpression)
    }

    private func refresh() async {
        let today = region.calendar.startOfDay(for: now)
        let plan = dayEngine.plan(for: today, region: region, context: context)
        model.refresh(inputs(snapshotOf: plan))
        if !booted {
            booted = true
            applyBoot()
        }
    }

    /// Entrada pela rota (`.guia`) ou pelos prints (`-debugScreen explorar-…`).
    private func applyBoot() {
        if let initialArea { model.select(area: initialArea) }
        switch debugScreen {
        case "explorar-kyoto": model.select(city: "kyoto")
        case "explorar-sem-foto":
            showsPhotoOverride = false
            model.select(area: "nakano")
        case "explorar-trilho":
            railActive = true
            railPreview = min(2, max(model.count - 1, 0))
        case "explorar-recorte", "explorar-recorte-pino", "explorar-recorte-fora":
            // `-debugExplorarArea naka-meguro`: onde as fontes de mentira do Por perto têm lugares de fora (UI tests).
            model.select(area: DebugFlags.string("debugExplorarArea") ?? "nakano")
            mapOpen = true
        default: break
        }
        if debugScreen == "explorar-trilho", let id = model.stations[safe: railPreview ?? 0]?.id { model.select(area: id) }
        refreshInputs()
    }

    private func refreshInputs() {
        let today = region.calendar.startOfDay(for: now)
        model.refresh(inputs(snapshotOf: dayEngine.plan(for: today, region: region, context: context)))
    }

    /// Recorte aberto: uma busca do Por perto (Google Nearby + fontes grátis) do centro do bairro, uma vez por bairro por sessão.
    /// Cache primeiro (já mostrado por `loadVisuals`); sem rede ou com Pouco Dados, só o que estava guardado.
    private func loadOutsideLive() async {
        guard mapOpen, let area = model.area else { return }
        let decision = model.outsideDecision(area: area.id, region: region, status: services.connectivity.status)
        guard decision == .fetch else { return }
        let batch = await services.nearby.load(lat: area.centroid.lat, lng: area.centroid.lng, region: region)
        model.outsideFinished()
        let fresh = batch.places.filter { !$0.sources.contains(.board) }
        if fresh != outside {
            outside = fresh
            refreshInputs()
        }
    }

    /// Foto do bairro (só o que já está no disco), snapshot do mapa e o "fora do board" do cache do Por perto.
    private func loadVisuals() async {
        guard let area = model.area else { return }
        // Fora do board: o cache do Por perto na célula do centro do bairro (nunca chama fonte).
        let batch = await services.nearby.cached(lat: area.centroid.lat, lng: area.centroid.lng, region: region)
        let fresh = batch?.places.filter { !$0.sources.contains(.board) } ?? []
        if fresh != outside {
            outside = fresh
            refreshInputs()
        }
        if showsPhotoOverride, !DebugFlags.bool("debugNoPhotos"), let (_, candidates) = CapaState.areaCandidates(region: region, areaId: area.id, places: places) {
            let found = await CapaState.diskPhoto(region: region, areaId: area.id, candidates: candidates)
            photo = found.flatMap { URL(string: $0.largeURL ?? $0.url) }
        } else {
            photo = nil
        }
        snapshot = nil
        let image = await ExplorarSnapshot.image(region: region, area: area, online: online)
        if model.area?.id == area.id { snapshot = image }
    }

    // MARK: Página

    private var page: some View {
        ScrollView {
            VStack(spacing: 0) {
                band
                rule
                paper
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) { BottomFade(color: V8.paper, height: 70).allowsHitTesting(false) }
    }

    private func swipe(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) * 2, abs(value.translation.width) > 60,
              let id = model.areaId else { return }
        if let next = ExplorarRail.step(model.stations, from: id, by: value.translation.width < 0 ? 1 : -1) { goTo(next) }
    }

    private func goTo(_ id: String) {
        guard id != model.areaId else { return }
        model.select(area: id)
    }

    // MARK: Bloco

    private var band: some View {
        let area = model.area
        let station = model.station
        return CutBand(photo: photo, alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                topRow.padding(.top, 58)
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        recorteButton
                        recorteCaption
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 18)
                Spacer(minLength: 20)
                sealRow(area: area, station: station)
                Text(area?.name ?? region.displayName)
                    .font(V8Font.display(84, width: 80, weight: 800))
                    .tracking(-3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
        }
        .overlay(alignment: .topTrailing) {
            if !model.stations.isEmpty {
                ExplorarRailView(stations: model.stations, currentId: model.areaId, tint: Color(hex: theme.coverRGB),
                                 showsCaptions: type <= .xLarge,
                                 onPreview: { index in railChanged(index) },
                                 onCommit: { index in railCommit(index) },
                                 onEnd: { railActive = false; railPreview = nil })
                    .frame(width: type <= .xLarge ? 168 : 80)
                    .padding(.top, type <= .xLarge ? 126 : 150)
                    .padding(.trailing, 14)
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { swipe($0) })
    }

    private func railChanged(_ index: Int) {
        railActive = true
        if railPreview != index {
            railPreview = index
            if let id = model.stations[safe: index]?.id { goTo(id) }
        }
    }

    private func railCommit(_ index: Int) {
        if let id = model.stations[safe: index]?.id { goTo(id) }
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsBack {
                squareButton("chevron.left", label: "Voltar") { dismiss() }
            }
            if model.cities.count > 1 { citySegment }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if type <= .xLarge {
                    ExplorarMono("bairro \(model.index + 1) de \(model.count)", size: 10, color: V8.white)
                    ExplorarMono(model.cities.count > 1 && !model.tripStarted ? "viagem futura" : "← → próximo", size: 9, color: V8.white.opacity(0.85))
                } else {
                    ExplorarMono("\(model.index + 1)/\(model.count)", size: 10, color: V8.white)
                }
            }
            .padding(.top, 6)
            squareButton("sparkle", label: "Assistente") { router.sheet = .assistant }
        }
    }

    private var citySegment: some View {
        HStack(spacing: 0) {
            ForEach(model.cities) { city in
                let on = city.group == model.cityGroup
                Button { model.select(city: city.group) } label: {
                    Text(city.name.uppercased())
                        .font(V8Font.mono(11, weight: .bold)).tracking(1)
                        .foregroundStyle(on ? V8.ink : V8.white)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 12).frame(height: 44)
                        .background(on ? V8.white : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .overlay(Rectangle().stroke(V8.white, lineWidth: 2))
    }

    private func squareButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(V8.white)
                .frame(width: 44, height: 44)
                .overlay(Rectangle().stroke(V8.white, lineWidth: 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var recorteButton: some View {
        Button { open() } label: {
            if let area = model.area {
                ExplorarRecorte(area: area, items: model.listed, snapshot: snapshot, you: model.isHere ? model.youCoordinate : nil,
                                trail: model.trail, showsTrail: model.layers.contains(.trail))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAction(named: "Abrir mapa completo") { router.push(.mapa, on: router.tab) }
    }

    private var recorteCaption: some View {
        let c = model.counts
        return VStack(alignment: .leading, spacing: 2) {
            ExplorarMono("mapa · toque pra abrir", size: 10, color: V8.white)
            ExplorarMono("\(c.open) \(c.open == 1 ? "aberto" : "abertos") · \(c.own) musts", size: 10, color: V8.white)
        }
        .frame(maxWidth: ExplorarSnapshot.side + 40, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sealRow(area: Area?, station: ExplorarStation?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(area?.seal ?? "")
                .font(V8Font.mono(15, weight: .bold))
                .foregroundStyle(V8.white)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 60, height: 60)
                .overlay(Rectangle().stroke(V8.white, lineWidth: 3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                ExplorarMono(sealLine1(area: area, station: station), size: 10, color: V8.white)
                if !model.lineCodes.isEmpty {
                    ExplorarMono(model.lineCodes.prefix(6).joined(separator: " · "), size: 10, color: V8.white.opacity(0.9))
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "Japão · você está aqui" / "Kyoto · dias 6 a 9" / "Japão · 5 min de trem".
    private func sealLine1(area: Area?, station: ExplorarStation?) -> String {
        let country = region.shortName
        guard let station else { return country }
        if model.isHere { return "\(country) · você está aqui" }
        if !model.tripStarted { return "\(country) · a partir do hotel" }
        switch station.mark {
        case .today(let time): return "\(country) · hoje\(time.map { " \($0)" } ?? "")"
        default: return station.minutes == 0 ? "\(country) · a partir do hotel" : "\(country) · \(station.minutes) min de trem"
        }
    }

    // MARK: Régua

    private var rule: some View {
        let name = model.area?.name.lowercased() ?? ""
        return CutRule(pullLabel: CutPull.staticLabel("↓ quero em \(name)", phase: corte.pull.phase, offset: corte.pull.offset))
            .cutPull(corte.pull, reduceMotion: reduceMotion, onOpen: { corte.open() }, onClose: { corte.close() })
            .accessibilityAction(named: "Quero em \(model.area?.name ?? "")") { corte.open() }
    }

    private func openQuero() { corte.open() }

    /// "+ dia" do pino: grava o Must (o do board ou um novo) e a parada no buraco calculado.
    private func fitToday(_ item: ExplorarItem, slot: DayFit.Slot, area: Area) -> Bool {
        let env = queroEnv(area)
        let lists = (try? context.fetch(FetchDescriptor<MustList>())) ?? []
        let row = ExplorarPinActions.row(for: item, slot: slot, areaId: area.id)
        guard let place = QueroSave.place(for: row, intent: nil, text: "", lists: lists, cityId: env.cityId, region: region,
                                          sync: services.sync, context: context),
              (try? QueroSave.encaixar(row, place: place, env: env, context: context)) != nil else { return false }
        refreshInputs()
        return true
    }

    /// "+ board" do pino de fora.
    private func saveToBoard(_ item: ExplorarItem, area: Area) -> String? {
        let env = queroEnv(area)
        let lists = (try? context.fetch(FetchDescriptor<MustList>())) ?? []
        let row = ExplorarPinActions.row(for: item, slot: nil, areaId: area.id)
        guard let place = QueroSave.place(for: row, intent: nil, text: "", lists: lists, cityId: env.cityId, region: region,
                                          sync: services.sync, context: context) else { return nil }
        // Guardado a partir da página do bairro: é desse bairro (senão o pino some da página na hora de virar seu).
        if (place.area ?? "").isEmpty {
            place.area = area.id
            try? context.save()
        }
        refreshInputs()
        return place.id
    }

    private func queroEnv(_ area: Area) -> QueroEnv {
        let all = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let today = region.calendar.startOfDay(for: now)
        let plan = dayEngine.plan(for: today, region: region, context: context)
        let base = QueroEnv.make(region: region, now: now, places: all, trip: trips.first, settings: settingsList.first, plan: plan,
                                 gps: services.location.current?.coordinate, online: online,
                                 upcoming: QueroEnv.upcomingDays(context: context, areas: AreaCatalog.areas(for: region), today: today),
                                 areaHint: area)
        return CorteState.corteEnv(base.atArea(area, places: all))
    }

    private func queroActions(_ area: Area) -> CorteResultActions {
        let lists = (try? context.fetch(FetchDescriptor<MustList>())) ?? []
        return CorteResultActions(
            openPlace: { router.push(.place(id: $0), on: router.tab) },
            route: { MapsLinks.openApple(to: $0.row.result.coordinate, name: $0.row.result.name) },
            addToBoard: { CorteSave.addToBoard($0, state: corte, env: queroEnv(area), lists: lists, services: services, context: context) },
            fitToday: { row in
                guard CorteSave.fitToday(row, state: corte, env: queroEnv(area), lists: lists, services: services, context: context) else { return }
                corte.close()
                router.push(.linha(date: region.calendar.startOfDay(for: now)), on: router.tab)
            })
    }

    // MARK: Papel

    private var otherCity: Bool {
        guard let here = model.hereAreaId ?? model.planAreaId,
              let ref = AreaCatalog.areas(for: region).first(where: { $0.id == here }) else { return false }
        return AreaCatalog.cityGroup(forCityId: ref.cityId) != model.cityGroup
    }

    private var paper: some View {
        let listed = model.listed
        let c = model.counts
        let area = model.area
        let other = otherCity
        let date = area.flatMap { model.upcomingDates[$0.id] }
        return VStack(spacing: 0) {
            if other {
                HStack {
                    MonoLabel("outra cidade · nada daqui entra hoje", size: 10, color: V8.white)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if let n = dayNumber(date) { MonoLabel("dia \(n)", size: 10, color: V8.white) }
                }
                .padding(.horizontal, 20).padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(V8.ink)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel(other ? "seus musts em \(area?.name ?? "")" : "aberto agora no bairro", size: 10, color: V8.mute)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(other ? plannedLine(date, count: c.own) : "\(c.own) Musts seus · \(c.outside) de fora · \(region.timeString(now))")
                        .font(V8Font.text(17)).foregroundStyle(V8.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("\(other ? c.own : c.open)")
                    .font(V8Font.numeral(76)).tracking(-2)
                    .foregroundStyle(V8.orangeDeep)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 3) }
            if listed.isEmpty { emptyState }
            ForEach(listed) { item in
                ExplorarRow(item: item,
                            leftOverride: other ? ("dia \(dayNumber(date) ?? 0)", item.meta.split(separator: "·").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "") : nil,
                            refs: model.photoRefs[item.id] ?? [], googleId: model.googleIds[item.id], tint: theme.coverRGB,
                            onTap: { tap(item) })
            }
            guide
            mapLink
            Color.clear.frame(height: 24)
        }
    }

    /// O que o Guia do bairro dizia: o texto do bairro e os vizinhos com o tempo de trem (tocar troca a página).
    @ViewBuilder private var guide: some View {
        if let area = model.area {
            let c = model.counts
            VStack(alignment: .leading, spacing: 14) {
                MonoLabel("sobre \(area.name)", size: 10, color: V8.mute)
                Text(GuiaBlurbs.blurb(areaId: area.id, name: area.name, musts: c.own, open: c.open))
                    .font(V8Font.text(16)).foregroundStyle(V8.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !area.neighbors.isEmpty {
                    MonoLabel("vizinhos", size: 10, color: V8.mute).padding(.top, 4)
                    CorteFlow(spacing: 8) {
                        ForEach(area.neighbors, id: \.areaId) { edge in
                            if let other = AreaCatalog.areas(for: region).first(where: { $0.id == edge.areaId }) {
                                Button { goTo(other.id) } label: {
                                    Text("\(other.name) · \(edge.minutes) min\(edge.line.map { " · \($0.code)" } ?? "")".uppercased())
                                        .font(V8Font.mono(11, weight: .semibold)).tracking(0.8).foregroundStyle(V8.ink)
                                        .padding(.horizontal, 12).padding(.vertical, 10)
                                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(other.name), \(edge.minutes) minutos\(edge.line.map { " pela \($0.name)" } ?? " a pé")")
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nada seu em \(model.area?.name ?? "") ainda.")
                .font(V8Font.display(26)).tracking(-0.6).foregroundStyle(V8.ink)
            Text("Cole um link no + ou puxe a régua: o quero acha o que tem aqui.")
                .font(V8Font.text(15)).foregroundStyle(V8.mute)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mapLink: some View {
        Button { router.push(.mapa, on: router.tab) } label: {
            HStack {
                MonoLabel("mapa completo · busca · mapas offline", size: 10, color: V8.ink)
                Spacer(minLength: 8)
                Text("→").font(V8Font.mono(14, weight: .bold)).foregroundStyle(V8.ink)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mapa completo, busca e mapas offline")
    }

    private func dayNumber(_ date: Date?) -> Int? {
        guard let date, let start = trips.first?.start else { return nil }
        let days = region.calendar.dateComponents([.day], from: region.calendar.startOfDay(for: start), to: region.calendar.startOfDay(for: date)).day ?? 0
        return days + 1
    }

    private func plannedLine(_ date: Date?, count: Int) -> String {
        guard let date else { return "\(count) \(count == 1 ? "Must" : "Musts") · sem dia montado" }
        let f = DateFormatter()
        f.locale = region.locale
        f.timeZone = region.timeZone
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        let n = dayNumber(date).map { "dia \($0) · " } ?? ""
        return "planejado pro \(n)\(f.string(from: date))"
    }

    private func tap(_ item: ExplorarItem) {
        if let id = item.placeId {
            router.push(.place(id: id), on: router.tab)
        } else {
            MapsLinks.openApple(to: item.coordinate, name: item.name)
        }
    }

    // MARK: Recorte aberto

    private func open() { withAnimation { mapOpen = true } }
    private func close() { withAnimation { mapOpen = false } }

    // MARK: Painel do trilho (B-2)

    private func railPanel(_ preview: Int) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            let selected = model.stations[safe: preview]?.id
            ExplorarRailPanel(stations: model.stations, selectedId: selected, cityName: model.cities.first { $0.group == model.cityGroup }?.name ?? "",
                              rows: ExplorarRailPanel.window(model.stations, around: selected))
                .padding(.bottom, 12)
        }
        .ignoresSafeArea(edges: .top)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

extension QueroEnv {
    /// O quero aberto no bairro da página: a busca sai do **centro do bairro** (não do GPS), e o board é o da cidade dele.
    @MainActor
    func atArea(_ area: Area, places: [Place]) -> QueroEnv {
        var e = self
        let point = area.centroid.clCoordinate
        e.origin = point
        e.center = point
        e.areaName = area.name
        e.originBasis = .area
        e.cityGroup = AreaCatalog.cityGroup(forCityId: area.cityId)
        e.cityId = area.cityId
        e.board = QueroEnv.board(places, cityGroup: e.cityGroup, now: now, timeZone: region.timeZone)
        e.boardAnyDistance = true
        return e
    }
}
