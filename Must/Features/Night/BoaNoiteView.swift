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
    private var ink: Color { theme.coverInk }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    SpecStack(lines: ["\(DayText.dayLine(now, region: region)) · \(region.timeString(now))",
                                      "dia \(plan?.dayNumber.map(String.init) ?? region.dayNumber(now)) fechado"], color: ink)
                    Spacer(minLength: 12)
                    SpecStack(lines: rightSpec, color: ink, alignment: .trailing)
                }
                .padding(.top, 10)

                Text("Boa noite.")
                    .font(V8Font.display(64))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 36)
                Text(summary?.sentence ?? "Nada montado hoje. Amanhã é outro dia.")
                    .font(V8Font.text(16))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.trailing, 30)

                if let summary { stats(summary).padding(.top, 36) }
                diaryCard.padding(.top, 36)
                tomorrowSection.padding(.top, 30)
                Color.clear.frame(height: 170)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            BigButton(title: "Fechar o dia", style: .ink, systemImage: "checkmark") { closeDay() }
                .padding(.horizontal, 20)
                .padding(.bottom, 92)
        }
        .background {
            ZStack {
                theme.cover
                Rings(color: ink, count: 3, diameter: 520, opacity: 0.45, offset: CGSize(width: 0, height: 60))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                BigNumeral(plan?.dayNumber.map(String.init) ?? region.dayNumber(now), size: 360, color: ink.opacity(0.15))
                    .fixedSize()
                    .offset(x: 70, y: 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
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

    private func stats(_ s: NightSummary) -> some View {
        let money = DayText.compactMoney(s.spent, region: region)
        return HStack(alignment: .top, spacing: 12) {
            stat(big: "\(s.done)", small: "/\(s.total)", label: "paradas")
            stat(big: s.walkKm.formatted(.number.locale(region.locale).precision(.fractionLength(1))), small: nil, label: "km a pé")
            stat(big: money.number, small: money.suffix.isEmpty ? nil : money.suffix,
                 label: s.percent.map { "gasto · \($0)%" } ?? "gasto")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.done) de \(s.total) paradas, \(Walk.kmText(s.walkKm)) a pé, gasto \(region.money(s.spent))")
    }

    private func stat(big: String, small: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(big).font(V8Font.numeral(50)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                if let small { Text(small).font(V8Font.numeral(26)).foregroundStyle(ink.opacity(0.6)) }
            }
            SpecLabel(label, color: ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Diário

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
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(V8.ink))
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Amanhã").font(V8Font.display(28)).foregroundStyle(ink)
                    Spacer(minLength: 8)
                    MonoLabel(["\(DayText.weekdayShort(t.date, region: region)) \(region.dayNumber(t.date))", t.area]
                        .compactMap { $0 }.joined(separator: " · "), color: ink)
                }
                HStack(spacing: 14) {
                    if let time = t.time {
                        Text(region.timeString(time)).font(V8Font.mono(20)).fontWeight(.semibold).foregroundStyle(ink)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(V8Font.text(15, weight: .bold)).foregroundStyle(ink).lineLimit(1)
                        if let advice = t.advice {
                            Text(advice).font(V8Font.text(13)).foregroundStyle(ink.opacity(0.85)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ink.opacity(0.14)))
                if !chips.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(chips) { chip in
                                Text(chip.short.uppercased())
                                    .font(V8Font.mono(9.5)).fontWeight(.semibold).tracking(0.8)
                                    .foregroundStyle(ink)
                                    .padding(.horizontal, 9).padding(.vertical, 7)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(ink.opacity(0.14)))
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
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
