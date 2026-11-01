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
        VStack(spacing: 0) {
            SheetHandle()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Micro("escondido · 5 toques na versão")
                        Text("Região").mustTitle()
                        Text("troca board, cidades, moeda, metrô e fontes de dados de uma vez")
                            .mustSerif(18)
                            .foregroundStyle(Color.must.secondary)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 14)

                    ForEach(Region.allCases) { region in
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
                            FormRow("Zerar o board desta região", titleColor: Color(hex: 0xC2261D))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 6)

                    if let error = store.lastError {
                        Text("Erro no armazenamento: \(error)").font(.must.meta).foregroundStyle(Color(hex: 0xC2261D))
                    }

                    Text("Cada região tem o próprio board e os próprios gastos. Trocar não apaga nada.")
                        .font(.must.meta)
                        .foregroundStyle(Color.must.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            PrimaryButton("Fechar", style: .dark) { dismiss() }
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
        }
        .background(Color.must.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .confirmationDialog("Zerar o board de \(store.region.displayName)?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Zerar \(store.region.shortName)", role: .destructive) { confirmResetAgain = true }
        } message: {
            Text("Apaga lugares, gastos e dias desta região e volta pro seed. A outra região não muda.")
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
        }
    }

    private func select(_ region: Region) {
        guard region != store.region else { return }
        dismiss()
        // Troca depois que a sheet sai; o root recria a árvore com `.id(region)`.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            store.choose(region, near: nil)
        }
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
                        if store.region == .jp, let preset = BoardDates(timeZone: Region.jp.timeZone).time("10:00", on: BoardDates(timeZone: Region.jp.timeZone).day(from: "2026-11-15")!) {
                            Button { simDate = preset } label: { Pill("15 nov 10:00") }
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
        let regionPresets = DevOverrides.gpsPresets.filter { preset in
            let isJapan = preset.coordinate.latitude > 0
            return (store.region == .jp) == isJapan
        }
        return regionPresets
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
                    .font(.must.mono(14))
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

/// Card de uma região: gradiente da cor quando selecionada, cinza quando não.
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
                        Circle().fill(Color.must.ink)
                        MustIconView(.ok, size: 16).foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Color(hex: 0xB9BDC4), lineWidth: 1.5)
                    }
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(region.displayName).font(.must.archivo(19, .semibold))
                        if let kanji = region.kanji {
                            Text(kanji).font(.must.kanji(15, bold: false)).opacity(0.6)
                        }
                    }
                    .foregroundStyle(Color.must.ink)
                    Text(subtitle)
                        .font(.must.archivo(13))
                        .foregroundStyle(selected ? region.color.text : Color.must.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Text(region.utcOffsetLabel)
                    .font(.must.mono(14, .semibold))
                    .foregroundStyle(selected ? Color.must.ink : Color.must.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(selected ? AnyShapeStyle(region.color.gradient) : AnyShapeStyle(Color.must.surface2))
            }
        }
        .buttonStyle(MustPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
