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
        CutSheet(title: "Região", corner: ["escondido", "5 toques na versão"],
                 subtitle: "troca board, cidades, moeda, metrô e fontes de dados de uma vez",
                 height: 190, footer: "Fechar", footerArrow: false, onFooter: { dismiss() }) {
            ForEach(store.trips.map(Region.init(trip:))) { region in
                RegionOption(region: region, selected: region == store.region,
                             subtitle: subtitle(for: region)) { select(region) }
            }

            FormSection {
                Button { liveData.toggle() } label: {
                    FormRow("Dados ao vivo (Places, tempo)") {
                        StatusChip(text: liveData ? "ligado" : "desligado", on: liveData)
                    }
                }
                .buttonStyle(.plain)
                RowDivider()
                dateRow
                RowDivider()
                gpsRow
                RowDivider()
                cloudRow
                RowDivider()
                Button(action: exportLogs) {
                    FormRow("Exportar logs", subtitle: "último dia · só esta abertura do app") {
                        if exportingLogs { ProgressView() } else {
                            MustIconView(.avancar, size: 14).foregroundStyle(Color.must.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                RowDivider()
                Button { confirmReset = true } label: {
                    FormRow("Zerar o board desta região", titleColor: V8.orangeDeep)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)

            if let error = store.lastError {
                Text("Erro no armazenamento: \(error)").font(.must.meta).foregroundStyle(V8.orangeDeep)
            }

            Text("Cada região tem o próprio board e os próprios gastos. Trocar não apaga nada.")
                .font(.must.meta)
                .foregroundStyle(Color.must.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
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
                FormRow("Simular data e hora") {
                    MonoValue(simDateOn ? store.region.shortDayTime(AppClock.now) : "off",
                              color: simDateOn ? Color.must.ink : Color.must.ink)
                }
            }
            .buttonStyle(.plain)
            if expanded == .date {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker("Data e hora", selection: $simDate)
                        .font(.must.body)
                        .environment(\.timeZone, store.region.timeZone)
                        .environment(\.locale, store.region.locale)
                        .tint(Color.must.ink)
                    HStack(spacing: 8) {
                        Button { DevOverrides.simulate(date: simDate); simDateOn = true } label: { Pill("Usar", style: .green) }
                        if let preset = datePreset {
                            Button { simDate = preset.date } label: { Pill(preset.label) }
                        }
                        Button { simDate = Date() } label: { Pill("agora") }
                        Spacer()
                        if simDateOn {
                            Button { DevOverrides.stopSimulatingDate(); simDateOn = false } label: { Pill("Desligar", isOn: true) }
                        }
                    }
                    .buttonStyle(MustPressStyle())
                    Text("O relógio continua andando a partir da data escolhida.")
                        .font(.must.meta).foregroundStyle(Color.must.secondary)
                }
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: Nuvens simuladas

    /// Força o % de nuvens da previsão (frase do golden no Lugar photo, solver de fotografia).
    private var cloudRow: some View {
        FormRow("Simular nuvens") {
            HStack(spacing: 6) {
                ForEach([-1, 20, 80], id: \.self) { v in
                    Button { simCloud = v } label: { Pill(v < 0 ? "real" : "\(v)%", isOn: simCloud == v) }
                        .buttonStyle(MustPressStyle())
                }
            }
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
                FormRow("Simular GPS") { MonoValue(gpsLabel) }
            }
            .buttonStyle(.plain)
            if expanded == .gps {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.name) { preset in
                                Button { useGPS(preset.coordinate) } label: { Pill(preset.name, isOn: gpsLabel == preset.name) }
                                    .buttonStyle(MustPressStyle())
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("lat", text: $latText)
                        TextField("lng", text: $lngText)
                    }
                    .font(V8Font.mono(14))
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                    HStack(spacing: 8) {
                        Button {
                            if let lat = Double(latText.replacingOccurrences(of: ",", with: ".")),
                               let lng = Double(lngText.replacingOccurrences(of: ",", with: ".")) {
                                useGPS(CLLocationCoordinate2D(latitude: lat, longitude: lng))
                            }
                        } label: { Pill("Usar", style: .green) }
                        Spacer()
                        if simGPSOn {
                            Button {
                                DevOverrides.stopSimulatingGPS()
                                simGPSOn = false
                                services.location.refreshOverrides()
                            } label: { Pill("Desligar", isOn: true) }
                        }
                    }
                    .buttonStyle(MustPressStyle())
                }
                .padding(.bottom, 14)
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

/// Faixa de uma região: tinta cheia quando selecionada, borda de 2 pt quando não.
private struct RegionOption: View {
    var region: Region
    var selected: Bool
    var subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    if selected {
                        Rectangle().fill(V8.orange)
                        MustIconView(.ok, size: 16).foregroundStyle(V8.ink)
                    } else {
                        Rectangle().strokeBorder(V8.ink, lineWidth: 2)
                    }
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(region.displayName).font(V8Font.text(19, weight: .semibold))
                    }
                    .foregroundStyle(selected ? V8.paper : V8.ink)
                    Text(subtitle)
                        .font(V8Font.text(13))
                        .foregroundStyle(selected ? V8.muteDark : V8.mute)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(region.utcOffsetLabel)
                    .font(V8Font.mono(14, weight: .semibold))
                    .foregroundStyle(selected ? V8.paper : V8.mute)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? V8.ink : Color.clear)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
        }
        .buttonStyle(MustPressStyle())
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
