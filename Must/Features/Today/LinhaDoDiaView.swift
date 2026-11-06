import SwiftData
import SwiftUI

/// 04 · Linha do dia (prompt 23 §2, `Dia.png` / `DiaIT.png`). Papel. Paradas (âncora = tinta, must = branco,
/// micro = tracejada), deslocamentos entre elas, último trem no fim. Toggle Linha/Mapa (Mapa = rota `.mapa`).
/// Estados: feito (50 %), agora (laranja). Tudo do `DayPlan` do motor; sem plano, um vazio que leva ao Montar.
struct LinhaDoDiaView: View {
    var date: Date

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(\.dayEngine) private var engine
    @Environment(\.showEvents) private var showEvents
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var plan: DayPlan?
    @State private var nowId: String?
    @State private var doneIds: Set<String> = []
    @State private var loaded = false

    private var region: Region { store.region }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(date) }

    var body: some View {
        ZStack(alignment: .top) {
            V8.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, 10)
                    if let plan {
                        if !shows.isEmpty { showsBand.padding(.top, 20) }
                        timeline(plan).padding(.top, shows.isEmpty ? 22 : 16)
                    } else if loaded {
                        empty.padding(.top, 40)
                    }
                    Color.clear.frame(height: 130)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            BottomFade(color: V8.paper, height: 150)
        }
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

    // MARK: Topo

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SpecStack(lines: [DayText.dayLine(date, region: region), plan?.title ?? "sem dia montado"], color: V8.mute)
                Spacer(minLength: 12)
                if let plan {
                    SpecStack(lines: ["\(plan.countLine) · \(plan.anchors.count == 1 ? "1 âncora" : "\(plan.anchors.count) âncoras")"
                                          + (shows.isEmpty ? "" : "\n\(shows.count) em cartaz"),
                                      "\(region.money(plan.spent)) de \(region.money(plan.budget, symbol: false))"],
                              color: V8.mute, alignment: .trailing)
                }
            }
            HStack(alignment: .bottom) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Button { dismiss() } label: {
                        Text("Dia").font(V8Font.display(44)).foregroundStyle(V8.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voltar")
                    BigNumeral(numeral, size: 84, color: V8.orange)
                        .fixedSize()
                        .padding(.bottom, -6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Dia \(numeral)")
                Spacer(minLength: 12)
                // Mandar o dia (prompt 25 · B.5): cartaz, link e PDF.
                if plan != nil {
                    RoundButton(systemImage: "paperplane", label: "Mandar o dia", style: .line, tint: V8.ink, size: 40) {
                        router.sheet = .mandar(date: region.calendar.startOfDay(for: date))
                    }
                }
                toggle
            }
        }
    }

    private var numeral: String {
        plan?.dayNumber.map(String.init) ?? region.dayNumber(date)
    }

    /// Linha | Mapa (o Mapa é a tela do mapa do dia).
    private var toggle: some View {
        HStack(spacing: 4) {
            Text("Linha")
                .font(V8Font.text(13, weight: .semibold))
                .foregroundStyle(V8.white)
                .padding(.horizontal, 16)
                .frame(minHeight: ButtonMetrics.pillHeight)
                .background(Capsule().fill(V8.ink))
                .accessibilityAddTraits(.isSelected)
            Button { router.push(.mapa, on: .hoje) } label: {
                Text("Mapa")
                    .font(V8Font.text(13, weight: .semibold))
                    .foregroundStyle(V8.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: ButtonMetrics.pillHeight)
            }
            .buttonStyle(.plain)
        }
        .padding(4)
        .background(Capsule().fill(V8.white))
        .overlay(Capsule().strokeBorder(V8.ink.opacity(0.14), lineWidth: 1))
    }

    // MARK: Em cartaz

    /// O que está em cartaz hoje (cache do aparelho; o motor decide se vira micro-parada).
    private var shows: [ShowEvent] { showEvents.today(region: region, at: date) }

    /// Faixa preta "Em cartaz hoje" (`DiaEmCartaz.png`): leva à tela Em cartaz.
    private var showsBand: some View {
        let first = shows[0]
        let more = shows.count > 1 ? " +\(shows.count - 1)" : ""
        return Button { router.push(.emCartaz, on: .hoje) } label: {
            HStack(spacing: 12) {
                Text("EM CARTAZ HOJE").font(V8Font.mono(11, weight: .bold)).tracking(1.4).foregroundStyle(V8.orange).lineLimit(1).fixedSize()
                Text(first.title + more).font(V8Font.text(16, weight: .bold)).foregroundStyle(V8.white).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .bold)).foregroundStyle(V8.white)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(V8.ink))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(MustPressStyle())
        .accessibilityLabel("Em cartaz hoje: \(first.title)\(more)")
    }

    // MARK: Linha

    private func timeline(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
