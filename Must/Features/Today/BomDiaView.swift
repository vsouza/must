import CoreLocation
import SwiftData
import SwiftUI

/// Frase do tempo da manhã (pura): "Sol o dia todo, golden às 16:38. Chuva só terça."
enum MorningText {
    static func sentence(today: DayWeather?, golden: Date?, nextRain: String?, region: Region) -> String {
        var first: String
        if let today {
            if DayText.isRainy(today) {
                first = "Chuva hoje, \(today.precipProb)% de chance"
            } else if today.isClear {
                first = "Sol o dia todo"
            } else {
                first = "\(DayText.sky(today.code).capitalizedFirst), máxima de \(Int(today.tempMax.rounded()))°"
            }
        } else {
            first = "Sem previsão no aparelho"
        }
        if let golden { first += ", golden às \(region.timeString(golden))" }
        var text = first + "."
        if let today, !DayText.isRainy(today), let nextRain { text += " Chuva só \(nextRain)." }
        return text
    }

    /// Primeiro dia com chuva depois de hoje (até 4 dias): "terça" / "terça, indo pra Kyoto".
    static func nextRain(_ days: [(date: Date, weather: DayWeather?, city: String?)], todayCity: String?, region: Region) -> String? {
        guard let rainy = days.first(where: { $0.weather.map(DayText.isRainy) ?? false }) else { return nil }
        var style = Date.FormatStyle(locale: region.locale, calendar: region.calendar).weekday(.wide)
        style.timeZone = region.timeZone
        let weekday = rainy.date.formatted(style).replacingOccurrences(of: "-feira", with: "")
        if let city = rainy.city, city != todayCity { return "\(weekday), indo pra \(city)" }
        return weekday
    }

    /// Primeiro trem/metrô útil do dia (a partir de agora).
    static func firstTrain(_ plan: DayPlan, after date: Date) -> DayLeg? {
        plan.legs.filter { [.train, .metro, .bus].contains($0.mode) }
            .first { ($0.departAt ?? .distantFuture) >= date.addingTimeInterval(-5 * 60) }
    }
}

/// 02 · Bom dia (prompt 23 §2, `Manha.png`; prompt 30: o corte). Bloco do bairro, papel com o índice. Tempo + golden, "Hoje você já tem" (âncoras), "Antes de sair"
/// (checklist gerado), primeiro trem útil. Ver o dia / Ajustar o dia. Lê só o que está no aparelho.
struct BomDiaView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.dayEngine) private var engine
    @Environment(\.modelContext) private var context

    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var wallet: [WalletItem]

    @State private var plan: DayPlan?
    @State private var items: [MorningItem] = []
    @State private var checked: Set<String> = []
    @State private var sentence = ""
    @State private var problem: DayProblem?
    @State private var specRight: [String] = []

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(today) }

    var body: some View {
        List {
            Section {
                if let problem { problemRow(problem) }
                Text(sentence).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            anchors
            checklist
            if let plan, let train = MorningText.firstTrain(plan, after: now) {
                Section("Primeiro trem") { trainRow(train, plan: plan) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(DayText.greeting(now, region: region))
        .navigationBarTitleDisplayMode(.large)
        .navigationSubtitle(subtitle)
        .safeAreaInset(edge: .bottom, spacing: 0) { buttons }
        .v9Screen(grouped: true)
        .onAppear(perform: load)
    }

    /// "sáb · 15 nov · Tóquio · dia 3": o que antes ia nos cantos do bloco.
    private var subtitle: String {
        ([DayText.dayLine(now, region: region)] + specRight).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func load() {
        let trip = trips.first
        let cal = region.calendar
        plan = DayClock.read(engine: engine, region: region, context: context, at: now).plan
        problem = DayProblem.today(context: context, trip: trip, region: region, now: now)
        let weather = services.sync.weather(on: now, region: region, trip: trip)
        let city = trip?.city(on: now, calendar: cal)
        let center = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude,
                                            longitude: city?.lng ?? region.defaultCenter.longitude)
        let golden = SunService.day(now, center, timeZone: region.timeZone).goldenPM?.start
        let next = (1...4).compactMap { n -> (date: Date, weather: DayWeather?, city: String?)? in
            guard let d = cal.date(byAdding: .day, value: n, to: today) else { return nil }
            return (d, services.sync.weather(on: d, region: region, trip: trip), trip?.city(on: d, calendar: cal)?.name)
        }
        sentence = MorningText.sentence(today: weather, golden: golden,
                                        nextRain: MorningText.nextRain(next, todayCity: city?.name, region: region), region: region)

        let dayNumber = plan?.dayNumber ?? DayText.tripDay(start: trip?.start, end: trip?.end, on: now, calendar: cal)?.index
        let temp = services.sync.now(region: region, trip: trip).map { "\(Int($0.temp.rounded()))°" }
        specRight = [[city?.name ?? CapaState.cityName(region), dayNumber.map { "dia \($0)" }].compactMap { $0 }.joined(separator: " · "),
                     [temp, weather.map { DayText.sky($0.code) }].compactMap { $0 }.joined(separator: " · ")]
            .filter { !$0.isEmpty }

        let notes = Dictionary(places.map { ($0.id, $0.notes) }, uniquingKeysWith: { a, _ in a })
        let card = wallet.first { $0.kind == .transitCard && $0.balance != nil }
            .map { MorningChecklist.TransitCard(name: $0.name, balance: $0.balance ?? 0) }
        items = MorningChecklist.items(plan: plan, placeNotes: notes, transitCard: card, weather: weather, region: region)
        checked = Set(UserDefaults.standard.stringArray(forKey: MorningChecklist.checkedKey(dayKey)) ?? [])
    }

    /// Dia de chegada / de trem / último dia: a linha principal do Bom dia.
    private func problemRow(_ problem: DayProblem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(problem.title).font(.footnote.weight(.semibold)).foregroundStyle(V9.accent)
            Text(problem.headline).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Âncoras

    @ViewBuilder private var anchors: some View {
        let anchors = plan?.anchors ?? []
        Section {
            if anchors.isEmpty {
                Text(plan == nil ? "Nada marcado ainda: monte o dia e as âncoras aparecem aqui." : "Nenhuma âncora hoje: o dia é livre.")
                    .foregroundStyle(.secondary)
            }
            ForEach(anchors) { stop in
                V9StopRow(stop: stop, state: .upcoming, region: region,
                          onTap: stop.placeId.map { id in { router.push(.place(id: id), on: .hoje) } })
            }
        } header: {
            Text("Hoje você já tem")
        } footer: {
            if !anchors.isEmpty { Text(anchors.count == 1 ? "1 âncora" : "\(anchors.count) âncoras") }
        }
    }

    // MARK: Antes de sair

    private var checklist: some View {
        Section {
            if items.isEmpty { Text("Nada a levar além do de sempre.").foregroundStyle(.secondary) }
            ForEach(items) { item in
                Button { toggle(item) } label: { checkRow(item, on: checked.contains(item.id)) }
                    .buttonStyle(.plain)
            }
        } header: {
            Text("Antes de sair")
        } footer: {
            if !items.isEmpty { Text(items.count == 1 ? "1 item" : "\(items.count) itens") }
        }
    }

    private func checkRow(_ item: MorningItem, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? V9.accent : Color.secondary)
                .accessibilityHidden(true)
            Text(item.text)
                .strikethrough(on)
                .foregroundStyle(on ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.text)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ item: MorningItem) {
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
        UserDefaults.standard.set(checked.sorted(), forKey: MorningChecklist.checkedKey(dayKey))
    }


    /// Primeiro trem útil: hora, linha e destino.
    private func trainRow(_ leg: DayLeg, plan: DayPlan) -> some View {
        let parts = leg.detail.components(separatedBy: " · ")
        let to = plan.stops.first { $0.id == leg.to }.map { DayText.head($0.label) }
        let detail = ([to.map { "até \($0)" }] + parts.dropFirst().map(Optional.some)).compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            Text(leg.departAt.map(region.timeString) ?? "\(leg.minutes) min")
                .font(.body.weight(.semibold)).monospacedDigit()
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(parts.first ?? leg.detail).font(.body.weight(.semibold)).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Primeiro trem")
    }

    // MARK: Botões

    private var buttons: some View {
        HStack(spacing: 12) {
            Button { router.push(.linha(date: today), on: .hoje) } label: {
                Text("Ver o dia").frame(maxWidth: .infinity)
            }
            .v9Secondary()
            Button { router.push(.montar(date: today), on: .hoje) } label: {
                Text("Ajustar o dia").frame(maxWidth: .infinity)
            }
            .v9Primary()
        }
        .padding(.horizontal, V9.gutter)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
