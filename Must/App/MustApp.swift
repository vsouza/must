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

/// Raiz da região atual: tab bar, onboarding na primeira abertura, GPS só em primeiro plano, deep links.
struct AppRoot: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = AppRouter()
    @State private var showOnboarding = false

    var body: some View {
        RootView()
            .environment(router)
            .fullScreenCover(isPresented: $showOnboarding) {
                ImportView(mode: .firstRun).environment(router)
            }
            .onAppear {
                showOnboarding = Self.shouldShowOnboarding(onboarded: store.isOnboarded)
                services.location.start()
                #if DEBUG
                DebugLaunch.apply(to: router)
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { services.location.start() } else if phase == .background { services.location.stop() }
            }
            .onOpenURL { router.handle(url: $0) }
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

#if DEBUG
/// `-debugScreen <tela>` abre uma tela direto (simulador/prints):
/// ajustes, regiao, musts, lista:<id>, fim, lugar:<id>, editar:<id>, nova-lista, adicionar[:url], hoje, mapa.
/// `-gallery` abre a Gallery.
@MainActor
enum DebugLaunch {
    static func apply(to router: AppRouter) {
        if ProcessInfo.processInfo.arguments.contains("-gallery") { router.cover = .gallery }
        guard let screen = UserDefaults.standard.string(forKey: "debugScreen") else { return }
        let parts = screen.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : nil
        switch parts[0] {
        case "ajustes", "regiao": router.push(.settings, on: .inicio)
        case "musts": router.select(.musts)
        case "lista": router.push(.list(id: arg ?? "eat"), on: .musts)
        case "fim": router.push(.saveForEnd, on: .musts)
        case "lugar": router.push(.place(id: arg ?? "p01"), on: .musts)
        case "editar": router.sheet = .editPlace(id: arg ?? "p01")
        case "nova-lista": router.select(.musts); router.cover = .newList
        case "adicionar": router.sheet = .addLink(url: arg, listId: nil)
        case "hoje": router.select(.hoje)
        case "mapa": router.select(.mapa)
        default: break
        }
    }
}
#endif
