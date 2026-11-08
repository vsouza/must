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
    @Environment(\.tripTheme) private var theme

    @State private var plan: DayPlan?
    @State private var items: [MorningItem] = []
    @State private var checked: Set<String> = []
    @State private var sentence = ""
    @State private var specRight: [String] = []

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(today) }

    var body: some View {
        VStack(spacing: 0) {
            DayBand(areaId: plan?.bandArea(from: now), places: places, height: 270) {
                VStack(alignment: .leading, spacing: 0) {
                    DayBandCorners(left: [DayText.dayLine(now, region: region), "\(region.timeString(now)) · acordou"], right: specRight)
                    Spacer(minLength: 8)
                    HStack(alignment: .bottom, spacing: 10) {
                        Text("Bom dia.")
                            .font(V8Font.display(56))
                            .foregroundStyle(theme.coverInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 4)
                        if let plan { DayBandNumeral(value: "\(plan.stops.count)", caption: "paradas hoje", size: 88) }
                    }
                }
            }
            CutRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sentence)
                        .font(V8Font.text(17, weight: .semibold))
                        .foregroundStyle(V8.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    IndexRule()
                    anchors
                    checklist
                    Color.clear.frame(height: 190)
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottom) { buttons }
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
    }

    private func load() {
        let trip = trips.first
        let cal = region.calendar
        plan = engine.plan(for: today, region: region, context: context)
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

    // MARK: Âncoras

    private func head(_ title: String, _ trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(V8Font.display(22)).foregroundStyle(V8.ink).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if let trailing { MonoLabel(trailing, color: V8.mute) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) { IndexRule() }
    }

    @ViewBuilder private var anchors: some View {
        let anchors = plan?.anchors ?? []
        VStack(alignment: .leading, spacing: 0) {
            head("Hoje você já tem", anchors.isEmpty ? nil : (anchors.count == 1 ? "1 âncora" : "\(anchors.count) âncoras"))
            if anchors.isEmpty {
                DayStrip {
                    Text(plan == nil ? "Nada marcado ainda: monte o dia e as âncoras aparecem aqui." : "Nenhuma âncora hoje: o dia é livre.")
                        .font(V8Font.text(14))
                        .foregroundStyle(V8.mute)
                }
            }
            ForEach(Array(anchors.enumerated()), id: \.element.id) { i, stop in
                DayStopRow(stop: stop, index: i + 1, state: .upcoming, region: region,
                           onTap: stop.placeId.map { id in { router.push(.place(id: id), on: .hoje) } })
            }
        }
    }

    // MARK: Antes de sair

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            head("Antes de sair", items.count == 1 ? "1 item" : "\(items.count) itens")
            if items.isEmpty {
                DayStrip { Text("Nada a levar além do de sempre.").font(V8Font.text(14)).foregroundStyle(V8.mute) }
            }
            ForEach(items) { item in
                Button { toggle(item) } label: { checkRow(item, on: checked.contains(item.id)) }
                    .buttonStyle(.plain)
            }
            if let plan, let train = MorningText.firstTrain(plan, after: now) { trainRow(train, plan: plan) }
        }
    }

    private func checkRow(_ item: MorningItem, on: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle().fill(on ? V8.ink : .clear)
                Rectangle().stroke(V8.ink, lineWidth: 2)
                if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(V8.orange) }
            }
            .frame(width: 22, height: 22)
            Text(item.text).font(V8Font.text(15, weight: .semibold)).foregroundStyle(V8.ink)
                .strikethrough(on, color: V8.ink)
                .opacity(on ? 0.55 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { IndexRule() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.text)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func toggle(_ item: MorningItem) {
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
        UserDefaults.standard.set(checked.sorted(), forKey: MorningChecklist.checkedKey(dayKey))
    }

    /// Primeiro trem útil: faixa tinta (o mundo lá fora), hora em número grande.
    private func trainRow(_ leg: DayLeg, plan: DayPlan) -> some View {
        let parts = leg.detail.components(separatedBy: " · ")
        let to = plan.stops.first { $0.id == leg.to }.map { DayText.head($0.label) }
        return DayStrip(tone: .ink) {
            HStack(spacing: 14) {
                Text(leg.departAt.map(region.timeString) ?? "\(leg.minutes)′")
                    .font(V8Font.numeral(26)).tracking(0.5)
                    .foregroundStyle(V8.orange)
                    .frame(width: 88, alignment: .leading)
                    .lineLimit(1).minimumScaleFactor(0.6)
                VStack(alignment: .leading, spacing: 2) {
                    MonoLabel("primeiro trem", size: 8.5, color: V8.muteDark)
                    Text(parts.first ?? leg.detail).font(V8Font.text(15, weight: .bold)).foregroundStyle(V8.white).lineLimit(1)
                    Text(([to.map { "até \($0)" }] + parts.dropFirst().map(Optional.some)).compactMap { $0 }.joined(separator: " · "))
                        .font(V8Font.text(12)).foregroundStyle(V8.muteDark).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Primeiro trem")
    }

    // MARK: Botões

    private var buttons: some View {
        HStack(spacing: 10) {
            BigButton(title: "Ver o dia", style: .line, lineColor: V8.ink, lineFill: V8.paper) { router.push(.linha(date: today), on: .hoje) }
            BigButton(title: "Ajustar o dia", style: .ink, systemImage: "arrow.up.right") { router.push(.montar(date: today), on: .hoje) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 96)
        .background {
            LinearGradient(colors: [V8.paper.opacity(0), V8.paper], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
