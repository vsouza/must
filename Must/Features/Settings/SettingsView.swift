import SwiftData
import SwiftUI

/// Ajustes: Dia / Inteligência / Dados. 5 toques no rótulo de versão abrem a sheet Região.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Query private var settingsList: [Settings]

    @State private var showRegion = false
    @State private var showReimport = false
    @State private var versionTaps: [Date] = []
    @State private var exportDocument: BoardDocument?
    @State private var showExporter = false
    @State private var exportError: String?

    var body: some View {
        Form {
            RegionPicker()
            OfflineMapsRow()
            if let settings = settingsList.first {
                SettingsSections(settings: settings, region: store.region,
                                 onExport: exportBoard, onReimport: { showReimport = true })
            }
            if let exportError {
                Section { Text(exportError).font(.footnote).foregroundStyle(.red) }
            }
            // O menu de testes (região, simular data/GPS) abre com 5 toques aqui. Não é navegação.
            Section {
                Text("Must · \(Self.version) · \(store.region.displayName)")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: countVersionTap)
                    .accessibilityAddTraits(.isStaticText)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.large)
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showRegion) { RegionSheet() }
        .sheet(isPresented: $showReimport) { ImportView(mode: .reimport) }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: BoardCodec(context: context, region: store.region).exportFileName()) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        #if DEBUG
        .onAppear {
            if DebugFlags.string("debugScreen") == "regiao" { showRegion = true }
        }
        #endif
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    /// 5 toques em menos de 3 s.
    private func countVersionTap() {
        let now = Date()
        versionTaps = versionTaps.filter { now.timeIntervalSince($0) < 3 } + [now]
        if versionTaps.count >= 5 {
            versionTaps = []
            showRegion = true
        }
    }

    private func exportBoard() {
        do {
            let board = try BoardCodec(context: context, region: store.region).export()
            exportDocument = BoardDocument(data: try BoardCodec.encode(board))
            exportError = nil
            showExporter = true
        } catch {
            exportError = error.localizedDescription
        }
    }
}

/// As três seções, ligadas ao `Settings` da região.
private struct SettingsSections: View {
    @Bindable var settings: Settings
    var region: Region
    var onExport: () -> Void
    var onReimport: () -> Void

    @Environment(Services.self) private var services
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    @State private var editingBudget = false
    @State private var budgetText = ""
    @State private var editingFX = false
    @State private var fxText = ""

    private static let walkOptions: [Double] = [0.5, 1, 1.5, 2, 2.5, 3]
    private static let startOptions: [Int] = stride(from: 6 * 60, through: 12 * 60, by: 30).map { $0 }

    var body: some View {
        Group {
            day
            AvisosForm()
            intelligence
            data
        }
        .alert("Orçamento padrão", isPresented: $editingBudget) {
            TextField(region.currencySymbol, text: $budgetText).keyboardType(.decimalPad)
            Button("Salvar") {
                if let v = Self.parse(budgetText), v >= 0 { settings.perDayBudget = v }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Por dia, em \(region.currencySymbol). Reservas aceitas ficam fora.")
        }
        .alert("Câmbio", isPresented: $editingFX) {
            TextField("R$ por \(region.fxUnitLabel)", text: $fxText).keyboardType(.decimalPad)
            Button("Salvar") {
                if let v = Self.parse(fxText), v > 0 {
                    settings.fxRate = v / region.fxUnit
                    settings.fxDate = AppClock.now
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Quantos reais valem \(region.fxUnitLabel) hoje?")
        }
    }

    // MARK: Dia

    private var day: some View {
        Section("Dia") {
            Button {
                budgetText = region.money(settings.perDayBudget, symbol: false)
                editingBudget = true
            } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text(region.money(settings.perDayBudget)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                } label: {
                    row("Orçamento padrão", "por dia, fora reservas aceitas")
                }
            }
            .foregroundStyle(.primary)
            Toggle(isOn: $settings.oneMealPerWindow) {
                row("Uma refeição por janela", "almoço e jantar, exceções pedem confirmação")
            }
            Picker(selection: $settings.walkMaxKm) {
                ForEach(Self.walkOptions, id: \.self) { Text(Self.km($0)).tag($0) }
            } label: { row("Andar", "máximo entre paradas") }
            Picker(selection: $settings.dayStartMinutes) {
                ForEach(Self.startOptions, id: \.self) { Text(Self.hhmm($0)).tag($0) }
            } label: { row("Começar o dia", "hora que você costuma sair") }
        }
    }

    private func row(_ title: String, _ subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    // MARK: Inteligência

    private var intelligence: some View {
        Section("Inteligência") {
            Toggle(isOn: $settings.onDeviceAI) {
                row("Modelo no aparelho", OnDeviceAI.unavailableReason.map { "Indisponível: \($0). Usando palavras-chave." }
                    ?? "Apple Foundation Models · pt/ja · offline")
            }
            Toggle(isOn: $settings.cloudBoost) {
                row("Reforço na nuvem", Secrets.anthropicKey == nil
                    ? "Claude Haiku só pra links difíceis · sem chave no Secrets.plist"
                    : "Claude Haiku só pra links difíceis")
            }
            Toggle(isOn: $settings.transcribeVideos) {
                // TODO: transcrição de vídeo (Gemini Flash, YouTube por URL) — fora do escopo desta versão.
                row("Transcrever vídeos", "Gemini Flash · YouTube por URL · em breve")
            }
            .disabled(true)
        }
    }

    // MARK: Dados

    private var flightRow: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Circle().fill(Secrets.aerodataboxKey == nil ? Color.secondary : V9.accent).frame(width: 8, height: 8)
                Text("\(FlightQuota.used()) / \(FlightQuota.planLimit)").monospacedDigit()
            }
        } label: { row("Status de voo", flightSubtitle) }
    }

    private var flightSubtitle: String {
        if Secrets.aerodataboxKey == nil { return "AeroDataBox · sem chave: só o horário programado" }
        if FlightQuota.isBlocked() { return "AeroDataBox · cota recusada neste mês · volta no mês que vem" }
        return "AeroDataBox · 2 unidades por consulta · para em \(FlightQuota.monthlyCap)"
    }

    private var data: some View {
        Group {
            Section("Dados") {
                Button { router.push(.googleUsage, on: .hoje) } label: {
                    LabeledContent {
                        HStack(spacing: 6) {
                            Circle().fill(Secrets.googlePlacesKey == nil ? Color.secondary : V9.accent).frame(width: 8, height: 8)
                            Text("\(ApiBudget.placesUsedThisMonth()) usados").monospacedDigit()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                    } label: { row("Google Maps", placesSubtitle) }
                }
                .foregroundStyle(.primary)
                TrustSyncRows()
                if let progress = services.sync.placesProgress {
                    HStack {
                        ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                        Text("\(progress.done)/\(progress.total)").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    Button("Sincronizar horários e preço") {
                        Task { await services.sync.syncPlaces(context: context, region: region) }
                    }
                    .disabled(services.sync.isSyncingPlaces)
                }
                PhotoDataRows()
                flightRow
                LabeledContent {
                    Text(weatherStatus).foregroundStyle(.secondary)
                } label: { row("Tempo", region.profile.transit?.weatherLabel ?? "Open-Meteo") }
            }
            Section("Fontes") {
                Toggle(isOn: $settings.flickrPhotos) {
                    row("Fotos de fundo", "Google Places e Wikimedia Commons · crédito sempre visível")
                }
                Toggle(isOn: $settings.peopleTips) {
                    row("Dicas de pessoas", "Google, Foursquare e Reddit no Lugar · desligar economiza chamadas")
                }
                Toggle(isOn: $settings.suggestNearby) {
                    row("Sugerir por perto", "Google, Wikipedia e Foursquare · a Home só lê o cache")
                }
                if region.hasFX {
                    Button {
                        fxText = (settings.fxRate * region.fxUnit).formatted(.number.locale(region.locale).precision(.fractionLength(2)))
                        editingFX = true
                    } label: {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text("\(region.fxUnitLabel) = \((settings.fxRate * region.fxUnit).formatted(.money("BRL")))").monospacedDigit()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        } label: {
                            row("Moeda", settings.fxDate.map { "câmbio salvo \(region.shortDay($0))" } ?? "câmbio padrão · toque pra atualizar")
                        }
                    }
                    .foregroundStyle(.primary)
                } else {
                    LabeledContent { Text("R$") } label: { row("Moeda", "real · sem câmbio") }
                }
            }
            Section {
                row("O que sai do aparelho", privacyLine)
                Button { router.push(.board(edit: false)) } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    } label: { row("Board completo", "todos os lugares · editar listas e lugares") }
                }
                .foregroundStyle(.primary)
                Button("Exportar board (.json)", action: onExport)
                Button("Reimportar", action: onReimport)
            } header: { Text("Board e privacidade") }
        }
    }

    /// Só isto vai pra rede; o board, os gastos e a localização ficam no iPhone.
    private var privacyLine: String {
        var items = ["Google Places (nome e coordenada do lugar)", "Open-Meteo (coordenada da cidade)", "Wikimedia Commons (busca de foto)"]
        if settings.cloudBoost { items.append("Claude Haiku (só o texto de legendas difíceis)") }
        return items.joined(separator: " · ")
    }

    private var placesSubtitle: String {
        if Secrets.googlePlacesKey == nil { return "sem chave no Secrets.plist · uso por SKU ao tocar" }
        return services.sync.placesSummary ?? "horários, preço e fotos · uso por SKU ao tocar · até \(SyncCoordinator.placesBatch) por vez"
    }

    private var weatherStatus: String {
        guard DevOverrides.liveData else { return "só cache" }
        switch services.sync.status {
        case .ok(let date): return "ok · \(region.timeString(date))"
        case .syncing: return "atualizando"
        case .failed: return "falhou"
        case .offline: return "só cache"
        case .idle: return "—"
        }
    }

    // MARK: Formatação

    static func km(_ value: Double) -> String {
        "\(value.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(0...1)))) km"
    }

    static func hhmm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return NumberInput.double(cleaned)
    }
}

/// Avisos do guia (liga/desliga de cada um), em Form nativo. Mesma lógica do `AvisosDoGuiaSection` do V8.
private struct AvisosForm: View {
    @Environment(\.modelContext) private var context
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @AppStorage(GuideNudgeScheduler.enabledKey) private var all = true
    @AppStorage(GuideNudgeScheduler.key(.morning)) private var morning = true
    @AppStorage(GuideNudgeScheduler.key(.leave)) private var leave = true
    @AppStorage(GuideNudgeScheduler.key(.golden)) private var golden = true
    @AppStorage(GuideNudgeScheduler.key(.lastTrain)) private var lastTrain = true
    @AppStorage(GuideNudgeScheduler.key(.opens)) private var opens = true

    var body: some View {
        Section {
            Toggle("Avisos do guia", isOn: $all)
            if all {
                row($morning, "Bom dia", "07:20 · o bairro de hoje e a primeira parada")
                row($leave, "Saia em 5 min", "pra próxima parada · com a Live Activity")
                row($golden, "Golden em 20 min", "quando o dia tem foto no golden")
                row($lastTrain, "Último trem", "50 min antes · ou 23:50")
                row($opens, "Abre agora", "quando um lugar do dia abre depois que você saiu")
            }
        } header: { Text("Avisos do guia") } footer: { Text("Só no aparelho · no máximo 1 a cada 45 min.") }
        .onChange(of: [all, morning, leave, golden, lastTrain, opens]) { _, _ in reschedule() }
    }

    private func row(_ value: Binding<Bool>, _ title: String, _ subtitle: String) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func reschedule() {
        let region = store.region
        let origin = services.location.current?.coordinate
        let context = context
        Task {
            if all {
                await GuideNudgeScheduler.refresh(context: context, region: region, origin: origin, askPermission: false)
            } else {
                await GuideNudgeScheduler.disable()
            }
        }
    }
}
