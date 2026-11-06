import SwiftUI

/// Barra v8 (Hoje / Guia / Musts / Viagem + `+`), cada aba com a própria NavigationStack.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    /// Abas já visitadas: cada uma é montada na primeira vez e fica viva depois (troca de aba não recria).
    /// Antes as quatro subiam no arranque; o Mapa pedia rotas e criava o MLNMapView antes do primeiro frame (prompt 18 · A.6).
    @State private var visited: Set<MustTab> = []

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            ForEach(MustTab.allCases) { tab in
                if visited.contains(tab) || router.tab == tab {
                    NavigationStack(path: router.path(for: tab)) {
                        root(for: tab)
                            .toolbar(.hidden, for: .navigationBar)
                            .mustDestinations()
                    }
                    .opacity(router.tab == tab ? 1 : 0)
                    .allowsHitTesting(router.tab == tab)
                    .accessibilityHidden(router.tab != tab)
                }
            }

            if !router.hidesNavBar {
                // `+`: Quero… (prompt 25 · A); toque longo: Montar o dia de hoje.
                V8NavBar(active: router.tab, onSelect: { router.select($0) },
                         onPlus: { router.sheet = .quero(text: nil) },
                         onPlusHold: { router.push(.montar(date: store.region.calendar.startOfDay(for: AppClock.now)), on: .hoje) })
                    .padding(.bottom, 4)
                    .ignoresSafeArea(.keyboard)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // A aba que sai já estava montada (era a visível): guarda também, senão o Início some ao sair dele.
        .animation(.snappy(duration: 0.25), value: router.hidesNavBar)
        .onChange(of: router.tab) { old, new in visited.formUnion([old, new]) }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .addLink(let url, let listId): AddLinkView(initialURL: url, preferredListId: listId)
            case .editPlace(let id): EditPlaceView(placeId: id)
            case .newPlace(let listId): EditPlaceView(newInListId: listId)
            case .expense(let placeId): ExpenseView(placeId: placeId)
            case .assistant: AssistantView()
            case .ticketImport(let inboxId): TicketImportFlow(inboxId: inboxId)
            case .buscarNome(let query, let listId): BuscarNomeView(initialQuery: query, preferredListId: listId)
            case .quero(let text): QueroView(initialText: text)
            case .mandar(let date): MandarView(date: date)
            case .viagens: TripSwitcherSheet()
            }
        }
        .collectibleCelebration()
        .fullScreenCover(item: $router.cover) { cover in
            switch cover {
            case .newList: NewListFlow()
            case .editList(let id): EditListFlow(listId: id)
            case .novaViagem(let step): NewTripFlow(startStep: step)
            case .gallery:
                #if DEBUG
                Gallery()
                #else
                EmptyView()
                #endif
            }
        }
    }

    @ViewBuilder private func root(for tab: MustTab) -> some View {
        switch tab {
        case .hoje: HomeView() // capa do dia (agente C)
        case .guia: GuiaTabView() // Guia do bairro (agente D)
        case .musts: MustsHubView()
        case .viagem: ProximosView() // Próximos (agente D)
        }
    }
}

/// Espaço reservado pra tab bar no fim das telas roláveis.
struct TabBarSpacer: View {
    var body: some View { Color.clear.frame(height: 96) }
}

// MARK: - Placeholders (prompts 05, 06, 08)

private struct PlaceholderScreen: View {
    var title: String
    var subtitle: String
    var note: String
    var icon: MustIcon

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .hoje)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).mustTitle().padding(.top, 70)
                Text(subtitle).mustSerif(18).foregroundStyle(Color.must.secondary)
                Spacer()
                HStack(spacing: 12) {
                    MustIconView(icon, size: 22)
                    Text(note).mustMeta()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
        }
    }
}
