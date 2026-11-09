import CoreLocation
import SwiftData
import SwiftUI

/// Escolhas do Montar v8 (puras, testáveis): chips de bairro, vizinhos, orçamento por região e "até que horas".
enum MontarOptions {
    struct AreaChip: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var count: Int
    }

    /// Bairros com Musts, do que tem mais pro que tem menos (empate: a ordem da tabela).
    static func chips(_ index: AreaIndex) -> [AreaChip] {
        index.populated.enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map { AreaChip(id: $0.element.id, name: $0.element.area.name, count: $0.element.count) }
    }

    /// O bairro escolhido ao abrir vem primeiro (como no design); tocar depois não reordena.
    static func leading(_ id: String, in chips: [AreaChip]) -> [AreaChip] {
        guard let i = chips.firstIndex(where: { $0.id == id }) else { return chips }
        var out = chips
        out.insert(out.remove(at: i), at: 0)
        return out
    }

    /// "+ Shin-Okubo e Nakano, a 5 min": até dois vizinhos a até 15 min (os mais perto), com o maior tempo.
    static func neighborLine(_ area: Area?, areas: [Area]) -> String? {
        guard let area else { return nil }
        let near = area.neighbors.filter { $0.minutes <= 15 }.sorted { $0.minutes < $1.minutes }.prefix(2)
        let names = near.compactMap { n in areas.first { $0.id == n.areaId }?.name }
        guard !names.isEmpty, let longest = near.map(\.minutes).max() else { return nil }
        return "+ \(names.joined(separator: " e ")), a \(longest) min"
    }

    static func budgets(_ region: Region) -> [Double] {
        region.profile.presets
    }

    /// "Até que horas": 21:00 → 22:00 → 23:30 → 01:00 (minutos depois da meia-noite do dia).
    static let untilMinutes = [21 * 60, 22 * 60, 23 * 60 + 30, 25 * 60]

    static func nextUntil(after minutes: Int) -> Int {
        let i = untilMinutes.firstIndex(of: minutes) ?? 1
        return untilMinutes[(i + 1) % untilMinutes.count]
    }

    static func paceLine(_ pace: Pace) -> String {
        switch pace {
        case .calm: "calmo · 2 bairros"
        case .normal: "normal · com pausas"
        case .intense: "intenso · sem parar"
        }
    }

    static func microLine(_ region: Region) -> String {
        "Micro-paradas (\(region.profile.day?.microStops ?? "café, descanso"))"
    }
}

/// 05 · Montar o dia (prompt 23 §2, `Montar.png`). Tinta. Bairro (chips com contagem + vizinhos), ritmo 6/9/12,
/// grana, até que horas, incluir (micro-paradas, foto no golden, compras) e "Gerar o dia · N paradas", que chama o
/// motor do dia (`\.dayEngine`) e mostra a proposta. Aceitar grava pelo motor (`DayEngine.accept`).
struct MontarView: View {
    let date: Date
    /// Bairro do foco ("Ajustar" em Bairros): abre com ele escolhido.
    var focusArea: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var engine

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var days: [PlannedDay]
    @Query private var flights: [Flight]

    @State private var planner: DayPlanner?
    @State private var chips: [MontarOptions.AreaChip] = []
    @State private var area: String?
    @State private var pace: Pace = .normal
    @State private var untilMinutes = 23 * 60 + 30
    @State private var includes: Set<DayInclude> = [.micro, .goldenPhoto]
    @State private var golden: Date?
    @State private var generated: DayPlan?
    @State private var showProposal = false
    @State private var working = false
    @State private var parsedText = ""
    @FocusState private var textFocused: Bool

    private var region: Region { store.region }
    private var areas: [Area] { AreaCatalog.areas(for: region) }

    var body: some View {
        Group {
            if let planner { content(planner) } else { V9.groupedBackground.ignoresSafeArea() }
        }
        .onAppear(perform: setUp)
    }

    private func setUp() {
        guard planner == nil else { return }
        let start = region.calendar.startOfDay(for: date)
        let p = DayPlanner(date: date, region: region, settings: settingsList.first, existing: days.first { $0.date == start })
        p.focusArea = focusArea
        p.weather = services.sync.weather(on: start, region: region, trip: trips.first)
        planner = p
        let index = AreaIndex.build(areas: areas, places: places.map(HomeState.areaPlace), openIds: [])
        chips = MontarOptions.chips(index)
        area = focusArea ?? chips.first?.id
        if let area { chips = MontarOptions.leading(area, in: chips) }
        let city = trips.first?.city(on: start, calendar: region.calendar)
        let center = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude,
                                            longitude: city?.lng ?? region.defaultCenter.longitude)
        golden = SunService.day(start.addingTimeInterval(12 * 3600), center, timeZone: region.timeZone).goldenPM?.start
        // Bairro do GPS quando não veio foco: o chip dele já vem escolhido.
        if focusArea == nil, let here = services.location.current {
            Task {
                if let current = await services.currentArea.area(at: here, region: region), chips.contains(where: { $0.id == current.id }) {
                    area = current.id
                    chips = MontarOptions.leading(current.id, in: chips)
                }
            }
        }
        // Tempos reais (Routes) antes da primeira proposta; sem rede, a estimativa.
        Task { await p.prefetchTravel(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first,
                                      location: services.location.current, flights: dayFlights(p)) }
        #if DEBUG
        if let screen = DebugFlags.string("debugScreen"), ["proposta", "trocar", "outra", "corte-proposta"].contains(screen) {
            Task { await generate(p) }
        }
        #endif
    }

    private func dayFlights(_ p: DayPlanner) -> [DayFlight] { FlightRules.dayFlights(flights, on: p.date, region: region) }

    /// Motor (a proposta v8: micro-paradas, deslocamentos) + solver (o que o Aceitar grava).
    private func generate(_ p: DayPlanner) async {
        working = true
        defer { working = false }
        if !p.text.isEmpty, parsedText != p.text { await parse(p) }
        p.focusArea = area
        await p.prefetchTravel(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first,
                               location: services.location.current, flights: dayFlights(p))
        p.build(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first,
                location: services.location.current, flights: dayFlights(p))
        let until = region.calendar.date(byAdding: .minute, value: untilMinutes, to: p.date) ?? p.date
        generated = await engine.build(on: p.date, area: area, pace: pace, budget: p.budget, until: until, includes: includes,
                                       seed: p.seed)
        showProposal = true
    }

    /// "Outra" da proposta: semente nova no solver (o Trocar e o Aceitar usam ele) e no motor (o que a tela mostra).
    private func another(_ p: DayPlanner) async {
        p.reshuffle(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first,
                    location: services.location.current, flights: dayFlights(p))
        let until = region.calendar.date(byAdding: .minute, value: untilMinutes, to: p.date) ?? p.date
        generated = await engine.build(on: p.date, area: area, pace: pace, budget: p.budget, until: until, includes: includes,
                                       seed: p.seed)
    }

    private func parse(_ p: DayPlanner) async {
        let text = p.text
        let intent = await IntentParser.parse(text, placeNames: places.map(\.name), useModel: settingsList.first?.onDeviceAI ?? true)
        p.apply(intent)
        parsedText = text
    }

    // MARK: Tela

    private func content(_ planner: DayPlanner) -> some View {
        Form {
            Section {
                areaPicker
                DatePicker("Sai às", selection: Binding(get: { planner.startAt }, set: { planner.startAt = $0 }),
                           displayedComponents: .hourAndMinute)
                    .environment(\.timeZone, region.timeZone)
                    .environment(\.locale, region.locale)
            } header: {
                Text("Bairro de hoje")
            } footer: {
                if let line = MontarOptions.neighborLine(area.flatMap { id in areas.first { $0.id == id } }, areas: areas) {
                    Text(line)
                }
            }

            Section("Ritmo") {
                Picker("Paradas no dia", selection: $pace) {
                    ForEach(Pace.allCases, id: \.self) { p in Text("\(p.rawValue)").tag(p) }
                }
                .pickerStyle(.segmented)
                Text(MontarOptions.paceLine(pace)).font(.subheadline).foregroundStyle(.secondary)
            }

            Section("Grana e horário") {
                Picker("Grana do dia", selection: Binding(get: { planner.budget }, set: { planner.budget = $0 })) {
                    ForEach(budgetOptions(planner), id: \.self) { value in Text(region.money(value)).tag(value) }
                }
                Picker("Até que horas", selection: $untilMinutes) {
                    ForEach(MontarOptions.untilMinutes, id: \.self) { minutes in Text(Self.timeText(minutes)).tag(minutes) }
                }
            }

            Section("Incluir") {
                Toggle(MontarOptions.microLine(region), isOn: includeBinding(.micro))
                Toggle("Foto no golden" + (golden.map { " (\(region.timeString($0)))" } ?? ""), isOn: includeBinding(.goldenPhoto))
                Toggle("Compras na volta", isOn: includeBinding(.shopping))
            }
            .tint(V9.accent)

            Section {
                TextField("Ou diga: templo cedo, ramen, andar pouco", text: Binding(get: { planner.text }, set: { planner.text = $0 }), axis: .vertical)
                    .lineLimit(1...3)
                    .focused($textFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await parse(planner) } }
                    .accessibilityIdentifier("montar.ask")
            } header: {
                Text("Pedido em texto")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Montar o dia")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                textFocused = false
                Task { await generate(planner) }
            } label: {
                Text(working ? "Montando…" : "Gerar o dia · \(pace.rawValue) paradas").frame(maxWidth: .infinity)
            }
            .v9Primary()
            .disabled(working)
            .padding(.horizontal, V9.gutter)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .v9Screen(grouped: true)
        .navigationDestination(isPresented: $showProposal) {
            ProposalView(planner: planner, plan: generated, another: { await another(planner) })
        }
    }

    @ViewBuilder private var areaPicker: some View {
        if chips.isEmpty {
            Text("Nenhum Must com bairro ainda: o dia sai da cidade toda.").font(.subheadline).foregroundStyle(.secondary)
        } else {
            Picker("Bairro", selection: Binding(get: { area ?? "" }, set: { area = $0 })) {
                ForEach(chips) { chip in Text("\(chip.name) · \(chip.count)").tag(chip.id) }
            }
        }
    }

    private func budgetOptions(_ planner: DayPlanner) -> [Double] {
        var values = MontarOptions.budgets(region)
        if !values.contains(planner.budget) { values.append(planner.budget); values.sort() }
        return values
    }

    private func includeBinding(_ item: DayInclude) -> Binding<Bool> {
        Binding(get: { includes.contains(item) }, set: { on in
            if on { includes.insert(item) } else { includes.remove(item) }
        })
    }

    private static func timeText(_ minutes: Int) -> String { String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60) }
}
