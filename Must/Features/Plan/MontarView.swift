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
        switch region {
        case .jp: [8_000, 12_000, 20_000]
        case .bh: [100, 200, 400]
        case .it: [60, 120, 200]
        }
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
        switch region {
        case .jp: "Micro-paradas (café, konbini, descanso)"
        case .bh: "Micro-paradas (café, padaria, descanso)"
        case .it: "Micro-paradas (café, gelato, descanso)"
        }
    }
}

/// 05 · Montar o dia (prompt 23 §2, `Montar.png`). Tinta. Bairro (chips com contagem + vizinhos), ritmo 6/9/12,
/// grana, até que horas, incluir (micro-paradas, foto no golden, compras) e "Gerar o dia · N paradas", que chama o
/// motor do dia (`\.dayEngine`) e mostra a proposta. Aceitar grava pela API do `DayPlanner` (solver).
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
    @State private var editingStart = false
    @State private var parsedText = ""
    @FocusState private var textFocused: Bool

    private var region: Region { store.region }
    private var areas: [Area] { AreaCatalog.areas(for: region) }

    var body: some View {
        Group {
            if let planner { content(planner) } else { V8.ink.ignoresSafeArea() }
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
        if let screen = DebugFlags.string("debugScreen"), ["proposta", "trocar"].contains(screen) {
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
        generated = await engine.build(area: area, pace: pace, budget: p.budget, until: until, includes: includes)
        showProposal = true
    }

    private func parse(_ p: DayPlanner) async {
        let text = p.text
        let intent = await IntentParser.parse(text, placeNames: places.map(\.name), useModel: settingsList.first?.onDeviceAI ?? true)
        p.apply(intent)
        parsedText = text
    }

    // MARK: Tela

    private func content(_ planner: DayPlanner) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(planner)
                areaSection.padding(.top, 24)
                paceSection.padding(.top, 26)
                budgetSection(planner).padding(.top, 22)
                includeSection(planner).padding(.top, 24)
                Color.clear.frame(height: 130)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            BigButton(title: working ? "Montando…" : "Gerar o dia · \(pace.rawValue) paradas", style: .orange,
                      systemImage: working ? nil : "arrow.up.right") {
                textFocused = false
                Task { await generate(planner) }
            }
            .disabled(working)
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 92)
            .background {
                LinearGradient(colors: [V8.ink.opacity(0), V8.ink], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .background {
            ZStack {
                V8.ink
                Rings(color: V8.white, count: 1, diameter: 560, opacity: 0.28, offset: CGSize(width: 110, height: -340))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea()
        }
        .navigationDestination(isPresented: $showProposal) {
            ProposalView(planner: planner, plan: generated).toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $editingStart) { startSheet(planner) }
    }

    private func header(_ planner: DayPlanner) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RoundButton(systemImage: "xmark", label: "Fechar", style: .line, tint: V8.white) { dismiss() }
                Spacer(minLength: 12)
                Button { editingStart = true } label: {
                    SpecStack(lines: [DayText.dayLine(planner.date, region: region),
                                      "a partir das \(region.timeString(planner.startAt))"],
                              color: V8.muteDark, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Muda a hora de sair")
                .padding(.top, 4)
            }
            .padding(.top, 10)
            Text("Montar o dia")
                .font(V8Font.display(44))
                .foregroundStyle(V8.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, 16)
            Text("Diga o bairro e o ritmo. O resto eu encaixo nos seus Musts.")
                .font(V8Font.text(16))
                .foregroundStyle(V8.muteDark)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    // MARK: Bairro

    private var areaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Bairro de hoje", size: 10, color: V8.muteDark)
            if chips.isEmpty {
                Text("Nenhum Must com bairro ainda: o dia sai da cidade toda.").font(V8Font.text(14)).foregroundStyle(V8.muteDark)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        let on = chip.id == area
                        Button { area = chip.id } label: {
                            HStack(spacing: 8) {
                                Text(chip.name).font(V8Font.text(15, weight: .semibold)).foregroundStyle(on ? V8.ink : V8.white)
                                Text("\(chip.count)").font(V8Font.mono(12)).fontWeight(.semibold)
                                    .foregroundStyle(on ? V8.orangeDeep : V8.orange)
                            }
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(Capsule().fill(on ? V8.white : .clear))
                            .overlay(Capsule().strokeBorder(on ? .clear : V8.white.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(MustPressStyle())
                        .accessibilityLabel("\(chip.name), \(chip.count) Musts")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -20)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            if let line = MontarOptions.neighborLine(area.flatMap { id in areas.first { $0.id == id } }, areas: areas) {
                MonoLabel(line, size: 10, color: V8.orange)
            }
        }
    }

    // MARK: Ritmo

    private var paceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Ritmo", size: 10, color: V8.muteDark)
            HStack(spacing: 10) {
                ForEach(Pace.allCases, id: \.self) { p in
                    let on = p == pace
                    Button { pace = p } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(p.rawValue)").font(V8Font.numeral(38)).foregroundStyle(on ? V8.ink : V8.white)
                                .accessibilityHidden(true)
                            Text(MontarOptions.paceLine(p)).font(V8Font.text(13))
                                .foregroundStyle(on ? V8.ink.opacity(0.7) : V8.muteDark)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(on ? V8.orange : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(on ? .clear : V8.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(MustPressStyle())
                    .accessibilityLabel("\(p.rawValue) paradas, \(MontarOptions.paceLine(p))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Grana e horário

    private func budgetSection(_ planner: DayPlanner) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Grana e horário", size: 10, color: V8.muteDark)
            HStack(spacing: 6) {
                ForEach(MontarOptions.budgets(region), id: \.self) { value in
                    let on = planner.budget == value
                    Button { planner.budget = value } label: {
                        chip(region.money(value), on: on)
                    }
                    .buttonStyle(MustPressStyle())
                }
                Spacer(minLength: 4)
                Button { untilMinutes = MontarOptions.nextUntil(after: untilMinutes) } label: {
                    HStack(spacing: 6) {
                        Text("até").font(V8Font.text(14, weight: .semibold))
                        Text(untilText).font(V8Font.mono(13)).fontWeight(.semibold)
                    }
                    .foregroundStyle(V8.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .overlay(Capsule().strokeBorder(V8.white.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(MustPressStyle())
                .accessibilityLabel("Até \(untilText)")
                .accessibilityHint("Toque pra mudar")
            }
        }
    }

    private var untilText: String { String(format: "%02d:%02d", (untilMinutes / 60) % 24, untilMinutes % 60) }

    private func chip(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(V8Font.text(14, weight: .semibold))
            .foregroundStyle(on ? V8.ink : V8.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 11)
            .frame(height: 42)
            .background(Capsule().fill(on ? V8.white : .clear))
            .overlay(Capsule().strokeBorder(on ? .clear : V8.white.opacity(0.35), lineWidth: 1))
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Incluir

    private func includeSection(_ planner: DayPlanner) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel("Incluir", size: 10, color: V8.muteDark).padding(.bottom, 10)
            includeRow(MontarOptions.microLine(region), .micro)
            includeRow("Foto no golden" + (golden.map { " (\(region.timeString($0)))" } ?? ""), .goldenPhoto)
            includeRow("Compras na volta", .shopping)
            Rectangle().fill(V8.white.opacity(0.14)).frame(height: 1)
            TextField("", text: Binding(get: { planner.text }, set: { planner.text = $0 }),
                      prompt: Text("ou diga: templo cedo, ramen, andar pouco").foregroundStyle(V8.muteDark), axis: .vertical)
                .font(V8Font.text(15))
                .foregroundStyle(V8.white)
                .tint(V8.orange)
                .lineLimit(1...3)
                .focused($textFocused)
                .submitLabel(.done)
                .onSubmit { Task { await parse(planner) } }
                .padding(.vertical, 16)
        }
    }

    private func includeRow(_ title: String, _ item: DayInclude) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(V8.white.opacity(0.14)).frame(height: 1)
            Toggle(isOn: Binding(get: { includes.contains(item) }, set: { on in
                if on { includes.insert(item) } else { includes.remove(item) }
            })) {
                Text(title).font(V8Font.text(15)).foregroundStyle(V8.white)
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
