@preconcurrency import UserNotifications
import Foundation

/// Toque num aviso local do guia (prompt 23 §4): abre o link do `userInfo["url"]` (`must://bom-dia`, `must://agora`)
/// pelo `AppRouter.handle`. Um toque que chega antes da árvore montar fica guardado até o `handler` existir.
@MainActor
final class NotificationTaps: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTaps()

    /// Quem abre o link (a raiz da região atual). Trocar de região troca o handler.
    var handler: ((URL) -> Void)? {
        didSet { if let handler, let url = pending { pending = nil; handler(url) } }
    }
    private var pending: URL?

    func install() { UNUserNotificationCenter.current().delegate = self }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: raw) else { return }
        await MainActor.run {
            if let handler { handler(url) } else { pending = url }
        }
    }

    /// Com o app aberto o aviso aparece como banner (sem isso o iOS o engole).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
