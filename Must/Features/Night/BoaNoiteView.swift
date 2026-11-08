import SwiftData
import SwiftUI

/// 14 · Boa noite (prompt 23 §2, `Noite.png`). Cor do lugar. "k das n paradas", km a pé, gasto, uma linha pro diário,
/// "Amanhã" com a âncora e o conselho do tempo, chips do que fazer antes. "Fechar o dia" marca o dia como fechado.
/// A linha do diário fica no UserDefaults por data (o modelo SwiftData não muda nesta rodada).
struct BoaNoiteView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context
    @Environment(\.tripTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Query private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var trips: [TripInfo]
    @Query private var wallet: [WalletItem]

    @State private var plan: DayPlan?
    @State private var summary: NightSummary?
    @State private var tomorrow: Tomorrow?
    @State private var chips: [MorningItem] = []
    @State private var diary = ""
    @State private var editing = false
    @FocusState private var diaryFocused: Bool

    struct Tomorrow {
        var date: Date
        var area: String?
        var time: Date?
        var title: String
        var advice: String?
    }

    private var region: Region { store.region }
    /// Tinta do bloco da foto (branca com viagem).
    private var ink: Color { theme.coverInk }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(today) }

    var body: some View {
        VStack(spacing: 0) {
            DayBand(areaId: plan?.bandArea(), places: places, height: 270) {
                VStack(alignment: .leading, spacing: 0) {
                    DayBandCorners(left: ["\(DayText.dayLine(now, region: region)) · \(region.timeString(now))",
                                          "dia \(plan?.dayNumber.map(String.init) ?? region.dayNumber(now)) fechado"],
                                   right: rightSpec)
                    Spacer(minLength: 8)
                    HStack(alignment: .bottom, spacing: 10) {
                        Text("Boa noite.")
                            .font(V8Font.display(52))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 4)
                        if let summary {
                            DayBandNumeral(value: "\(summary.done)", caption: "de \(summary.total) paradas", size: 88)
                        }
                    }
                }
            }
            CutRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(summary?.sentence ?? "Nada montado hoje. Amanhã é outro dia.")
                        .font(V8Font.text(17, weight: .semibold))
                        .foregroundStyle(V8.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    IndexRule()
                    if let summary { stats(summary) }
                    diaryCard
                    tomorrowSection
                    Color.clear.frame(height: 190)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) {
                BigButton(title: "Fechar o dia", style: .ink, systemImage: "checkmark") { closeDay() }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 92)
                    .background {
                        LinearGradient(colors: [V8.paper.opacity(0), V8.paper], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3))
                            .ignoresSafeArea().allowsHitTesting(false)
                    }
            }
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
    }

    private var rightSpec: [String] {
        var lines: [String] = []
        if let train = plan?.lastTrain { lines.append("último trem \(region.timeString(train.at))") }
        if let last = lastPlace { lines.append("você: \(last)") }
        return lines
    }

    /// Onde você está: a última parada feita (ou já começada).
    private var lastPlace: String? {
        guard let plan else { return nil }
        let done = DayDoneStore().ids(day: dayKey)
        let stop = plan.stops.last { $0.done || done.contains($0.id) || $0.start <= now }
        return stop.map { DayText.head($0.label) }
    }

    private func load() {
        let cal = region.calendar
        let trip = trips.first
        plan = engine.plan(for: today, region: region, context: context)
        let spentExpenses = HomeState.spent(expenses, on: now, region: region)
        summary = plan.map { NightSummary.build(plan: $0, doneIds: DayDoneStore().ids(day: dayKey), spent: spentExpenses > 0 ? spentExpenses : $0.spent) }
        diary = UserDefaults.standard.string(forKey: NightSummary.diaryKey(dayKey)) ?? ""

        let tomorrowDate = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let next = engine.plan(for: tomorrowDate, region: region, context: context)
        let weather = services.sync.weather(on: tomorrowDate, region: region, trip: trip)
        tomorrow = Self.tomorrow(plan: next, date: tomorrowDate, places: places, weather: weather, region: region)
        let notes = Dictionary(places.map { ($0.id, $0.notes) }, uniquingKeysWith: { a, _ in a })
        let card = wallet.first { $0.kind == .transitCard && $0.balance != nil }
            .map { MorningChecklist.TransitCard(name: $0.name, balance: $0.balance ?? 0) }
        chips = MorningChecklist.items(plan: next, placeNotes: notes, transitCard: card, weather: weather, region: region)
    }

    /// Amanhã: a primeira âncora do plano; sem plano, a reserva ou o ingresso do dia no board.
    static func tomorrow(plan: DayPlan?, date: Date, places: [Place], weather: DayWeather?, region: Region) -> Tomorrow {
        let cal = region.calendar
        let advice = weather.map { w -> String in
            if DayText.isRainy(w) { return "chuva amanhã (\(w.precipProb)%): comece pelo que é coberto" }
            if w.isClear { return "sol, \(Int(w.tempMax.rounded()))°: bom dia pra andar e pro golden" }
            return "\(DayText.sky(w.code)), \(Int(w.tempMin.rounded()))–\(Int(w.tempMax.rounded()))°"
        }
        let areaName = plan?.area.flatMap { id in AreaCatalog.areas(for: region).first { $0.id == id }?.name }
        if let anchor = plan?.anchors.first {
            return Tomorrow(date: date, area: areaName, time: anchor.start, title: anchor.label, advice: advice ?? anchor.note)
        }
        let booked = places.compactMap { p -> (String, Date)? in
            if let r = p.reservation, cal.isDate(r.at, inSameDayAs: date) { return (p.name, r.at) }
            if let t = p.tickets.first(where: { cal.isDate($0.at, inSameDayAs: date) }) { return (p.name, t.at) }
            return nil
        }.min { $0.1 < $1.1 }
        if let booked { return Tomorrow(date: date, area: areaName, time: booked.1, title: booked.0, advice: advice) }
        if let first = plan?.stops.first {
            return Tomorrow(date: date, area: areaName, time: first.start, title: first.label, advice: advice)
        }
        return Tomorrow(date: date, area: areaName, time: nil, title: "Nada marcado ainda", advice: advice ?? "monte o dia de manhã")
    }

    // MARK: Números

    /// Km a pé e gasto: duas colunas separadas por régua de 2 pt.
    private func stats(_ s: NightSummary) -> some View {
        let money = DayText.compactMoney(s.spent, region: region)
        return HStack(alignment: .top, spacing: 0) {
            stat(big: s.walkKm.formatted(.number.locale(region.locale).precision(.fractionLength(1))), small: nil, label: "km a pé")
            Rectangle().fill(V8.ink).frame(width: 2)
            stat(big: money.number, small: money.suffix.isEmpty ? nil : money.suffix,
                 label: s.percent.map { "gasto · \($0)%" } ?? "gasto")
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) { IndexRule() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.done) de \(s.total) paradas, \(Walk.kmText(s.walkKm)) a pé, gasto \(region.money(s.spent))")
    }

    private func stat(big: String, small: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(big).font(V8Font.numeral(44)).foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.5)
                if let small { Text(small).font(V8Font.numeral(24)).foregroundStyle(V8.mute) }
            }
            SpecLabel(label, color: V8.mute)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Diário

    /// Faixa tinta inteira: a linha do diário (é sua, mas é o que fica; o laranja fica pro "Fechar o dia").
    private var diaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Uma linha sobre hoje", size: 10, color: V8.orange)
            if editing {
                TextField("O que valeu hoje?", text: $diary, axis: .vertical)
                    .font(V8Font.text(18).italic())
                    .foregroundStyle(V8.white)
                    .tint(V8.orange)
                    .lineLimit(1...4)
                    .focused($diaryFocused)
                    .submitLabel(.done)
                    .onSubmit(saveDiary)
                    .onChange(of: diaryFocused) { _, focused in if !focused { saveDiary() } }
            } else {
                Text(diary.isEmpty ? "Toque pra escrever uma linha sobre hoje." : "“\(diary)”")
                    .font(V8Font.text(18).italic())
                    .foregroundStyle(diary.isEmpty ? V8.muteDark : V8.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            MonoLabel(editing ? "pronto fecha o teclado" : "toque pra editar · vai pro diário", size: 9.5, color: V8.muteDark)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(V8.ink)
        .overlay(alignment: .bottom) { IndexRule() }
        .contentShape(Rectangle())
        .onTapGesture {
            editing = true
            diaryFocused = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Escreve uma linha sobre hoje")
    }

    private func saveDiary() {
        let text = diary.trimmingCharacters(in: .whitespacesAndNewlines)
        diary = text
        UserDefaults.standard.set(text.isEmpty ? nil : text, forKey: NightSummary.diaryKey(dayKey))
        editing = false
    }

    // MARK: Amanhã

    @ViewBuilder private var tomorrowSection: some View {
        if let t = tomorrow {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Amanhã").font(V8Font.display(26)).foregroundStyle(V8.ink)
                    Spacer(minLength: 8)
                    MonoLabel(["\(DayText.weekdayShort(t.date, region: region)) \(region.dayNumber(t.date))", t.area]
                        .compactMap { $0 }.joined(separator: " · "), color: V8.mute)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) { IndexRule() }
                HStack(spacing: 14) {
                    if let time = t.time {
                        Text(region.timeString(time)).font(V8Font.numeral(28)).tracking(0.5).foregroundStyle(V8.ink)
                            .lineLimit(1).minimumScaleFactor(0.6).frame(width: 88, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.title).font(V8Font.text(17, weight: .bold)).foregroundStyle(V8.ink).lineLimit(1)
                        if let advice = t.advice {
                            Text(advice).font(V8Font.text(12.5)).foregroundStyle(V8.mute).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .frame(minHeight: 68)
                .overlay(alignment: .bottom) { IndexRule() }
                .accessibilityElement(children: .combine)
                if !chips.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(chips) { chip in
                                Text(chip.short.uppercased())
                                    .font(V8Font.mono(9.5, weight: .semibold)).tracking(0.8)
                                    .foregroundStyle(V8.ink)
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                    .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
                            }
                        }
                        .padding(2)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal, 18, for: .scrollContent)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { IndexRule() }
                }
            }
        }
    }

    private func closeDay() {
        saveDiary()
        UserDefaults.standard.set(true, forKey: NightSummary.closedKey(dayKey))
        router.paths[.hoje] = []
    }
}
