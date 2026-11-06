import SwiftData
import SwiftUI

@main
struct MustApp: App {
    @State private var regionStore = RegionStore()
    @State private var services = Services()
    /// Só pra Quick Action "SOS" (prompt 25 · C.3): o SwiftUI não entrega atalhos do ícone.
    @UIApplicationDelegateAdaptor(MustAppDelegate.self) private var appDelegate

    init() {
        LaunchTiming.appDidInit()
        HTTP.configureCache()
        NotificationTaps.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(generation: regionStore.generation)
                // Trocar região (ou zerar) recria a árvore inteira com o container novo.
                .id("\(regionStore.region.rawValue)-\(regionStore.generation)")
                .modelContainer(regionStore.container)
                .environment(regionStore)
                .environment(\.tripTheme, regionStore.theme)
                .environment(services)
                .environment(\.dayEngine, DayEngineV8(store: regionStore, services: services))
                .environment(\.showEvents, Self.showEvents(regionStore)).environment(\.films, WikidataFilms.shared)
                // Nova viagem (prompt 28): o fluxo entrega o rascunho, o store grava e abre.
                .environment(\.tripCreator, StoreTripCreator(store: regionStore))
                .preferredColorScheme(.light)
                // Fonte padrão: `Text` sem fonte explícita sai em Schibsted (texto v8), não em SF.
                .font(V8Font.text(15))
                .dynamicTypeSize(...DynamicTypeSize.mustCap)
        }
    }
}

extension MustApp {
    /// Em cartaz da região atual: o board (RODADA-23 · A) + os feeds em cache do `EventsService` (E), sem repetição.
    static func showEvents(_ store: RegionStore) -> BoardShowEvents {
        let container = store.container
        return .live(region: store.region) { (try? container.mainContext.fetch(FetchDescriptor<Place>())) ?? [] }
            .merging(source: EventsService.shared)
    }
}

/// Raiz da região atual: tab bar, onboarding na primeira abertura, GPS só em primeiro plano, deep links.
struct AppRoot: View {
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(\.dayEngine) private var engine

    /// Geração do container desta árvore. Depois de uma troca (região, zerar), a árvore velha ainda recebe eventos
    /// por um instante (o `didSave` do board novo, a animação): `isCurrent` falso = não mexe em nada.
    let generation: Int
    private var isCurrent: Bool { store.generation == generation }

    @State private var router = AppRouter()
    @State private var showOnboarding = false
    /// Sincronização: a primeira espera o arranque (prompt 18 · A.6); pedidos seguidos viram um.
    @State private var syncGate = StartupSync()

    var body: some View {
        RootView()
            .environment(router)
            .fullScreenCover(isPresented: $showOnboarding) {
                ImportView(mode: .firstRun).environment(router)
            }
            .onAppear {
                LaunchTiming.firstFrame()
                showOnboarding = Self.shouldShowOnboarding(onboarded: store.isOnboarded)
                services.location.start()
                #if DEBUG
                // `-debugTrip portugal` (prompt 28, prints): cria uma vez a viagem de Portugal do desenho e abre nela.
                if DebugFlags.string("debugTrip") == "portugal", !store.trips.contains(where: { $0.countryCode == "PT" }) {
                    _ = try? store.create(NewTripDraft.debugPortugal, openNow: true)
                    return
                }
                DebugLaunch.apply(to: router, context: context, region: store.region, services: services, engine: engine)
                #endif
            }
            // Arranque: nada de rede antes do primeiro frame (prompt 18 · A.6). Abre com o que está salvo.
            .task { requestSync() }
            .onDisappear { syncGate.cancel(); outsideTask?.cancel() }
            // Volta a rede: a fila de saída (voos, links lidos) reenvia sem esperar a próxima abertura.
            .onChange(of: services.connectivity.status) { _, status in
                if status == .online { requestSync() }
            }
            // Wi-Fi voltou: o que falta de hoje e amanhã baixa agora (prompt 18 · A.5). No celular, a política não deixa.
            .onChange(of: services.connectivity.prefetchNetwork) { _, network in
                if PrefetchPolicy.allows(network) {
                runPrefetchPending()
                if isCurrent {
                    let context = context, region = store.region
                    Task { await services.sync.resolveBoardIfNeeded(context: context, region: region, network: network) }
                }
            }
            }
            // 07:00 com o app aberto (prompt 18 · A.5). Sem background task: fechado, fica pra próxima abertura.
            .task(id: store.region) { await prefetchAtSevenLoop() }
            #if DEBUG
            // `-debugSyncEvery 3` (rodada 23 · G): sincroniza a cada N s, pra digitar com o sync gravando no meio.
            .task(id: generation) { await debugSyncLoop() }
            #endif
            // Widgets e Live Activity acompanham qualquer gravação (dia aceito, 済, troca, gasto).
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                guard isCurrent else { return }
                refreshOutsideSoon()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    services.location.start()
                    requestSync()
                    refreshGuide()
                    // Ingresso compartilhado que o Share Extension não conseguiu abrir: pega aqui.
                    if router.sheet == nil, let waiting = ShareInbox.pending().first {
                        router.handle(url: ShareInbox.importURL(for: waiting.id), region: store.region)
                    }
                } else if phase == .background {
                    services.location.stop()
                }
            }
            .onOpenURL { router.handle(url: $0, region: store.region) }
            // Toque num aviso do guia: o mesmo caminho dos links (`must://bom-dia`, `must://agora`).
            .onAppear {
                guard isCurrent else { return }
                let router = router, store = store
                NotificationTaps.shared.handler = { router.handle(url: $0, region: store.region) }
                QuickActions.shared.handler = { type in
                    if type == QuickActions.sosType { router.handle(url: URL(string: "must://sos")!, region: store.region) }
                }
            }
            // Abre a viagem certa pra onde você está (Ajustes › Região › Automático; prompt 28 §3.10:
            // datas de hoje › país do GPS › casa).
            .onChange(of: services.location.current.flatMap { store.autoPick(near: $0.coordinate)?.rawValue }, initial: true) { _, _ in
                if let c = services.location.current?.coordinate { store.followGPS(c) }
            }
            // Viagem nova: abre quando a folha do fluxo fecha (o passo 9 mostra o "Pronto" antes).
            .onChange(of: router.cover == nil) { _, closed in
                if closed, store.pendingTrip != nil { store.openPending() }
            }
    }

    @State private var outsideTask: Task<Void, Never>?

    /// Sincroniza e atualiza widgets. Se a região trocar no meio (GPS, Ajustes), para: a árvore nova
    /// já faz o dela, e o `context` daqui é do board antigo (o container fica vivo até o fim).
    /// Pede a sincronização com o board desta árvore, capturado agora: o pedido da abertura espera 2 s e, se a
    /// região trocar nesse meio (GPS na primeira abertura no Japão), esta árvore já saiu. Ler o `context` dela
    /// depois disso derruba o app (SwiftData), então o trabalho leva o contexto e o container daqui.
    private func requestSync() {
        guard isCurrent else { return }
        let tree = Tree(context: context, container: context.container, region: store.region, generation: store.generation)
        syncGate.request { await syncThenRefresh(tree) }
    }

    private struct Tree {
        let context: ModelContext
        let container: ModelContainer
        let region: Region
        let generation: Int
    }

    private func syncThenRefresh(_ tree: Tree) async {
        guard store.region == tree.region, store.generation == tree.generation, !Task.isCancelled else { return }
        let region = tree.region
        let context = tree.context
        defer { withExtendedLifetime(tree.container) {} }
        LaunchTiming.mark("sync começou")
        await services.sync.syncIfNeeded(context: context, region: region)
        // Fila de saída: o que ficou sem rede sai agora; cada item segue a própria política (voo, cota).
        // Places entra pra conferir texto colado que ficou na fila sem rede (prompt 18 · E.23).
        await Outbox.drain(context: context, region: region, places: services.places)
        LaunchTiming.mark("sync terminou")
        guard store.region == region, store.generation == tree.generation, !Task.isCancelled else { return }
        OutsideBridge.refresh(context: context, region: region, services: services)
        // Lugares do seed sem `placeId`: resolve no Wi-Fi (fotos, horários e dicas dependem disso).
        await services.sync.resolveBoardIfNeeded(context: context, region: region, network: services.connectivity.prefetchNetwork)
        guard store.region == region, store.generation == tree.generation, !Task.isCancelled else { return }
        await rebuildGeneratedAreas(context: context, region: region)
    }

    /// Viagem criada no app (prompt 28 §3.5): bairros gerados dos Musts. O geocoder só roda com rede e só pras células
    /// novas; sem rede, os nomes vêm do board ("Alfama") ou "Lisboa · 2".
    private func rebuildGeneratedAreas(context: ModelContext, region: Region) async {
        guard !region.trip.isBuiltIn else { return }
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let inputs = places.compactMap { p -> GeneratedAreas.Input? in
            guard p.lat != 0 || p.lng != 0 else { return nil }
            return GeneratedAreas.Input(id: p.id, lat: p.lat, lng: p.lng, cityId: p.cityId, areaName: p.area)
        }
        let cityNames = Dictionary(context.tripInfo().cities.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let online = !services.connectivity.isOffline
        await GeneratedAreaStore.shared.rebuild(trip: region.rawValue, places: inputs, cityNames: cityNames,
                                                geocode: online ? GeneratedAreaStore.deviceGeocoder : nil)
    }

    #if DEBUG
    private func debugSyncLoop() async {
        let every = DebugFlags.double("debugSyncEvery")
        guard every > 0 else { return }
        let context = context, region = store.region, container = context.container
        defer { withExtendedLifetime(container) {} }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int(every * 1000)))
            guard !Task.isCancelled, isCurrent else { return }
            Log.app.info("debugSyncEvery: sync")
            await services.sync.sync(context: context, region: region)
            await services.sync.syncPlaces(context: context, region: region)
            await Outbox.drain(context: context, region: region, places: services.places)
        }
    }
    #endif

    /// Hoje e amanhã que ainda não estão salvos offline. A política (Wi-Fi, fora do Pouco Dados) decide se roda.
    private func runPrefetchPending() {
        guard isCurrent else { return }
        let region = store.region
        let network = services.connectivity.prefetchNetwork
        let context = context
        let container = context.container
        let places = ((try? context.fetch(FetchDescriptor<Place>())) ?? []).map(HomeState.areaPlace)
        Task {
            defer { withExtendedLifetime(container) {} }
            await services.prefetch.runPending(context: context, region: region, network: network, now: AppClock.now)
            // Capa de cada bairro do board (prompt 21 · fatia 2): só Wi-Fi, a política decide dentro.
            await AreaCoverPrefetch.run(region: region, places: places, network: network, photos: services.photos,
                                        cityName: region.displayName)
        }
    }

    /// Espera as 07:00 (hora da região) e pede o pré-download de hoje e amanhã.
    private func prefetchAtSevenLoop() async {
        while !Task.isCancelled {
            let now = AppClock.now
            let next = DayPrefetch.nextSevenAM(after: now, calendar: store.region.calendar)
            try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSince(now))))
            guard !Task.isCancelled else { return }
            runPrefetchPending()
        }
    }

    /// Junta várias gravações seguidas numa atualização só.
    private func refreshOutsideSoon() {
        guard isCurrent else { return }
        outsideTask?.cancel()
        let region = store.region
        let generation = store.generation
        // O contexto desta árvore, capturado agora (ler o @Environment depois que a árvore saiu derruba o app).
        let context = context
        let container = context.container
        outsideTask = Task {
            defer { withExtendedLifetime(container) {} }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, store.region == region, store.generation == generation else { return }
            OutsideBridge.refresh(context: context, region: store.region, services: services)
            if !DebugFlags.isTestHost {
                await GuideNudgeScheduler.refresh(context: context, region: store.region, origin: services.location.current?.coordinate, askPermission: false)
            }
        }
    }

    /// Avisos do guia do dia aceito (prompt 18 · C.17): recalcula sem esperar a próxima gravação. Nunca pede permissão.
    private func refreshGuide() {
        // No host de testes o app não toca na Central de Notificações (a suíte usa um fake).
        guard !DebugFlags.isTestHost, isCurrent else { return }
        let region = store.region
        let context = context
        let container = context.container
        let origin = services.location.current?.coordinate
        Task {
            defer { withExtendedLifetime(container) {} }
            await GuideNudgeScheduler.refresh(context: context, region: region, origin: origin, askPermission: false)
        }
    }

    private static func shouldShowOnboarding(onboarded: Bool) -> Bool {
        #if DEBUG
        let defaults = UserDefaults.standard
        if DebugFlags.string("debugScreen") == "importar" { return true }
        if DebugFlags.bool("skipOnboarding") || DebugFlags.string("debugScreen") != nil { return false }
        #endif
        return !onboarded
    }
}

#if DEBUG
/// `-debugScreen <tela>` abre uma tela direto (simulador/prints):
/// ajustes, regiao, mapas-offline, musts, lista:<id>, fim, lugar:<id>, editar:<id>, nova-lista, adicionar[:url], hoje, hoje-aceito, mapa,
/// inicio (sem dia), inicio-aceito (dia de hoje aceito, fica na Início),
/// board, board:editar (2 selecionados), editar-lista:<id>.
/// `ingresso` abre um ingresso de exemplo (TicketDemo). `ingresso-entrada` e `ingresso-revisar` abrem Trazer ingresso
/// (o segundo com um PDF de exemplo na caixa). `experiencias` abre Experiências (com exemplos); `descobrir` abre Por perto
/// (use `-debugNearby fake` pra não gastar Google). `carteira` põe itens de exemplo na Carteira e abre a tela.
/// `voos` abre Voos (aba da agenda); `viagem-voos` e `viagem-reservas` passam pelo calendário da Viagem.
/// `-debugFlight fake` troca o AeroDataBox por status de mentira (prints, sem cota). `-gallery` abre a Gallery.
/// `-debugNetwork offline` força "sem rede" (chip, falha na hora, fila de saída); `-debugNetwork slow` põe 3 s de
/// latência e 30% de falha em cada tentativa HTTP (prompt 18 · A.4: a UI não pode travar). `wifi` e `celular` fingem
/// o tipo de rede (o pré-download do dia só roda no Wi-Fi, prompt 18 · A.5).
/// `avisos` lista no log os avisos do guia que seriam agendados pro dia aceito (prompt 18 · C.17).
/// `como-chegar:<id>` abre Como chegar; `-debugRoutes fake` troca o Routes por respostas de exemplo. `buscar-nome:<texto>` abre
/// Buscar por nome (com `-debugAutocomplete fake` pras sugestões de "koffee mam").
@MainActor
enum DebugLaunch {
    static func apply(to router: AppRouter, context: ModelContext, region: Region, services: Services, engine: any DayEngine) {
        let location = services.location
        if DebugFlags.has("-gallery") { router.cover = .gallery }
        // `-debugSyncOnly ids`: resolve só esses lugares no Places (prompt 19, QA das fotos reais).
        if DebugFlags.string("debugSyncOnly") != nil {
            Task { await services.sync.syncPlaces(context: context, region: region) }
        }
        guard let screen = DebugFlags.string("debugScreen") else { return }
        let parts = screen.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : nil
        switch parts[0] {
        case "ajustes", "regiao": router.push(.settings, on: .hoje)
        case "mapas-offline": // mapas-offline:bh já começa a baixar BH
            router.push(.settings, on: .hoje)
            router.push(.offlineMaps, on: .hoje)
            if let pack = MapPack.catalog.first(where: { $0.id == arg }) { services.maps.download(pack) }
        case "musts": router.select(.musts)
        case "board": router.push(.board(edit: arg == "editar"), on: .musts) // board:editar já em modo edição
        case "editar-lista": router.cover = .editList(id: arg ?? "eat")
        case "lista": router.push(.list(id: arg ?? "eat"), on: .musts)
        case "fim": router.push(.saveForEnd, on: .musts)
        case "lugar": router.push(.place(id: arg ?? "p01"), on: .musts)
        case "painel": router.push(.place(id: arg ?? "j18"), on: .musts) // rola até o painel do tipo (PlaceView)
        case "3d": router.push(.place(id: arg ?? "p01"), on: .musts) // abre o Lugar › 3D (PlaceView)
        case "luz": router.push(.light(date: region.calendar.startOfDay(for: AppClock.now)), on: .hoje)
        case "dicas": // v8: sem arg, a tela Dicas (prompt 23 · 07); dicas:<lugar> rola até as Dicas do Lugar
            if let arg { router.push(.place(id: arg.replacingOccurrences(of: ":fim", with: "")), on: .musts) } else { router.push(.dicas, on: .hoje) }
        case "editar": router.sheet = .editPlace(id: arg ?? "p01")
        case "nova-lista": router.select(.musts); router.cover = .newList
        case "adicionar": router.sheet = .addLink(url: arg, listId: nil)
        case "colar-texto": router.sheet = .addLink(url: nil, listId: nil) // aba Texto (o arg `amostra` lê a amostra)
        case "hoje": router.select(.hoje)
        case "hoje-aceito": // dia de hoje aceito, na aba Hoje (prints do selos de progresso, prompt 18 · D.20)
            acceptToday(context: context, region: region, location: location)
            router.select(.hoje)
            prefetchDays(services: services, context: context, region: region)
        case "montar", "proposta", "trocar", "outra": router.push(.montar(date: region.calendar.startOfDay(for: AppClock.now)), on: .hoje)
        case "gasto": router.select(.hoje); router.sheet = .expense(placeId: nil)
        case "aceitar":
            acceptToday(context: context, region: region, location: location)
            router.select(.hoje)
            prefetchDays(services: services, context: context, region: region)
        case "inicio-aceito": // dia de hoje aceito, e fica na Início (prints do card do dia, prompt 18 · B)
            acceptToday(context: context, region: region, location: location)
            router.select(.hoje)
            prefetchDays(services: services, context: context, region: region)
        case "inicio": // sem dia montado (prints do "Hoje, pra onde?"): tira o dia de hoje de prints anteriores
            clearToday(context: context, region: region)
            router.select(.hoje)
        case "mapa":
            // mapa:aceitar monta e aceita hoje e amanhã antes (rota e pinos numerados).
            if arg == "aceitar" {
                acceptToday(context: context, region: region, location: location)
                acceptToday(context: context, region: region, location: location, offset: 1)
                prefetchDays(services: services, context: context, region: region)
            }
            router.select(.guia)
        case "assistente": router.sheet = .assistant
        case "viagem": router.push(.trip, on: .hoje)
        case "reservas": router.push(.reservations, on: .hoje)
        case "experiencias":
            ExperienceDemo.ensure(context: context, region: region)
            router.push(.experiences, on: .musts)
        case "descobrir": router.push(.discover, on: .hoje)
        case "voos": router.push(.schedule(tab: .voos), on: .hoje)
        case "viagem-voos": router.push(.trip, on: .hoje); router.push(.schedule(tab: .voos), on: .hoje)
        case "viagem-reservas": router.push(.trip, on: .hoje); router.push(.schedule(tab: .reservas), on: .hoje)
        case "carteira": // itens de exemplo (Suica, JR Pass, eSIM, Visit Japan Web com QR) e a Carteira
            WalletDemo.ensure(context: context, region: region)
            router.push(.carteira, on: .hoje)
        case "ingresso-entrada": router.sheet = .ticketImport(inboxId: nil)
        case "ingresso-revisar": // PDF de exemplo na caixa (como o Share Extension faria) e a conferência
            router.sheet = .ticketImport(inboxId: TicketSamples.stashSamplePDF())
        case "ingresso": // ingresso: cria a experiência de exemplo (Tsukiji) e abre o Ingresso
            TicketDemo.ensure(context: context, region: region)
            router.push(.ticket(placeId: TicketDemo.placeId, ticketId: TicketDemo.ticketId), on: .hoje)
        case "como-chegar": // como-chegar:j01 (Naka-Meguro → Udatsu, GPS e hora simulados); com -debugRoutes fake, sem rede
            router.push(.comoChegar(placeId: arg ?? "j01"), on: .hoje)
        case "como-chegar-encontro": // ingresso: o ponto de encontro (Ir ao encontro)
            TicketDemo.ensure(context: context, region: region)
            router.push(.comoChegar(placeId: TicketDemo.placeId, meeting: true), on: .hoje)
        case "uso-google": router.push(.googleUsage, on: .hoje)
        case "compras": // lista de exemplo (câmera, Portra, Kit Kat, ramen tonkotsu, saquê, faca, pomada) e Compras
            ShoppingDemo.ensure(context: context)
            router.push(.compras, on: .hoje)
        case "compras-regras":
            ShoppingDemo.ensure(context: context)
            router.push(.regrasVolta, on: .hoje)
        case "buscar-nome": // buscar-nome:koffee mam (com -debugAutocomplete fake); buscar-nome:koffee mam:escolher já escolhe a 1ª
            router.sheet = .buscarNome(query: (arg ?? "").replacingOccurrences(of: ":escolher", with: ""), listId: nil)
        case "avisos": // avisos do guia do dia aceito, no log (prompt 18 · C.17); não agenda nada
            router.select(.hoje)
            GuideNudgeScheduler.logPreview(context: context, region: region, origin: location.current?.coordinate)
        case "bairros": // bairros (prompt 18 · C.14); bairros:shinjuku já abre a sheet do bairro (prints)
            router.push(.bairros(areaId: arg), on: .hoje)
        case "ajustar": // o que o "Ajustar" da sheet do bairro abre: Bairros e, por cima, o Montar com o foco no bairro
            let area = arg ?? "shinjuku"
            router.push(.bairros(areaId: area), on: .hoje)
            router.push(.montar(date: region.calendar.startOfDay(for: AppClock.now), focusArea: area), on: .hoje)
        case "guia": // Shinjuku+ montado e aceito hoje (se ainda não há dia aceito), e o Guia do dia (prompt 18 · C.16)
            if !hasAcceptedToday(context: context, region: region) {
                acceptFocusToday(context: context, region: region, location: location, areaId: arg ?? "shinjuku")
            }
            router.push(.guia(date: region.calendar.startOfDay(for: AppClock.now)), on: .hoje)
        // v8 (prompt 23 §2), contrato da rodada 22: uma entrada por tela, pros prints do `qa-screens.sh`.
        case "capa": router.select(.hoje)
        case "aceitar-dia": // aceitar-dia:<bairro>: o motor v8 monta (ritmo 9, micro-paradas) e aceita hoje; abre a capa
            acceptEngineToday(context: context, region: region, engine: engine, areaId: arg)
            router.select(.hoje)
        case "bom-dia": router.push(.bomDia, on: .hoje)
        case "agora": router.push(.agora, on: .hoje)
        case "dia", "linha": router.push(.linha(date: region.calendar.startOfDay(for: AppClock.now)), on: .hoje)
        case "ir": router.push(.ir(placeId: arg ?? "j05"), on: .hoje)
        case "noite": router.push(.boaNoite, on: .hoje)
        case "bolso": router.push(.bolso, on: .hoje)
        case "proximos": router.select(.viagem)
        case "museu": router.push(.place(id: arg ?? "r46"), on: .musts)
        // prompt 25 (contrato): Atalhos é um painel sobre a capa (o agente 25/1 lê `-debugScreen atalhos`).
        case "atalhos": router.select(.hoje)
        case "quero": router.sheet = .quero(text: arg) // quero:quero comprar um Seiko
        case "compartilhar", "mandar": router.sheet = .mandar(date: region.calendar.startOfDay(for: AppClock.now))
        case "sos": router.push(.sos, on: .hoje)
        // RODADA-23 + prompt 26 (contrato): uma entrada por tela nova.
        case "emcartaz": router.push(.emCartaz, on: .hoje)
        case "filmes": router.push(.filmes(placeId: arg ?? "j105"), on: .musts)
        case "colecao": router.push(.colecao, on: .viagem)
        case "colecionavel-novo": router.push(.colecao, on: .viagem); CollectibleCelebration.present(for: arg ?? "p01")
        case "trocar-viagem": router.select(.hoje); router.sheet = .viagens
        case "novaviagem1", "novaviagem2", "novaviagem3", "novaviagem4", "novaviagem5", "novaviagem6", "novaviagem7", "novaviagem8", "novaviagem9":
            router.cover = .novaViagem(step: Int(parts[0].dropFirst("novaviagem".count)) ?? 1) // prompt 28 · F3
        case "mapa-pino", "mapa-filtro": router.push(.mapa, on: .hoje) // o agente C lê o debugScreen pra abrir o card/filtro
        case "lugar-amigos", "lugar-emcartaz": router.push(.place(id: arg ?? "j28"), on: .musts)
        case "capa-inteligente": router.select(.hoje)
        case "sincronizar":
            router.push(.settings, on: .hoje)
            Task { await services.sync.syncPlaces(context: context, region: region) }
        default: break
        }
    }

    /// Já há um dia aceito hoje (de um `aceitar-dia` anterior): os prints seguintes usam esse dia.
    private static func hasAcceptedToday(context: ModelContext, region: Region) -> Bool {
        let start = region.calendar.startOfDay(for: AppClock.now)
        let days = (try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == start }))) ?? []
        return days.contains { $0.accepted }
    }

    /// O que o Montar faz com os padrões (ritmo 9, até 23:30, micro-paradas e golden): o dia do motor, aceito.
    private static func acceptEngineToday(context: ModelContext, region: Region, engine: any DayEngine, areaId: String?) {
        let settings = try? context.fetch(FetchDescriptor<Settings>()).first
        let date = region.calendar.startOfDay(for: AppClock.now)
        let budget = DayPlanner(date: date, region: region, settings: settings, existing: nil).budget
        let until = region.calendar.date(byAdding: .minute, value: 23 * 60 + 30, to: date) ?? date
        Task {
            let plan = await engine.build(on: date, area: areaId, pace: .normal, budget: budget, until: until,
                                          includes: [.micro, .goldenPhoto])
            try? DayEngineV8.save(plan, region: region, context: context)
        }
    }

    /// Apaga o dia de hoje (aceito ou não), pra print "sem dia" não herdar o de uma rodada anterior.
    private static func clearToday(context: ModelContext, region: Region) {
        let start = region.calendar.startOfDay(for: AppClock.now)
        let days = (try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == start }))) ?? []
        days.forEach { context.delete($0) }
        try? context.save()
    }

    /// Pré-download dos dias aceitos (como o aceite pela tela faria), conforme a rede do `-debugNetwork`.
    private static func prefetchDays(services: Services, context: ModelContext, region: Region) {
        let network = services.connectivity.prefetchNetwork
        Task { await services.prefetch.runPending(context: context, region: region, network: network, now: AppClock.now) }
    }

    /// Monta e aceita hoje no bairro, com vizinhos (o "Montar <bairro>+" da tela Bairros), pros prints do Guia.
    private static func acceptFocusToday(context: ModelContext, region: Region, location: LocationService, areaId: String) {
        let settings = try? context.fetch(FetchDescriptor<Settings>()).first
        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let date = region.calendar.startOfDay(for: AppClock.now)
        let planner = DayPlanner(date: date, region: region, settings: settings, existing: nil)
        planner.focusArea = areaId
        let flights = FlightRules.dayFlights(context.flights(), on: planner.date, region: region)
        planner.build(catalog: places.solverCatalog, trip: trip, settings: settings, location: location.current, flights: flights)
        try? planner.accept(context: context)
    }

    /// Monta e aceita um dia (hoje + `offset`) com os padrões (prints da tela Hoje e do Mapa).
    private static func acceptToday(context: ModelContext, region: Region, location: LocationService, offset: Int = 0) {
        let settings = try? context.fetch(FetchDescriptor<Settings>()).first
        let trip = try? context.fetch(FetchDescriptor<TripInfo>()).first
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let date = region.calendar.date(byAdding: .day, value: offset, to: AppClock.now) ?? AppClock.now
        let planner = DayPlanner(date: date, region: region, settings: settings, existing: nil)
        let flights = FlightRules.dayFlights(context.flights(), on: planner.date, region: region)
        planner.build(catalog: places.solverCatalog, trip: trip, settings: settings, location: offset == 0 ? location.current : nil, flights: flights)
        try? planner.accept(context: context)
    }
}
#endif
