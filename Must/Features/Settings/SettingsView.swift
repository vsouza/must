import SwiftData
import SwiftUI

/// Ajustes: Dia / Inteligência / Dados. 5 toques no rótulo de versão abrem a sheet Região.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
        ZStack(alignment: .top) {
            Color.must.bg.ignoresSafeArea()
            BlobBackground(style: .custom([
                Blob(cx: 352, cy: 110, rx: 92, ry: 52, rotation: -14, fill: .green),
                Blob(cx: 50, cy: 805, rx: 72, ry: 62, rotation: 10, fill: .blue),
            ]))

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    topBar
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ajustes").mustTitle()
                        Text("como o Must monta o seu dia").mustSerif(18).foregroundStyle(Color.must.secondary)
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                    if let settings = settingsList.first {
                        SettingsSections(settings: settings, region: store.region,
                                         onExport: exportBoard, onReimport: { showReimport = true })
                    }
                    if let exportError {
                        Text(exportError).font(.must.meta).foregroundStyle(Color(hex: 0xC2261D))
                    }
                    Text("Must · \(Self.version) · \(store.region.displayName)")
                        .font(.must.mono(11))
                        .foregroundStyle(Color.must.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showRegion) { RegionSheet() }
        .sheet(isPresented: $showReimport) { ImportView(mode: .reimport) }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                      defaultFilename: BoardCodec(context: context, region: store.region).exportFileName()) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "debugScreen") == "regiao" { showRegion = true }
        }
        #endif
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var topBar: some View {
        HStack {
            IconButton(.voltar, label: "Voltar") { dismiss() }
            Spacer()
            Micro("Must · \(Self.version) · só pra mim")
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture(perform: countVersionTap)
                .accessibilityAddTraits(.isStaticText)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 8)
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

    @State private var editingBudget = false
    @State private var budgetText = ""
    @State private var editingFX = false
    @State private var fxText = ""

    private static let walkOptions: [Double] = [0.5, 1, 1.5, 2, 2.5, 3]
    private static let startOptions: [Int] = stride(from: 6 * 60, through: 12 * 60, by: 30).map { $0 }

    var body: some View {
        VStack(spacing: 14) {
            day
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
            TextField("R$ por ¥100", text: $fxText).keyboardType(.decimalPad)
            Button("Salvar") {
                if let v = Self.parse(fxText), v > 0 {
                    settings.fxRate = v / 100
                    settings.fxDate = AppClock.now
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Quantos reais valem ¥100 hoje?")
        }
    }

    // MARK: Dia

    private var day: some View {
        FormSection("Dia") {
            Button {
                budgetText = region.money(settings.perDayBudget, symbol: false)
                editingBudget = true
            } label: {
                FormRow("Orçamento padrão", subtitle: "por dia, fora reservas aceitas") {
                    MonoValue(region.money(settings.perDayBudget), chevron: true)
                }
            }
            .buttonStyle(.plain)
            RowDivider()
            Toggle(isOn: $settings.oneMealPerWindow) {
                FormRow("Uma refeição por janela", subtitle: "almoço e jantar, exceções pedem confirmação")
            }
            .toggleStyle(.must)
            RowDivider()
            Menu {
                Picker("Andar", selection: $settings.walkMaxKm) {
                    ForEach(Self.walkOptions, id: \.self) { Text(Self.km($0)).tag($0) }
                }
            } label: {
                FormRow("Andar", subtitle: "máximo entre paradas") { MonoValue(Self.km(settings.walkMaxKm)) }
            }
            .buttonStyle(.plain)
            RowDivider()
            Menu {
                Picker("Começar o dia", selection: $settings.dayStartMinutes) {
                    ForEach(Self.startOptions, id: \.self) { Text(Self.hhmm($0)).tag($0) }
                }
            } label: {
                FormRow("Começar o dia", subtitle: "hora que você costuma sair") { MonoValue(settings.dayStart) }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Inteligência

    private var intelligence: some View {
        FormSection("Inteligência") {
            Toggle(isOn: $settings.onDeviceAI) {
                FormRow("Modelo no aparelho", subtitle: OnDeviceAI.unavailableReason.map { "modelo no aparelho indisponível · \($0) · usando palavras-chave" }
                        ?? "Apple Foundation Models · pt/ja · offline")
            }
            .toggleStyle(.must)
            RowDivider()
            Toggle(isOn: $settings.cloudBoost) {
                FormRow("Reforço na nuvem", subtitle: Secrets.anthropicKey == nil
                        ? "Claude Haiku só pra links difíceis · sem chave no Secrets.plist"
                        : "Claude Haiku só pra links difíceis")
            }
            .toggleStyle(.must)
            RowDivider()
            Toggle(isOn: $settings.transcribeVideos) {
                // TODO: transcrição de vídeo (Gemini Flash, YouTube por URL) — fora do escopo desta versão.
                FormRow("Transcrever vídeos", subtitle: "Gemini Flash · YouTube por URL · em breve")
            }
            .toggleStyle(.must)
            .disabled(true)
            .opacity(0.6)
        }
        .glass(cornerRadius: 22)
    }

    // MARK: Dados

    private var data: some View {
        FormSection("Dados") {
            FormRow("Google Places", subtitle: placesSubtitle) {
                HStack(spacing: 8) {
                    Circle().fill(Secrets.googlePlacesKey == nil ? Color(hex: 0xC5C9D0) : Color.must.green).frame(width: 8, height: 8)
                    MonoValue("\(PlacesUsage.thisMonth) usados")
                }
            }
            Button {
                Task { await services.sync.syncPlaces(context: context, region: region) }
            } label: {
                HStack {
                    if let progress = services.sync.placesProgress {
                        ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                            .tint(Color.must.green)
                        Text("\(progress.done)/\(progress.total)").font(.must.mono(13)).foregroundStyle(Color.must.secondary)
                    } else {
                        Pill("Sincronizar horários e preço", style: .green, icon: .outraProposta)
                        Spacer()
                    }
                }
            }
            .buttonStyle(MustPressStyle())
            .disabled(services.sync.isSyncingPlaces)
            .padding(.bottom, 14)
            RowDivider()
            FormRow("Tempo", subtitle: region == .jp ? "Open-Meteo + JMA" : "Open-Meteo") {
                MonoValue(weatherStatus, color: Color.must.secondary)
            }
            RowDivider()
            Toggle(isOn: $settings.flickrPhotos) {
                FormRow("Fotos de fundo", subtitle: "Wikimedia Commons · CC · crédito sempre visível")
            }
            .toggleStyle(.must)
            RowDivider()
            Toggle(isOn: $settings.peopleTips) {
                FormRow("Dicas de pessoas", subtitle: "Google, Foursquare e Reddit no Lugar · desligar economiza chamadas")
            }
            .toggleStyle(.must)
            RowDivider()
            if region == .jp {
                Button {
                    fxText = (settings.fxRate * 100).formatted(.number.locale(region.locale).precision(.fractionLength(2)))
                    editingFX = true
                } label: {
                    FormRow("Moeda", subtitle: settings.fxDate.map { "câmbio salvo \(region.shortDay($0))" }
                            ?? "câmbio padrão · toque pra atualizar") {
                        MonoValue("¥100 = \((settings.fxRate * 100).formatted(.money("BRL")))", chevron: true)
                    }
                }
                .buttonStyle(.plain)
            } else {
                FormRow("Moeda", subtitle: "real · sem câmbio") { MonoValue("R$") }
            }
            RowDivider()
            FormRow("O que sai do aparelho", subtitle: privacyLine)
            RowDivider()
            Button(action: onExport) {
                FormRow("Exportar board (.json)") { MustIconView(.exportar, size: 18).foregroundStyle(Color.must.ink) }
            }
            .buttonStyle(.plain)
            RowDivider()
            Button(action: onReimport) {
                FormRow("Reimportar") { MustIconView(.avancar, size: 14).foregroundStyle(Color.must.secondary) }
            }
            .buttonStyle(.plain)
        }
    }

    /// Só isto vai pra rede; o board, os gastos e a localização ficam no iPhone.
    private var privacyLine: String {
        var items = ["Google Places (nome e coordenada do lugar)", "Open-Meteo (coordenada da cidade)", "Wikimedia Commons (busca de foto)"]
        if settings.cloudBoost { items.append("Claude Haiku (só o texto de legendas difíceis)") }
        return items.joined(separator: " · ")
    }

    private var placesSubtitle: String {
        if Secrets.googlePlacesKey == nil { return "sem chave no Secrets.plist · 1.000 grátis/mês" }
        return services.sync.placesSummary ?? "horários e preço · 1.000 grátis/mês · até \(SyncCoordinator.placesBatch) por vez"
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
        return Double(cleaned)
    }
}

/// Contador de chamadas pagas do Places no mês (o serviço real incrementa no prompt 07).
enum PlacesUsage {
    static var monthKey: String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: AppClock.now)
        return String(format: "places.calls.%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static var thisMonth: Int { UserDefaults.standard.integer(forKey: monthKey) }

    static func record(_ calls: Int = 1) {
        UserDefaults.standard.set(thisMonth + calls, forKey: monthKey)
    }
}
