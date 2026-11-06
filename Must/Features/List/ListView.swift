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
        let showPhotos = !noPhotos && base.count <= Self.photoLimit
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header(count: base.count, open: base.filter { snapshot.isOpen($0.id) }.count).padding(.top, 8)
                titleRow(count: base.count).padding(.top, 22)
                if !saveForEndOnly { filters.padding(.top, 20) }
                ForEach(groups) { group in
                    groupHeader(group).padding(.top, 28)
                    ForEach(group.places, id: \.id) { place in
                        let number = (groups.prefix { $0.id != group.id }.map(\.places.count).reduce(0, +))
                            + (group.places.firstIndex { $0.id == place.id } ?? 0) + 1
                        Button { router.push(.place(id: place.id), on: router.tab) } label: {
                            ListPlaceRow(index: "\(number)", place: place, meta: ListGrouping.meta(place, region: region),
                                         state: state(place, openState: snapshot.states[place.id], currentPlaceId: currentPlaceId),
                                         trailing: trailing(place, distance: snapshot.distance(place.id)), showPhoto: showPhotos)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Editar") { router.sheet = .editPlace(id: place.id) }
                        }
                    }
                }
                if !saveForEndOnly { addRow(empty: visible.isEmpty).padding(.top, 18) }
                V8BarSpacer()
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Topo

    private func header(count: Int, open: Int) -> some View {
        let listName = saveForEndOnly ? "fica pro fim" : (list?.displayName ?? "")
        let city = trips.first?.city(on: now, calendar: region.calendar)?.name ?? region.shortName
        return HStack(alignment: .top) {
            V8CornerButton(systemName: "chevron.left", label: "Voltar") { dismiss() }
            Spacer(minLength: 12)
            V8SpecStack(lines: ["\(listName) · \(city)", "\(count) lugares · \(open) abertos"], alignment: .trailing)
                .padding(.top, 14)
        }
    }

    private func titleRow(count: Int) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(saveForEndOnly ? "Fica pro fim" : (sub ?? list?.name.capitalized ?? "Lista"))
                .font(V8Font.display(52))
                .tracking(-1.6)
                .foregroundStyle(V8.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            BigNumeral("\(count)", size: 74, color: V8.orange)
            SpecLabel("por bairro").padding(.bottom, 10)
        }
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
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Estado

    /// Lugar da parada de agora no dia aceito (motor do dia), se houver.
    private func currentStopPlaceId() -> String? {
        guard let plan = dayEngine.plan(for: region.calendar.startOfDay(for: now), region: region, context: context) else { return nil }
        return dayEngine.now(in: plan, at: now)?.current.placeId
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

/// Uma linha da Lista: índice laranja, miniatura (lista curta), nome, meta e o estado com a distância à direita.
/// Sem miniatura é o `IndexRow` do contrato.
struct ListPlaceRow: View {
    var index: String
    var place: Place
    var meta: String
    var state: IndexRowState
    var trailing: String?
    var showPhoto: Bool

    var body: some View {
        Group {
            if showPhoto {
                withPhoto
            } else {
                IndexRow(index: index, title: place.name, meta: meta, state: state, trailing: trailing)
            }
        }
        .opacity(state == .done ? 0.55 : 1)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink.opacity(0.12)).frame(height: 1) }
        .contentShape(Rectangle())
    }

    private var withPhoto: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(index)
                .font(V8Font.numeral(30))
                .foregroundStyle(V8.orangeDeep)
                .frame(width: 30, alignment: .leading)
                .accessibilityHidden(true)
            V8Thumb(placeId: place.placeId, refs: place.photoRefs, size: 46, dimmed: state == .done)
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                Text(meta).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                if state != .none {
                    HStack(spacing: 5) {
                        Circle().fill(dotColor).frame(width: 6, height: 6)
                        Text(stateLabel.uppercased()).font(V8Font.mono(10)).tracking(0.8).foregroundStyle(stateColor).lineLimit(1)
                    }
                }
                if let trailing { Text(trailing).font(V8Font.mono(11).weight(.bold)).foregroundStyle(V8.ink).lineLimit(1) }
            }
            .fixedSize()
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([place.name, meta, stateLabel, trailing].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    /// Reserva mostra só "reserva" (a hora vai embaixo, como no design).
    private var stateLabel: String {
        if case .reservation = state { return "reserva" }
        return state.label
    }

    private var stateColor: Color {
        switch state {
        case .now, .reservation: V8.orangeDeep
        case .open: V8.orangeDeep.opacity(0.85)
        default: V8.mute
        }
    }

    private var dotColor: Color {
        switch state {
        case .now, .reservation, .open: V8.orange
        default: V8.mute
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
