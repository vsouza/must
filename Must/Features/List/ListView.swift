import SwiftData
import SwiftUI

/// Uma lista (Must eat › Sushi) ou o filtro "Fica pro fim".
struct ListView: View {
    var saveForEndOnly = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query(sort: \Place.name) private var allPlaces: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]

    @State private var listId: String?
    @State private var sub: String?
    @State private var nearSort = true
    @State private var openOnly = false
    @State private var cityName: String?
    @State private var cheapOnly = false
    /// Abertos e distâncias: recalculados só quando muda o minuto, a posição (≥ 50 m), o conjunto ou os filtros (A.3).
    @State private var openNow = OpenNowIndex()

    init(listId: String?, initialSub: String?, saveForEndOnly: Bool = false) {
        self.saveForEndOnly = saveForEndOnly
        _listId = State(initialValue: listId)
        _sub = State(initialValue: initialSub)
    }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var list: MustList? { lists.first { $0.id == listId } }
    private var color: MustColor { saveForEndOnly ? .night : (list?.color ?? .eat) }

    /// Lugares da lista (ou da sub) antes dos filtros de pílula.
    private var basePlaces: [Place] {
        if saveForEndOnly { return allPlaces.filter(\.saveForEnd) }
        guard let list else { return [] }
        return list.places.filter { sub == nil || $0.sub == sub }
    }

    private var visiblePlaces: [Place] {
        let location = services.location.current
        let tz = region.timeZone
        let cheapLimit = (settingsList.first?.perDayBudget ?? region.defaultBudget) * 0.35
        let snapshot = openNow.snapshot(for: basePlaces, now: now, timeZone: tz, location: location)
        let filtered = basePlaces.filter { place in
            if openOnly && !snapshot.isOpen(place.id) { return false }
            if let cityName, trips.first?.city(id: place.cityId)?.name != cityName { return false }
            if cheapOnly, (place.price ?? 0) > cheapLimit { return false }
            return true
        }
        // Chaves de ordenação calculadas uma vez por lugar (antes eram recalculadas a cada comparação).
        return filtered.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            let ao = snapshot.isOpen(a.id), bo = snapshot.isOpen(b.id)
            if ao != bo { return ao }
            if nearSort, let da = snapshot.distance(a.id), let db = snapshot.distance(b.id) {
                return da < db
            }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                filters.padding(.top, 14).padding(.horizontal, 22)
                content.padding(.top, 20).padding(.horizontal, 22)
                TabBarSpacer()
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Color.must.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header

    private var photoURL: URL? { saveForEndOnly ? nil : list?.photo?.url.flatMap(URL.init(string:)) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    MustIconView(.voltar, size: 18)
                        .foregroundStyle(Color.must.ink)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.55)))
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Voltar")
                Spacer()
                Micro(topLabel, color: color.text)
                Spacer()
                IconButton(.adicionar, style: .dark, label: "Adicionar") {
                    router.sheet = .addLink(url: nil, listId: saveForEndOnly ? nil : listId)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if photoURL != nil, let credit = list?.photo?.credit {
                    Credit(credit, color: color.text, url: list?.photo?.page.flatMap(URL.init(string:))).offset(y: 30)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title).mustTitle()
                Text(subtitle).mustSerif(18).foregroundStyle(color.text.opacity(0.85))
            }
            .padding(.top, 34)

            if !saveForEndOnly { tabs.padding(.top, 18) }
        }
        .padding(.horizontal, 22)
        .padding(.top, 62)
        .background(alignment: .top) {
            // Foto tingida de 240 pt que some no branco.
            // Vivo: foto em cima, cor sólida a partir do título (texto escuro sobre a cor).
            TintedPhoto(url: photoURL, color: color, ramp: 0.16...0.46)
                .frame(height: 300)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }
    }

    private var topLabel: String {
        if saveForEndOnly { return "fica pro fim · \(basePlaces.count) lugares" }
        return "\(list?.displayName ?? "") · \(list?.places.count ?? 0) lugares"
    }

    private var title: String {
        if saveForEndOnly { return "Fica pro fim" }
        return sub ?? list?.displayName ?? "Lista"
    }

    private var subtitle: String {
        let places = basePlaces
        let snapshot = openNow.snapshot(for: places, now: now, timeZone: region.timeZone, location: services.location.current)
        let open = places.filter { snapshot.isOpen($0.id) }.count
        let reserved = places.filter { ($0.reservation?.at ?? .distantPast) >= region.calendar.startOfDay(for: now) }.count
        var parts = ["\(places.count) musts", "\(open) abertos agora"]
        if reserved > 0 { parts.append("\(reserved) com reserva") }
        if saveForEndOnly { parts = ["\(places.count) musts", trips.first?.hasTrip == true ? "entram nos últimos dias da cidade" : "quando você pedir"] }
        return parts.joined(separator: " · ")
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                if let list {
                    tabButton("Todos", selected: sub == nil) { sub = nil }
                    ForEach(list.subs, id: \.self) { s in
                        tabButton(s, selected: sub == s) { sub = s }
                    }
                }
                ForEach(lists.filter { $0.id != listId }) { other in
                    tabButton(other.name.capitalized, selected: false) {
                        listId = other.id
                        sub = nil
                    }
                }
            }
            .padding(.bottom, 1)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.must.line).frame(height: 1) }
    }

    private func tabButton(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.must.archivo(16, selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.must.ink : Color.must.secondary)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    if selected { Rectangle().fill(Color.must.ink).frame(height: 2) }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Filtros

    private var cityNames: [String] {
        var seen: [String] = []
        for c in trips.first?.cities ?? [] where !seen.contains(c.name) { seen.append(c.name) }
        return seen.count > 1 ? seen : []
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { nearSort.toggle() } label: { Pill("Perto", isOn: nearSort) }
                Button { openOnly.toggle() } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Color.must.green).frame(width: 8, height: 8)
                        Text("Abertos")
                    }
                    .font(.must.archivo(13, .semibold))
                    .foregroundStyle(openOnly ? .white : Color.must.ink)
                    .padding(.vertical, 9).padding(.horizontal, 13)
                    .background(Capsule().fill(openOnly ? Color.must.ink : Color.must.surface))
                }
                ForEach(cityNames, id: \.self) { name in
                    Button { cityName = cityName == name ? nil : name } label: { Pill(name, isOn: cityName == name) }
                }
                Button { cheapOnly.toggle() } label: { Pill(region.currencySymbol + region.currencySymbol, isOn: cheapOnly) }
                    .accessibilityLabel("Mais baratos")
            }
            .buttonStyle(MustPressStyle())
        }
        .scrollClipDisabled()
    }

    // MARK: Lugares

    @ViewBuilder private var content: some View {
        let places = visiblePlaces
        PlaceListCard(
            places: places, region: region, trip: trips.first, location: services.location.current,
            onOpen: { router.push(.place(id: $0.id), on: router.tab) },
            onEdit: { router.sheet = .editPlace(id: $0.id) },
            footer: saveForEndOnly ? nil : AnyView(addRow(empty: places.isEmpty))
        )
    }

    private func addRow(empty: Bool) -> some View {
        Button { router.sheet = .newPlace(listId: listId) } label: {
            HStack(spacing: 12) {
                MustIconView(.adicionar, size: 18)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(color.gradient))
                    .foregroundStyle(color.text)
                VStack(alignment: .leading, spacing: 2) {
                    Text(empty ? "Nada aqui ainda" : "Adicionar à mão").font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
                    Text(empty ? "adicione à mão ou cole um link no +" : "nome, bairro, preço, janela").mustMeta()
                }
                Spacer()
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
