import SwiftData
import SwiftUI

/// 04 · Linha do dia (prompt 23 §2, `Dia.png` / `DiaIT.png`; prompt 30: o corte). Bloco do bairro do dia, régua, papel com o
/// índice de paradas (âncora = tinta, must = papel, micro = linha baixa tracejada), deslocamentos entre elas, último trem no fim. Toggle Linha/Mapa (Mapa = rota `.mapa`).
/// Estados: feito (50 %), agora (laranja). Tudo do `DayPlan` do motor; sem plano, um vazio que leva ao Montar.
struct LinhaDoDiaView: View {
    var date: Date

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(\.dayEngine) private var engine
    @Environment(\.showEvents) private var showEvents
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tripTheme) private var theme
    @Environment(Services.self) private var services

    @Query private var places: [Place]

    @State private var plan: DayPlan?
    @State private var clock: DayClock?
    @State private var nowId: String?
    @State private var doneIds: Set<String> = []
    @State private var loaded = false

    private var region: Region { store.region }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(date) }

    var body: some View {
        List {
            if let plan {
                Section {
                    summary(plan)
                    if let clock, clock.adjusted { adjustedNote(clock) }
                    if !shows.isEmpty { showsRow }
                }
                Section {
                    timeline(plan)
                } header: {
                    Text("Paradas")
                }
                Section {
                    Button { router.push(.montar(date: region.calendar.startOfDay(for: date)), on: .hoje) } label: {
                        Label("Ajustar o dia", systemImage: "slider.horizontal.3")
                    }
                    Button { router.sheet = .mandar(date: region.calendar.startOfDay(for: date)) } label: {
                        Label("Mandar o dia · cartaz, link, PDF", systemImage: "paperplane")
                    }
                }
            } else if loaded {
                empty
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DayText.dayLine(date, region: region))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.mapa, on: .hoje) } label: { Label("Mapa", systemImage: "map") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.sheet = .assistant } label: { Image(systemName: "sparkles") }.accessibilityLabel("Assistente")
            }
        }
        .v9Screen(grouped: true)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in load() }
    }

    private func load() {
        let start = region.calendar.startOfDay(for: date)
        let now = AppClock.now
        if region.calendar.isDate(now, inSameDayAs: start) {
            // Hoje: o relógio único (o mesmo da capa, do Agora e do Guia).
            let c = DayClock.read(engine: engine, region: region, context: context, at: now, position: services.location.current?.coordinate)
            clock = c
            plan = c.plan
            nowId = c.now?.current.id
        } else {
            clock = nil
            plan = engine.plan(for: start, region: region, context: context)
            nowId = nil
        }
        doneIds = DayDoneStore().ids(day: dayKey)
        loaded = true
    }

    // MARK: Resumo

    private func summary(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !plan.title.isEmpty { Text(plan.title).font(.headline) }
            let anchors = plan.anchors.count == 1 ? "1 âncora" : "\(plan.anchors.count) âncoras"
            Text("\(plan.stops.count) \(plan.stops.count == 1 ? "parada" : "paradas") · \(anchors) · \(region.money(plan.spent)) de \(region.money(plan.budget, symbol: false))")
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            if let n = plan.dayNumber { Text("Dia \(n)").font(.footnote).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Em cartaz

    /// O que está em cartaz hoje (cache do aparelho; o motor decide se vira micro-parada).
    private var shows: [ShowEvent] { showEvents.today(region: region, at: date) }

    private var showsRow: some View {
        let first = shows[0]
        let more = shows.count > 1 ? " +\(shows.count - 1)" : ""
        return Button { router.push(.emCartaz, on: .hoje) } label: {
            HStack {
                Label("Em cartaz hoje: \(first.title)\(more)", systemImage: "ticket").lineLimit(2)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Linha

    /// "Atrasou? Ajustei: faltam 5 paradas" (nunca "você deveria"): o resto do dia foi refeito a partir de agora.
    private func adjustedNote(_ clock: DayClock) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(DayText.adjustedLine(remaining: clock.remaining)).font(.subheadline.weight(.semibold))
            Text("Ficou pra depois: " + clock.skipped.map { DayText.head($0.label) }.joined(separator: ", "))
                .font(.footnote).foregroundStyle(.secondary).lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func timeline(_ plan: DayPlan) -> some View {
        ForEach(plan.stops, id: \.id) { stop in
            let state = LinhaStopState.of(stop, nowId: nowId, doneIds: doneIds, skippedIds: clock?.skippedIds ?? [])
            V9StopRow(stop: stop, state: state, region: region, onTap: tapAction(stop, state: state))
            if let leg = plan.leg(after: stop) {
                V9LegRow(leg: leg).listRowSeparator(.hidden)
            }
        }
        if let last = plan.lastTrain {
            Label("último trem \(last.line) \(region.timeString(last.at))", systemImage: "tram.fill")
                .font(.footnote).foregroundStyle(V9.alert)
        }
    }

    private func tapAction(_ stop: DayStop, state: LinhaStopState) -> (() -> Void)? {
        if state == .now { return { router.push(.agora, on: .hoje) } }
        guard let placeId = stop.placeId else { return nil }
        return { router.push(.place(id: placeId), on: .hoje) }
    }

    @ViewBuilder private var empty: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nada montado pra este dia.").font(.title3.weight(.semibold))
                Text("Diga o bairro e o ritmo; o resto sai dos seus Musts, com as micro-paradas e os deslocamentos.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Montar o dia") { router.push(.montar(date: region.calendar.startOfDay(for: date)), on: .hoje) }.v9Primary()
            }
            .padding(.vertical, 6)
        }
    }
}
