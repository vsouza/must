import SwiftData
import SwiftUI

/// Carteira (V9, prompt 32 Fase 2): lista nativa com os cartões (saldo anotado à mão, validade, "Abrir no Wallet") e os
/// documentos (eSIM, QR de entrada, seguro, passaporte). Tudo fica no aparelho e abre sem internet.
struct WalletView: View {
    @Environment(\.openURL) private var openURL
    @Environment(RegionStore.self) private var store
    @Environment(AppRouter.self) private var router

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

        List {
            if region.profile.money?.shoppingList == true {
                Section {
                    Button { router.push(.compras, on: router.tab) } label: {
                        V9Row(title: "Compras da viagem", detail: shopping.isEmpty ? "lista do que trazer" : "\(shopping.count) na lista") {
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if items.isEmpty {
                Section { emptyState }
            } else {
                if !cards.isEmpty {
                    Section("Cartões e passes") {
                        ForEach(cards, id: \.id) { item in
                            WalletCardView(item: item,
                                           facts: WalletCardFacts.make(item, region: region, now: now, cardSpend: cardSpend, fxRate: fxRate),
                                           onTap: { opened = item },
                                           onWallet: { openURL(WalletRules.walletURL) })
                        }
                    }
                }
                if !documents.isEmpty {
                    Section("Documentos · \(documents.count)") {
                        ForEach(documents, id: \.id) { item in
                            Button { opened = item } label: { documentRow(item) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle("Carteira")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { V9OfflineChip() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Adicionar à carteira")
            }
        }
        .v9Screen(grouped: true)
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

    // MARK: Documentos

    private func documentRow(_ item: WalletItem) -> some View {
        let facts = WalletDocumentFacts.make(item, region: region, now: now)
        return HStack(spacing: 12) {
            Text(facts.badge)
                .font(.caption2.weight(.semibold)).monospaced()
                .frame(width: 44, height: 44)
                .background(V9.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                if !facts.subtitle.isEmpty {
                    Text(facts.subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            documentTag(facts)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func documentTag(_ facts: WalletDocumentFacts) -> some View {
        switch facts.emphasis {
        case .ready: Text(facts.tag).font(.footnote.weight(.semibold)).foregroundStyle(V9.accent)
        case .alert: Text(facts.tag).font(.footnote.weight(.semibold)).foregroundStyle(.red)
        case nil: Text(facts.tag).font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: Vazio

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nada guardado ainda").font(.headline)
            Text("Toque em + pra adicionar à mão. Trem e o QR do Visit Japan Web entram pelo Trazer ingresso.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
