import SwiftData
import SwiftUI

@main
struct MustApp: App {
    @State private var regionStore = RegionStore()
    @State private var services = Services()

    init() {
        HTTP.configureCache()
    }

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
    @Environment(\.modelContext) private var context

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
                DebugLaunch.apply(to: router, context: context, region: store.region, services: services)
                #endif
            }
            .task { await syncThenRefresh() }
            // Widgets e Live Activity acompanham qualquer gravação (dia aceito, 済, troca, gasto).
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                refreshOutsideSoon()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    services.location.start()
                    Task { await syncThenRefresh() }
                } else if phase == .background {
                    services.location.stop()
                }
            }
            .onOpenURL { router.handle(url: $0, region: store.region) }
            // Abre na região onde você está (Ajustes › Região › Automático).
            .onChange(of: services.location.current.map { Region.detect($0.coordinate) }, initial: true) { _, _ in
                if let c = services.location.current?.coordinate { store.followGPS(c) }
            }
    }

    @State private var outsideTask: Task<Void, Never>?

    /// Sincroniza e atualiza widgets. Se a região trocar no meio (GPS, Ajustes), para: a árvore nova
    /// já faz o dela, e o `context` daqui é do board antigo (o container fica vivo até o fim).
    private func syncThenRefresh() async {
        let region = store.region
        let container = context.container
        defer { withExtendedLifetime(container) {} }
        await services.sync.syncIfNeeded(context: context, region: region)
        guard store.region == region, !Task.isCancelled else { return }
        OutsideBridge.refresh(context: context, region: region, services: services)
    }

    /// Junta várias gravações seguidas numa atualização só.
    private func refreshOutsideSoon() {
        outsideTask?.cancel()
        let region = store.region
        let container = context.container
        outsideTask = Task {
            defer { withExtendedLifetime(container) {} }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, store.region == region else { return }
            OutsideBridge.refresh(context: context, region: store.region, services: services)
        }
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
    static func apply(to router: AppRouter, context: ModelContext, region: Region, services: Services) {
        let location = services.location
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
        case "painel": router.push(.place(id: arg ?? "j18"), on: .musts) // rola até o painel do tipo (PlaceView)
        case "luz": router.push(.light(date: region.calendar.startOfDay(for: AppClock.now)), on: .hoje)
        case "dicas": router.push(.place(id: (arg ?? "p01").replacingOccurrences(of: ":fim", with: "")), on: .musts) // rola até as Dicas (PlaceView)
        case "editar": router.sheet = .editPlace(id: arg ?? "p01")
        case "nova-lista": router.select(.musts); router.cover = .newList
        case "adicionar": router.sheet = .addLink(url: arg, listId: nil)
        case "hoje": router.select(.hoje)
        case "montar", "proposta", "trocar": router.push(.montar(date: region.calendar.startOfDay(for: AppClock.now)), on: .hoje)
        case "gasto": router.select(.hoje); router.sheet = .expense(placeId: nil)
        case "aceitar":
            acceptToday(context: context, region: region, location: location)
            router.select(.hoje)
        case "mapa":
            // mapa:aceitar monta e aceita hoje e amanhã antes (rota e pinos numerados).
            if arg == "aceitar" {
                acceptToday(context: context, region: region, location: location)
                acceptToday(context: context, region: region, location: location, offset: 1)
            }
            router.select(.mapa)
        case "assistente": router.sheet = .assistant
        case "viagem": router.push(.trip, on: .inicio)
        case "reservas": router.push(.reservations, on: .inicio)
        case "sincronizar":
            router.push(.settings, on: .inicio)
            Task { await services.sync.syncPlaces(context: context, region: region) }
        default: break
        }
    }

    /// Monta e aceita um dia (hoje + `offset`) com os padrões (prints da tela Hoje e do Mapa).
    private static func acceptToday(context: ModelContext, region: Region, location: LocationService, offset: Int = 0) {
        let settings = try? context.fetch(FetchDescriptor<Settings>()).first
        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let date = region.calendar.date(byAdding: .day, value: offset, to: AppClock.now) ?? AppClock.now
        let planner = DayPlanner(date: date, region: region, settings: settings, existing: nil)
        planner.build(catalog: places.solverCatalog, trip: trip, settings: settings, location: offset == 0 ? location.current : nil)
        try? planner.accept(context: context)
    }
}
#endif
