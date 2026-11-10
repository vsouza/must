import CoreLocation
import SwiftData
import SwiftUI

/// Lista (V9): uma lista agrupada **por bairro** ("Shinjuku · 6 · você está aqui"), em `List` nativa, com miniatura (só
/// do disco e só em lista curta), estado em texto (agora / aberto / abre 17h / fechado / feito / reserva) e distância.
/// Lista longa (ou "Sem foto" nos Musts) vira só texto. Também o filtro "Fica pro fim".
struct ListView: View {
    var saveForEndOnly = false

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context

    @Query(sort: \MustList.order) private var lists: [MustList]
    /// Só os "fica pro fim" (o resto vem de `list.places`).
    @Query(filter: #Predicate<Place> { $0.saveForEnd }, sort: \Place.name) private var saveForEndPlaces: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var listId: String?
    @State private var sub: String?
    @State private var nearSort = true
    @State private var openOnly = false
    @State private var cheapOnly = false
    @State private var search = ""
    @State private var doneFor: Place?
    @State private var deleting: Place?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tripTheme) private var theme
    @AppStorage(MustsPrefs.noPhotosKey) private var noPhotos = false
    /// Abertos e distâncias: recalculados só quando muda o minuto, a posição (≥ 50 m), o conjunto ou os filtros.
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
        let base = basePlaces
        let snapshot = openNow.snapshot(for: base, now: now, timeZone: region.timeZone, location: location)
        let cheapLimit = (settingsList.first?.perDayBudget ?? region.defaultBudget) * 0.35
        let visible = base.filter { place in
            if openOnly && !snapshot.isOpen(place.id) { return false }
            if cheapOnly, (place.price ?? 0) > cheapLimit { return false }
            if !search.isEmpty, !BoardQuery.fold(place.name + " " + (place.area ?? "")).contains(BoardQuery.fold(search)) { return false }
            return true
        }
        let currentPlaceId = currentStopPlaceId()
        let groups = ListGrouping.groups(places: visible, region: region, location: location, nearSort: nearSort, pinned: currentPlaceId,
                                         distance: { snapshot.distance($0) }, isOpen: { snapshot.isOpen($0) })
        let openCount = base.filter { snapshot.isOpen($0.id) }.count
        let showThumbs = !noPhotos && base.count <= Self.photoLimit
        VStack(spacing: 0) {
        header(count: base.count)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                paperHeader(count: base.count, open: openCount)
                if let list, !saveForEndOnly { wishButton(list) }
                CutSearchField(text: $search, placeholder: "Buscar nesta lista") { EmptyView() }
                    .padding(.horizontal, 20)
                if !saveForEndOnly { filters.padding(.top, 12).padding(.bottom, 14) }
                ForEach(groups) { group in
                    groupHeader(group)
                    ForEach(group.places, id: \.id) { place in
                        row(place, snapshot: snapshot, currentPlaceId: currentPlaceId, thumb: showThumbs)
                    }
                }
                if !saveForEndOnly { addRow(empty: visible.isEmpty).padding(.horizontal, 20).padding(.top, 14) }
                V8BarSpacer()
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $doneFor) { place in DoneSheet(place: place, region: region).presentationDetents([.medium]) }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Apagar", role: .destructive) {
                if let deleting { try? BoardEdits.delete([deleting], context: context) }
                deleting = nil
            }
        } message: {
            Text("Apaga do board, sem lixeira. O export do board é o backup.")
        }
        .v8Legacy()
    }

    private var deleteTitle: String { deleting.map { "Apagar \($0.name)?" } ?? "Apagar?" }

    private var listTitle: String { saveForEndOnly ? "Fica pro fim" : (sub ?? list?.displayName ?? "Lista") }

    private var coverURL: URL? {
        guard !saveForEndOnly, !noPhotos, let list, let photo = ListCover.photo(for: list) else { return nil }
        return URL(string: photo.largeURL ?? photo.url)
    }

    /// Capa da lista (a que já está no disco; nunca baixa) com o nome gigante; sem foto, a cor do lugar.
    private func header(count: Int) -> some View {
        let city = trips.first?.city(on: now, calendar: region.calendar)?.name ?? region.shortName
        let listName = saveForEndOnly ? "fica pro fim" : (list?.displayName ?? "")
        return CutScreenHeader(title: listTitle, corner: ["\(listName) · \(city)", "\(count) lugares"], photo: coverURL, height: 190,
                               onBack: { dismiss() }) {
            if let list, !saveForEndOnly {
                CutCornerButton(systemName: "pencil", label: "Editar lista", tint: theme.coverInk) { router.cover = .editList(id: list.id) }
            }
        }
    }

    /// Cabeçalho do papel: quantos lugares e o numeral laranja = quantos estão abertos agora.
    private func paperHeader(count: Int, open: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
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
        .overlay(alignment: .bottom) { IndexRule() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(open > 0 ? "\(open) abertos agora, de \(count) lugares" : "\(count) lugares, nenhum aberto agora")
    }

    /// "Quero <verbo da lista>": botão visível que abre o Quero já com o verbo.
    private func wishButton(_ list: MustList) -> some View {
        let verb = ListWish.text(listId: list.id, name: list.name)
        return Button { router.openQuero(text: verb) } label: {
            HStack {
                Text("Quero \(verb)…").font(V8Font.mono(12, weight: .semibold)).tracking(0.8).textCase(.uppercase)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(V8.paper)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(V8.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Quero \(verb) desta lista")
        .accessibilityHint("abre a busca com o que tem perto")
    }

    // MARK: Linhas

    private func reservationTime(_ place: Place) -> String? {
        guard let r = place.reservation, region.calendar.isDate(r.at, inSameDayAs: now), r.at > now else { return nil }
        return region.timeString(r.at)
    }

    private func row(_ place: Place, snapshot: OpenNowIndex.Snapshot, currentPlaceId: String?, thumb: Bool) -> some View {
        let st = state(place, openState: snapshot.states[place.id], currentPlaceId: currentPlaceId)
        return HStack(spacing: 0) {
            Button { router.push(.place(id: place.id), on: router.tab) } label: {
                ListIndexRow(distance: snapshot.distance(place.id), reservation: reservationTime(place), title: place.name,
                             meta: ListGrouping.meta(place, region: region), state: st,
                             thumbnail: thumb ? AnyView(PlaceThumb(placeId: place.placeId, refs: place.photoRefs, color: place.list?.color ?? .eat, size: 44)) : nil)
            }
            .buttonStyle(.plain)
            PlaceRowMenu(place: place,
                         onOpen: { router.push(.place(id: place.id), on: router.tab) },
                         onDone: { doneFor = place },
                         onSaveForEnd: { try? BoardEdits.setSaveForEnd([place], on: !place.saveForEnd, context: context) },
                         onEdit: { router.sheet = .editPlace(id: place.id) },
                         onDelete: { deleting = place })
                .padding(.trailing, 8)
        }
        .overlay(alignment: .bottom) { IndexRule() }
    }

    // MARK: Filtros (visíveis, nada escondido)

    private var filters: some View {
        var items: [CutChipRow.Item] = [
            .init(id: "near", title: "Perto", on: nearSort),
            .init(id: "open", title: "Abertos", on: openOnly),
        ]
        for s in list?.subs ?? [] { items.append(.init(id: "sub:\(s)", title: s, on: sub == s)) }
        items.append(.init(id: "cheap", title: region.currencySymbol + region.currencySymbol, on: cheapOnly))
        for other in lists where other.id != listId && other.kind != .experience {
            items.append(.init(id: "list:\(other.id)", title: other.displayName, on: false))
        }
        return CutChipRow(items: items) { id in
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

    /// Bairro: nome em Bricolage, legenda mono ("6 · você está aqui"), régua de 2 pt em cima e embaixo.
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
        .overlay(alignment: .top) { IndexRule() }
        .overlay(alignment: .bottom) { IndexRule() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Lugar da parada de agora no dia aceito (motor do dia), se houver.
    private func currentStopPlaceId() -> String? {
        DayClock.read(engine: dayEngine, region: region, context: context, at: now).now?.current.placeId
    }

    /// `openState` vem do `OpenNowIndex` (já calculado no minuto): a linha não relê o horário de cada lugar ao rolar.
    private func state(_ place: Place, openState: OpenState?, currentPlaceId: String?) -> ListRowState {
        if place.isDone { return .done }
        if place.id == currentPlaceId { return .now }
        if let r = place.reservation, region.calendar.isDate(r.at, inSameDayAs: now), r.at > now { return .reservation }
        switch openState ?? place.openState(at: now, timeZone: region.timeZone) {
        case .closed(_, let time): return time.map { .opensAt(ListGrouping.hourLabel($0)) } ?? .closed
        case .open: return .open
        case .unknown: return .none
        }
    }

    private func addRow(empty: Bool) -> some View {
        Button { router.sheet = .newPlace(listId: listId) } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(V8.paper)
                    .frame(width: 34, height: 34)
                    .background(Rectangle().fill(V8.ink))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(empty ? "Nada aqui ainda" : "Adicionar à mão").font(V8Font.text(16, weight: .semibold)).foregroundStyle(V8.ink)
                    Text(empty ? "adicione à mão ou cole um link no Quero" : "nome, bairro, preço, janela").font(V8Font.text(13))
                        .foregroundStyle(V8.mute)
                }
                Spacer()
            }
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Uma linha da Lista no padrão índice: a distância grande em mono (ou a hora da reserva de hoje), o nome, o motivo (meta)
/// e o estado em texto. Miniatura só em lista curta.
struct ListIndexRow: View {
    var distance: CLLocationDistance?
    var reservation: String?
    var title: String
    var meta: String
    var state: ListRowState
    var thumbnail: AnyView?

    private var big: (value: String, unit: String)? {
        if let reservation { return (reservation, "reserva") }
        guard let distance else { return nil }
        let text = ListGrouping.distanceText(distance)
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return (text, "") }
        return (parts[0], parts[1] == "m" ? "metros" : parts[1])
    }

    private var live: Bool {
        switch state { case .now, .open, .reservation: true; default: false }
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
            .frame(width: 70, alignment: .leading)
            if let thumbnail { thumbnail.clipShape(Rectangle()) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                if !meta.isEmpty {
                    Text(meta).font(V8Font.text(12)).foregroundStyle(V8.mute).lineLimit(1).truncationMode(.tail)
                }
                if state != .none {
                    HStack(spacing: 5) {
                        Circle().fill(live ? V8.orange : V8.mute).frame(width: 6, height: 6)
                        Text(state.label.uppercased()).font(V8Font.mono(9.5)).tracking(0.8)
                            .foregroundStyle(live ? V8.orangeDeep : V8.mute).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .opacity(state == .done ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, meta, state.label, big.map { "\($0.value) \($0.unit)" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/// Estado de um lugar na linha (texto; "agora" e "reserva" em destaque pelo acento só no ponto).
enum ListRowState: Hashable, Sendable {
    case now, open, opensAt(String), closed, done, reservation, none

    var label: String {
        switch self {
        case .now: "agora"
        case .open: "aberto"
        case .opensAt(let h): "abre \(h)"
        case .closed: "fechado"
        case .done: "feito"
        case .reservation: "reserva hoje"
        case .none: ""
        }
    }
}

/// O texto do Quero que a lista abre: o verbo da lista (Must eat → "comer", Must drink → "beber"…).
enum ListWish {
    static func text(listId: String, name: String) -> String {
        switch listId {
        case "eat": "comer"
        case "drink": "beber"
        case "shop": "lojas"
        case "see", "photo", "art": "ver"
        case "do", "sport": "fazer"
        default: name.lowercased()
        }
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
