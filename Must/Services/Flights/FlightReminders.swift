import Foundation
import UserNotifications

/// Lembretes locais dos itens do checklist com `dueAt` (prompt 15 · C). Sem servidor, sem push.
/// A permissão só é pedida quando o usuário liga "Lembrar no horário" em Voos; desligado, nada é agendado.
@MainActor
enum FlightReminders {
    static let enabledKey = "flights.reminders"
    private static let prefix = "flight."

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Liga: pede a permissão agora e agenda. Devolve se a permissão foi dada.
    @discardableResult
    static func enable(_ flights: [Flight], now: Date = AppClock.now) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        UserDefaults.standard.set(granted, forKey: enabledKey)
        if granted { await sync(flights, now: now) }
        return granted
    }

    /// Desliga e tira o que estava agendado.
    static func disable() async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
    }

    /// Reagenda os itens ainda não feitos com `dueAt` no futuro (chamado quando o checklist muda). Sem ligar, não faz nada.
    static func sync(_ flights: [Flight], now: Date = AppClock.now) async {
        guard enabled else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        for flight in flights where !flight.isOver(now: now) {
            let number = flight.firstLeg?.number ?? "voo"
            for item in flight.checklist where !item.done {
                guard let due = item.dueAt, due > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = "Voo \(number)"
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSince(now)), repeats: false)
                let request = UNNotificationRequest(identifier: "\(prefix)\(flight.id).\(item.id)", content: content, trigger: trigger)
                try? await center.add(request)
            }
        }
    }
}
