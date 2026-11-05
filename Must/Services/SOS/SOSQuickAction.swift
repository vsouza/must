import UIKit

/// Quick Action "SOS" no ícone (prompt 25 · C.3, `UIApplicationShortcutItems` no `project.yml`). O SwiftUI não entrega
/// atalhos do ícone: o delegate da cena recebe e repassa pra raiz (como `NotificationTaps`). Se a raiz ainda não
/// montou (o app abriu pelo atalho), fica pendente e sai quando o `handler` chega.
@MainActor
final class QuickActions {
    static let shared = QuickActions()
    static let sosType = "dev.viniso.must.sos"

    /// Quem abre (a raiz da região atual). Trocar de região troca o handler.
    var handler: ((String) -> Void)? {
        didSet { if let handler, let type = pending { pending = nil; handler(type) } }
    }
    private var pending: String?

    func receive(_ type: String) {
        if let handler { handler(type) } else { pending = type }
    }
}

/// App delegate mínimo: só pra pôr o delegate de cena que recebe o atalho.
final class MustAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Aberto pelo atalho (app fechado): o item vem aqui, não no delegate da cena.
        if let item = options.shortcutItem { QuickActions.shared.receive(item.type) }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = MustSceneDelegate.self
        return config
    }
}

final class MustSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        QuickActions.shared.receive(shortcutItem.type)
        return shortcutItem.type == QuickActions.sosType
    }
}
