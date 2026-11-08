import ActivityKit
import CoreLocation
import Foundation
import SwiftData
import UIKit
import WidgetKit

/// Mantém o que aparece fora do app em dia: widgets (via App Group) e a Live Activity da próxima parada.
/// Chamado quando o SwiftData salva, quando o app volta pra frente e depois da sincronização.
@MainActor
enum OutsideBridge {
    static func refresh(context: ModelContext, region: Region, services: Services) {
        let snapshot = makeSnapshot(context: context, region: region, services: services)
        if snapshot != WidgetSnapshot.load().map({ var s = $0; s.updatedAt = snapshot.updatedAt; return s }) {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
        syncLiveActivity(context: context, region: region, services: services)
    }

    // MARK: Widgets

    static func makeSnapshot(context: ModelContext, region: Region, services: Services) -> WidgetSnapshot {
        let now = AppClock.now
        let cal = region.calendar
        let start = cal.startOfDay(for: now)
        let day = try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == start && $0.accepted })).first
        let stops = day?.orderedStops ?? []
        let next = stops.first { !$0.done }
        let range = region.dayRange(now)
        let spent = ((try? context.fetch(FetchDescriptor<Expense>())) ?? []).filter { range.contains($0.at) }.reduce(0) { $0 + $1.amount }
        let settings = context.settings(for: region)
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        let here = services.location.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let model = HomeModel(places: places, expenses: [], days: [], trip: trip, region: region, now: now, location: here)
        let weather = services.sync.weather(on: tomorrow, region: region, trip: trip)

        var minutes: Int?
        if let place = next?.place, let here {
            let leg = DaySolver.leg(here.coordinate, place.coordinate, walkMax: settings.walkMaxKm)
            minutes = services.eta.minutes(from: here.coordinate, to: place.coordinate, transit: leg.mode == .metro) ?? leg.minutes
        }
        let reservations = places.filter { $0.hasReservation(on: tomorrow, calendar: cal) }.map(\.name)
        var area = model.nearbyLine.components(separatedBy: " · ").first ?? region.displayName
        if here == nil { area = trip?.city(on: now, calendar: cal)?.name ?? region.displayName }

        return WidgetSnapshot(
            updatedAt: now, hasDay: day != nil,
            spentText: region.money(spent), budgetText: region.money(day?.budget ?? settings.perDayBudget, symbol: false),
            doneCount: stops.filter(\.done).count, totalCount: stops.count,
            seals: stops.map { $0.done ? .done : ($0.id == next?.id ? .next : .future) },
            nextName: next?.place?.name, nextTime: next.map { region.timeString($0.at) }, nextMinutes: minutes,
            nearbyCount: model.openNearby.count, area: area,
            tempNow: services.sync.now(region: region, trip: trip).map { Int($0.temp.rounded()) },
            tomorrowWeather: weather.map { "\(Int($0.tempMax.rounded()))° \($0.label)" },
            tomorrowLine: reservations.isEmpty ? "toque pra montar" : "reserva: \(reservations.joined(separator: ", "))",
            tomorrowDate: BoardDates(timeZone: region.timeZone).dayString(tomorrow)
        )
    }

    // MARK: Live Activity

    /// Começa quando há dia aceito com parada pela frente; atualiza a cada mudança; encerra quando o dia acaba.
    /// v8 (prompt 23 §4): a parada pra onde se vai, o "saia às" da Linha (`DayNowRules`), a seguinte e o último trem.
    static func syncLiveActivity(context: ModelContext, region: Region, services: Services) {
        let now = AppClock.now
        let cal = region.calendar
        let start = cal.startOfDay(for: now)
        let running = Activity<NextStopAttributes>.activities
        guard let accepted = DayEngineV8.accepted(on: start, region: region, context: context) else {
            end(running, reason: "sem dia")
            return
        }
        // O relógio único: feitos e o que ficou pra depois saem da conta (a Live Activity diz o mesmo que a capa).
        let clock = DayClock.make(plan: accepted, doneIds: DayDoneStore().ids(day: BoardDates(timeZone: region.timeZone).dayString(now)),
                                  at: now, region: region, position: services.location.current?.coordinate)
        let plan = clock.active ?? accepted
        guard let state = liveState(plan, region: region, now: now, here: services.location.current, eta: services.eta) else {
            end(running, reason: "dia feito 済")
            return
        }
        // Some 2 h depois da hora da parada, ou depois do último trem.
        let stale = max(state.at.addingTimeInterval(2 * 3600), plan.lastTrain?.at ?? .distantPast)
        let content = ActivityContent(state: state, staleDate: stale)

        if let activity = running.first {
            guard activity.content.state != state else { return }
            let id = activity.id
            let extras = running.dropFirst().map(\.id)
            Task {
                for a in Activity<NextStopAttributes>.activities {
                    if a.id == id { await a.update(content) } else if extras.contains(a.id) { await a.end(nil, dismissalPolicy: .immediate) }
                }
            }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                Log.app.info("Live Activity: desligada nos Ajustes do iOS")
                return
            }
            // Só dá pra iniciar com o app na frente; a próxima ativação tenta de novo.
            guard UIApplication.shared.applicationState == .active else {
                Log.app.info("Live Activity: app não está ativo, fica pra próxima")
                return
            }
            do {
                var style = Date.FormatStyle(locale: region.locale, calendar: cal).weekday(.abbreviated).day().month(.abbreviated)
                style.timeZone = region.timeZone
                _ = try Activity.request(attributes: NextStopAttributes(dayLabel: now.formatted(style)), content: content, pushType: nil)
                Log.app.info("Live Activity iniciada: \(state.name, privacy: .public)")
            } catch {
                Log.app.error("Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Estado da Live Activity num instante: a parada pra onde se vai, "saia às" (com o GPS e o ETA quando há), a seguinte e
    /// o último trem. `nil` = nada mais pela frente.
    static func liveState(_ plan: DayPlan, region: Region, now: Date, here: CLLocation?, eta: ETACache?) -> NextStopAttributes.ContentState? {
        guard let head = DayNowRules.heading(in: plan, at: now) else { return nil }
        let stop = head.stop
        var minutes = plan.leg(before: stop)?.minutes
        var leave = head.leaveAt
        var detail: [String] = []
        if let here, let target = DayComposer.coordinate(stop) {
            let location = CLLocation(latitude: target.latitude, longitude: target.longitude)
            let leg = DaySolver.leg(here.coordinate, target, walkMax: 1.5)
            let real = eta?.minutes(from: here.coordinate, to: target, transit: leg.mode == .metro) ?? leg.minutes
            minutes = real
            leave = RoutesService.leaveAt(DayNowRules.arriveBy(stop) ?? stop.start, travelMinutes: real)
            detail.append(Walk.distanceText(here.distance(from: location)))
        }
        let arrive = DayNowRules.arriveBy(stop)
        switch stop.anchor {
        case .reservation: detail.append("reserva \(region.timeString(stop.start))")
        case .ticket: detail.append("ingresso \(region.timeString(stop.start))")
        default: detail.append(arrive.map { "chegue \(region.timeString($0))" } ?? region.timeString(stop.start))
        }
        let following = head.index + 1 < plan.stops.count ? plan.stops[head.index + 1] : nil
        return NextStopAttributes.ContentState(
            number: head.index + 1, name: stop.label, nameLocal: nil, at: stop.start, leaveAt: leave, minutesAway: minutes,
            detail: detail.joined(separator: " · "), done: plan.stops.filter(\.done).count, total: plan.stops.count,
            arriveBy: arrive, nextName: following?.label, nextAt: following?.start,
            lastTrainLine: plan.lastTrain?.line, lastTrainAt: plan.lastTrain?.at, isAnchor: stop.kind == .anchor)
    }

    private static func end(_ activities: [Activity<NextStopAttributes>], reason: String) {
        guard !activities.isEmpty else { return }
        Task {
            for activity in Activity<NextStopAttributes>.activities { await activity.end(nil, dismissalPolicy: .default) }
        }
        Log.app.info("Live Activity encerrada: \(reason, privacy: .public)")
    }
}
