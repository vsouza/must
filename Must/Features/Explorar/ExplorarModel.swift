import CoreLocation
import Foundation
import Observation

/// Estado do Explorar (prompt 31 · 8): o bairro da página, o trilho, o índice. Tudo calculado nos gatilhos (`refresh`), nunca
/// no `body`. Só lê o que está no aparelho; a camada "fora do board" vem do cache do Por perto (sem chamada nova).
@MainActor
@Observable
final class ExplorarModel {
    struct City: Hashable, Identifiable {
        var group: String
        var name: String
        var id: String { group }
    }

    /// O que o `refresh` lê (cópias, sem `@Model` dentro do que fica guardado).
    struct Inputs {
        var region: Region
        var now: Date
        var places: [Place]
        var gps: CLLocationCoordinate2D?
        /// Plano de hoje (aceito ou do motor).
        var plan: DayPlan?
        /// Bairros dos próximos dias montados (`areaIds` por dia).
        var upcoming: [(date: Date, areaIds: Set<String>)] = []
        var cities: [(group: String, name: String)] = []
        /// "Fora do board" que já está no cache do Por perto, por bairro (id do bairro → itens).
        var outside: [NearbyPlace] = []
        var openIds: Set<String>
        var distances: [String: Double]
    }

    private(set) var cities: [City] = []
    var cityGroup: String = ""
    /// Bairro da página.
    private(set) var areaId: String?
    private(set) var stations: [ExplorarStation] = []
    private(set) var area: Area?
    /// Itens do bairro, sem camadas aplicadas.
    private(set) var items: [ExplorarItem] = []
    /// Paradas de hoje dentro do bairro, em ordem (a trilha).
    private(set) var trail: [CLLocationCoordinate2D] = []
    private(set) var hereAreaId: String?
    private(set) var planAreaId: String?
    private(set) var tripStarted = true
    /// Linhas de trem do bairro ("JY", "JC"…), pelos vizinhos da tabela.
    private(set) var lineCodes: [String] = []
    private(set) var youCoordinate: CLLocationCoordinate2D?
    /// Fotos do Google de cada Must do bairro (só as refs; o arquivo só aparece se já está no disco).
    private(set) var photoRefs: [String: [PlacePhotoRef]] = [:]
    private(set) var googleIds: [String: String] = [:]
    /// Hora/dia dos bairros de dias montados: "dia 7" em outra cidade (data do primeiro dia montado que passa pelo bairro).
    private(set) var upcomingDates: [String: Date] = [:]

    var layers: Set<ExplorarLayer> = ExplorarLayer.standard

    /// "Fora do board" ao vivo: uma busca por bairro por sessão (`ExplorarOutsidePolicy`), nunca offline nem com Pouco Dados.
    private(set) var outsideState: ExplorarOutsideState = .idle
    static var outsidePolicy = ExplorarOutsidePolicy()

    func outsideDecision(area id: String, region: Region, status: Connectivity.Status) -> ExplorarOutsidePolicy.Decision {
        let decision = Self.outsidePolicy.decide(area: id, region: region, status: status)
        switch decision {
        case .fetch: outsideState = .loading
        case .offline: outsideState = .offline
        case .lowData: outsideState = .lowData
        case .alreadyThisSession: outsideState = .loaded
        }
        return decision
    }

    func outsideFinished() { outsideState = .loaded }

    /// Bairro escolhido à mão (trilho, deslize); `nil` = o inicial (GPS › dia › primeiro).
    @ObservationIgnored private var chosen: String?
    @ObservationIgnored private var lastInputs: Inputs?

    var index: Int { stations.firstIndex { $0.id == areaId } ?? 0 }
    var count: Int { stations.count }
    var isHere: Bool { areaId != nil && areaId == hereAreaId }

    var station: ExplorarStation? { stations.first { $0.id == areaId } }

    /// O que a lista mostra com as camadas atuais (numerado), sem recorte de tela.
    var listed: [ExplorarItem] { ExplorarLayers.listed(items, layers: layers) }

    var counts: (own: Int, outside: Int, open: Int) { ExplorarLayers.counts(ExplorarLayers.filter(items, layers: ExplorarLayer.standard)) }

    func select(area id: String) {
        chosen = id
        if let group = AreaCatalog.areas(for: lastInputs?.region ?? .jp).first(where: { $0.id == id }).map({ AreaCatalog.cityGroup(forCityId: $0.cityId) }) {
            cityGroup = group
        }
        if let inputs = lastInputs { refresh(inputs) }
    }

    func select(city group: String) {
        cityGroup = group
        chosen = nil
        if let inputs = lastInputs { refresh(inputs) }
    }

    func refresh(_ i: Inputs) {
        lastInputs = i
        let areas = AreaCatalog.areas(for: i.region)
        let assigner = AreaAssigner(areas: areas)
        youCoordinate = i.gps
        planAreaId = i.plan?.area

        // Cidades: as da viagem que têm bairros na tabela, na ordem das cidades; senão as da tabela.
        let groups = Dictionary(grouping: areas, by: { AreaCatalog.cityGroup(forCityId: $0.cityId) })
        var found: [City] = []
        for (group, name) in i.cities where groups[group] != nil && !found.contains(where: { $0.group == group }) {
            found.append(City(group: group, name: name))
        }
        for group in groups.keys.sorted() where !found.contains(where: { $0.group == group }) {
            found.append(City(group: group, name: group.capitalized))
        }
        cities = found

        // GPS: o bairro de onde você está, se for da cidade da viagem.
        hereAreaId = nil
        if let gps = i.gps, let here = CurrentAreaService.curated(CLLocation(latitude: gps.latitude, longitude: gps.longitude), in: areas) {
            hereAreaId = here.id
        }
        tripStarted = i.plan != nil || hereAreaId != nil

        // Cidade da página: a escolhida no segmentado; senão a do GPS ou do dia; senão a primeira.
        if cityGroup.isEmpty || !found.contains(where: { $0.group == cityGroup }) {
            let seed = chosen ?? hereAreaId ?? i.plan?.area
            let seedGroup = seed.flatMap { id in areas.first { $0.id == id } }.map { AreaCatalog.cityGroup(forCityId: $0.cityId) }
            cityGroup = seedGroup ?? found.first?.group ?? ""
        }

        // Quais bairros têm Musts, quais são de hoje (com a hora) e quais estão todos feitos.
        var byArea: [String: [Place]] = [:]
        for place in i.places {
            guard let id = assigner.areaId(name: place.area, cityId: place.cityId, lat: place.lat, lng: place.lng) else { continue }
            byArea[id, default: []].append(place)
        }
        var today: [String: String?] = [:]
        let planStops = i.plan?.stops ?? []
        for stop in planStops where stop.kind != .micro {
            guard let id = stop.area ?? stop.placeId.flatMap({ pid in i.places.first { $0.id == pid } }).flatMap({
                assigner.areaId(name: $0.area, cityId: $0.cityId, lat: $0.lat, lng: $0.lng) }) else { continue }
            if today[id] == nil { today[id] = .some(i.region.hourLabel(stop.start)) }
        }
        for upcomingDay in i.upcoming {
            for id in upcomingDay.areaIds where today[id] == nil { today[id] = .some(nil) }
        }
        let done = Set(byArea.filter { !$0.value.isEmpty && $0.value.allSatisfy(\.isDone) }.keys)
        let origin = ExplorarRail.origin(hereId: hereAreaId, planAreaId: i.plan?.area, areas: areas, cityGroup: cityGroup)
        stations = ExplorarRail.stations(areas: areas, cityGroup: cityGroup, originId: origin, populated: Set(byArea.keys),
                                         today: today, done: done, hereId: hereAreaId)

        let wanted = chosen.flatMap { id in stations.contains { $0.id == id } ? id : nil }
        areaId = wanted ?? origin.flatMap { id in stations.contains { $0.id == id } ? id : nil } ?? stations.first?.id
        area = areas.first { $0.id == areaId }
        guard let area else { items = []; trail = []; lineCodes = []; return }

        // Origem das distâncias: o GPS só se estiver na cidade da página; senão o centro do bairro.
        let centroid = area.centroid.clCoordinate
        let gpsHere = i.gps.flatMap { DaySolver.streetKm($0, centroid) < WantOrigin.cityKm ? $0 : nil }
        let origin2D = gpsHere ?? centroid
        let originLoc = CLLocation(latitude: origin2D.latitude, longitude: origin2D.longitude)
        let planIds = Set(planStops.compactMap(\.placeId))

        var built: [ExplorarItem] = []
        photoRefs = [:]
        googleIds = [:]
        for place in byArea[area.id] ?? [] {
            if !place.photoRefs.isEmpty { photoRefs[place.id] = place.photoRefs }
            if let gid = place.placeId { googleIds[place.id] = gid }
        }
        upcomingDates = [:]
        for day in i.upcoming.sorted(by: { $0.date < $1.date }) {
            for id in day.areaIds where upcomingDates[id] == nil { upcomingDates[id] = day.date }
        }
        for place in byArea[area.id] ?? [] where place.lat != 0 || place.lng != 0 {
            let open = i.openIds.contains(place.id)
            let tone: ExplorarItem.Tone = open && !place.isDone ? .own : .paper
            let trust = place.trust
            let planStart = planStops.first { $0.placeId == place.id && $0.kind != .micro }?.start
            built.append(ExplorarItem(
                id: place.id, placeId: place.id, name: place.name, lat: place.lat, lng: place.lng, tone: tone, isOpen: open,
                done: place.isDone, inPlan: planIds.contains(place.id), meta: Self.meta(place, open: open, region: i.region, now: i.now),
                meters: i.distances[place.id] ?? place.location.distance(from: originLoc),
                planTime: planStart.map { i.region.timeString($0) }, hoursConfirmed: trust.hoursConfirmed))
        }
        let boardNames = Set(i.places.map { $0.name.lowercased() })
        for outside in i.outside where !outside.sources.contains(.board) && !boardNames.contains(outside.name.lowercased()) {
            let here = CLLocation(latitude: outside.lat, longitude: outside.lng)
            guard here.distance(from: CLLocation(latitude: centroid.latitude, longitude: centroid.longitude)) <= 1_200 else { continue }
            built.append(ExplorarItem(
                id: "out-\(outside.id)", placeId: nil, name: outside.name, lat: outside.lat, lng: outside.lng, tone: .outside,
                isOpen: outside.openNow == true, done: false, inPlan: false, meta: Self.outsideMeta(outside),
                meters: here.distance(from: originLoc), googleId: outside.googlePlaceId, hoursConfirmed: outside.openNow != nil))
        }
        items = built

        // Trilha: as paradas de hoje que caem no bairro, na ordem do dia.
        trail = planStops.filter { $0.kind != .micro }.compactMap { stop -> CLLocationCoordinate2D? in
            guard let pid = stop.placeId, let place = i.places.first(where: { $0.id == pid }),
                  assigner.areaId(name: place.area, cityId: place.cityId, lat: place.lat, lng: place.lng) == area.id else { return nil }
            return place.coordinate
        }

        var codes: [String] = []
        for n in area.neighbors {
            if let code = n.line?.code, !codes.contains(code) { codes.append(code) }
        }
        lineCodes = codes
    }

    // MARK: Textos

    static func meta(_ place: Place, open: Bool, region: Region, now: Date) -> String {
        var parts: [String] = ["seu Must \(place.list?.name.lowercased() ?? "")".trimmingCharacters(in: .whitespaces)]
        if let q = place.queueMinutes, q > 0 { parts.append("fila \(q) min") }
        if place.isDone { parts.append("feito") }
        else if case .open(let until) = place.openState(at: now, timeZone: region.timeZone) { parts.append(until.map { "fecha \($0)" } ?? "aberto") }
        else if case .closed(_, let at) = place.openState(at: now, timeZone: region.timeZone) { parts.append(at.map { "abre \($0)" } ?? "fechado") }
        if !place.trust.hoursConfirmed { parts.append(PlaceTrust.hoursEstimated) }
        _ = open
        return parts.joined(separator: " · ")
    }

    static func outsideMeta(_ p: NearbyPlace) -> String {
        var parts = ["fora do board"]
        if let rating = p.rating { parts.append("★ \(String(format: "%.1f", rating).replacingOccurrences(of: ".", with: ","))") }
        if p.openNow == true { parts.append("aberto") } else if p.openNow == false { parts.append("fechado") }
        return parts.joined(separator: " · ")
    }
}

extension Region {
    /// "19h" / "19h30" no fuso da região.
    func hourLabel(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return m == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", m))"
    }
}
