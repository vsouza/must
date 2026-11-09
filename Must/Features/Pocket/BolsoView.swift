import SwiftData
import SwiftUI

/// Bolso (V9, prompt 32 Fase 2): o que se consulta dez vezes por dia, numa lista nativa, 100 % offline. Empilhado a partir da
/// capa (botão de voltar do sistema). No topo, os atalhos (Suica, ingressos de hoje, mapa offline, SOS, linhas perto).
/// Conteúdo por país em `PocketRules`; câmbio guardado em Ajustes, saldo anotado da Carteira e último trem da tabela do
/// app. Nada aqui chama rede.
struct BolsoView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var settingsList: [Settings]
    @Query(sort: \WalletItem.order) private var wallet: [WalletItem]
    @Query private var places: [Place]

    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
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
        List {
            AtalhosPanel { run($0) }
            Section(region.profile.day?.pocketTitle ?? "Bolso · \(region.shortName)") {
                ForEach(cards) { card in
                    Button { tap(card) } label: { PocketCardView(card: card) }
                        .buttonStyle(.plain)
                        .accessibilityHint(card.kind == .exchange ? "abre o conversor" : card.kind == .phrases ? "abre as frases com áudio" : "abre o detalhe")
                }
            }
            Section { sosRow }
            Section { syncRow }
        }
        .navigationTitle("Bolso")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { V9OfflineChip() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .assistant } label: { Image(systemName: "sparkles") }.accessibilityLabel("Assistente")
            }
        }
        .v9Screen(grouped: true)
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

    /// O que um toque nos atalhos do topo faz (o Bolso é uma tela empurrada: as rotas empilham em cima dele).
    private func run(_ action: AtalhosAction) {
        switch action {
        case .route(let route): router.push(route)
        case .sheet(let sheet): router.sheet = sheet
        case .selectTab(let tab): router.select(tab)
        case .url(let url): openURL(url)
        }
    }

    // MARK: SOS (prompt 25 · C.3: item fixo do Bolso)

    private var sosRow: some View {
        let numbers = EmergencyKit.bundled.kit(for: region)?.primary.prefix(3).map(\.number) ?? []
        return Button { router.push(.sos) } label: {
            HStack(spacing: 12) {
                Image(systemName: "cross.case.fill").font(.title2).foregroundStyle(.red).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SOS · preciso de ajuda").font(.headline).foregroundStyle(.red)
                    Text((numbers + ["hospital", "onde estou"]).joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("SOS, preciso de ajuda")
        .accessibilityHint("números de emergência do país, hospital e onde estou; funciona sem internet")
    }

    /// A linha de confiança: "105 lugares · 94 confirmados" e sincronizar (só no Wi-Fi), como em Ajustes.
    private var syncRow: some View {
        let confidence = BoardConfidence(places)
        let wifi = services.connectivity.isWiFi
        return Button {
            Task { await services.sync.syncPlaces(context: modelContext, region: region) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(confidence.headline).font(.body).foregroundStyle(.primary)
                    Text(confidence.detail(onWiFi: wifi)).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(confidence.isComplete ? "ok" : "Sincronizar").font(.subheadline).foregroundStyle(confidence.isComplete ? Color.secondary : V9.accent)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(services.sync.isSyncingPlaces || confidence.isComplete || !wifi)
        .accessibilityHint("Busca horário e local no Google, só no Wi-Fi")
    }

    private func tap(_ card: PocketCard) {
        switch card.kind {
        case .exchange: showConverter = true
        case .phrases: showPhrases = true
        default: open = card
        }
    }
}

/// Uma linha do Bolso: rótulo pequeno, valor e detalhe, tudo quebrando. Aviso (tom laranja do conteúdo) em acento; o que
/// vem de fora (câmbio) com o valor em acento.
struct PocketCardView: View {
    var card: PocketCard

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.label.capitalized).font(.footnote.weight(.semibold))
                    .foregroundStyle(card.tone == .orange ? V9.accent : Color.secondary)
                Text(card.value.replacingOccurrences(of: "\n", with: " "))
                    .font(card.kind == .exchange ? .title2.weight(.bold) : .body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(card.tone == .ink ? V9.accent : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(card.detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.label): \(card.value.replacingOccurrences(of: "\n", with: " ")). \(card.detail)")
    }
}
