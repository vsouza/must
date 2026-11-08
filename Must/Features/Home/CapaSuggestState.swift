import CoreLocation
import Foundation
import Observation

/// "Agora vale" da capa (prompt 26): liga o board, o plano, o tempo, o sol, os eventos e o cache de "por perto" no
/// `SuggestionEngine`. Recalcula nos gatilhos da capa (aparecer, minuto, salvar, posição, voltar pra frente); nunca no `body`
/// e nunca com rede (só o que já está no aparelho).
@MainActor
@Observable
final class CapaSuggestState {
    private(set) var cards: [Suggestion] = []
    private(set) var stateLine = ""
    private(set) var night: SuggestCopy.Night?
    /// Bairro de foco do card da noite (`Area.id`), pro Montar.
    private(set) var nightAreaId: String?
    private(set) var sources: [String] = []
    /// Eventos de hoje (feeds + board) pro chip "Em cartaz".
    private(set) var showsToday = 0
    /// A linha "Em cartaz" do índice (nil = sem evento hoje).
    private(set) var showLine: CorteShowLine?
    /// O numeral da capa do corte: quantas coisas abertas a 10 min (board + fora do board).
    private(set) var openNearby = 0
    /// Perto (10 min) mas sem horário confirmado: não conta como aberto.
    private(set) var unconfirmedNearby = 0
    /// Cache de "por perto" da célula atual (fora do board).
    @ObservationIgnored var indicated: [NearbyPlace] = []
    @ObservationIgnored private let prefs = SuggestPrefs()

    struct Inputs {
        var region: Region
        var now: Date
        var here: CLLocationCoordinate2D?
        var currentArea: Area?
        var places: [Place]
        var plan: DayPlan?
        var dayNow: DayNow?
        /// O relógio único do dia (ajuste, quantas faltam).
        var clock: DayClock? = nil
        var events: [ShowEvent]
        var boardShows: [ShowEvent]
        var forecast: DayWeather?
        var eventSourceName: (String) -> String?
    }

    /// O dia aceito não vale mais na capa: sem dia, ou você saiu do bairro do plano.
    static func isSmart(plan: DayPlan?, currentArea: Area?) -> Bool {
        guard let plan else { return true }
        guard let here = currentArea?.id, let planArea = plan.area else { return false }
        return here != planArea
    }

    /// Minutos a pé/trem daqui até a parada do plano, só quando ela está longe (≥ 10 min): "agora: X · a 18 min daqui".
    static func awayMinutes(from here: CLLocationCoordinate2D, to stop: SuggestPlanStop?) -> Int? {
        guard let stop, let lat = stop.lat, let lng = stop.lng, lat != 0 || lng != 0 else { return nil }
        let minutes = DaySolver.leg(here, CLLocationCoordinate2D(latitude: lat, longitude: lng), walkMax: 1.5).minutes
        return minutes >= 10 ? minutes : nil
    }

    func recompute(_ i: Inputs) {
        let region = i.region
        let tz = region.timeZone
        let places = i.places.map { Self.suggestPlace($0, now: i.now, tz: tz) }
        let areas = AreaCatalog.areas(for: region)
        let here = i.here ?? i.currentArea?.centroid.clCoordinate ?? region.defaultCenter

        var planStop: SuggestPlanStop?
        if i.plan != nil, let now = i.dayNow {
            let verb = now.arriveBy != nil ? "chegue" : "saia"
            planStop = SuggestPlanStop(id: now.current.id, placeId: now.current.placeId, label: DayText.head(now.current.label),
                                       action: "\(verb) \(region.timeString(now.arriveBy ?? now.leaveAt))",
                                       lat: now.current.lat, lng: now.current.lng,
                                       lateSince: nil)
        }

        if let h = i.here, let stop = planStop { planStop?.away = Self.awayMinutes(from: h, to: stop) }
        let sun = SunService.day(i.now, here, timeZone: tz)
        var light: SuggestLight?
        if let golden = sun.goldenPM, golden.end > i.now {
            light = SuggestLight(start: golden.start, end: golden.end, isToday: true)
        } else if let tomorrow = region.calendar.date(byAdding: .day, value: 1, to: i.now),
                  let golden = SunService.day(tomorrow, here, timeZone: tz).goldenPM {
            light = SuggestLight(start: golden.start, end: golden.end, isToday: false)
        }

        var rain: Int?
        if let hours = i.forecast?.hours {
            rain = hours.filter { $0.time.addingTimeInterval(3600) > i.now && $0.time < i.now.addingTimeInterval(2 * 3600) && ($0.precipProb ?? 0) >= 60 }
                .map { max(0, Int($0.time.timeIntervalSince(i.now) / 60)) }.min()
        }

        let events = EventsMapping.dedupe(i.boardShows + i.events)
        let inputs = SuggestInputs(region: region, now: i.now, here: here, places: places, plan: planStop,
                                   events: events, indicated: indicated,
                                   boardNames: Set(places.map { $0.name.lowercased() }), rainInMinutes: rain, light: light,
                                   taste: Self.taste(places), dismissed: prefs.dismissed(region: region, now: i.now),
                                   shownEarlier: prefs.shownEarlier(region: region, now: i.now))
        cards = SuggestionEngine.suggest(inputs)
        prefs.markShown(cards.map(\.id), region: region, now: i.now)

        // O numeral e o texto da capa contam a mesma coisa: abertos (horário confirmado) a 10 min. O que não tem horário
        // confirmado não entra como "aberto"; vai à parte ("sem horário").
        let counts = CorteCount.counts(places: places, indicated: indicated, here: here)
        openNearby = counts.open
        unconfirmedNearby = counts.unconfirmed
        var eventCoords: [String: CLLocationCoordinate2D] = [:]
        for e in events { if let id = e.placeId, let p = i.places.first(where: { $0.id == id }) { eventCoords[e.id] = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng) } }
        showLine = CorteShowLine.make(events: events, now: i.now, region: region, here: here, coordinates: eventCoords)
        if showLine?.countsNearby == true { openNearby += 1 }
        stateLine = SuggestCopy.stateLine(region: region, now: i.now, plan: planStop, openNearby: openNearby, unconfirmed: unconfirmedNearby,
                                          adjustedRemaining: i.clock?.adjusted == true ? i.clock?.remaining : nil,
                                          awayMinutes: planStop?.away)

        let focus = i.currentArea ?? areas.first { $0.id == i.plan?.area }
        let neighbor = focus?.neighbors.min { $0.minutes < $1.minutes }.flatMap { n in areas.first { $0.id == n.areaId } }
        night = SuggestCopy.night(region: region, now: i.now, areas: [focus?.name, neighbor?.name].compactMap { $0 })
        nightAreaId = focus?.id
        sources = SuggestCopy.sources(cards, eventSourceName: i.eventSourceName)
        showsToday = events.filter { EventsMapping.isOn($0, day: i.now, calendar: region.calendar) }.count
    }

    /// "Não me sugere isso hoje": some agora e não volta até amanhã.
    func dismiss(_ card: Suggestion, region: Region, now: Date) {
        prefs.dismiss(card.id, region: region, now: now)
        cards.removeAll { $0.id == card.id }
    }

    static func suggestPlace(_ p: Place, now: Date, tz: TimeZone) -> SuggestPlace {
        SuggestPlace(id: p.id, name: p.name, listName: p.list?.name ?? "", color: p.list?.colorRaw ?? "",
                     kind: p.list?.kind ?? .place, sub: p.sub, lat: p.lat, lng: p.lng, done: p.isDone,
                     state: p.openState(at: now, timeZone: tz), windows: Set(p.windowsRaw))
    }

    /// As duas cores de lista mais usadas (feitos; sem nenhum, as maiores): 2 e 1.
    static func taste(_ places: [SuggestPlace]) -> [String: Int] {
        var done: [String: Int] = [:], all: [String: Int] = [:]
        for p in places where !p.color.isEmpty {
            all[p.color, default: 0] += 1
            if p.done { done[p.color, default: 0] += 1 }
        }
        let base = done.isEmpty ? all : done
        let top = base.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(2)
        return Dictionary(uniqueKeysWithValues: top.enumerated().map { ($0.element.key, 2 - $0.offset) })
    }
}
