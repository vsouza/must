import SwiftData
import SwiftUI

/// Carteira (`design/screens/Carteira.png`): cartões empilhados (saldo anotado à mão, validade, "Abrir no Wallet")
/// e a lista de documentos (eSIM, QR de entrada, seguro, passaporte). Tudo fica no aparelho.
struct WalletView: View {
    @Environment(\.dismiss) private var dismiss
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

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Carteira").mustTitle()
                    Text("cartões, passes e documentos — toque e vai direto pro Wallet ou pro app")
                        .mustSerif(18).foregroundStyle(Color.must.secondary)
                    if region == .jp {
                        Button { router.push(.compras, on: router.tab) } label: {
                            Tag(shopping.isEmpty ? "Compras da viagem" : "Compras da viagem · \(shopping.count)")
                        }
                        .buttonStyle(MustPressStyle())
                        .padding(.top, 6)
                    }
                }
                .padding(.top, 22)

                if items.isEmpty {
                    emptyState.padding(.top, 28)
                } else {
                    if !cards.isEmpty {
                        cardStack(cardSpend: cardSpend, fxRate: fxRate).padding(.top, 26)
                    }
                    if !documents.isEmpty {
                        documentList.padding(.top, 26)
                    }
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background(Color.must.bg)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $opened) { item in WalletItemSheet(item: item) }
        .sheet(isPresented: $adding) { WalletEditor(item: nil) }
    }

    // MARK: Topo

    private var topBar: some View {
        HStack {
            IconButton(.voltar, label: "Voltar") { dismiss() }
            Spacer()
            Micro("\(region.shortName) · central da viagem")
            Spacer()
            IconButton(.adicionar, style: .dark, label: "Adicionar à carteira") { adding = true }
        }
    }

    // MARK: Cartões

    /// Cartões empilhados, cada um girado um pouco (1–2°), como o design.
    private func cardStack(cardSpend: Double, fxRate: Double) -> some View {
        let tilts: [Double] = [-1.5, 1, -0.8]
        return VStack(spacing: -16) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, item in
                WalletCardView(item: item,
                               facts: WalletCardFacts.make(item, region: region, now: now, cardSpend: cardSpend, fxRate: fxRate),
                               rotation: tilts[index % tilts.count],
                               onTap: { opened = item },
                               onWallet: { openURL(WalletRules.walletURL) })
            }
        }
    }

    // MARK: Documentos

    private var documentList: some View {
        VStack(spacing: 0) {
            ForEach(Array(documents.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                Button { opened = item } label: { documentRow(item) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.must.line))
    }

    private func documentRow(_ item: WalletItem) -> some View {
        let facts = WalletDocumentFacts.make(item, region: region, now: now)
        return HStack(spacing: 12) {
            Text(facts.badge)
                .font(.must.mono(10, .semibold))
                .foregroundStyle(Color.must.ink)
                .frame(width: 34, height: 34)
                .background(Color.must.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                if !facts.subtitle.isEmpty {
                    Text(facts.subtitle).font(.must.archivo(12)).foregroundStyle(Color.must.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            documentTag(facts)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func documentTag(_ facts: WalletDocumentFacts) -> some View {
        switch facts.emphasis {
        case .ready: Tag(facts.tag, style: .green)
        case .alert: Tag(facts.tag, dot: Color(hex: 0xFFB020))
        case nil: Tag(facts.tag)
        }
    }

    // MARK: Vazio

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("nada guardado ainda")
            Text("Toque em + pra adicionar à mão. Trem e o QR do Visit Japan Web entram pelo Trazer ingresso.")
                .mustMeta()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
