import CoreLocation
import SwiftData
import SwiftUI

/// Bairros (⋯ › Bairros do Explorar, rota `.guia`), no visual V9: uma lista dos bairros da cidade em ordem de tempo de trem
/// (aqui · hoje · feito), e a página do bairro com os seus Musts, o que tem de fora do board (só o cache do Por perto) e os
/// vizinhos. Substitui as páginas do conceito B (foto, trilho, recorte), que não têm controle visível pra tudo. Só lê o que
/// está no aparelho; nenhuma chamada de rede.
struct BairrosV9View: View {
    /// Bairro que abre já aberto (o do dia aceito, quando vem de "Montar").
    var initialArea: String?

    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(\.dayEngine) private var dayEngine
    @Environment(\.modelContext) private var context
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]

    @State private var model = ExplorarModel()
    @State private var openIndex = OpenNowIndex()
    @State private var outside: [NearbyPlace] = []
    @State private var picked: String?
    @State private var booted = false

    private var region: Region { store.region }
    private var now: Date { AppClock.now }

    var body: some View {
        List {
            if model.cities.count > 1 {
                Section {
                    Picker("Cidade", selection: Binding(get: { model.cityGroup }, set: { model.select(city: $0) })) {
                        ForEach(model.cities) { Text($0.name).tag($0.group) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            Section {
                ForEach(model.stations) { station in
                    Button { picked = station.id } label: { stationRow(station) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("Em ordem de tempo desde \(originName)")
            } footer: {
                if model.stations.isEmpty { Text("Nenhum bairro com Musts nesta cidade ainda.") }
            }
        }
        .navigationTitle("Bairros")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $picked) { id in
            BairroPageV9(model: model, areaId: id, region: region)
        }
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
        .task(id: refreshKey) { refresh() }
        .task(id: model.areaId) { await loadOutside() }
        .onAppear {
            guard !booted else { return }
            booted = true
            if let initialArea { model.select(area: initialArea); picked = initialArea }
        }
    }

    private var originName: String { model.stations.first?.area.name ?? region.displayName }

    private func stationRow(_ station: ExplorarStation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(station.area.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text(caption(station)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if station.mark == .here {
                Circle().fill(V9.accent).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func caption(_ station: ExplorarStation) -> String {
        switch station.mark {
        case .here: "você está aqui"
        case .today(let time): time.map { "no dia de hoje · \($0)" } ?? "no dia de hoje"
        case .done: "tudo feito"
        case .other: station.minutes == 0 ? "ponto de partida" : "\(station.minutes) min de trem"
        }
    }

    // MARK: Dados

    private var refreshKey: String {
        let cell = services.location.current.map { "\(Int(($0.coordinate.latitude * 2000).rounded())),\(Int(($0.coordinate.longitude * 2000).rounded()))" } ?? "-"
        return "\(region.rawValue)|\(Int(now.timeIntervalSinceReferenceDate / 60))|\(PlacesRevision.of(places))|\(cell)|\(outside.count)"
    }

    private func refresh() {
        let today = region.calendar.startOfDay(for: now)
        let areas = AreaCatalog.areas(for: region)
        let snapshot = openIndex.snapshot(for: places, now: now, timeZone: region.timeZone, location: services.location.current)
        var cities: [(group: String, name: String)] = []
        for city in trips.first?.cities ?? [] {
            let group = AreaCatalog.cityGroup(forCityId: city.id)
            if !cities.contains(where: { $0.group == group }) { cities.append((group, Self.cityName(city.name, group: group))) }
        }
        let plan = dayEngine.plan(for: today, region: region, context: context)
        model.refresh(.init(
            region: region, now: now, places: places, gps: services.location.current?.coordinate, plan: plan,
            upcoming: QueroEnv.upcomingDays(context: context, areas: areas, today: today), cities: cities, outside: outside,
            openIds: Set(places.filter { snapshot.isOpen($0.id) }.map(\.id)), distances: snapshot.distances))
    }

    /// "Tokyo 2" → "Tóquio"; o resto como está.
    static func cityName(_ name: String, group: String) -> String {
        if group == "tokyo" { return "Tóquio" }
        if group == "kyoto" { return "Kyoto" }
        return name.replacingOccurrences(of: #"\s+\d+$"#, with: "", options: .regularExpression)
    }

    /// "Fora do board" do bairro aberto: só o cache do Por perto (nunca chama fonte).
    private func loadOutside() async {
        guard let area = model.area, picked != nil else { return }
        let batch = await services.nearby.cached(lat: area.centroid.lat, lng: area.centroid.lng, region: region)
        let fresh = batch?.places.filter { !$0.sources.contains(.board) } ?? []
        if fresh != outside { outside = fresh }
    }
}

/// A página de um bairro: o que fazer (pedir, ver no mapa, ir) e as listas.
struct BairroPageV9: View {
    var model: ExplorarModel
    var areaId: String
    var region: Region

    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    private var items: [ExplorarItem] { model.areaId == areaId ? ExplorarLayers.sorted(model.items) : [] }
    private var own: [ExplorarItem] { items.filter(\.isOwn) }
    private var fora: [ExplorarItem] { items.filter { !$0.isOwn } }
    private var area: Area? { model.stations.first { $0.id == areaId }?.area ?? model.area }
    private var station: ExplorarStation? { model.stations.first { $0.id == areaId } }

    var body: some View {
        List {
            Section {
                Button { router.openQuero(text: "em \(area?.name ?? "")") } label: {
                    Label("Pedir algo em \(area?.name ?? "")", systemImage: "magnifyingglass")
                }
                Button { showOnMap() } label: { Label("Ver no mapa", systemImage: "map") }
                    .disabled(items.isEmpty)
            } footer: {
                if let station { Text(caption(station)) }
            }
            if !own.isEmpty {
                Section("Seus Musts · \(own.count)") {
                    ForEach(own) { item in
                        Button { if let id = item.placeId { router.push(.place(id: id)) } } label: { row(item) }
                            .buttonStyle(.plain)
                    }
                }
            } else if model.areaId == areaId {
                Section { Text("Nenhum Must seu aqui ainda.").foregroundStyle(.secondary) }
            }
            if !fora.isEmpty {
                Section {
                    ForEach(fora) { item in
                        Button { MapsLinks.openApple(to: item.coordinate, name: item.name) } label: { row(item) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    Text("Indicados fora do board · \(fora.count)")
                } footer: {
                    Text("Do cache do Por perto. Toque pra abrir no Mapas.")
                }
            }
            if let area, !area.neighbors.isEmpty {
                Section("Vizinhos") {
                    ForEach(area.neighbors, id: \.areaId) { n in
                        if let neighbor = AreaCatalog.areas(for: region).first(where: { $0.id == n.areaId }) {
                            Button { model.select(area: neighbor.id) } label: {
                                HStack {
                                    Text(neighbor.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(n.minutes) min").foregroundStyle(.secondary).monospacedDigit()
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(area?.name ?? "Bairro")
        .navigationBarTitleDisplayMode(.large)
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
        .onAppear { if model.areaId != areaId { model.select(area: areaId) } }
    }

    private func caption(_ station: ExplorarStation) -> String {
        switch station.mark {
        case .here: "Você está aqui."
        case .today(let time): time.map { "No dia de hoje, às \($0)." } ?? "No dia de hoje."
        case .done: "Tudo feito por aqui."
        case .other: station.minutes == 0 ? "Ponto de partida." : "\(station.minutes) min de trem desde o ponto de partida."
        }
    }

    private func row(_ item: ExplorarItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).strikethrough(item.done)
                Text(item.meta).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if let time = item.planTime {
                    Text("no dia · \(time)").font(.subheadline).foregroundStyle(V9.accent).monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            Text(meters(item.meters)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func meters(_ m: Double) -> String {
        m < 1000 ? "\(Int((m / 10).rounded()) * 10) m" : String(format: "%.1f km", m / 1000).replacingOccurrences(of: ".", with: ",")
    }

    private func showOnMap() {
        let ids = own.compactMap(\.placeId)
        let points = fora.map { MapShowcase.Point(name: $0.name, lat: $0.lat, lng: $0.lng) }
        router.showOnMap(MapShowcase(title: area?.name ?? "Bairro", placeIds: ids, outside: points))
    }
}
