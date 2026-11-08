import SwiftData
import SwiftUI

/// Carteira (`design/screens/Carteira.png`): cartões empilhados (saldo anotado à mão, validade, "Abrir no Wallet")
/// e a lista de documentos (eSIM, QR de entrada, seguro, passaporte). Tudo fica no aparelho.
struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(RegionStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.tripTheme) private var theme

    @Query(sort: [SortDescriptor(\WalletItem.order), SortDescriptor(\WalletItem.createdAt)]) private var items: [WalletItem]
    @Query private var expenses: [Expense]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var shopping: [ShoppingItem]

    @State private var opened: WalletItem?
    @State private var adding = false

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var cards: [WalletItem] { items.filter { $0.kind.isCard } }
    private var documents: [WalletItem] { items.filter { !$0.kind.isCard } }

    var body: some View {
        let trip = trips.first?.hasTrip == true ? trips.first : nil
        let period = TripStats.period(trip: trip, now: now, calendar: region.calendar)
        let cardSpend = TripStats.spent(expenses.filter { $0.method == .card }, in: period, calendar: region.calendar)
        let fxRate = settingsList.first?.fxRate ?? 0

        VStack(spacing: 0) {
            CutScreenHeader(title: "Carteira", corner: ["\(region.shortName) · central"], subtitle: "Cartões, passes e documentos. Toque e vai.",
                            height: 220, onBack: { dismiss() }) {
                CutCornerButton(systemName: "plus", label: "Adicionar à carteira", tint: theme.coverInk) { adding = true }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if region.profile.money?.shoppingList == true {
                        Button { router.push(.compras, on: router.tab) } label: {
                            CutRow(title: "Compras da viagem", detail: shopping.isEmpty ? "lista do que trazer" : "\(shopping.count) na lista") {
                                CutValue(text: "abrir", chevron: true)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if items.isEmpty {
                        emptyState
                    } else {
                        if !cards.isEmpty {
                            cardStack(cardSpend: cardSpend, fxRate: fxRate)
                        }
                        if !documents.isEmpty {
                            CutSection(label: "documentos · \(documents.count)", inset: false) { documentList }
                        }
                    }
                    V8BarSpacer()
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            #if DEBUG
            switch DebugFlags.string("debugScreen") {
            case "carteira-editor": adding = true
            case "carteira-item": opened = items.first
            default: break
            }
            #endif
        }
        .sheet(item: $opened) { item in WalletItemSheet(item: item) }
        .sheet(isPresented: $adding) { WalletEditor(item: nil) }
    }

    // MARK: Cartões

    /// Cartões empilhados, cada um girado um pouco (1–2°), como o design.
    private func cardStack(cardSpend: Double, fxRate: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(cards, id: \.id) { item in
                WalletCardView(item: item,
                               facts: WalletCardFacts.make(item, region: region, now: now, cardSpend: cardSpend, fxRate: fxRate),
                               onTap: { opened = item },
                               onWallet: { openURL(WalletRules.walletURL) })
            }
        }
    }

    // MARK: Documentos

    private var documentList: some View {
        VStack(spacing: 0) {
            ForEach(documents, id: \.id) { item in
                Button { opened = item } label: { documentRow(item) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func documentRow(_ item: WalletItem) -> some View {
        let facts = WalletDocumentFacts.make(item, region: region, now: now)
        return HStack(spacing: 12) {
            Text(facts.badge)
                .font(V8Font.mono(10, weight: .semibold))
                .foregroundStyle(V8.ink)
                .frame(width: 44, height: 44)
                .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                if !facts.subtitle.isEmpty {
                    Text(facts.subtitle).font(V8Font.text(13)).foregroundStyle(V8.mute).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            documentTag(facts)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { IndexRule() }
        .contentShape(Rectangle())
    }

    @ViewBuilder private func documentTag(_ facts: WalletDocumentFacts) -> some View {
        switch facts.emphasis {
        case .ready: CutTag(text: facts.tag, filled: true, orange: true)
        case .alert: CutTag(text: facts.tag, filled: true)
        case nil: CutTag(text: facts.tag)
        }
    }

    // MARK: Vazio

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("nada guardado ainda", size: 10, color: V8.mute)
            Text("Toque em + pra adicionar à mão. Trem e o QR do Visit Japan Web entram pelo Trazer ingresso.")
                .font(V8Font.text(15)).foregroundStyle(V8.ink)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { IndexRule() }
    }
}
