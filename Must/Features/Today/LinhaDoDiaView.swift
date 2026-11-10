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
    @State private var safeTop: CGFloat = 0

    private var region: Region { store.region }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(date) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                band
                CutRule()
                if plan != nil { controls }
                if let plan {
                    if !shows.isEmpty { showsBand }
                    if let clock, clock.adjusted { adjustedNote(clock) }
                    timeline(plan)
                } else if loaded {
                    empty.padding(.horizontal, 20).padding(.top, 36)
                }
                V8BarSpacer()
            }
        }
        .scrollIndicators(.hidden)
        .cutBleed($safeTop)
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .v8Legacy()
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

    // MARK: Topo (o corte)

    /// Bloco do bairro do dia: cantos, "Dia N" e o numeral grande = quantas paradas.
    private var band: some View {
        DayBand(areaId: plan?.bandArea(from: nowId == nil ? nil : AppClock.now), places: places, topInset: safeTop) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    CutCornerButton(systemName: "chevron.left", label: "Voltar", tint: theme.coverInk) { dismiss() }
                    Spacer(minLength: 12)
                    DayBandCorners(left: [], right: [DayText.dayLine(date, region: region),
                                                     plan.map { "\($0.anchors.count == 1 ? "1 âncora" : "\($0.anchors.count) âncoras")"
                                                         + (shows.isEmpty ? "" : " · \(shows.count) em cartaz")
                                                         + " · \(region.money($0.spent)) de \(region.money($0.budget, symbol: false))" } ?? "sem dia montado"])
                    CutCornerButton(systemName: "sparkle", label: "Assistente", tint: theme.coverInk) { router.sheet = .assistant }
                }
                Spacer(minLength: 8)
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = plan?.title, !title.isEmpty { MonoLabel(title, size: 10, color: theme.coverInk.opacity(0.9)) }
                        Text("Dia \(numeral)")
                            .font(V8Font.display(46))
                            .foregroundStyle(theme.coverInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 8)
                    if let plan { DayBandNumeral(value: "\(plan.stops.count)", caption: plan.stops.count == 1 ? "parada" : "paradas") }
                }
            }
        }
    }

    private var numeral: String {
        plan?.dayNumber.map(String.init) ?? region.dayNumber(date)
    }

    /// Linha | Mapa e, embaixo do dia, "Ajustar o dia" e "Mandar o dia" por extenso.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            toggle
            HStack(spacing: 10) {
                wide("AJUSTAR O DIA", icon: "slider.horizontal.3", label: "Ajustar o dia") {
                    router.push(.montar(date: region.calendar.startOfDay(for: date)), on: .hoje)
                }
                wide("MANDAR O DIA", icon: "paperplane", label: "Mandar o dia") {
                    router.sheet = .mandar(date: region.calendar.startOfDay(for: date))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    private func wide(_ title: String, icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(title).font(V8Font.mono(11, weight: .semibold)).tracking(0.8).lineLimit(2).multilineTextAlignment(.leading)
            }
            .foregroundStyle(V8.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Linha | Mapa (o Mapa é a tela do mapa do dia).
    private var toggle: some View {
        HStack(spacing: 0) {
            Text("LINHA")
                .font(V8Font.mono(11, weight: .semibold)).tracking(1)
                .foregroundStyle(V8.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(V8.ink)
                .accessibilityAddTraits(.isSelected)
            Button { router.push(.mapa, on: .hoje) } label: {
                Text("MAPA")
                    .font(V8Font.mono(11, weight: .semibold)).tracking(1)
                    .foregroundStyle(V8.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
        .fixedSize()
    }

    // MARK: Em cartaz

    /// O que está em cartaz hoje (cache do aparelho; o motor decide se vira micro-parada).
    private var shows: [ShowEvent] { showEvents.today(region: region, at: date) }

    /// Faixa tinta "Em cartaz hoje": leva à tela Em cartaz.
    private var showsBand: some View {
        let first = shows[0]
        let more = shows.count > 1 ? " +\(shows.count - 1)" : ""
        return Button { router.push(.emCartaz, on: .hoje) } label: {
            DayStrip(tone: .ink) {
                HStack(spacing: 12) {
                    Text("EM CARTAZ HOJE").font(V8Font.mono(11, weight: .bold)).tracking(1.4).foregroundStyle(V8.orange).lineLimit(1).fixedSize()
                    Text(first.title + more).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.white).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .bold)).foregroundStyle(V8.white)
                }
                .frame(minHeight: 32)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Em cartaz hoje: \(first.title)\(more)")
    }

    // MARK: Linha

    /// "Atrasou? Ajustei: faltam 5 paradas" (nunca "você deveria"): o resto do dia foi refeito a partir de agora.
    private func adjustedNote(_ clock: DayClock) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(DayText.adjustedLine(remaining: clock.remaining))
                .font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.ink)
            Text("Ficou pra depois: " + clock.skipped.map { DayText.head($0.label) }.joined(separator: ", "))
                .font(V8Font.text(12.5)).foregroundStyle(V8.mute).lineLimit(3)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { IndexRule() }
        .accessibilityElement(children: .combine)
    }

    private func timeline(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan.stops, id: \.id) { stop in
                let state = LinhaStopState.of(stop, nowId: nowId, doneIds: doneIds, skippedIds: clock?.skippedIds ?? [])
                DayStopRow(stop: stop, state: state, region: region, onTap: tapAction(stop, state: state))
                if let leg = plan.leg(after: stop) {
                    DayLegItem(leg: leg)
                }
            }
            if let last = plan.lastTrain {
                DayLegItem(leg: DayLeg(mode: .train, minutes: 0, from: "", to: "",
                                       detail: "último trem \(last.line) \(region.timeString(last.at))"),
                           color: V8.orangeDeep)
            }
        }
    }

    private func tapAction(_ stop: DayStop, state: LinhaStopState) -> (() -> Void)? {
        if state == .now { return { router.push(.agora, on: .hoje) } }
        guard let placeId = stop.placeId else { return nil }
        return { router.push(.place(id: placeId), on: .hoje) }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nada montado pra este dia.")
                .font(V8Font.display(28))
                .foregroundStyle(V8.ink)
            Text("Diga o bairro e o ritmo; o resto sai dos seus Musts, com as micro-paradas e os deslocamentos.")
                .font(V8Font.text(15))
                .foregroundStyle(V8.mute)
            HojeWideButton(title: "Montar o dia") {
                router.push(.montar(date: region.calendar.startOfDay(for: date)), on: .hoje)
            }
            .padding(.horizontal, -20)
        }
    }
}
