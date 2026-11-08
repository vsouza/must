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

    @Query private var places: [Place]

    @State private var plan: DayPlan?
    @State private var nowId: String?
    @State private var doneIds: Set<String> = []
    @State private var loaded = false

    private var region: Region { store.region }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(date) }

    var body: some View {
        VStack(spacing: 0) {
            band
            CutRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if plan != nil { controls }
                    if let plan {
                        if !shows.isEmpty { showsBand }
                        timeline(plan)
                    } else if loaded {
                        empty.padding(.horizontal, 20).padding(.top, 36)
                    }
                    Color.clear.frame(height: 130)
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) { BottomFade(color: V8.paper, height: 150) }
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in load() }
    }

    private func load() {
        let start = region.calendar.startOfDay(for: date)
        plan = engine.plan(for: start, region: region, context: context)
        let now = AppClock.now
        nowId = plan.flatMap { region.calendar.isDate(now, inSameDayAs: start) ? engine.now(in: $0, at: now)?.current.id : nil }
        doneIds = DayDoneStore().ids(day: dayKey)
        loaded = true
    }

    // MARK: Topo (o corte)

    /// Bloco do bairro do dia: cantos, "Dia N" e o numeral gigante = quantas paradas.
    private var band: some View {
        DayBand(areaId: plan?.bandArea(from: nowId == nil ? nil : AppClock.now), places: places) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    RoundButton(systemImage: "chevron.left", label: "Voltar", style: .line, tint: theme.coverInk, size: 40) { dismiss() }
                    Spacer(minLength: 12)
                    DayBandCorners(left: [], right: [DayText.dayLine(date, region: region),
                                                     plan.map { "\($0.anchors.count == 1 ? "1 âncora" : "\($0.anchors.count) âncoras")"
                                                         + (shows.isEmpty ? "" : " · \(shows.count) em cartaz")
                                                         + " · \(region.money($0.spent)) de \(region.money($0.budget, symbol: false))" } ?? "sem dia montado"])
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

    /// Mandar o dia (prompt 25 · B.5) e Linha | Mapa, numa faixa de papel.
    private var controls: some View {
        HStack(spacing: 10) {
            toggle
            Spacer(minLength: 8)
            RoundButton(systemImage: "paperplane", label: "Mandar o dia", style: .line, tint: V8.ink, size: 40) {
                router.sheet = .mandar(date: region.calendar.startOfDay(for: date))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    /// Linha | Mapa (o Mapa é a tela do mapa do dia).
    private var toggle: some View {
        HStack(spacing: 0) {
            Text("LINHA")
                .font(V8Font.mono(11, weight: .semibold)).tracking(1)
                .foregroundStyle(V8.white)
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .background(V8.ink)
                .accessibilityAddTraits(.isSelected)
            Button { router.push(.mapa, on: .hoje) } label: {
                Text("MAPA")
                    .font(V8Font.mono(11, weight: .semibold)).tracking(1)
                    .foregroundStyle(V8.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
        }
        .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
    }

    // MARK: Em cartaz

    /// O que está em cartaz hoje (cache do aparelho; o motor decide se vira micro-parada).
    private var shows: [ShowEvent] { showEvents.today(region: region, at: date) }

    /// Faixa tinta "Em cartaz hoje" (`DiaEmCartaz.png`): leva à tela Em cartaz.
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

    private func timeline(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.stops.enumerated()), id: \.element.id) { i, stop in
                let state = LinhaStopState.of(stop, nowId: nowId, doneIds: doneIds)
                DayStopRow(stop: stop, index: i + 1, state: state, region: region, onTap: tapAction(stop, state: state))
                if let leg = plan.leg(after: stop) {
                    DayLegRow(leg: leg)
                }
            }
            if let last = plan.lastTrain {
                DayLegRow(leg: DayLeg(mode: .train, minutes: 0, from: "", to: "",
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
            BigButton(title: "Montar o dia", style: .orange, systemImage: "arrow.up.right") {
                router.push(.montar(date: region.calendar.startOfDay(for: date)), on: .hoje)
            }
            .padding(.top, 8)
        }
    }
}
