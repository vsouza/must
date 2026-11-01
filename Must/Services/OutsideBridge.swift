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

    /// Começa quando há dia aceito com parada futura; atualiza a cada mudança; encerra no fim do dia.
    static func syncLiveActivity(context: ModelContext, region: Region, services: Services) {
        let now = AppClock.now
        let cal = region.calendar
        let start = cal.startOfDay(for: now)
        let day = try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == start && $0.accepted })).first
        let stops = day?.orderedStops.filter { $0.place != nil } ?? []
        let running = Activity<NextStopAttributes>.activities

        guard let index = stops.firstIndex(where: { !$0.done }), let place = stops[index].place else {
            end(running, reason: stops.isEmpty ? "sem dia" : "dia feito 済")
            return
        }
        let stop = stops[index]
        let settings = context.settings(for: region)
        var minutes: Int?
        var detailParts: [String] = []
        if let here = services.location.current {
            let leg = DaySolver.leg(here.coordinate, place.coordinate, walkMax: settings.walkMaxKm)
            minutes = services.eta.minutes(from: here.coordinate, to: place.coordinate, transit: leg.mode == .metro) ?? leg.minutes
            detailParts.append(Walk.distanceText(here.distance(from: place.location)))
        }
        detailParts.append(stop.isAnchor ? "reserva \(region.timeString(stop.at))" : region.timeString(stop.at))
        let leave = minutes.map { RoutesService.leaveAt(stop.at, travelMinutes: $0) }
        let state = NextStopAttributes.ContentState(
            number: index + 1, name: place.name, nameLocal: place.nameLocal, at: stop.at, leaveAt: leave, minutesAway: minutes,
            detail: detailParts.joined(separator: " · "), done: stops.filter(\.done).count, total: stops.count
        )
        // Some depois da última parada + 2 h, ou à meia-noite.
        let stale = min(stop.at.addingTimeInterval(2 * 3600), cal.date(byAdding: .day, value: 1, to: start) ?? stop.at)
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
                Log.app.info("Live Activity iniciada: \(place.name, privacy: .public)")
            } catch {
                Log.app.error("Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func end(_ activities: [Activity<NextStopAttributes>], reason: String) {
        guard !activities.isEmpty else { return }
        Task {
            for activity in Activity<NextStopAttributes>.activities { await activity.end(nil, dismissalPolicy: .default) }
        }
        Log.app.info("Live Activity encerrada: \(reason, privacy: .public)")
    }
}
