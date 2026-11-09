import SwiftUI

/// O que a barra nativa seleciona: uma das quatro abas ou a lupa (o Quero…).
enum RootTab: Hashable {
    case main(MustTab)
    case quero
}

/// Barra de abas nativa do iOS 26 (Liquid Glass): Hoje · Explorar · Musts · Viagem e, separada à direita, a lupa que é o
/// Quero…. Cada aba tem a própria NavigationStack. A faixa "agora" fica na `tabViewBottomAccessory`.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    /// Contexto estável de Hoje (prompt 32 §3): um por árvore (a árvore é recriada ao trocar de região).
    @State private var todayContext = TodayContextModel()

    private var selection: Binding<RootTab> {
        Binding(get: { router.queroSelected ? .quero : .main(router.tab) },
                set: { new in
                    switch new {
                    case .quero: router.openQuero()
                    case .main(let tab): router.select(tab)
                    }
                })
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: selection) {
            ForEach(MustTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: RootTab.main(tab)) {
                    NavigationStack(path: router.path(for: tab)) {
                        root(for: tab)
                            .toolbar(.hidden, for: .navigationBar)
                            .mustDestinations()
                    }
                    // Telas que escondiam a barra (Montar, Ir, Lugar, SOS, quero aberto…).
                    .toolbar(router.hidesNavBar ? .hidden : .visible, for: .tabBar)
                }
            }
            Tab("Quero", systemImage: "magnifyingglass", value: RootTab.quero, role: .search) {
                QueroTabPage().v8Legacy()
            }
        }
        .tint(V9.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .modifier(NowAccessoryModifier(enabled: !router.hidesNavBar && !router.queroSelected))
        .sheet(item: $router.sheet) { sheet in
            Group {
            switch sheet {
            case .addLink(let url, let listId): AddLinkView(initialURL: url, preferredListId: listId)
            case .editPlace(let id): EditPlaceView(placeId: id)
            case .newPlace(let listId): EditPlaceView(newInListId: listId)
            case .expense(let placeId): ExpenseView(placeId: placeId)
            case .assistant: AssistantView().presentationCornerRadius(0)
            case .assistantAsk(let text): AssistantView(initialQuestion: text).presentationCornerRadius(0)
            case .ticketImport(let inboxId): TicketImportFlow(inboxId: inboxId)
            case .buscarNome(let query, let listId): BuscarNomeView(initialQuery: query, preferredListId: listId)
            case .mandar(let date): MandarView(date: date)
            case .viagens: TripSwitcherSheet()
            case .presenteNovo(let source): PresenteNovoView(source: source)
            case .aOuB(let placeId): NovaVotacaoView(placeId: placeId)
            }
            }
            .v8LegacySheet(sheet.legacyLight)
        }
        .environment(todayContext)
        .collectibleCelebration()
        .fullScreenCover(item: $router.cover) { cover in
            Group {
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
            .v8LegacySheet()
        }
    }

    @ViewBuilder private func root(for tab: MustTab) -> some View {
        // Prompt 32: cada raiz convertida pro V9 tira o `.v8Legacy()` (modo escuro só nas telas V9).
        switch tab {
        case .hoje: HomeView().v8Legacy()
        case .explorar: ExplorarView().v8Legacy()
        case .musts: MustsHubView().v8Legacy()
        case .viagem: ProximosView().v8Legacy()
        }
    }
}

/// Antes reservava 96 pt pra barra customizada; a barra nativa já entra na safe area. Sobra só um respiro.
struct TabBarSpacer: View {
    var body: some View { Color.clear.frame(height: 16) }
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

extension AppRouter.Sheet {
    /// Sheets que ainda são V8 (ficam no claro). Tirar daqui ao converter.
    var legacyLight: Bool {
        switch self {
        default: return true
        }
    }
}
