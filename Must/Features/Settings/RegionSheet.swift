import CoreLocation
import SwiftData
import SwiftUI

/// Menu escondido (Ajustes → 5 toques na versão): região, dados ao vivo, simulações, logs, zerar.
struct RegionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var trips: [TripInfo]

    @AppStorage(DevOverrides.Key.liveData) private var liveData = true
    @AppStorage(DevOverrides.Key.simDateOn) private var simDateOn = false
    @AppStorage(DevOverrides.Key.simGPSOn) private var simGPSOn = false
    @AppStorage(DevOverrides.Key.simCloud) private var simCloud = -1

    @State private var expanded: Expanded?
    @State private var simDate = AppClock.now
    @State private var latText = ""
    @State private var lngText = ""
    @State private var confirmReset = false
    @State private var confirmResetAgain = false
    @State private var logDocument: TextDocument?
    @State private var showLogExporter = false
    @State private var exportingLogs = false

    private enum Expanded { case date, gps }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.trips.map(Region.init(trip:))) { region in
                        RegionOption(region: region, selected: region == store.region,
                                     subtitle: subtitle(for: region)) { select(region) }
                    }
                } header: { Text("Região") } footer: {
                    Text("Troca board, cidades, moeda, metrô e fontes de dados de uma vez. Cada região tem o próprio board e os próprios gastos; trocar não apaga nada.")
                }

                Section("Testes") {
                    Toggle("Dados ao vivo (Places, tempo)", isOn: $liveData)
                    dateRow
                    gpsRow
                    cloudRow
                    Button(action: exportLogs) {
                        LabeledContent {
                            if exportingLogs { ProgressView() }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Exportar logs")
                                Text("último dia · só esta abertura do app").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    Button("Zerar o board desta região", role: .destructive) { confirmReset = true }
                }

                if let error = store.lastError {
                    Section { Text("Erro no armazenamento: \(error)").font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Região")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            .v9Screen(grouped: true)
            .scrollContentBackground(.hidden)
        }
        .presentationDetents([.large])
        .confirmationDialog("Zerar o board de \(store.region.displayName)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Zerar \(store.region.shortName)", role: .destructive) { confirmResetAgain = true }
        } message: {
            Text("Apaga lugares, gastos e dias desta região e volta pro seed. As outras regiões não mudam.")
        }
        .alert("Tem certeza?", isPresented: $confirmResetAgain) {
            Button("Apagar e reimportar o seed", role: .destructive) {
                store.resetBoard()
                dismiss()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Exporte o board antes se quiser guardar. Não dá pra desfazer.")
        }
        .fileExporter(isPresented: $showLogExporter, document: logDocument, contentType: .plainText,
                      defaultFilename: "must-logs-\(BoardDates(timeZone: store.region.timeZone).dayString(AppClock.now)).txt") { _ in }
        .onAppear(perform: loadGPSFields)
    }

    // MARK: Região

    private func subtitle(for region: Region) -> String {
        switch region {
        case .bh:
            return "board BH · R$ · metrô linha 1 · pt-BR" + (store.region == .bh ? " · agora" : "")
        case .jp:
            var text = "board Japão · ¥ · Tokyo Metro + Toei + JR"
            if store.region == .jp, let trip = trips.first, let start = trip.start, let end = trip.end {
                text += " · \(region.dayNumber(start))–\(region.dayNumber(end)) \(region.monthShort(end))"
            } else if store.region != .jp {
                text += " · 11–24 nov"
            }
            return text
        case .it:
            var text = "board Roma · € · Metro A/B + tram + bus"
            if store.region == .it, let trip = trips.first, let start = trip.start, let end = trip.end {
                text += " · \(region.dayNumber(start))–\(region.dayNumber(end)) \(region.monthShort(end)) · datas a confirmar"
            } else if store.region != .it {
                text += " · abr 2027 a confirmar"
            }
            return text
        default:
            // Viagem criada no app (prompt 28).
            var text = "board \(region.displayName) · \(region.currencySymbol)"
            if let range = region.trip.range { text += " · \(TripSwitcherModel.rangeText(range, region: region))" }
            return text + (store.region == region ? " · agora" : "")
        }
    }

    private func select(_ region: Region) {
        guard region != store.region else { return }
        dismiss()
        RegionSwitch.afterDismiss(region, store: store)
    }

    // MARK: Data simulada

    private var dateRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle(.date) } label: {
                LabeledContent("Simular data e hora") {
                    Text(simDateOn ? store.region.shortDayTime(AppClock.now) : "off").monospacedDigit()
                }
            }
            .foregroundStyle(.primary)
            if expanded == .date {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker("Data e hora", selection: $simDate)
                        .environment(\.timeZone, store.region.timeZone)
                        .environment(\.locale, store.region.locale)
                    HStack(spacing: 8) {
                        Button("Usar") { DevOverrides.simulate(date: simDate); simDateOn = true }.buttonStyle(.borderedProminent).tint(V9.accent)
                        if let preset = datePreset {
                            Button(preset.label) { simDate = preset.date }.buttonStyle(.bordered)
                        }
                        Button("Agora") { simDate = Date() }.buttonStyle(.bordered)
                        if simDateOn {
                            Button("Desligar") { DevOverrides.stopSimulatingDate(); simDateOn = false }.buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.small)
                    Text("O relógio continua andando a partir da data escolhida.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: Nuvens simuladas

    /// Força o % de nuvens da previsão (frase do golden no Lugar photo, solver de fotografia).
    private var cloudRow: some View {
        Picker("Simular nuvens", selection: $simCloud) {
            Text("real").tag(-1)
            Text("20%").tag(20)
            Text("80%").tag(80)
        }
    }

    // MARK: GPS simulado

    private var presets: [(name: String, coordinate: CLLocationCoordinate2D)] {
        DevOverrides.gpsPresets.filter { Region.detect($0.coordinate) == store.region }
    }

    /// Dia de teste da viagem: Japão 15 nov (Udatsu), Roma 14 abr (dia 4, Monti + Colosseo, do `DiaIT.png`).
    private var datePreset: (label: String, date: Date)? {
        let (day, label): (String, String)
        switch store.region {
        case .jp: (day, label) = ("2026-11-15", "15 nov 10:00")
        case .it: (day, label) = ("2027-04-14", "14 abr 10:00")
        default: return nil
        }
        let dates = BoardDates(timeZone: store.region.timeZone)
        guard let start = dates.day(from: day), let at = dates.time("10:00", on: start) else { return nil }
        return (label, at)
    }

    private var gpsLabel: String {
        guard simGPSOn, let c = DevOverrides.simulatedCoordinate else { return "off" }
        if let preset = DevOverrides.gpsPresets.first(where: {
            abs($0.coordinate.latitude - c.latitude) < 0.0005 && abs($0.coordinate.longitude - c.longitude) < 0.0005
        }) { return preset.name }
        return String(format: "%.4f, %.4f", c.latitude, c.longitude)
    }

    private var gpsRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle(.gps) } label: {
                LabeledContent("Simular GPS") { Text(gpsLabel).monospacedDigit() }
            }
            .foregroundStyle(.primary)
            if expanded == .gps {
                VStack(alignment: .leading, spacing: 12) {
                    FlowLayout(spacing: 8) {
                        ForEach(presets, id: \.name) { preset in
                            Button(preset.name) { useGPS(preset.coordinate) }
                                .buttonStyle(.bordered).tint(gpsLabel == preset.name ? V9.accent : nil)
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("lat", text: $latText)
                        TextField("lng", text: $lngText)
                    }
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("Usar") {
                            if let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
                               let lng = Double(lngText.replacingOccurrences(of: ",", with: ".")) {
                                useGPS(CLLocationCoordinate2D(latitude: lat, longitude: lng))
                            }
                        }
                        .buttonStyle(.borderedProminent).tint(V9.accent)
                        if simGPSOn {
                            Button("Desligar") {
                                DevOverrides.stopSimulatingGPS()
                                simGPSOn = false
                                services.location.refreshOverrides()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func useGPS(_ coordinate: CLLocationCoordinate2D) {
        DevOverrides.simulate(coordinate: coordinate)
        simGPSOn = true
        latText = String(format: "%.4f", coordinate.latitude)
        lngText = String(format: "%.4f", coordinate.longitude)
        services.location.refreshOverrides()
    }

    private func loadGPSFields() {
        let c = DevOverrides.simulatedCoordinate ?? store.region.defaultCenter
        latText = String(format: "%.4f", c.latitude)
        lngText = String(format: "%.4f", c.longitude)
        if let now = DevOverrides.simulatedNow { simDate = now }
    }

    private func toggle(_ section: Expanded) {
        withAnimation(.snappy) { expanded = expanded == section ? nil : section }
    }

    // MARK: Logs

    private func exportLogs() {
        exportingLogs = true
        Task {
            let text = await Log.exportText(hours: 24)
            logDocument = TextDocument(text: text)
            exportingLogs = false
            showLogExporter = true
        }
    }
}

/// Linha de uma região: marca de seleção à direita, sublinha com moeda e metrô.
private struct RegionOption: View {
    var region: Region
    var selected: Bool
    var subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(region.displayName).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(region.utcOffsetLabel).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                if selected { Image(systemName: "checkmark").foregroundStyle(V9.accent).accessibilityHidden(true) }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Troca de região depois que a sheet sai (menu escondido e "Minhas viagens"): o root recria a árvore com `.id(region)`,
/// e o `RegionStore` troca o container com o fade de 0,4 s sem apagar nada. Escolher à mão desliga o automático.
@MainActor
enum RegionSwitch {
    static func afterDismiss(_ region: Region, store: RegionStore) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            store.choose(region, near: nil)
        }
    }
}
