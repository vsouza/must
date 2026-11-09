import CoreLocation
import SwiftData
import SwiftUI

/// "Ir pra um bairro": 1) escolhe o bairro; 2) marca os Musts dele; 3) "Montar trajeto · N" ordena SÓ os marcados (e as
/// âncoras de hoje) a partir de onde você está, agora. A proposta é a mesma do Montar (Aceitar grava o dia).
struct IrBairroView: View {
    /// Bairro já escolhido (prints, atalhos). `nil` = seletor primeiro.
    var areaId: String?

    @Environment(\.dismiss) private var dismiss
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
        VStack(spacing: 0) {
            if let id = selected, let entry = index.entry(id) {
                checklist(entry, index: index, snapshot: snapshot, now: now)
            } else {
                picker(IrBairro.areaRows(index))
            }
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { if selected == nil { selected = areaId } }
        .navigationDestination(isPresented: $showProposal) {
            if let planner {
                ProposalView(planner: planner, plan: nil, another: { another(planner) }, asked: asked)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    // MARK: Cabeçalho

    private func header(title: String, sub: String, back: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            GiftSquareButton(systemName: "arrow.left", label: "Voltar", onInk: false, action: back)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(V8Font.display(34)).tracking(-0.8)
                    .foregroundStyle(V8.ink).lineLimit(2).minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(sub).font(V8Font.text(14)).foregroundStyle(V8.mute).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(V8.ink).frame(height: 2) }
    }

    // MARK: 1 · Seletor

    private func picker(_ rows: [IrBairro.AreaRow]) -> some View {
        VStack(spacing: 0) {
            header(title: "Ir pra um bairro", sub: "escolha onde e marque os Musts que quer ver", back: { dismiss() })
            ScrollView {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text("Nenhum Must com bairro ainda. Adicione lugares ao board e volte.")
                            .font(V8Font.text(15)).foregroundStyle(V8.mute)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(rows) { row in
                        Button { checked = []; selected = row.id } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(row.name).font(V8Font.display(28)).tracking(-0.5)
                                        .foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.6)
                                    MonoLabel(row.metaLine, size: 10, color: row.openCount > 0 ? V8.ink : V8.mute)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(V8.orange)
                            }
                            .padding(.horizontal, 20).padding(.vertical, 14)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.name), \(row.count) Musts, \(row.openCount) abertos agora")
                        .accessibilityAddTraits(.isButton)
                        Rectangle().fill(V8.ink).frame(height: 2)
                    }
                    Color.clear.frame(height: 40)
                }
            }
            .scrollIndicators(.hidden)
        }
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
        return VStack(spacing: 0) {
            header(title: entry.area.name,
                   sub: "\(rows.count) \(rows.count == 1 ? "Must" : "Musts") · \(entry.openCount) \(entry.openCount == 1 ? "aberto" : "abertos") agora",
                   back: { if areaId == nil { selected = nil } else { dismiss() } })
            ScrollView {
                VStack(spacing: 0) {
                    if rows.isEmpty {
                        Text("Tudo desse bairro já está feito.").font(V8Font.text(15)).foregroundStyle(V8.mute)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(rows) { row in mustRow(row) }
                    Color.clear.frame(height: 130)
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) { buildButton(n, rows: rows) }
        }
    }

    private func mustRow(_ row: IrBairro.MustRow) -> some View {
        let on = checked.contains(row.id)
        return Button {
            if on { checked.remove(row.id) } else { checked.insert(row.id) }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Rectangle().fill(on ? V8.ink : Color.clear)
                    Rectangle().stroke(V8.ink, lineWidth: 2)
                    if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(V8.white) }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(2)
                    Text(row.meta).font(V8Font.text(13)).foregroundStyle(row.isOpen ? V8.ink : V8.mute).lineLimit(1)
                }
                Spacer(minLength: 0)
                if row.isOpen { Rectangle().fill(V8.orange).frame(width: 8, height: 8).accessibilityHidden(true) }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(row.meta), \(on ? "marcado" : "desmarcado")")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    private func buildButton(_ n: Int, rows: [IrBairro.MustRow]) -> some View {
        Button { Task { await build() } } label: {
            HStack(spacing: 10) {
                Text((working ? "Montando…" : n == 0 ? "Marque os Musts" : "Montar trajeto · \(n)").uppercased())
                    .font(V8Font.mono(14, weight: .semibold)).tracking(1.2).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if !working && n > 0 { Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .bold)) }
            }
            .foregroundStyle(n == 0 ? V8.mute : V8.ink)
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 26)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background((n == 0 ? V8.paper : V8.orange).ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(V8.ink).frame(height: 2) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(n > 0 && !working)
        .accessibilityLabel(n == 0 ? "Montar trajeto, marque ao menos um Must" : "Montar trajeto com \(n) Musts")
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
