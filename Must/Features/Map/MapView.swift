import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// Camadas do mapa.
enum MapLayer: String, CaseIterable, Identifiable {
    case route, openNow, metro, allMusts

    var id: String { rawValue }

    var label: String {
        switch self {
        case .route: "Roteiro"
        case .openNow: "Abertos agora"
        case .metro: "Metrô"
        case .allMusts: "Todos os musts"
        }
    }
}

/// Mapa do Must: base clara e vazia, metrô nas cores oficiais, rota azul do dia, pinos 済/número,
/// musts abertos em anel azul, escala fixa e card da próxima parada.
struct MapView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var places: [Place]
    @Query private var days: [PlannedDay]
    @Query private var settingsList: [Settings]
    @Query private var trips: [TripInfo]

    @State private var position: MapCameraPosition = .automatic
    @State private var layers: Set<MapLayer> = [.route, .metro]
    @State private var locked = true
    @State private var span: MKCoordinateSpan?
    @State private var center: CLLocationCoordinate2D?
    @State private var mapHeight: CGFloat = 800
    @State private var routes = RouteGeometry()
    @State private var selectedId: String?
    @State private var query = ""
    @State private var didCenter = false

    /// Distância da câmera na escala de bairro (~1,4 km de largura na tela).
    static let neighborhoodDistance: CLLocationDistance = 2600

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var transit: TransitMap { TransitLoader.load(region) }
    private var walkMaxKm: Double { settingsList.first?.walkMaxKm ?? 1.5 }

    private var today: PlannedDay? {
        let start = region.calendar.startOfDay(for: now)
        return days.first { $0.date == start && $0.accepted }
    }

    private var stops: [Stop] { today?.orderedStops.filter { $0.place != nil } ?? [] }
    private var nextStop: Stop? { stops.first { !$0.done } }

    private var here: CLLocationCoordinate2D? { services.location.current?.coordinate }

    private var fallbackCenter: CLLocationCoordinate2D {
        if let here { return here }
        if let next = nextStop?.place { return next.coordinate }
        if let city = trips.first?.city(on: now, calendar: region.calendar) {
            return CLLocationCoordinate2D(latitude: city.lat, longitude: city.lng)
        }
        return region.defaultCenter
    }

    var body: some View {
        ZStack {
            Color.must.surface2.ignoresSafeArea()
            GeometryReader { geo in
                map.onAppear { mapHeight = geo.size.height }
            }
            .ignoresSafeArea()
            overlays
        }
        .onAppear(perform: appear)
        .onChange(of: router.mapShowsOpenNow) { _, open in if open { consumeOpenNow() } }
        .onChange(of: stops.map(\.id)) { _, _ in requestRoutes() }
    }

    // MARK: Mapa

    private var map: some View {
        Map(position: $position, bounds: locked ? MapCameraBounds(maximumDistance: Self.neighborhoodDistance * 1.6) : nil) {
            if layers.contains(.metro) { metroContent }
            if layers.contains(.route) { routeContent }
            if layers.contains(.openNow) || layers.contains(.allMusts) { ringsContent }
            if let here {
                Annotation("Você", coordinate: here, anchor: .center) { YouDot() }
                    .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {}
        .onMapCameraChange(frequency: .continuous) { context in
            span = context.region.span
            center = context.region.center
        }
    }

    @MapContentBuilder private var metroContent: some MapContent {
        ForEach(transit.lines) { line in
            ForEach(Array(line.paths.enumerated()), id: \.offset) { _, path in
                MapPolyline(coordinates: path).stroke(line.color, lineWidth: 3)
            }
        }
        let zoom = span?.latitudeDelta ?? 1
        if zoom < 0.06 {
            ForEach(visibleStations) { station in
                Annotation(station.name, coordinate: station.coordinate, anchor: .center) {
                    StationDot(name: station.name, showsLabel: zoom < 0.025, isJapanese: region == .jp)
                }
                .annotationTitles(.hidden)
            }
        }
    }

    private var visibleStations: [TransitStation] {
        guard let center, let span else { return [] }
        return transit.stations.filter {
            abs($0.coordinate.latitude - center.latitude) < span.latitudeDelta * 0.7
                && abs($0.coordinate.longitude - center.longitude) < span.longitudeDelta * 0.7
        }
    }

    @MapContentBuilder private var routeContent: some MapContent {
        let route = stops
        ForEach(Array(zip(route, route.dropFirst()).enumerated()), id: \.offset) { _, pair in
            if let a = pair.0.place, let b = pair.1.place {
                let done = pair.1.done
                MapPolyline(coordinates: routes.path(from: a, to: b))
                    .stroke(Color.must.blue.opacity(0.95),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: done ? [] : [2, 9]))
            }
        }
        ForEach(Array(route.enumerated()), id: \.element.id) { index, stop in
            if let place = stop.place {
                Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                    Button { selectedId = place.id } label: {
                        StopPin(number: index + 1, done: stop.done, isNext: stop.id == nextStop?.id)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(index + 1). \(place.name)\(stop.done ? ", feito" : "")")
                }
                .annotationTitles(.hidden)
            }
        }
    }

    /// Musts fora do roteiro: abertos agora (ou todos), como anel azul.
    @MapContentBuilder private var ringsContent: some MapContent {
        let inRoute = Set(stops.compactMap { $0.place?.id })
        let cityName = trips.first?.city(on: now, calendar: region.calendar)?.name
        let showAll = layers.contains(.allMusts)
        let rings = places.filter { p in
            let sameCity = cityName == nil || trips.first?.city(id: p.cityId)?.name == cityName
            return !inRoute.contains(p.id) && !p.isDone && sameCity
                && (showAll || p.openState(at: now, timeZone: region.timeZone).isOpen)
        }
        ForEach(rings) { place in
            Annotation(place.name, coordinate: place.coordinate, anchor: .center) {
                Button { router.push(.place(id: place.id), on: .mapa) } label: { OpenRing(selected: selectedId == place.id) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(place.name)
            }
            .annotationTitles(.hidden)
        }
    }

    // MARK: Por cima

    private var overlays: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    searchField
                    layersMenu
                }
                HStack(spacing: 6) {
                    ForEach([MapLayer.route, .openNow, .metro]) { layer in
                        Button { toggle(layer) } label: { layerPill(layer) }
                            .buttonStyle(MustPressStyle())
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)

            Spacer()

            HStack(alignment: .bottom) {
                ScaleBar(metersPerPoint: metersPerPoint)
                Spacer()
                VStack(spacing: 8) {
                    IconButton(.voceGps, style: .glass, label: "Centralizar em mim") { centerOn(fallbackCenter) }
                    Button { toggleLock() } label: {
                        Text("300").font(.must.mono(11, .semibold))
                            .foregroundStyle(locked ? .white : Color.must.ink)
                            .frame(width: 40, height: 40)
                            .background { if locked { Circle().fill(Color.must.ink) } else { Color.clear.glass(cornerRadius: 20) } }
                    }
                    .buttonStyle(MustPressStyle())
                    .accessibilityLabel(locked ? "Destravar zoom" : "Travar zoom no bairro")
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            bottomCard
                .padding(.horizontal, 22)
                .padding(.bottom, 92)
        }
    }

    private var openNearby: [Place] {
        guard let location = services.location.current else { return [] }
        return places.filter { !$0.isDone && $0.openState(at: now, timeZone: region.timeZone).isOpen && $0.location.distance(from: location) <= 1500 }
    }

    private var areaName: String {
        let c = fallbackCenter
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let nearest = places.filter { $0.area != nil }.min { $0.location.distance(from: location) < $1.location.distance(from: location) }
        if let nearest, nearest.location.distance(from: location) < 2500, let area = nearest.area { return area }
        return trips.first?.city(on: now, calendar: region.calendar)?.name ?? region.displayName
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            MustIconView(.buscar, size: 16).foregroundStyle(Color.must.secondary)
            TextField("\(areaName) · \(openNearby.count) musts abertos", text: $query)
                .font(.must.archivo(14))
                .submitLabel(.search)
                .onSubmit(search)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .glass(cornerRadius: 20)
    }

    private var layersMenu: some View {
        Menu {
            ForEach(MapLayer.allCases) { layer in
                Button { toggle(layer) } label: {
                    Label(layer.label, systemImage: layers.contains(layer) ? "checkmark.circle.fill" : "circle")
                }
            }
            if let attribution = transit.attribution {
                Section { Text("metrô: \(attribution)") }
            }
        } label: {
            MustIconView(.camadas, size: 17)
                .foregroundStyle(Color.must.ink)
                .frame(width: 40, height: 40)
                .background(Color.clear.glass(cornerRadius: 20))
        }
        .accessibilityLabel("Camadas")
    }

    private func layerPill(_ layer: MapLayer) -> some View {
        let on = layers.contains(layer)
        return Text(layer.label)
            .font(.must.archivo(13, .semibold))
            .foregroundStyle(on ? .white : Color.must.ink)
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .background {
                if on { Capsule().fill(Color.must.ink).shadow(color: Color(hex: 0x121316, opacity: 0.14), radius: 8, y: 6) }
                else { Color.clear.glass(cornerRadius: 18) }
            }
    }

    // MARK: Card inferior

    @ViewBuilder private var bottomCard: some View {
        let selected = selectedId.flatMap { id in places.first { $0.id == id } }
        if let place = selected ?? nextStop?.place {
            let index = stops.firstIndex { $0.place?.id == place.id }
            placeCard(place, number: index.map { $0 + 1 }, stop: index.map { stops[$0] })
        } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(today == nil ? "Nenhum dia montado hoje" : "Dia feito 済").mustPlace()
                    Text(today == nil ? "monte o dia pra ver a rota e as paradas no mapa" : "todas as paradas de hoje têm 済").mustMeta()
                }
                if today == nil {
                    PrimaryButton("Montar o dia", icon: .montarAjustar, style: .dark) {
                        router.push(.montar(date: region.calendar.startOfDay(for: now)), on: .hoje)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glass(cornerRadius: 22)
        }
    }

    private func placeCard(_ place: Place, number: Int?, stop: Stop?) -> some View {
        let at = stop?.at ?? place.reservation?.at
        var meta = Text("")
        var leave: String?
        var pieces: [Text] = []
        if place.hasReservation(on: now, calendar: region.calendar), let r = place.reservation {
            let time = Text(region.timeString(r.at)).font(.must.mono(14, .semibold)).foregroundStyle(Color.must.ink)
            pieces.append(Text("reserva \(time)"))
        } else if let at {
            pieces.append(Text(region.timeString(at)).font(.must.mono(14, .semibold)).foregroundStyle(Color.must.ink))
        }
        if let current = services.location.current {
            let leg = DaySolver.leg(current.coordinate, place.coordinate, walkMax: walkMaxKm)
            let minutes = services.eta.minutes(from: current.coordinate, to: place.coordinate, transit: leg.mode == .metro) ?? leg.minutes
            pieces.append(Text(leg.mode == .walk ? "\(minutes) min a pé" : "metrô ~\(minutes) min"))
            if let at, RoutesService.leaveAt(at, travelMinutes: minutes) > now {
                leave = region.timeString(RoutesService.leaveAt(at, travelMinutes: minutes))
            }
        }
        if case .closed(.none, let opensAt?) = place.openState(at: now, timeZone: region.timeZone),
           let minutes = Settings.minutes(from: opensAt) {
            let nowMinutes = region.calendar.component(.hour, from: now) * 60 + region.calendar.component(.minute, from: now)
            let delta = minutes - nowMinutes
            pieces.append(Text(delta < 60 ? "abre em \(max(1, delta)) min" : "abre \(opensAt)"))
        }
        for (i, piece) in pieces.enumerated() { meta = i == 0 ? piece : Text("\(meta) · \(piece)") }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if let number {
                    Text("\(number)").font(.must.mono(13, .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(Circle().fill(stop?.done == true ? Color.must.green : Color.must.ink))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(place.name).font(.must.archivo(19, .semibold)).tracking(-0.2).foregroundStyle(Color.must.ink).lineLimit(1)
                        if let local = place.nameLocal {
                            Text(local).font(.must.kanji(12, bold: false)).foregroundStyle(Color.must.secondary).lineLimit(1)
                        }
                    }
                    meta.font(.must.archivo(13)).foregroundStyle(Color.must.secondary).lineLimit(2)
                }
                Spacer(minLength: 6)
                if let leave {
                    Text("saia \(leave)").font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.greenText)
                        .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Color.must.green))
                }
            }
            HStack(spacing: 8) {
                Button { MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit) } label: {
                    HStack(spacing: 7) { MustIconView(.rota, size: 15); Text("Apple Maps") }
                        .font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.ink)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .overlay(Capsule().strokeBorder(Color.must.lineStrong))
                }
                Button { MapsLinks.openGoogle(to: place.coordinate, mode: .transit) } label: {
                    Text("Google Maps").font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.ink)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .overlay(Capsule().strokeBorder(Color.must.lineStrong))
                }
                IconButton(.avancar, style: .dark, size: 42, label: "Abrir \(place.name)") {
                    router.push(.place(id: place.id), on: .mapa)
                }
            }
            .buttonStyle(MustPressStyle())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glass(cornerRadius: 22)
        .onTapGesture { router.push(.place(id: place.id), on: .mapa) }
    }

    // MARK: Ações

    private var metersPerPoint: Double? {
        guard let span, mapHeight > 0 else { return nil }
        return span.latitudeDelta * 111_000 / Double(mapHeight)
    }

    private func appear() {
        consumeOpenNow()
        requestRoutes()
        guard !didCenter else { return }
        didCenter = true
        centerOn(fallbackCenter, animated: false)
    }

    private func consumeOpenNow() {
        guard router.mapShowsOpenNow else { return }
        router.mapShowsOpenNow = false
        layers.insert(.openNow)
        selectedId = nil
        centerOn(here ?? fallbackCenter)
    }

    private func requestRoutes() {
        routes.request(stops: stops.compactMap(\.place), walkMaxKm: walkMaxKm)
    }

    private func toggle(_ layer: MapLayer) {
        if layers.contains(layer) { layers.remove(layer) } else { layers.insert(layer) }
    }

    private func toggleLock() {
        locked.toggle()
        if locked { centerOn(center ?? fallbackCenter) }
    }

    private func centerOn(_ coordinate: CLLocationCoordinate2D, animated: Bool = true) {
        let camera = MapCameraPosition.camera(MapCamera(centerCoordinate: coordinate, distance: Self.neighborhoodDistance))
        if animated { withAnimation(.snappy) { position = camera } } else { position = camera }
    }

    private func search() {
        let found = places.filter { $0.matches(query) }
        guard let first = found.first else { return }
        selectedId = first.id
        centerOn(first.coordinate)
    }
}

// MARK: - Peças

/// Parada: feita = 済 verde; próxima = preta com número; futura = branca com borda.
struct StopPin: View {
    var number: Int
    var done: Bool
    var isNext: Bool

    var body: some View {
        ZStack {
            if done {
                Circle().fill(Color.must.green)
                Text("済").font(.must.kanji(14)).foregroundStyle(Color.must.greenText)
            } else if isNext {
                Circle().fill(Color.must.ink)
                Text("\(number)").font(.must.mono(13, .semibold)).foregroundStyle(.white)
            } else {
                Circle().fill(.white)
                Circle().strokeBorder(Color.must.ink, lineWidth: 1.6)
                Text("\(number)").font(.must.mono(13, .semibold)).foregroundStyle(Color.must.ink)
            }
        }
        .frame(width: isNext ? 32 : 30, height: isNext ? 32 : 30)
        .shadow(color: Color(hex: 0x121316, opacity: 0.18), radius: 6, x: 0, y: 6)
    }
}

/// Must aberto fora do roteiro: anel azul 12 pt.
struct OpenRing: View {
    var selected = false

    var body: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(Color.must.blue, lineWidth: 1.6))
            .frame(width: selected ? 16 : 12, height: selected ? 16 : 12)
            .padding(10) // área de toque
            .contentShape(Circle())
            .shadow(color: Color(hex: 0x121316, opacity: 0.18), radius: 6, x: 0, y: 6)
    }
}

/// Você: ponto azul com halo.
struct YouDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.must.blue.opacity(0.18)).frame(width: 34, height: 34)
            Circle().fill(Color.must.blue).frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
        }
        .accessibilityLabel("Você")
    }
}

/// Estação: círculo branco com borda preta + nome.
struct StationDot: View {
    var name: String
    var showsLabel: Bool
    var isJapanese: Bool

    var body: some View {
        Circle()
            .fill(.white)
            .overlay(Circle().strokeBorder(Color.must.ink, lineWidth: 1.6))
            .frame(width: 9, height: 9)
            .overlay(alignment: .leading) {
                if showsLabel {
                    Text(name)
                        .font(isJapanese ? .must.kanji(11, bold: false) : .must.archivo(11))
                        .foregroundStyle(Color.must.secondary)
                        .fixedSize()
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.white.opacity(0.7)))
                        .offset(x: 10, y: -10)
                }
            }
            .accessibilityLabel("Estação \(name)")
    }
}

/// Escala fixa no canto: escolhe 300 m (ou o valor redondo mais perto) pro zoom atual.
struct ScaleBar: View {
    var metersPerPoint: Double?

    private static let steps: [Double] = [50, 100, 200, 300, 500, 1000, 2000, 5000, 10_000]

    var body: some View {
        if let mpp = metersPerPoint, mpp > 0 {
            let meters = Self.steps.min { abs($0 / mpp - 80) < abs($1 / mpp - 80) } ?? 300
            let width = min(160, max(24, meters / mpp))
            VStack(spacing: 2) {
                Text(meters >= 1000 ? "\(Int(meters / 1000)) km" : "\(Int(meters)) m")
                    .font(.must.mono(10, .semibold))
                    .foregroundStyle(Color.must.ink)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 0, y: 8))
                    p.addLine(to: CGPoint(x: width, y: 8)); p.addLine(to: CGPoint(x: width, y: 0))
                }
                .stroke(Color.must.ink, lineWidth: 1.4)
                .frame(width: width, height: 8)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.7)))
            .accessibilityLabel("Escala: \(Int(meters)) metros")
        }
    }
}
