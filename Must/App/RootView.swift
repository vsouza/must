import SwiftUI

/// Tab bar flutuante (Início / Hoje / Mapa / Musts), cada aba com a própria NavigationStack.
struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            ForEach(MustTab.allCases) { tab in
                NavigationStack(path: router.path(for: tab)) {
                    root(for: tab)
                        .toolbar(.hidden, for: .navigationBar)
                        .mustDestinations()
                }
                .opacity(router.tab == tab ? 1 : 0)
                .allowsHitTesting(router.tab == tab)
                .accessibilityHidden(router.tab != tab)
            }

            MustTabBar(selected: Binding(get: { router.tab }, set: { router.select($0) }))
                .padding(.bottom, 4)
                .ignoresSafeArea(.keyboard)
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .addLink(let url, let listId): AddLinkView(initialURL: url, preferredListId: listId)
            case .editPlace(let id): EditPlaceView(placeId: id)
            case .newPlace(let listId): EditPlaceView(newInListId: listId)
            case .expense(let placeId): ExpenseView(placeId: placeId)
            case .assistant: AssistantPlaceholder()
            }
        }
        .fullScreenCover(item: $router.cover) { cover in
            switch cover {
            case .newList: NewListFlow()
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
        case .inicio: HomeView()
        case .hoje: TodayView()
        case .mapa: MapPlaceholder()
        case .musts: MustsHubView()
        }
    }
}

/// Espaço reservado pra tab bar no fim das telas roláveis.
struct TabBarSpacer: View {
    var body: some View { Color.clear.frame(height: 96) }
}

// MARK: - Placeholders (prompts 05, 06, 08)

struct MapPlaceholder: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        PlaceholderScreen(title: "Mapa", subtitle: router.mapShowsOpenNow ? "abertos agora perto de você" : "o roteiro no mapa",
                          note: "O mapa customizado chega no prompt 06.", icon: .mapa)
    }
}

struct AssistantPlaceholder: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .assistente)
            VStack(alignment: .leading, spacing: 10) {
                IconButton(.fechar) { dismiss() }
                Spacer()
                Text("Como posso ajudar agora, Vinicius?").mustTitle()
                Text("no aparelho · o Assistente chega no prompt 08").mustSerif(18).foregroundStyle(Color.must.secondary)
                Spacer()
            }
            .padding(22)
        }
    }
}

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
