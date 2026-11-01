import SwiftData
import SwiftUI

/// Montar o dia: tipo de dia, listas (auto/ligada/desligada), orçamento, andar e "ou diga…".
struct MontarView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var days: [PlannedDay]

    @State private var planner: DayPlanner?
    @State private var showProposal = false
    @State private var editingStart = false
    @FocusState private var textFocused: Bool

    private var region: Region { store.region }

    var body: some View {
        Group {
            if let planner {
                content(planner)
            } else {
                Color.must.bg
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if planner == nil {
                let start = region.calendar.startOfDay(for: date)
                planner = DayPlanner(date: date, region: region, settings: settingsList.first, existing: days.first { $0.date == start })
                #if DEBUG
                if let screen = UserDefaults.standard.string(forKey: "debugScreen"), ["proposta", "trocar"].contains(screen), let planner {
                    planner.build(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first, location: services.location.current)
                    showProposal = true
                }
                #endif
            }
        }
    }

    private func content(_ planner: DayPlanner) -> some View {
        let catalog = places.solverCatalog
        let preview = planner.solve(catalog: catalog, trip: trips.first, settings: settingsList.first, location: services.location.current)
        return ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(planner, preview: preview)
                    kindCard(planner).padding(.top, 8)
                    listsCard(planner, preview: preview)
                    HStack(alignment: .top, spacing: 12) {
                        budgetCard(planner)
                        walkCard(planner)
                    }
                    sayField(planner)
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton("Montar o dia", icon: .avancar, iconTrailing: true) {
                textFocused = false
                if !planner.text.isEmpty { planner.applyText(lists: lists, placeNames: places.map(\.name)) }
                planner.build(catalog: catalog, trip: trips.first, settings: settingsList.first, location: services.location.current)
                showProposal = true
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 92)
            .background {
                LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .center).ignoresSafeArea()
            }
        }
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .custom([
                    Blob(cx: 352, cy: 90, rx: 92, ry: 66, rotation: -22, fill: .green),
                    Blob(cx: 30, cy: 690, rx: 92, ry: 66, rotation: 12, fill: .blue),
                ]))
            }
            .ignoresSafeArea()
        }
        .navigationDestination(isPresented: $showProposal) {
            ProposalView(planner: planner).toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $editingStart) {
            VStack(spacing: 16) {
                SheetHandle()
                Text("A que horas você sai?").mustPlace()
                DatePicker("", selection: Binding(get: { planner.startAt }, set: { planner.startAt = $0 }), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.timeZone, region.timeZone)
                    .environment(\.locale, region.locale)
                PrimaryButton("Pronto", style: .dark) { editingStart = false }.padding(.horizontal, 22)
            }
            .presentationDetents([.height(340)])
        }
    }

    // MARK: Topo

    private func header(_ planner: DayPlanner, preview: DayProposal) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                IconButton(.voltar, style: .glass, label: "Voltar") { dismiss() }
                Spacer()
                Button { editingStart = true } label: {
                    Micro("\(weekdayShort(planner.date)) · \(region.shortDay(planner.date)) · \(planner.isToday ? "sai" : "acorda") \(region.timeString(planner.startAt))")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Muda a hora de sair")
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.top, 8)
            VStack(alignment: .leading, spacing: 6) {
                Text("Montar o dia").mustTitle()
                Text(subtitle(planner, preview: preview)).mustSerif(18).foregroundStyle(Color.must.secondary)
            }
        }
    }

    private func weekdayShort(_ date: Date) -> String {
        PlaceHours.weekdayShort[region.calendar.component(.weekday, from: date) - 1]
    }

    private func subtitle(_ planner: DayPlanner, preview: DayProposal) -> String {
        var parts: [String] = []
        let cal = region.calendar
        if let trip = trips.first, let city = trip.city(on: planner.date, calendar: cal) {
            if let idx = trip.dayIndex(in: city, on: planner.date, calendar: cal) {
                parts.append("dia \(idx.index) de \(idx.total) em \(city.name)")
            } else {
                var style = Date.FormatStyle(locale: region.locale, calendar: cal).weekday(.wide)
                style.timeZone = region.timeZone
                parts.append("\(city.name) · \(planner.date.formatted(style))")
            }
        }
        let anchors = preview.stops.filter(\.isAnchor).count
        parts.append(anchors == 0 ? "nada reservado" : anchors == 1 ? "1 reserva" : "\(anchors) reservas")
        return parts.joined(separator: " · ")
    }

    // MARK: Tipo de dia

    private func kindCard(_ planner: DayPlanner) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Micro("tipo de dia")
            FlowLayout(spacing: 8) {
                ForEach(DayKind.allCases) { kind in
                    Button { planner.kind = kind } label: { Pill(kind.label.capitalized, isOn: planner.kind == kind) }
                        .buttonStyle(MustPressStyle())
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 24)
    }

    // MARK: Listas

    private func listsCard(_ planner: DayPlanner, preview: DayProposal) -> some View {
        FormSection {
            ForEach(Array(lists.enumerated()), id: \.element.id) { index, list in
                if index > 0 { RowDivider() }
                let on = isOn(list, planner: planner, preview: preview)
                Toggle(isOn: Binding(get: { on }, set: { planner.lists[list.id] = $0 ? .on : .off })) {
                    FormRow(list.displayName, subtitle: context(for: list, preview: preview, on: on))
                }
                .toggleStyle(.must)
            }
        }
    }

    /// Ligada explicitamente, ou `auto` e o tipo de dia usa essa lista (ou o solver escolheu algo dela).
    private func isOn(_ list: MustList, planner: DayPlanner, preview: DayProposal) -> Bool {
        switch planner.lists[list.id] ?? .auto {
        case .on: return true
        case .off: return false
        case .auto:
            if preview.stops.contains(where: { $0.place.listId == list.id }) { return true }
            return DaySolver.plan(for: planner.intent.kind ?? planner.kind).required.contains(StopRole(color: list.color))
        }
    }

    /// "Ramen hoje · Fuunji, Menya Kaijin" / "Ginza Music Bar · fica pro fim".
    private func context(for list: MustList, preview: DayProposal, on: Bool) -> String {
        let chosen = preview.stops.filter { $0.place.listId == list.id }
        if !chosen.isEmpty {
            let subs = Set(chosen.compactMap(\.place.sub))
            let lead = subs.count == 1 ? "\(subs.first!) hoje" : "hoje"
            return "\(lead) · \(chosen.map(\.place.name).joined(separator: ", "))"
        }
        if let left = preview.leftOut.first(where: { $0.place.listId == list.id && $0.reason != "outra cidade" }) {
            return "\(left.place.name) · \(left.reason)"
        }
        let names = list.places.filter { !$0.isDone }.prefix(2).map(\.name)
        if names.isEmpty { return "nada pra hoje" }
        return on ? "\(names.joined(separator: ", ")) · se couber" : "\(names.joined(separator: ", ")) · desligada"
    }

    // MARK: Orçamento e andar

    private var budgetChips: [Double] { region == .jp ? [8_000, 15_000, 25_000] : [100, 200, 400] }

    private func chipLabel(_ value: Double) -> String {
        region == .jp ? "\(Int(value / 1000))k" : region.money(value)
    }

    private func budgetCard(_ planner: DayPlanner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("orçamento", color: Color.must.blueText)
            MonoNumber(region.money(planner.budget), size: 26).foregroundStyle(Color.must.ink)
            HStack(spacing: 6) {
                ForEach(budgetChips, id: \.self) { value in
                    Button { planner.budget = value } label: { chip(chipLabel(value), on: planner.budget == value) }
                        .buttonStyle(MustPressStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MustGradient.sky(opacity: (1, 0.95)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func walkCard(_ planner: DayPlanner) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Micro("andar", color: Color.must.greenTextSoft)
            Text(planner.walk.label.capitalized).font(.must.archivo(26, .semibold)).foregroundStyle(Color.must.ink)
            HStack(spacing: 6) {
                ForEach(WalkLevel.allCases) { level in
                    Button { planner.walk = level } label: { chip(level.label.capitalized, on: planner.walk == level) }
                        .buttonStyle(MustPressStyle())
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MustColor.eat.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func chip(_ text: String, on: Bool) -> some View {
        Text(text)
            .font(.must.archivo(12, .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(on ? .white : Color.must.ink)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(Capsule().fill(on ? Color.must.ink : Color.white.opacity(0.7)))
    }

    // MARK: Ou diga

    private func sayField(_ planner: DayPlanner) -> some View {
        HStack(spacing: 10) {
            TextField("ou diga: templo cedo, ramen, café e andar pouco", text: Binding(get: { planner.text }, set: { planner.text = $0 }),
                      axis: .vertical)
                .font(.must.serif(19))
                .lineLimit(1...4)
                .focused($textFocused)
                .submitLabel(.done)
                .onSubmit { planner.applyText(lists: lists, placeNames: places.map(\.name)) }
                .onChange(of: textFocused) { _, focused in
                    if !focused, !planner.text.isEmpty { planner.applyText(lists: lists, placeNames: places.map(\.name)) }
                }
            Button { textFocused = true } label: {
                MustIconView(.falar, size: 18).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.must.ink))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Ditar (use o microfone do teclado)")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.must.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
