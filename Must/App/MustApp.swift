import SwiftUI

@main
struct MustApp: App {
    @State private var regionStore = RegionStore()
    @State private var services = Services()

    var body: some Scene {
        WindowGroup {
            AppRoot()
                // Trocar região (ou zerar) recria a árvore inteira com o container novo.
                .id("\(regionStore.region.rawValue)-\(regionStore.generation)")
                .modelContainer(regionStore.container)
                .environment(regionStore)
                .environment(services)
                .preferredColorScheme(.light)
        }
    }
}

/// Raiz da região atual: onboarding na primeira abertura, GPS só em primeiro plano.
struct AppRoot: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    @State private var showOnboarding = false
    @State private var lastOpenedURL: URL?

    var body: some View {
        ContentView(lastOpenedURL: lastOpenedURL)
            .fullScreenCover(isPresented: $showOnboarding) { ImportView(mode: .firstRun) }
            .onAppear {
                showOnboarding = Self.shouldShowOnboarding(onboarded: store.isOnboarded)
                services.location.start()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { services.location.start() } else if phase == .background { services.location.stop() }
            }
            // must://add?url=… — o fluxo "Adicionar por link" chega no prompt 04.
            .onOpenURL { lastOpenedURL = $0 }
    }

    private static func shouldShowOnboarding(onboarded: Bool) -> Bool {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "debugScreen") == "importar" { return true }
        if defaults.bool(forKey: "skipOnboarding") || defaults.string(forKey: "debugScreen") != nil { return false }
        #endif
        return !onboarded
    }
}
