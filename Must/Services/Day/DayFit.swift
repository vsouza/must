import CoreLocation
import Foundation

/// "Encaixar hoje" do Quero… (prompt 25 · A.3): um lugar novo entra no dia como parada de 25 min num buraco que já existe
/// entre duas paradas (com o deslocamento e a margem do "saia às"), então **nada mais se move** — âncoras, Musts e
/// micro-paradas ficam onde estavam. Puro e determinístico, como as micro-paradas (`MicroStops.fit`).
enum DayFit {
    /// Minutos lá dentro.
    static let minutes = 25
    /// Depois disso não encaixa nada novo (o dia acaba; o último trem manda).
    static let latestEnd = (hour: 22, minute: 30)
    /// Desvio que ainda conta como "no caminho".
    static let onTheWayMinutes = 10

    struct Slot: Hashable, Sendable {
        var start: Date
        var end: Date
        /// Parada antes e depois do encaixe (`nil` = começo/fim do dia).
        var after: DayStop?
        var before: DayStop?
        /// Minutos de quem está antes (ou de onde você está) até o lugar.
        var travelIn: Int
        /// Minutos a mais no caminho por causa do desvio.
        var detour: Int
    }

    /// Onde cabe hoje: o buraco mais cedo no caminho (desvio ≤ 10 min), senão o de menor desvio. `plan` nil ou vazio = sai daqui, agora.
    /// `closesAt`: fechamento conhecido do lugar (a parada tem que acabar antes).
    static func slot(at here: CLLocationCoordinate2D, plan: DayPlan?, now: Date, region: Region, origin: CLLocationCoordinate2D,
                     walkMaxKm: Double = 1.5, closesAt: Date? = nil) -> Slot? {
        let day = region.calendar.startOfDay(for: plan?.date ?? now)
        let input = DayComposer.Input(date: day, region: region, stops: [], hotel: origin, walkMaxKm: walkMaxKm, budget: plan?.budget ?? 0)
        let latest = day.addingTimeInterval(Double(latestEnd.hour * 60 + latestEnd.minute) * 60)
        let length = Double(minutes) * 60
        func ok(_ start: Date) -> Bool {
            let end = start.addingTimeInterval(length)
            return start >= now.addingTimeInterval(-60) && end <= latest && end <= (closesAt ?? .distantFuture)
        }
        func travel(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Int { MicroStops.travel(a, b, input) }

        let timeline = (plan?.stops ?? []).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        guard let first = timeline.first, let last = timeline.last else {
            let start = MicroStops.roundUp(now.addingTimeInterval(Double(travel(origin, here)) * 60), day: day)
            guard ok(start) else { return nil }
            return Slot(start: start, end: start.addingTimeInterval(length), after: nil, before: nil, travelIn: travel(origin, here), detour: 0)
        }
        var options: [Slot] = []
        // Antes da primeira parada, saindo daqui.
        if first.start > now, let start = MicroStops.fit(minutes, at: here, prev: nil, next: first, floor: now, latest: false, input: input), ok(start) {
            let detour = travel(origin, here) + travel(here, DayComposer.coordinate(first)) - travel(origin, DayComposer.coordinate(first))
            options.append(Slot(start: start, end: start.addingTimeInterval(length), after: nil, before: first, travelIn: travel(origin, here),
                                detour: max(0, detour)))
        }
        // Entre duas paradas (o buraco tem que estar no futuro).
        for (prev, next) in zip(timeline, timeline.dropFirst()) where next.start > now {
            guard let start = MicroStops.fit(minutes, at: here, prev: prev, next: next, floor: now, latest: false, input: input), ok(start)
            else { continue }
            let a = DayComposer.coordinate(prev), b = DayComposer.coordinate(next)
            let detour = travel(a, here) + travel(here, b) - travel(a, b)
            options.append(Slot(start: start, end: start.addingTimeInterval(length), after: prev, before: next, travelIn: travel(a, here),
                                detour: max(0, detour)))
        }
        // Depois da última.
        let from = DayComposer.coordinate(last) ?? origin
        let start = MicroStops.roundUp(max(last.end, now).addingTimeInterval(Double(travel(from, here)) * 60), day: day)
        if ok(start) {
            options.append(Slot(start: start, end: start.addingTimeInterval(length), after: last, before: nil, travelIn: travel(from, here),
                                detour: travel(from, here)))
        }
        // O mais cedo que fica no caminho (até 10 min de desvio); senão o de menor desvio.
        if let onTheWay = options.filter({ $0.detour <= onTheWayMinutes }).min(by: { $0.start < $1.start }) { return onTheWay }
        return options.min { ($0.detour, $0.start) < ($1.detour, $1.start) }
    }

    /// A parada do encaixe (card branco de Must, 25 min).
    static func stop(placeId: String, name: String, note: String, slot: Slot, area: String?, at here: CLLocationCoordinate2D) -> DayStop {
        DayStop(id: "q-\(placeId)", placeId: placeId, kind: .must, start: slot.start, end: slot.end, label: name, note: note,
                area: area, lat: here.latitude, lng: here.longitude)
    }

    /// O dia com a parada nova: as outras ficam iguais, só as pernas vizinhas são refeitas (as que não mudaram guardam o
    /// tempo real do Routes). Sem dia montado, vira um dia de uma parada.
    static func inserting(_ stop: DayStop, into plan: DayPlan?, date: Date, region: Region, walkMaxKm: Double = 1.5) -> DayPlan {
        let areas = AreaCatalog.areas(for: region)
        var out = plan ?? DayPlan(date: region.calendar.startOfDay(for: date),
                                  title: areas.first { $0.id == stop.area }?.name ?? region.displayName, dayNumber: nil, area: stop.area,
                                  stops: [], legs: [], lastTrain: nil, pace: .normal, budget: region.defaultBudget, includes: [])
        out.stops.removeAll { $0.id == stop.id || ($0.placeId == stop.placeId && stop.placeId != nil) }
        out.stops.append(stop)
        out.stops.sort { ($0.start, $0.id) < ($1.start, $1.id) }
        let fresh = DayComposer.legs(for: out.stops, region: region, walkMaxKm: walkMaxKm, travel: nil, areas: areas)
        let old = plan?.legs ?? []
        out.legs = fresh.map { leg in old.first { $0.from == leg.from && $0.to == leg.to } ?? leg }
        return out
    }
}
