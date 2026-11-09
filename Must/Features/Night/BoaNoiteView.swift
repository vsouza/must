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

    @Query private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var trips: [TripInfo]
    @Query private var wallet: [WalletItem]

    @State private var plan: DayPlan?
    @State private var summary: NightSummary?
    @State private var tomorrow: Tomorrow?
    @State private var chips: [MorningItem] = []
    @State private var diary = ""
    @FocusState private var diaryFocused: Bool

    struct Tomorrow {
        var date: Date
        var area: String?
        var time: Date?
        var title: String
        var advice: String?
    }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(today) }

    var body: some View {
        List {
            Section {
                Text(summary?.sentence ?? "Nada montado hoje. Amanhã é outro dia.")
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let summary { stats(summary) }
            diarySection
            tomorrowSection
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Boa noite")
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitle(subtitle)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { closeDay() } label: {
                Label("Fechar o dia", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .v9Primary()
            .padding(.horizontal, V9.gutter)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .v9Screen(grouped: true)
        .onAppear(perform: load)
    }

    /// "sáb · 15 nov · último trem 23:41 · você: Gyoen": o que antes ia nos cantos do bloco.
    private var subtitle: String {
        var parts = [DayText.dayLine(now, region: region)]
        if let train = plan?.lastTrain { parts.append("último trem \(region.timeString(train.at))") }
        if let last = lastPlace { parts.append("você: \(last)") }
        return parts.joined(separator: " · ")
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

    private func stats(_ s: NightSummary) -> some View {
        let money = DayText.compactMoney(s.spent, region: region)
        return Section("Hoje") {
            LabeledContent("Paradas") { Text("\(s.done) de \(s.total)").monospacedDigit() }
            LabeledContent("A pé") {
                Text("\(s.walkKm.formatted(.number.locale(region.locale).precision(.fractionLength(1)))) km").monospacedDigit()
            }
            LabeledContent(s.percent.map { "Gasto · \($0)%" } ?? "Gasto") {
                Text(money.number + money.suffix).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.done) de \(s.total) paradas, \(Walk.kmText(s.walkKm)) a pé, gasto \(region.money(s.spent))")
    }

    // MARK: Diário

    /// A linha do diário: é sua, e é o que fica. Salva ao sair do campo ou no "Fechar o dia".
    private var diarySection: some View {
        Section {
            TextField("O que valeu hoje?", text: $diary, axis: .vertical)
                .lineLimit(1...4)
                .focused($diaryFocused)
                .submitLabel(.done)
                .onSubmit(saveDiary)
                .onChange(of: diaryFocused) { _, focused in if !focused { saveDiary() } }
        } header: {
            Text("Uma linha sobre hoje")
        } footer: {
            Text("Vai pro diário.")
        }
    }

    private func saveDiary() {
        let text = diary.trimmingCharacters(in: .whitespacesAndNewlines)
        diary = text
        UserDefaults.standard.set(text.isEmpty ? nil : text, forKey: NightSummary.diaryKey(dayKey))
    }

    // MARK: Amanhã

    @ViewBuilder private var tomorrowSection: some View {
        if let t = tomorrow {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if let time = t.time {
                        Text(region.timeString(time)).font(.body.weight(.semibold)).monospacedDigit()
                            .frame(minWidth: 56, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.body.weight(.semibold)).lineLimit(2)
                        if let advice = t.advice { Text(advice).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
                    }
                }
                .accessibilityElement(children: .combine)
                ForEach(chips) { chip in
                    Label(chip.text, systemImage: "checklist").font(.subheadline)
                }
            } header: {
                Text("Amanhã · " + ["\(DayText.weekdayShort(t.date, region: region)) \(region.dayNumber(t.date))", t.area]
                    .compactMap { $0 }.joined(separator: " · "))
            }
        }
    }

    private func closeDay() {
        saveDiary()
        UserDefaults.standard.set(true, forKey: NightSummary.closedKey(dayKey))
        router.paths[.hoje] = []
    }
}
