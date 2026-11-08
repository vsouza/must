import CoreLocation
import SwiftData
import SwiftUI

/// 11 · Lista (prompt 23 §2, `Lista.png`): uma lista agrupada **por bairro** ("Shinjuku · 6 · você está aqui"), com
/// índice, estado à direita (agora / aberto / abre 17h / fechado / feito / reserva) e distância. Miniatura só do disco
/// e só em lista curta; lista longa (ou "Sem foto" nos Musts) vira só índice. Também o filtro "Fica pro fim".
struct ListView: View {
    var saveForEndOnly = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.showEvents) private var showEvents
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context

    @Query(sort: \MustList.order) private var lists: [MustList]
    /// Só os "fica pro fim" (o resto vem de `list.places`): antes era o board inteiro, ordenado, a cada redesenho (rodada 23 · G).
    @Query(filter: #Predicate<Place> { $0.saveForEnd }, sort: \Place.name) private var saveForEndPlaces: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var listId: String?
    @State private var sub: String?
    @State private var nearSort = true
    @State private var openOnly = false
    @State private var cheapOnly = false
    @AppStorage(MustsPrefs.noPhotosKey) private var noPhotos = false
    @State private var carousel: PhotoCarousel?
    /// O corte (prompt 30): a régua "↓ quero <lista>" abre o quero já filtrado pela lista.
    @State private var corte = CorteState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Abertos e distâncias: recalculados só quando muda o minuto, a posição (≥ 50 m), o conjunto ou os filtros (A.3).
    @State private var openNow = OpenNowIndex()

    /// Acima disso a lista perde as miniaturas (economia de dado e de atenção).
    static let photoLimit = 30

    init(listId: String?, initialSub: String?, saveForEndOnly: Bool = false) {
        self.saveForEndOnly = saveForEndOnly
        _listId = State(initialValue: listId)
        _sub = State(initialValue: initialSub)
    }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var list: MustList? { lists.first { $0.id == listId } }

    private var basePlaces: [Place] {
        if saveForEndOnly { return saveForEndPlaces }
        guard let list else { return [] }
        return list.places.filter { sub == nil || $0.sub == sub }
    }

    var body: some View {
        let location = services.location.current
        // Uma leitura da relação por redesenho (antes `basePlaces` era recalculado seis vezes no mesmo `body`).
        let base = basePlaces
        let snapshot = openNow.snapshot(for: base, now: now, timeZone: region.timeZone, location: location)
        let cheapLimit = (settingsList.first?.perDayBudget ?? region.defaultBudget) * 0.35
        let visible = base.filter { place in
            if openOnly && !snapshot.isOpen(place.id) { return false }
            if cheapOnly, (place.price ?? 0) > cheapLimit { return false }
            return true
        }
        let currentPlaceId = currentStopPlaceId()
        let groups = ListGrouping.groups(places: visible, region: region, location: location, nearSort: nearSort, pinned: currentPlaceId,
                                         distance: { snapshot.distance($0) }, isOpen: { snapshot.isOpen($0) })
        let openCount = base.filter { snapshot.isOpen($0.id) }.count
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                cutBlock(count: base.count)
                CutPullSlit(progress: corte.pull.progress)
                    .frame(height: CutFrame.heights(pull: corte.pull.offset, rest: 0).slit)
                pullRule
                paperHeader(count: base.count, open: openCount)
                if !saveForEndOnly { filters.padding(.top, 16).padding(.bottom, 14) }
                ForEach(groups) { group in
                    groupHeader(group)
                    ForEach(group.places, id: \.id) { place in
                        Button { router.push(.place(id: place.id), on: router.tab) } label: {
                            ListIndexRow(distance: snapshot.distance(place.id), reservation: reservationTime(place), title: place.name,
                                         meta: ListGrouping.meta(place, region: region),
                                         state: state(place, openState: snapshot.states[place.id], currentPlaceId: currentPlaceId))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Editar") { router.sheet = .editPlace(id: place.id) }
                        }
                    }
                }
                if !saveForEndOnly { addRow(empty: visible.isEmpty).padding(.horizontal, 20).padding(.top, 14) }
                V8BarSpacer()
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(V8.paper.ignoresSafeArea())
        .overlay { queroLayer }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: corte.stage) { _, stage in router.setQuero("lista", open: stage != .rest) }
        .onAppear { router.setQuero("lista", open: corte.stage != .rest) }
        .onDisappear { router.setQuero("lista", open: false) }
        #if DEBUG
        .task {
            // `-debugScreen corte-lista-quero:<lista>` (prints): a régua já puxada.
            let screen = DebugFlags.string("debugScreen") ?? ""
            if screen.hasPrefix("corte-lista-puxando") {
                try? await Task.sleep(for: .milliseconds(900))
                corte.pull.drag(translation: 80)
                return
            }
            guard screen.hasPrefix("corte-lista-quero"), let list else { return }
            try? await Task.sleep(for: .milliseconds(900))
            openQuero(list)
        }
        #endif
    }

    private func reservationTime(_ place: Place) -> String? {
        guard let r = place.reservation, region.calendar.isDate(r.at, inSameDayAs: now), r.at > now else { return nil }
        return region.timeString(r.at)
    }

    // MARK: Topo (o corte)

    private var coverURL: URL? {
        guard !saveForEndOnly, !noPhotos, let list, let photo = ListCover.photo(for: list) else { return nil }
        return URL(string: photo.largeURL ?? photo.url)
    }

    private var listTitle: String { saveForEndOnly ? "Fica pro fim" : (sub ?? list?.name.capitalized ?? "Lista") }

    /// Bloco = capa da lista (a que já está no disco; nunca baixa) com o nome gigante; sem foto, a cor do lugar.
    private func cutBlock(count: Int) -> some View {
        let city = trips.first?.city(on: now, calendar: region.calendar)?.name ?? region.shortName
        let listName = saveForEndOnly ? "fica pro fim" : (list?.displayName ?? "")
        return CutBand(photo: coverURL) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    V8CornerButton(systemName: "chevron.left", label: "Voltar", onPhoto: true) { dismiss() }
                    Spacer(minLength: 12)
                    V8SpecStack(lines: ["\(listName) · \(city)", "\(count) lugares"], color: V8.white, alignment: .trailing)
                        .padding(.top, 14)
                }
                .padding(.top, 58)
                Spacer(minLength: 16)
                if corte.pull.progress > 0.25 {
                    // Puxando: o título vira a frase do pedido.
                    Text("\(list?.displayName ?? listTitle),\nquero")
                        .font(V8Font.display(44))
                        .tracking(-1.4)
                        .lineSpacing(-10)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("\(list?.displayName ?? listTitle), quero")
                } else {
                    Text(listTitle)
                        .font(V8Font.display(64))
                        .tracking(-2)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .containerRelativeFrame(.vertical) { [pull = corte.pull.offset] height, _ in CutFrame.heights(pull: pull, rest: height * 0.38).band }
        .clipped()
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { openCover() }
        .photoCarousel($carousel)
    }

    /// Toque na capa: todas as fotos do lugar que deu a capa; capa do Commons ou escolhida à mão, só ela.
    private func openCover() {
        guard let list, !saveForEndOnly else { return }
        if PhotoStyle.current == .vivid, !ListCover.isManual(list), let place = ListCover.googlePlace(for: list) {
            carousel = .place(placeId: place.placeId, refs: place.photoRefs, resolver: services.photoResolver)
        } else if let url = coverURL, let photo = ListCover.photo(for: list) {
            carousel = PhotoCarousel(pages: [.init(id: 0, url: url, credit: photo.credit, load: nil)])
        }
    }

    /// "↓ quero <lista>": puxar abre o quero já filtrado pela lista. Sem lista (fica pro fim) a régua é estática.
    @ViewBuilder private var pullRule: some View {
        if saveForEndOnly || list == nil {
            CutRule()
        } else if let list {
            let noun = "quero \(list.name.lowercased())"
            CutRule(pullLabel: CutPull.label(phase: corte.pull.phase, offset: corte.pull.offset, noun: noun))
                .cutPull(corte.pull, reduceMotion: reduceMotion, onOpen: { openQuero(list) }, onClose: { corte.close() })
                .accessibilityAction(named: "Abrir quero") { openQuero(list) }
        }
    }

    /// Cabeçalho do papel: quantos lugares e o numeral laranja = quantos estão abertos agora.
    private func paperHeader(count: Int, open: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                // Nada aberto (ou sem horário conhecido): o numeral vira o tamanho da lista, em tinta, em vez de um "0" laranja gigante.
                MonoLabel(open > 0 ? "aberto agora · de \(count)" : "lugares · nenhum aberto agora", size: 10, color: V8.mute)
                Text(saveForEndOnly ? "o que fica pro fim da viagem" : "por bairro, do mais perto")
                    .font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.ink).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            let shown = open > 0 ? open : count
            Text(shown > 99 ? "99+" : "\(shown)")
                .font(V8Font.numeral(84)).tracking(-4).foregroundStyle(open > 0 ? V8.orange : V8.ink)
                .lineLimit(1).fixedSize()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .overlay(alignment: .bottom) { CorteRule2() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(open > 0 ? "\(open) abertos agora, de \(count) lugares" : "\(count) lugares, nenhum aberto agora")
    }

    // MARK: Quero filtrado pela lista

    private func openQuero(_ list: MustList) {
        corte.open()
        corte.preset(CorteListWish.wish(listId: list.id, name: list.name))
    }

    @ViewBuilder private var queroLayer: some View {
        if corte.stage != .rest, let list {
            CorteQueroOverlay(state: corte, photo: coverURL, subject: list.displayName, originName: region.shortName,
                              makeEnv: { queroEnv(list) }, actions: queroActions(list))
                .transition(.opacity)
        }
    }

    /// O ambiente do quero na lista: o da capa (GPS, dia de hoje) com o board reduzido à lista.
    private func queroEnv(_ list: MustList) -> QueroEnv {
        let all = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let today = region.calendar.startOfDay(for: now)
        let plan = dayEngine.plan(for: today, region: region, context: context)
        let base = QueroEnv.make(region: region, now: now, places: all, trip: trips.first, settings: settingsList.first, plan: plan,
                                 gps: services.location.current?.coordinate, online: services.connectivity.status != .offline,
                                 upcoming: QueroEnv.upcomingDays(context: context, areas: AreaCatalog.areas(for: region), today: today),
                                 shows: showEvents.today(region: region, at: now))
        return CorteState.corteEnv(base).scoped(toList: list.id)
    }

    private func queroActions(_ list: MustList) -> CorteResultActions {
        CorteResultActions(
            openPlace: { router.push(.place(id: $0), on: router.tab) },
            route: { MapsLinks.openApple(to: $0.row.result.coordinate, name: $0.row.result.name) },
            addToBoard: { CorteSave.addToBoard($0, state: corte, env: queroEnv(list), lists: lists, services: services, context: context) },
            fitToday: { row in
                guard CorteSave.fitToday(row, state: corte, env: queroEnv(list), lists: lists, services: services, context: context) else { return }
                corte.close()
                router.push(.linha(date: region.calendar.startOfDay(for: now)), on: router.tab)
            })
    }

    private var filters: some View {
        var items: [V8FilterRow.Item] = [
            .init(id: "near", title: "Perto", on: nearSort),
            .init(id: "open", title: "Abertos", on: openOnly),
        ]
        for s in list?.subs ?? [] { items.append(.init(id: "sub:\(s)", title: s, on: sub == s)) }
        items.append(.init(id: "cheap", title: region.currencySymbol + region.currencySymbol, on: cheapOnly))
        for other in lists where other.id != listId && other.kind != .experience {
            items.append(.init(id: "list:\(other.id)", title: other.name.capitalized, on: false))
        }
        return V8FilterRow(items: items) { id in
            switch id {
            case "near": nearSort.toggle()
            case "open": openOnly.toggle()
            case "cheap": cheapOnly.toggle()
            default:
                if id.hasPrefix("sub:") {
                    let s = String(id.dropFirst(4))
                    sub = sub == s ? nil : s
                } else if id.hasPrefix("list:") {
                    listId = String(id.dropFirst(5))
                    sub = nil
                }
            }
        }
    }

    /// Bairro: nome em Bricolage, legenda mono ("6 · você está aqui"), régua dura de 2 pt em cima e embaixo.
    private func groupHeader(_ group: ListGrouping.Group) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(group.name)
                .font(V8Font.display(26))
                .tracking(-0.8)
                .foregroundStyle(V8.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            SpecLabel(group.caption)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .overlay(alignment: .top) { CorteRule2() }
        .overlay(alignment: .bottom) { CorteRule2() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Estado

    /// Lugar da parada de agora no dia aceito (motor do dia), se houver.
    private func currentStopPlaceId() -> String? {
        DayClock.read(engine: dayEngine, region: region, context: context, at: now).now?.current.placeId
    }

    /// `openState` vem do `OpenNowIndex` (já calculado no minuto): a linha não relê o horário de cada lugar ao rolar.
    private func state(_ place: Place, openState: OpenState?, currentPlaceId: String?) -> IndexRowState {
        if place.isDone { return .done }
        if place.id == currentPlaceId { return .now }
        if let r = place.reservation, region.calendar.isDate(r.at, inSameDayAs: now), r.at > now { return .reservation(region.timeString(r.at)) }
        switch openState ?? place.openState(at: now, timeZone: region.timeZone) {
        case .closed(_, let time): return time.map { .opensAt(ListGrouping.hourLabel($0)) } ?? .closed
        case .open: return .open
        case .unknown: return .none
        }
    }

    private func trailing(_ place: Place, distance: CLLocationDistance?) -> String? {
        if let r = place.reservation, region.calendar.isDate(r.at, inSameDayAs: now), r.at > now { return region.timeString(r.at) }
        return distance.map(ListGrouping.distanceText)
    }

    private func addRow(empty: Bool) -> some View {
        Button { router.sheet = .newPlace(listId: listId) } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V8.paper)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(V8.ink))
                VStack(alignment: .leading, spacing: 2) {
                    Text(empty ? "Nada aqui ainda" : "Adicionar à mão").font(V8Font.text(16, weight: .semibold)).foregroundStyle(V8.ink)
                    Text(empty ? "adicione à mão ou cole um link no +" : "nome, bairro, preço, janela").font(V8Font.text(13))
                        .foregroundStyle(V8.mute)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Uma linha da Lista no padrão índice (prompt 30): a distância grande em mono (ou a hora da reserva de hoje), o nome, o
/// motivo (meta) e o estado à direita. Régua de 2 pt embaixo; sem miniatura (a foto fica no bloco do topo).
struct ListIndexRow: View {
    var distance: CLLocationDistance?
    var reservation: String?
    var title: String
    var meta: String
    var state: IndexRowState

    private var big: (value: String, unit: String)? {
        if let reservation { return (reservation, "reserva") }
        guard let distance else { return nil }
        let parts = CorteSplit.distanceParts(distance)
        return (parts.value, parts.unit == "m" ? "metros" : parts.unit)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(big?.value ?? "·")
                    .font(V8Font.mono(22, weight: .semibold)).foregroundStyle(V8.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text((big?.unit ?? "sem gps").uppercased())
                    .font(V8Font.mono(8.5)).tracking(0.8).foregroundStyle(V8.mute).lineLimit(1)
            }
            .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                if !meta.isEmpty {
                    Text(meta).font(V8Font.text(12)).foregroundStyle(V8.mute).lineLimit(1).truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if state != .none {
                HStack(spacing: 5) {
                    Circle().fill(state.isLive ? V8.orange : V8.mute).frame(width: 6, height: 6)
                    Text(stateLabel.uppercased()).font(V8Font.mono(9.5)).tracking(0.8)
                        .foregroundStyle(state.isLive ? V8.orangeDeep : V8.mute).lineLimit(1)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .opacity(state == .done ? 0.55 : 1)
        .overlay(alignment: .bottom) { CorteRule2() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, meta, stateLabel, big.map { "\($0.value) \($0.unit)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// Reserva mostra só "reserva" (a hora vai na coluna da esquerda).
    private var stateLabel: String {
        if case .reservation = state { return "reserva" }
        return state.label
    }
}

/// Agrupamento por bairro e textos da Lista (puro, testável).
@MainActor
enum ListGrouping {
    struct Group: Identifiable {
        var id: String
        var name: String
        var caption: String
        var places: [Place]
    }

    /// Bairros na ordem: onde você está primeiro, depois os vizinhos pelo tempo e o resto pela distância.
    static func groups(places: [Place], region: Region, location: CLLocation?, nearSort: Bool, pinned: String? = nil,
                       distance: (String) -> CLLocationDistance?, isOpen: (String) -> Bool) -> [Group] {
        let areas = AreaCatalog.areas(for: region)
        let assigner = AreaAssigner(areas: areas)
        let byId = Dictionary(areas.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let here = location.flatMap { CurrentAreaService.curated($0, in: areas) }

        var buckets: [String: (name: String, places: [Place])] = [:]
        for place in places {
            let areaId = assigner.areaId(name: place.area, cityId: place.cityId, lat: place.lat, lng: place.lng)
            let key = areaId ?? "free:" + (place.area?.isEmpty == false ? place.area! : "Outros")
            let name = areaId.flatMap { byId[$0]?.name } ?? (place.area?.isEmpty == false ? place.area! : "Outros")
            buckets[key, default: (name, [])].places.append(place)
        }

        func sortPlaces(_ list: [Place]) -> [Place] {
            list.sorted { a, b in
                if (a.id == pinned) != (b.id == pinned) { return a.id == pinned }
                if a.isDone != b.isDone { return !a.isDone }
                let ao = isOpen(a.id), bo = isOpen(b.id)
                if ao != bo { return ao }
                if nearSort, let da = distance(a.id), let db = distance(b.id), da != db { return da < db }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }

        var groups: [(group: Group, rank: Double)] = []
        for (key, bucket) in buckets {
            let sorted = sortPlaces(bucket.places)
            let nearest = sorted.compactMap { distance($0.id) }.min()
            var caption = "\(sorted.count)"
            var rank = nearest ?? 1e9
            if let here, key == here.id {
                caption += " · você está aqui"
                rank = -1
            } else if let here, let edge = here.neighbors.first(where: { $0.areaId == key }) {
                caption += " · \(edge.minutes) min" + (edge.line.map { " · \($0.code)" } ?? " · a pé")
                rank = Double(edge.minutes) * 80 // vizinho ganha de bairro solto a mesma distância
            } else if let nearest {
                caption += " · " + distanceText(nearest)
            }
            groups.append((Group(id: key, name: bucket.name, caption: caption, places: sorted), rank))
        }
        return groups.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.group.name < $1.group.name }.map(\.group)
    }

    /// "tsukemen · fila ~20 min · ¥ 1.250" (sub, fila, preço, feito).
    static func meta(_ place: Place, region: Region) -> String {
        var parts: [String] = []
        if let sub = place.sub, !sub.isEmpty { parts.append(sub.lowercased()) }
        if let q = place.queueMinutes, q > 0 { parts.append("fila ~\(q) min") }
        if let p = place.price, p > 0 { parts.append(region.money(p)) }
        if let done = place.done { parts.append("feito \(region.shortDay(done.at))") }
        if parts.isEmpty, !place.notes.isEmpty {
            parts.append(String(place.notes.split(separator: ".").first ?? "").trimmingCharacters(in: .whitespaces).lowercased())
        }
        return parts.joined(separator: " · ")
    }

    /// "650 m", "1,1 km".
    static func distanceText(_ meters: CLLocationDistance) -> String {
        if meters < 1000 { return "\(Int((meters / 50).rounded()) * 50) m" }
        return (meters / 1000).formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(1))) + " km"
    }

    /// "17:00" → "17h"; "17:30" fica.
    static func hourLabel(_ time: String) -> String {
        time.hasSuffix(":00") ? String(time.dropLast(3)).replacingOccurrences(of: "^0", with: "", options: .regularExpression) + "h" : time
    }
}
