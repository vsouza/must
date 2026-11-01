import SwiftUI

@main
struct MustApp: App {
    @State private var lastOpenedURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(lastOpenedURL: lastOpenedURL)
                .preferredColorScheme(.light)
                // must://add?url=… — o fluxo "Adicionar por link" chega no prompt 04.
                .onOpenURL { url in lastOpenedURL = url }
        }
    }
}
