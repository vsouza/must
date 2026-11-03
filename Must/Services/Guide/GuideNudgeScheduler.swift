import CoreLocation
import Foundation
import OSLog
import SwiftData
import UserNotifications

// Agendador dos avisos do guia (prompt 18 · C.17). Só mexe nos `guide.*`; o resto fica como está.

/// Aviso pendente como o sistema devolve (só o que a comparação precisa).
struct PendingNudge: Sendable, Equatable {
    var id: String
    var fireAt: Date?
    var title: String
    var body: String
}

/// Central de notificações, atrás de um protocolo pra os testes usarem um fake.
@MainActor
protocol NudgeScheduling {
    /// Tem permissão? Pede só se `askIfNeeded` e ainda não foi decidida.
    func allowed(askIfNeeded: Bool) async -> Bool
    /// Avisos `guide.*` pendentes.
    func pendingGuide() async -> [PendingNudge]
    /// Horas dos avisos `guide.*` que já tocaram (contam pro espaçamento de 45 min).
    func deliveredGuideDates() async -> [Date]
    func remove(ids: [String])
    func add(_ nudge: GuideNudge, calendar: Calendar) async
}

/// `UNUserNotificationCenter` de verdade. Trigger de calendário no fuso da região.
@MainActor
struct UNNudgeCenter: NudgeScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func allowed(askIfNeeded: Bool) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined:
            guard askIfNeeded else { return false }
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    func pendingGuide() async -> [PendingNudge] {
        await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(GuideNudges.idPrefix) }
            .map { request in
                PendingNudge(id: request.identifier,
                             fireAt: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
                             title: request.content.title, body: request.content.body)
            }
    }

    func deliveredGuideDates() async -> [Date] {
        await center.deliveredNotifications()
            .filter { $0.request.identifier.hasPrefix(GuideNudges.idPrefix) }
            .map(\.date)
    }

    func remove(ids: [String]) {
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func add(_ nudge: GuideNudge, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = nudge.title
        content.body = nudge.body
        content.sound = .default
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nudge.fireAt)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: nudge.id, content: content, trigger: trigger))
    }
}

@MainActor
enum GuideNudgeScheduler {
    /// Ajustes › Dia › "Avisos do guia". Ligado por padrão.
    static let enabledKey = "guide.nudges"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Recalcula os avisos do dia aceito de hoje e troca os `guide.*` pendentes. Sem dia aceito, ou desligado, tira os seus.
    /// `askPermission` só no aceite: a permissão é pedida ali, não em todo recálculo.
    static func refresh(context: ModelContext, region: Region, origin: CLLocationCoordinate2D?, askPermission: Bool,
                        enabled: Bool = isEnabled, now: Date = AppClock.now, center: any NudgeScheduling = UNNudgeCenter()) async {
        guard enabled else { await clear(center: center); return }
        let taken = await center.deliveredGuideDates()
        let planned = day(context: context, region: region, origin: origin, now: now).map { GuideNudges.plan($0, now: now, taken: taken) } ?? []
        let pending = await center.pendingGuide()
        guard !planned.isEmpty else {
            center.remove(ids: pending.map(\.id))
            return
        }
        guard await center.allowed(askIfNeeded: askPermission) else {
            center.remove(ids: pending.map(\.id))
            return
        }
        // Nada mudou desde o último cálculo: não reagenda (o sistema guarda o que já está lá).
        guard !matches(pending, planned) else { return }
        center.remove(ids: pending.map(\.id))
        for nudge in planned { await center.add(nudge, calendar: region.calendar) }
        Log.guide.info("avisos do guia: \(planned.count) agendados")
    }

    /// Desliga: tira os `guide.*` pendentes (os que já tocaram ficam na Central).
    static func disable(center: any NudgeScheduling = UNNudgeCenter()) async {
        let pending = await center.pendingGuide()
        center.remove(ids: pending.map(\.id))
    }

    /// `-debugScreen avisos`: lista no log o que seria agendado agora pro dia aceito. Não agenda.
    static func logPreview(context: ModelContext, region: Region, origin: CLLocationCoordinate2D?, now: Date = AppClock.now) {
        guard let day = day(context: context, region: region, origin: origin, now: now) else {
            Log.guide.notice("avisos: nenhum dia aceito hoje")
            return
        }
        let nudges = GuideNudges.plan(day, now: now)
        Log.guide.notice("avisos: \(nudges.count) pro dia \(nudges.first?.id ?? "-", privacy: .public)")
        for n in nudges {
            Log.guide.notice("aviso \(GuideNudges.clock(n.fireAt, region.timeZone), privacy: .public) \(n.kind.label, privacy: .public) · \(n.title, privacy: .public) · \(n.body, privacy: .public)")
        }
    }

    // MARK: Dia aceito → entrada pura

    /// Dia aceito de hoje (no fuso da região) com as paradas, horário e origem. `nil` sem dia aceito.
    static func day(context: ModelContext, region: Region, origin: CLLocationCoordinate2D?, now: Date) -> GuideDay? {
        let cal = region.calendar
        let date = cal.startOfDay(for: now)
        let planned = (try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == date })))?.first
        guard let planned, planned.accepted else { return nil }
        let settings = (try? context.fetch(FetchDescriptor<Settings>()))?.first
        let trip = (try? context.fetch(FetchDescriptor<TripInfo>()))?.first
        let city = trip?.city(on: date, calendar: cal)
        let center = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude,
                                            longitude: city?.lng ?? region.defaultCenter.longitude)
        // Mesma regra do DayPlanner: sai de onde está se estiver na cidade (até 40 km), senão do centro.
        var from = center
        if let origin, CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < 40_000 {
            from = origin
        }
        let stops: [GuideStop] = planned.orderedStops.compactMap { stop in
            guard let place = stop.place else { return nil }
            let duration = TimeInterval(SolverPlace(place).role.duration * 60)
            return GuideStop(placeId: place.id, name: place.name, lat: place.lat, lng: place.lng, start: stop.at,
                             end: stop.at.addingTimeInterval(duration), isPhoto: place.kind == .photo, isDone: stop.done,
                             hours: place.hours)
        }
        return GuideDay(date: date,
                        dayStart: cal.date(byAdding: .minute, value: settings?.dayStartMinutes ?? 9 * 60 + 30, to: date) ?? date,
                        timeZone: region.timeZone, origin: from,
                        walkMaxKm: DaySolver.effectiveWalkMax(walkMaxKm: settings?.walkMaxKm ?? 1.5, walk: planned.walk),
                        stops: stops)
    }

    /// Os pendentes já são estes? (mesmos ids, horas, títulos e textos)
    static func matches(_ pending: [PendingNudge], _ planned: [GuideNudge]) -> Bool {
        guard pending.count == planned.count else { return false }
        let byId = Dictionary(pending.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return planned.allSatisfy { nudge in
            guard let p = byId[nudge.id], p.title == nudge.title, p.body == nudge.body, let fire = p.fireAt else { return false }
            return abs(fire.timeIntervalSince(nudge.fireAt)) < 1
        }
    }

    private static func clear(center: any NudgeScheduling) async {
        let pending = await center.pendingGuide()
        center.remove(ids: pending.map(\.id))
    }
}

extension GuideNudge.Kind {
    /// Rótulo pro log de QA.
    var label: String {
        switch self {
        case .leave: "saída"
        case .golden: "golden"
        case .opens: "abre"
        }
    }
}
