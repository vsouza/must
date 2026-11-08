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
    @Environment(\.tripTheme) private var theme
    @ScaledMetric(relativeTo: .title) private var scale: CGFloat = 1

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
        VStack(spacing: 0) {
            header
            CutRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(cards) { card in cell(card) }
                    sosCard
                    V8BarSpacer()
                }
            }
            .scrollIndicators(.hidden)
        }
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

    /// Bloco do corte: cor do lugar e trama (sem foto), o título e o que o Bolso é.
    private var header: some View {
        CutBand(photo: nil) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    DayBandCorners(left: [region.profile.day?.pocketTitle ?? "Bolso · \(region.shortName)", "Tudo funciona offline"], right: [])
                    Spacer(minLength: 12)
                    V8CornerButton(systemName: "xmark", label: "Fechar") { dismiss() }
                }
                Spacer(minLength: 8)
                Text("Bolso")
                    .font(V8Font.display(56))
                    .tracking(-1.6)
                    .foregroundStyle(theme.coverInk)
                    .accessibilityAddTraits(.isHeader)
                Text("O que você consulta dez vezes por dia, numa tela só.")
                    .font(V8Font.text(14))
                    .foregroundStyle(theme.coverInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .frame(height: 220 * min(scale, 1.4))
    }

    // MARK: SOS (prompt 25 · C.3: item fixo do Bolso)

    /// A única faixa laranja do Bolso: é ação (o SOS em si, em `Features/SOS/`, continua tinta).
    private var sosCard: some View {
        let numbers = EmergencyKit.bundled.kit(for: region)?.primary.prefix(3).map(\.number) ?? []
        return Button { router.push(.sos) } label: {
            HStack(spacing: 14) {
                Text("SOS")
                    .font(V8Font.numeral(44))
                    .tracking(-1)
                    .foregroundStyle(V8.ink)
                    .frame(width: 100, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preciso de ajuda").font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.ink)
                    Text((numbers + ["hospital", "onde estou"]).joined(separator: " · "))
                        .font(V8Font.text(13)).foregroundStyle(V8.ink.opacity(0.75)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold)).foregroundStyle(V8.ink)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(V8.orange)
            .overlay(alignment: .bottom) { IndexRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SOS, preciso de ajuda")
        .accessibilityHint("números de emergência do país, hospital e onde estou; funciona sem internet")
    }

    // MARK: Faixas

    private func cell(_ card: PocketCard) -> some View {
        Button { tap(card) } label: { PocketCardView(card: card) }
            .buttonStyle(.plain)
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

/// Uma faixa inteira do Bolso: micro-rótulo, valor grande e uma linha de detalhe, régua de 2 pt embaixo. Tinta = o que
/// vem de fora (câmbio, aviso); papel = o resto; aviso (tom laranja do conteúdo) = papel com filete laranja na esquerda.
struct PocketCardView: View {
    var card: PocketCard

    private var lines: Int { card.value.split(separator: "\n").count }
    private var ink: Bool { card.tone == .ink }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SpecLabel(card.label, color: ink ? V8.muteDark : V8.mute)
                Text(card.value.replacingOccurrences(of: "\n", with: " "))
                    .font(card.kind == .exchange ? V8Font.numeral(40) : V8Font.display(lines >= 3 ? 24 : 28))
                    .tracking(-0.8)
                    .foregroundStyle(ink ? V8.orange : V8.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.detail)
                    .font(V8Font.text(13))
                    .foregroundStyle(ink ? V8.muteDark : V8.ink.opacity(0.75))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .bold)).foregroundStyle(ink ? V8.white : V8.ink)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(ink ? V8.ink : Color.clear)
        .overlay(alignment: .leading) {
            if card.tone == .orange { Rectangle().fill(V8.orange).frame(width: 8) }
        }
        .overlay(alignment: .bottom) { IndexRule(color: V8.ink) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.label): \(card.value.replacingOccurrences(of: "\n", with: " ")). \(card.detail)")
    }
}
