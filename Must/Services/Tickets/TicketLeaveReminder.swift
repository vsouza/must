import Foundation
import UserNotifications

/// Lembrete local "saia às" do ingresso (fatia 3, prompt 15 · A). Só uma notificação no horário de sair; sem Live Activity.
/// A permissão é pedida quando o usuário liga o aviso e salva; sem permissão, nada é agendado.
@MainActor
enum TicketLeaveReminder {
    /// Agenda o aviso. Devolve se foi agendado (false se a hora já passou ou se a permissão foi negada).
    static func schedule(title: String, leaveAt: Date, now: Date = AppClock.now) async -> Bool {
        guard leaveAt > now else { return false }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Saia pro \(title)"
        content.body = "Hora de sair · estimativa de deslocamento"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, leaveAt.timeIntervalSince(now)), repeats: false)
        let id = "ticket.leave.\(Int(leaveAt.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        return (try? await center.add(request)) != nil
    }
}
