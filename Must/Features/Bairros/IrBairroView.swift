import CoreLocation
import SwiftData
import SwiftUI

/// "Ir pra um bairro": 1) escolhe o bairro; 2) marca os Musts dele; 3) "Montar trajeto · N" ordena SÓ os marcados (e as
/// âncoras de hoje) a partir de onde você está, agora. A proposta é a mesma do Montar (Aceitar grava o dia).
struct IrBairroView: View {
    /// Bairro já escolhido (prints, atalhos). `nil` = seletor primeiro.
    var areaId: String?

    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var flights: [Flight]

    @State private var selected: String?
    @State private var checked: Set<String> = []
    @State private var openNow = OpenNowIndex()
    @State private var planner: DayPlanner?
    @State private var showProposal = false
    @State private var working = false
    @State private var asked: [SolverPlace] = []

    private var region: Region { store.region }

    var body: some View {
        // Um único cálculo por redesenho: abertos agora e índice de bairros (só Musts não feitos).
        let now = AppClock.now
        let todo = places.filter { !$0.isDone }
        let snapshot = openNow.snapshot(for: todo, now: now, timeZone: region.timeZone, location: nil)
        let openIds = Set(todo.filter { snapshot.isOpen($0.id) }.map(\.id))
        let index = AreaIndex.build(areas: AreaCatalog.areas(for: region), places: todo.map(HomeState.areaPlace), openIds: openIds)
        Group {
            if let id = selected, let entry = index.entry(id) {
                checklist(entry, index: index, snapshot: snapshot, now: now)
            } else {
                picker(IrBairro.areaRows(index))
            }
        }
        .v9Screen(grouped: true)
        .scrollContentBackground(.hidden)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if selected != nil, areaId == nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button { selected = nil } label: { Label("Bairros", systemImage: "chevron.backward") }
                }
            }
        }
        .navigationBarBackButtonHidden(selected != nil && areaId == nil)
        .onAppear { if selected == nil { selected = areaId } }
        .navigationDestination(isPresented: $showProposal) {
            if let planner {
                ProposalView(planner: planner, plan: nil, another: { another(planner) }, asked: asked)
            }
        }
    }

    // MARK: 1 · Seletor

    private func picker(_ rows: [IrBairro.AreaRow]) -> some View {
        List {
            Section {
                if rows.isEmpty {
                    Text("Nenhum Must com bairro ainda. Adicione lugares ao board e volte.").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    Button { checked = []; selected = row.id } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                Text(row.metaLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            if row.openCount > 0 {
                                Circle().fill(V9.accent).frame(width: 8, height: 8).accessibilityHidden(true)
                            }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(row.name), \(row.count) Musts, \(row.openCount) abertos agora")
                    .accessibilityAddTraits(.isButton)
                }
            } header: {
                Text("Escolha onde e marque os Musts que quer ver")
                    .textCase(nil)
            }
        }
        .navigationTitle("Ir pra um bairro")
    }

    // MARK: 2 · Checklist

    private func checklist(_ entry: AreaEntry, index: AreaIndex, snapshot: OpenNowIndex.Snapshot, now: Date) -> some View {
        let byId = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let info = Dictionary(uniqueKeysWithValues: entry.placeIds.compactMap { id in
            byId[id].map { p in
                (id, IrBairro.MustInfo(id: id, name: p.name, sub: p.sub, isDone: p.isDone, state: snapshot.states[id] ?? .unknown,
                                        hasReservationToday: p.hasReservation(on: now, calendar: region.calendar)))
            }
        })
        let rows = IrBairro.mustRows(ids: entry.placeIds, info: info)
        let n = rows.filter { checked.contains($0.id) }.count
        return List {
            Section {
                if rows.isEmpty {
                    Text("Tudo desse bairro já está feito.").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in mustRow(row) }
            } header: {
                Text("\(rows.count) \(rows.count == 1 ? "Must" : "Musts") · \(entry.openCount) \(entry.openCount == 1 ? "aberto" : "abertos") agora")
                    .textCase(nil)
            }
        }
        .navigationTitle(entry.area.name)
        .safeAreaInset(edge: .bottom) { buildButton(n) }
    }

    private func mustRow(_ row: IrBairro.MustRow) -> some View {
        let on = checked.contains(row.id)
        return Button {
            if on { checked.remove(row.id) } else { checked.insert(row.id) }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(on ? V9.accent : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                    Text(row.meta).font(.subheadline).foregroundStyle(row.isOpen ? Color.primary : Color.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if row.isOpen { Circle().fill(V9.accent).frame(width: 8, height: 8).accessibilityHidden(true) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(row.meta), \(on ? "marcado" : "desmarcado")")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func buildButton(_ n: Int) -> some View {
        Button { Task { await build() } } label: {
            Text(working ? "Montando…" : n == 0 ? "Marque os Musts" : "Montar trajeto · \(n)")
                .frame(maxWidth: .infinity)
        }
        .v9Primary()
        .disabled(n == 0 || working)
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: 3 · Trajeto

    private var today: Date { region.calendar.startOfDay(for: AppClock.now) }

    private func dayFlights(_ p: DayPlanner) -> [DayFlight] { FlightRules.dayFlights(flights, on: p.date, region: region) }

    /// Catálogo restrito: marcados + âncoras de hoje. Nada que não foi marcado entra.
    private func restricted() -> [SolverPlace] {
        IrBairro.restrictedCatalog(places.solverCatalog, checked: checked, date: today, calendar: region.calendar)
    }

    private func build() async {
        working = true
        defer { working = false }
        let p = DayPlanner(date: today, region: region, settings: settingsList.first, existing: nil)
        p.pace = nil
        p.focusArea = nil
        let all = places.solverCatalog
        let catalog = IrBairro.restrictedCatalog(all, checked: checked, date: today, calendar: region.calendar)
        p.intent.mustInclude = IrBairro.mustIncludeNames(all, checked: checked)
        p.weather = services.sync.weather(on: today, region: region, trip: trips.first)
        await p.prefetchTravel(catalog: catalog, trip: trips.first, settings: settingsList.first,
                               location: services.location.current, flights: dayFlights(p))
        p.build(catalog: catalog, trip: trips.first, settings: settingsList.first,
                location: services.location.current, flights: dayFlights(p))
        asked = all.filter { checked.contains($0.id) && !$0.done }
        planner = p
        showProposal = true
    }

    /// "Outra": semente nova, sempre com o catálogo restrito (o completo traria Musts que você não marcou).
    private func another(_ p: DayPlanner) {
        p.reshuffle(catalog: restricted(), trip: trips.first, settings: settingsList.first,
                    location: services.location.current, flights: dayFlights(p))
    }
}
