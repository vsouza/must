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
            return true
        }
        let currentPlaceId = currentStopPlaceId()
        let groups = ListGrouping.groups(places: visible, region: region, location: location, nearSort: nearSort, pinned: currentPlaceId,
                                         distance: { snapshot.distance($0) }, isOpen: { snapshot.isOpen($0) })
        let openCount = base.filter { snapshot.isOpen($0.id) }.count
        let showThumbs = !noPhotos && base.count <= Self.photoLimit
        List {
            Section {
                summary(count: base.count, open: openCount)
                if !saveForEndOnly { filters }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.places, id: \.id) { place in
                        row(place, snapshot: snapshot, currentPlaceId: currentPlaceId, thumb: showThumbs)
                    }
                } header: {
                    HStack {
                        Text(group.name).font(.headline).foregroundStyle(.primary).textCase(nil).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(group.caption).font(.footnote).textCase(nil)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
            if !saveForEndOnly {
                Section { addRow(empty: visible.isEmpty) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(listTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let list, !saveForEndOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.openQuero(text: ListWish.text(listId: list.id, name: list.name)) } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Quero algo desta lista")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.cover = .editList(id: list.id) } label: { Image(systemName: "pencil") }
                        .accessibilityLabel("Editar lista")
                }
            }
        }
        .v9Screen(grouped: true)
    }

    private var listTitle: String { saveForEndOnly ? "Fica pro fim" : (sub ?? list?.displayName ?? "Lista") }

    private func summary(count: Int, open: Int) -> some View {
        let city = trips.first?.city(on: now, calendar: region.calendar)?.name ?? region.shortName
        let text = open > 0 ? "\(open) abertos agora, de \(count) lugares" : "\(count) lugares, nenhum aberto agora"
        return VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.body.weight(.semibold))
            Text(saveForEndOnly ? "o que fica pro fim da viagem" : "\(city) · por bairro, do mais perto")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Linhas

    private func row(_ place: Place, snapshot: OpenNowIndex.Snapshot, currentPlaceId: String?, thumb: Bool) -> some View {
        let st = state(place, openState: snapshot.states[place.id], currentPlaceId: currentPlaceId)
        let distance = snapshot.distance(place.id)
        let detail = [reservationTime(place).map { "reserva \($0)" } ?? distance.map(ListGrouping.distanceText),
                      ListGrouping.meta(place, region: region)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 4) {
            Button { router.push(.place(id: place.id), on: router.tab) } label: {
                V9Row(title: place.name, detail: detail.isEmpty ? nil : detail,
                      reason: st == .none ? nil : st.label,
                      thumbnail: thumb ? AnyView(PlaceThumb(placeId: place.placeId, refs: place.photoRefs, color: place.list?.color ?? .eat, size: V9.thumb)) : nil,
                      dimmed: st == .done)
            }
            .buttonStyle(.plain)
            Menu {
                Button { router.push(.place(id: place.id), on: router.tab) } label: { Label("Abrir", systemImage: "arrow.up.right") }
                Button { router.sheet = .editPlace(id: place.id) } label: { Label("Editar", systemImage: "pencil") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Ações de \(place.name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { router.sheet = .editPlace(id: place.id) } label: { Label("Editar", systemImage: "pencil") }.tint(.gray)
        }
    }

    private func reservationTime(_ place: Place) -> String? {
        guard let r = place.reservation, region.calendar.isDate(r.at, inSameDayAs: now), r.at > now else { return nil }
        return region.timeString(r.at)
    }

    // MARK: Filtros (visíveis, nada escondido)

    @ViewBuilder private var filters: some View {
        Toggle("Do mais perto", isOn: $nearSort)
        Toggle("Só abertos agora", isOn: $openOnly)
        Toggle("Só barato (\(region.currencySymbol)\(region.currencySymbol))", isOn: $cheapOnly)
        if let list, !list.subs.isEmpty {
            Picker("Sub-lista", selection: Binding(get: { sub ?? "" }, set: { sub = $0.isEmpty ? nil : $0 })) {
                Text("Todas").tag("")
                ForEach(list.subs, id: \.self) { Text($0).tag($0) }
            }
        }
        let others = lists.filter { $0.id != listId && $0.kind != .experience }
        if !others.isEmpty {
            Picker("Trocar de lista", selection: Binding(get: { listId ?? "" }, set: { listId = $0; sub = nil })) {
                ForEach(lists.filter { $0.kind != .experience }) { Text($0.displayName).tag($0.id) }
            }
        }
    }

    // MARK: Estado

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
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(V9.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(empty ? "Nada aqui ainda" : "Adicionar à mão").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(empty ? "adicione à mão ou cole um link no +" : "nome, bairro, preço, janela")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
