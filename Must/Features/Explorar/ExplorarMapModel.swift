import CoreLocation
import Foundation
import Observation

/// Estado da raiz do Explorar (prompt 32 §4): os pontos do mapa, as camadas, o filtro por lista, o "Ver no mapa", o que está na
/// tela e os 3 cartões "Agora vale" do **centro do mapa**. Tudo calculado nos gatilhos (`refresh`, câmera parada), nunca no
/// `body`. O ranker roda fora do main, com debounce de 400 ms depois que a câmera para.
@MainActor
@Observable
final class ExplorarMapModel {
    /// O que o `refresh` lê (o `@Model` só é lido aqui dentro; o que fica guardado são cópias).
    struct Inputs {
        var region: Region
        var now: Date
        var places: [Place]
        var lists: [(id: String, name: String)]
        /// Paradas do dia aceito de hoje, em ordem.
        var stops: [(placeId: String, at: Date, done: Bool)]
        /// Eventos de hoje (feeds + board), já sem repetição.
        var events: [ShowEvent]
        var gps: CLLocationCoordinate2D?
        /// Centro da cidade de hoje (pra saber se o GPS está na cidade da viagem).
        var cityCenter: CLLocationCoordinate2D
    }

    private(set) var region: Region = .jp
    private(set) var items: [ExplorarMapItem] = []
    private(set) var indicatedItems: [ExplorarMapItem] = []
    private(set) var layers: Set<ExplorarMapLayer> = ExplorarMapLayer.defaults
    private(set) var filter = MapMustFilter()
    private(set) var showcase: MapShowcase?
    private(set) var selectedId: String?

    /// Derivados (recalculados por `rebuild`).
    private(set) var shown: [ExplorarMapItem] = []
    private(set) var pins: [MapPin] = []
    private(set) var routeDone: [[CLLocationCoordinate2D]] = []
    private(set) var routeFuture: [[CLLocationCoordinate2D]] = []
    private(set) var chips: [MapMustFilter.Count] = []
    private(set) var visible: [ExplorarMapItem] = []
    private(set) var sections: [ExplorarMapFilter.Section] = []

    /// Centro do mapa (o contexto do Explorar) e o bairro dele.
    private(set) var center: CLLocationCoordinate2D?
    private(set) var centerArea: Area?
    private(set) var rect: GeoRect?
    /// Os 3 cartões do ranker pro centro do mapa.
    private(set) var cards: [Suggestion] = []
    private(set) var ranked = false
    /// GPS dentro da cidade da viagem (as distâncias saem dele; senão do centro do mapa).
    private(set) var gpsInCity: CLLocationCoordinate2D?

    private(set) var photoRefs: [String: [PlacePhotoRef]] = [:]
    private(set) var googleIds: [String: String] = [:]
    private(set) var indicatedState: ExplorarOutsideState = .idle

    @ObservationIgnored private var lists: [(id: String, name: String)] = []
    @ObservationIgnored private var showcaseIds: Set<String>?
    @ObservationIgnored private var showcaseExtra: [ExplorarMapItem] = []
    @ObservationIgnored private var suggestPlaces: [SuggestPlace] = []
    @ObservationIgnored private var events: [ShowEvent] = []
    @ObservationIgnored private var indicatedRaw: [String: NearbyPlace] = [:]
    @ObservationIgnored private var boardNames: Set<String> = []
    @ObservationIgnored private var now = Date()
    @ObservationIgnored private var rankedCenter: CLLocationCoordinate2D?
    @ObservationIgnored private var rankTask: Task<Void, Never>?
    @ObservationIgnored var indicatedPolicy = ExplorarOutsidePolicy()

    // MARK: Entrada

    func refresh(_ i: Inputs) {
        region = i.region
        now = i.now
        lists = i.lists
        let tz = i.region.timeZone
        let minutesNow = i.region.calendar.component(.hour, from: i.now) * 60 + i.region.calendar.component(.minute, from: i.now)
        let goldenAt = i.gps ?? i.cityCenter
        let golden = SunService.day(i.now, goldenAt, timeZone: tz).goldenPM.map { $0.start.addingTimeInterval(-45 * 60) <= i.now && i.now <= $0.end } ?? false
        gpsInCity = i.gps.flatMap { DaySolver.streetKm($0, i.cityCenter) < WantOrigin.cityKm ? $0 : nil }

        var stopIndex: [String: (number: Int, at: Date, done: Bool)] = [:]
        for (n, stop) in i.stops.enumerated() where stopIndex[stop.placeId] == nil {
            stopIndex[stop.placeId] = (n + 1, stop.at, stop.done)
        }
        let nextId = i.stops.first { !$0.done }?.placeId

        var built: [ExplorarMapItem] = []
        var refs: [String: [PlacePhotoRef]] = [:]
        var gids: [String: String] = [:]
        for place in i.places where place.lat != 0 || place.lng != 0 {
            let state = place.openState(at: i.now, timeZone: tz)
            let stop = stopIndex[place.id]
            var reason = ExplorarModel.meta(place, open: state.isOpen, region: i.region, now: i.now)
            if let stop { reason = "parada \(stop.number) · \(i.region.timeString(stop.at)) · " + reason }
            built.append(ExplorarMapItem(
                id: place.id, kind: .must, name: place.name, lat: place.lat, lng: place.lng, placeId: place.id,
                listId: place.list?.id, listName: place.list.map { MapMustFilter.label($0.name) } ?? "", color: place.list?.color,
                done: place.isDone || stop?.done == true, stopNumber: stop?.number, isNextStop: place.id == nextId,
                stopTime: stop.map { i.region.timeString($0.at) }, open: Self.pinState(state, minutesNow: minutesNow),
                hoursConfirmed: place.trust.hoursConfirmed, golden: golden && place.list?.kind == .photo && !place.isDone,
                reason: reason, googleId: place.placeId))
            if !place.photoRefs.isEmpty { refs[place.id] = place.photoRefs }
            if let gid = place.placeId { gids[place.id] = gid }
        }
        let byId = Dictionary(i.places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for event in i.events {
            let place = event.placeId.flatMap { byId[$0] }
            guard let lat = event.lat ?? place?.lat, let lng = event.lng ?? place?.lng, lat != 0 || lng != 0 else { continue }
            var parts = ["evento"]
            if let start = event.startsAt { parts.append(i.region.timeString(start)) }
            if let venue = event.venue ?? place?.name { parts.append(venue) }
            built.append(ExplorarMapItem(id: "ev-\(event.id)", kind: .event, name: event.title, lat: lat, lng: lng, placeId: place?.id,
                                         reason: parts.joined(separator: " · "), eventId: event.id))
        }
        items = built
        photoRefs = refs
        googleIds = gids
        events = i.events
        suggestPlaces = i.places.map { CapaSuggestState.suggestPlace($0, now: i.now, tz: tz) }
        boardNames = Set(i.places.map { $0.name.lowercased() })
        rebuildIndicated()
        if let showcase { applyShowcase(showcase) }
        rebuild()
    }

    /// `OpenState` do lugar → o que o pino mostra (fecha em ≤ 30 min = arco).
    static func pinState(_ state: OpenState, minutesNow: Int) -> PinOpenState {
        switch state {
        case .open(let until):
            guard let until, let close = Settings.minutes(from: until) else { return .open }
            var left = close - minutesNow
            if left < 0 { left += 1440 }
            return left <= 30 ? .closingSoon(remaining: Double(left) / 30) : .open
        case .closed: return .closed
        case .unknown: return .unknown
        }
    }

    // MARK: Controles

    func toggle(layer: ExplorarMapLayer) {
        layers = ExplorarMapLayer.toggled(layers, layer)
        rebuild()
    }

    func setLayer(_ layer: ExplorarMapLayer, on: Bool) {
        if layers.contains(layer) != on { toggle(layer: layer) }
    }

    func toggle(list id: String) {
        filter.toggle(id)
        filter.save(region)
        rebuild()
    }

    func showAllLists() {
        filter.showAll()
        filter.save(region)
        rebuild()
    }

    func loadFilter(_ region: Region) {
        filter = MapMustFilter.load(region)
        rebuild()
    }

    func select(_ id: String?) {
        guard id != selectedId else { return }
        selectedId = id
        rebuildPins()
    }

    var selected: ExplorarMapItem? {
        guard let selectedId else { return nil }
        return (items + indicatedItems + showcaseExtra).first { $0.id == selectedId }
    }

    /// "Ver no mapa": só estes pinos. Devolve os pontos a enquadrar.
    @discardableResult
    func setShowcase(_ showcase: MapShowcase?) -> [MapCameraCommand.Coordinate] {
        rankedCenter = nil
        self.showcase = showcase
        guard let showcase else {
            showcaseIds = nil
            showcaseExtra = []
            rebuild()
            return []
        }
        applyShowcase(showcase)
        selectedId = nil
        rebuild()
        return ExplorarShowcaseLogic.fitPoints(shown, near: center)
    }

    private func applyShowcase(_ showcase: MapShowcase) {
        let result = ExplorarShowcaseLogic.items(showcase, board: items)
        showcaseIds = result.ids
        showcaseExtra = result.extra
    }

    // MARK: Câmera

    /// A câmera parou: a lista grande passa a ser o que está na tela; o ranker recalcula (debounce) se o centro andou.
    func cameraIdle(center: CLLocationCoordinate2D, rect: GeoRect?) {
        self.center = center
        if let rect { self.rect = rect }
        let area = CurrentAreaService.curated(CLLocation(latitude: center.latitude, longitude: center.longitude), in: AreaCatalog.areas(for: region))
        if area?.id != centerArea?.id { centerArea = area }
        rebuildVisible()
        if ExplorarCenter.moved(from: rankedCenter, to: center) { scheduleRank() }
    }

    /// O ranker do centro do mapa, fora do main, 400 ms depois do último movimento.
    func scheduleRank(debounce: Duration = ExplorarCenter.debounce) {
        guard let center else { return }
        rankTask?.cancel()
        let inputs = rankInputs(center: center)
        rankTask = Task { [weak self] in
            if debounce > .zero { try? await Task.sleep(for: debounce) }
            guard !Task.isCancelled else { return }
            let cards = await Task.detached(priority: .userInitiated) { Self.rank(inputs) }.value
            guard !Task.isCancelled, let self else { return }
            self.cards = cards
            self.ranked = true
            self.rankedCenter = center
        }
    }

    /// Os 3 cartões (sem o "plano": o mapa responde "o que tem aqui", não "o que vem agora").
    nonisolated static func rank(_ inputs: SuggestInputs) -> [Suggestion] {
        Array(SuggestionEngine.suggest(inputs).filter { $0.kind != .plan }.prefix(3))
    }

    func rankInputs(center: CLLocationCoordinate2D) -> SuggestInputs {
        let tz = region.timeZone
        let sun = SunService.day(now, center, timeZone: tz)
        var light: SuggestLight?
        if let golden = sun.goldenPM, golden.end > now { light = SuggestLight(start: golden.start, end: golden.end, isToday: true) }
        let indicated = Array(indicatedRaw.values).sorted { $0.id < $1.id }
        return SuggestInputs(region: region, now: now, here: center, places: suggestPlaces, plan: nil, events: events,
                             indicated: indicated, boardNames: boardNames, rainInMinutes: nil, light: light,
                             taste: CapaSuggestState.taste(suggestPlaces), dismissed: SuggestPrefs().dismissed(region: region, now: now))
    }

    // MARK: Indicados

    /// Junta o que veio do Por perto (cache ou busca) e refaz os pinos de fora.
    func addIndicated(_ places: [NearbyPlace]) {
        var changed = false
        for p in places where !p.sources.contains(.board) && indicatedRaw[p.id] == nil {
            indicatedRaw[p.id] = p
            changed = true
        }
        guard changed else { return }
        rebuildIndicated()
        rebuild()
        if center != nil { scheduleRank(debounce: .zero) }
    }

    func setIndicatedState(_ state: ExplorarOutsideState) { indicatedState = state }

    /// Link do evento (feed), pra "Abrir" quando o evento não é de um lugar do board.
    func eventURL(_ id: String) -> URL? { events.first { $0.id == id }?.url }

    private func rebuildIndicated() {
        indicatedItems = indicatedRaw.values
            .filter { !boardNames.contains($0.name.lowercased()) && ($0.lat != 0 || $0.lng != 0) }
            .sorted { $0.id < $1.id }
            .map { p in
                ExplorarMapItem(id: "out-\(p.id)", kind: .indicated, name: p.name, lat: p.lat, lng: p.lng,
                                open: p.openNow == true ? .open : (p.openNow == false ? .closed : .unknown),
                                hoursConfirmed: p.openNow != nil, reason: ExplorarModel.outsideMeta(p), googleId: p.googlePlaceId)
            }
    }

    // MARK: Derivados

    private func rebuild() {
        let all = items + indicatedItems + showcaseExtra
        shown = ExplorarMapFilter.shown(all, layers: layers, filter: filter, showcase: showcaseIds)
        chips = ExplorarMapFilter.chips(items: items, lists: lists)
        let route = showcaseIds == nil ? ExplorarMapPins.route(shown, layers: layers) : (done: [], future: [])
        routeDone = route.done
        routeFuture = route.future
        if let selectedId, !shown.contains(where: { $0.id == selectedId }) { self.selectedId = nil }
        rebuildPins()
        rebuildVisible()
    }

    private func rebuildPins() {
        pins = ExplorarMapPins.pins(shown, layers: showcaseIds == nil ? layers : [.musts], selected: selectedId)
    }

    private func rebuildVisible() {
        guard let rect, let center else {
            visible = []
            sections = []
            return
        }
        visible = ExplorarMapFilter.visible(shown, in: rect, center: center)
        sections = ExplorarMapFilter.sections(visible, lists: lists)
    }

    /// De onde as distâncias saem: o GPS se você está na cidade; senão o centro do mapa.
    var distanceOrigin: CLLocationCoordinate2D? { gpsInCity ?? center }

    func meters(to item: ExplorarMapItem) -> Double? {
        guard let o = distanceOrigin else { return nil }
        return CLLocation(latitude: o.latitude, longitude: o.longitude).distance(from: CLLocation(latitude: item.lat, longitude: item.lng))
    }

    func meters(to c: CLLocationCoordinate2D) -> Double? {
        guard let o = distanceOrigin else { return nil }
        return CLLocation(latitude: o.latitude, longitude: o.longitude).distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }

    /// "600 m · 8 min a pé".
    static func distanceLine(_ meters: Double?) -> String? {
        guard let meters else { return nil }
        let d = ExplorarTravel.distance(meters)
        return "\(d.value) \(d.unit) · \(ExplorarTravel.caption(meters))"
    }

    /// "Agora vale · 3 perto" / "Agora vale · nada perto daqui".
    var summaryLine: String {
        guard ranked else { return "Agora vale · calculando…" }
        return cards.isEmpty ? "Agora vale · nada perto daqui" : "Agora vale · \(cards.count) perto"
    }
}
