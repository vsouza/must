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
    @Environment(\.tripTheme) private var theme

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
    @State private var editingStart = false
    @State private var parsedText = ""
    @FocusState private var textFocused: Bool

    private var region: Region { store.region }
    private var areas: [Area] { AreaCatalog.areas(for: region) }

    var body: some View {
        Group {
            if let planner { content(planner) } else { V8.paper.ignoresSafeArea() }
        }
        .toolbar(.hidden, for: .navigationBar)
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
        VStack(spacing: 0) {
            header(planner)
            CutRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    areaSection
                    paceSection
                    budgetSection(planner)
                    includeSection(planner)
                    Color.clear.frame(height: 120)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .bottom) {
            // Botão principal: laranja inteiro no pé, de ponta a ponta, régua de tinta em cima.
            Button {
                textFocused = false
                Task { await generate(planner) }
            } label: {
                HStack(spacing: 10) {
                    Text((working ? "Montando…" : "Gerar o dia · \(pace.rawValue) paradas").uppercased())
                        .font(V8Font.mono(14, weight: .semibold)).tracking(1.2)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if !working { Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold)) }
                }
                .foregroundStyle(V8.ink)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .background(V8.orange.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(working)
        }
        .background(V8.paper.ignoresSafeArea())
        .navigationDestination(isPresented: $showProposal) {
            ProposalView(planner: planner, plan: generated, another: { await another(planner) }).toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $editingStart) { startSheet(planner) }
    }

    /// Bloco do bairro escolhido (o corte): fechar, hora de sair, "Montar o dia".
    private func header(_ planner: DayPlanner) -> some View {
        DayBand(areaId: area, places: places, height: 230) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    V8CornerButton(systemName: "xmark", label: "Fechar", tint: theme.coverInk) { dismiss() }
                    Spacer(minLength: 12)
                    Button { editingStart = true } label: {
                        DayBandCorners(left: [], right: [DayText.dayLine(planner.date, region: region),
                                                         "a partir das \(region.timeString(planner.startAt))"])
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Muda a hora de sair")
                }
                Spacer(minLength: 8)
                Text("Montar o dia")
                    .font(V8Font.display(46))
                    .foregroundStyle(theme.coverInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text("Diga o bairro e o ritmo. O resto eu encaixo nos seus Musts.")
                    .font(V8Font.text(14))
                    .foregroundStyle(theme.coverInk.opacity(0.9))
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
    }

    /// Uma pergunta = uma faixa: micro-rótulo mono, o conteúdo e a régua de 2 pt embaixo.
    private func band<Content: View>(_ label: String, trailing: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                MonoLabel(label, size: 10, color: V8.mute)
                Spacer(minLength: 8)
                if let trailing { MonoLabel(trailing, size: 10, color: V8.ink) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            content()
            Color.clear.frame(height: 18)
            CorteRule2()
        }
    }

    // MARK: Bairro

    private var areaSection: some View {
        band("Bairro de hoje", trailing: MontarOptions.neighborLine(area.flatMap { id in areas.first { $0.id == id } }, areas: areas)) {
            if chips.isEmpty {
                Text("Nenhum Must com bairro ainda: o dia sai da cidade toda.")
                    .font(V8Font.text(14)).foregroundStyle(V8.mute).padding(.horizontal, 20)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        let on = chip.id == area
                        Button { area = chip.id } label: {
                            CutChip(text: "\(chip.name) \(chip.count)", isOn: on, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(chip.name), \(chip.count) Musts")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
        }
    }

    // MARK: Ritmo

    private var paceSection: some View {
        band("Ritmo · paradas no dia") {
            HStack(spacing: 8) {
                ForEach(Pace.allCases, id: \.self) { p in
                    let on = p == pace
                    Button { pace = p } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(p.rawValue)").font(V8Font.numeral(44)).foregroundStyle(on ? V8.paper : V8.ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .accessibilityHidden(true)
                            Text(MontarOptions.paceLine(p)).font(V8Font.mono(10)).foregroundStyle(on ? V8.paper.opacity(0.85) : V8.mute)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .background(on ? V8.ink : Color.clear)
                        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.rawValue) paradas, \(MontarOptions.paceLine(p))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Grana e horário

    private func budgetSection(_ planner: DayPlanner) -> some View {
        band("Grana e horário", trailing: "até \(untilText)") {
            VStack(alignment: .leading, spacing: 12) {
                Text(region.money(planner.budget))
                    .font(V8Font.numeral(44)).foregroundStyle(V8.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityLabel("Grana do dia \(region.money(planner.budget))")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(MontarOptions.budgets(region), id: \.self) { value in
                            Button { planner.budget = value } label: {
                                CutChip(text: region.money(value), isOn: planner.budget == value, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                        Button { untilMinutes = MontarOptions.nextUntil(after: untilMinutes) } label: {
                            CutChip(text: "até \(untilText)", minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Até \(untilText)")
                        .accessibilityHint("Toque pra mudar")
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -20)
                .contentMargins(.horizontal, 20, for: .scrollContent)
            }
            .padding(.horizontal, 20)
        }
    }

    private var untilText: String { String(format: "%02d:%02d", (untilMinutes / 60) % 24, untilMinutes % 60) }

    // MARK: Incluir

    private func includeSection(_ planner: DayPlanner) -> some View {
        band("Incluir") {
            VStack(alignment: .leading, spacing: 0) {
                includeRow(MontarOptions.microLine(region), .micro)
                includeRow("Foto no golden" + (golden.map { " (\(region.timeString($0)))" } ?? ""), .goldenPhoto)
                includeRow("Compras na volta", .shopping)
                TextField("", text: Binding(get: { planner.text }, set: { planner.text = $0 }),
                          prompt: Text("OU DIGA: TEMPLO CEDO, RAMEN, ANDAR POUCO").font(V8Font.mono(11)).foregroundStyle(V8.mute), axis: .vertical)
                    .font(V8Font.text(15))
                    .foregroundStyle(V8.ink)
                    .tint(V8.orange)
                    .lineLimit(1...3)
                    .focused($textFocused)
                    .submitLabel(.done)
                    .onSubmit { Task { await parse(planner) } }
                    .accessibilityIdentifier("montar.ask")
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Rectangle().fill(V8.ink.opacity(0.2)).frame(height: 1) }
            }
            .padding(.horizontal, 20)
        }
    }

    private func includeRow(_ title: String, _ item: DayInclude) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(V8.ink.opacity(0.2)).frame(height: 1)
            Toggle(isOn: Binding(get: { includes.contains(item) }, set: { on in
                if on { includes.insert(item) } else { includes.remove(item) }
            })) {
                Text(title).font(V8Font.text(15)).foregroundStyle(V8.ink)
            }
            .tint(V8.orange)
            .padding(.vertical, 9)
        }
    }

    private func startSheet(_ planner: DayPlanner) -> some View {
        VStack(spacing: 16) {
            Text("A que horas você sai?").font(V8Font.display(22)).foregroundStyle(V8.ink).padding(.top, 24)
            DatePicker("", selection: Binding(get: { planner.startAt }, set: { planner.startAt = $0 }), displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.timeZone, region.timeZone)
                .environment(\.locale, region.locale)
            BigButton(title: "Pronto", style: .ink) { editingStart = false }.padding(.horizontal, 20)
        }
        .presentationDetents([.height(360)])
        .presentationBackground(V8.paper)
    }
}
