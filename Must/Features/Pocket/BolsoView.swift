import SwiftData
import SwiftUI

/// 08 · Bolso (prompt 23 §2, `Utilidades.png`; Roma em `BolsoIT.png`): o que se consulta dez vezes por dia, numa grade
/// 2×N, 100 % offline. Conteúdo por país em `PocketRules`; câmbio guardado em Ajustes, saldo anotado da Carteira e
/// último trem da tabela do app. Nada aqui chama rede.
struct BolsoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var settingsList: [Settings]
    @Query(sort: \WalletItem.order) private var wallet: [WalletItem]

    @State private var open: PocketCard?
    @State private var showConverter = false
    @State private var showPhrases = false

    private var region: Region { store.region }

    private var transitCard: WalletItem? {
        wallet.first { $0.kind == .transitCard && $0.balance != nil } ?? wallet.first { $0.kind == .transitCard }
    }

    private var context: PocketContext {
        PocketContext(now: AppClock.now, brlPerUnit: settingsList.first?.fxRate, transitBalance: transitCard?.balance,
                      lastTrain: LastTrains.home(region: region, near: services.location.current?.coordinate,
                                                 transit: TransitLoader.load(region)))
    }

    var body: some View {
        let cards = PocketRules.cards(for: region, context: context)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.top, 8)
                Text("Bolso")
                    .font(V8Font.display(52))
                    .tracking(-1.6)
                    .foregroundStyle(V8.ink)
                    .padding(.top, 26)
                    .accessibilityAddTraits(.isHeader)
                Text("O que você consulta dez vezes por dia, numa tela só.")
                    .font(V8Font.text(15))
                    .foregroundStyle(V8.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                grid(cards).padding(.top, 34)
                V8BarSpacer()
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $open) { card in
            PocketDetailSheet(card: card, region: region, onWallet: card.kind == .transitCard ? {
                open = nil
                router.push(.carteira)
            } : nil)
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showConverter) {
            PocketConverterSheet(region: region, rate: PocketRules.rate(region, stored: settingsList.first?.fxRate))
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showPhrases) {
            PocketPhrasesSheet(region: region).presentationDetents([.large])
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            V8SpecStack(lines: [region == .jp ? "Utilidades" : "Bolso · \(region.shortName)", "Tudo funciona offline"])
                .padding(.top, 14)
            Spacer(minLength: 12)
            V8CornerButton(systemName: "xmark", label: "Fechar") { dismiss() }
        }
    }

    // MARK: Grade

    private func grid(_ cards: [PocketCard]) -> some View {
        let rows = stride(from: 0, to: cards.count, by: 2).map { Array(cards[$0..<min($0 + 2, cards.count)]) }
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { card in cell(card) }
                    if row.count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
    }

    private func cell(_ card: PocketCard) -> some View {
        Button { tap(card) } label: { PocketCardView(card: card) }
            .buttonStyle(MustPressStyle())
            .accessibilityHint(card.kind == .exchange ? "abre o conversor" : card.kind == .phrases ? "abre as frases com áudio" : "abre o detalhe")
    }

    private func tap(_ card: PocketCard) {
        switch card.kind {
        case .exchange: showConverter = true
        case .phrases: showPhrases = true
        default: open = card
        }
    }
}

/// Um card da grade: micro-rótulo, valor grande (uma a três linhas) e uma linha de detalhe.
struct PocketCardView: View {
    var card: PocketCard

    private var lines: Int { card.value.split(separator: "\n").count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SpecLabel(card.label, color: labelColor)
            Spacer(minLength: 8)
            Text(card.value)
                .font(card.kind == .exchange ? V8Font.numeral(lines > 1 ? 30 : 34) : V8Font.display(lines >= 3 ? 23 : (lines == 2 ? 26 : 32)))
                .tracking(-0.8)
                .foregroundStyle(valueColor)
                .lineSpacing(-4)
                .lineLimit(lines)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(card.detail)
                .font(V8Font.text(13))
                .foregroundStyle(detailColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill))
        .overlay {
            if card.tone == .white {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(V8.ink.opacity(0.1), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.label): \(card.value.replacingOccurrences(of: "\n", with: " ")). \(card.detail)")
    }

    private var fill: Color {
        switch card.tone {
        case .ink: V8.ink
        case .orange: V8.orange
        case .white: V8.white
        }
    }

    private var labelColor: Color {
        switch card.tone {
        case .ink: V8.white.opacity(0.85)
        case .orange: V8.ink.opacity(0.7)
        case .white: V8.mute
        }
    }

    private var valueColor: Color { card.tone == .ink ? V8.orange : V8.ink }
    private var detailColor: Color { card.tone == .ink ? V8.muteDark : V8.ink.opacity(0.8) }
}
