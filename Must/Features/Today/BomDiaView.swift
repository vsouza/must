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

/// 02 · Bom dia (prompt 23 §2, `Manha.png`). Laranja. Tempo + golden, "Hoje você já tem" (âncoras), "Antes de sair"
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
    @State private var specRight: [String] = []

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var today: Date { region.calendar.startOfDay(for: now) }
    private var dayKey: String { BoardDates(timeZone: region.timeZone).dayString(today) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    SpecStack(lines: [DayText.dayLine(now, region: region), "\(region.timeString(now)) · acordou"], color: V8.ink)
                    Spacer(minLength: 12)
                    SpecStack(lines: specRight, color: V8.ink, alignment: .trailing)
                }
                .padding(.top, 10)

                Text("Bom dia.")
                    .font(V8Font.display(60))
                    .foregroundStyle(V8.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 36)
                Text(sentence)
                    .font(V8Font.text(16))
                    .foregroundStyle(V8.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.trailing, 40)

                anchors.padding(.top, 30)
                checklist.padding(.top, 28)
                Color.clear.frame(height: 190)
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { buttons }
        .background {
            ZStack {
                V8.orange
                Rings(color: V8.ink, count: 2, diameter: 520, opacity: 0.5, offset: CGSize(width: 120, height: -200))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .ignoresSafeArea()
        }
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

    @ViewBuilder private var anchors: some View {
        let anchors = plan?.anchors ?? []
        VStack(alignment: .leading, spacing: 0) {
            SectionHead(title: "Hoje você já tem", trailing: anchors.isEmpty ? nil : (anchors.count == 1 ? "1 âncora" : "\(anchors.count) âncoras"),
                        mute: V8.ink.opacity(0.55))
                .padding(.bottom, 10)
            if anchors.isEmpty {
                rule
                Text(plan == nil ? "Nada marcado ainda: monte o dia e as âncoras aparecem aqui." : "Nenhuma âncora hoje: o dia é livre.")
                    .font(V8Font.text(14))
                    .foregroundStyle(V8.ink.opacity(0.75))
                    .padding(.vertical, 12)
            }
            ForEach(anchors) { stop in
                rule
                Button {
                    if let id = stop.placeId { router.push(.place(id: id), on: .hoje) }
                } label: {
                    HStack(spacing: 12) {
                        Text(region.timeString(stop.start)).font(V8Font.mono(13, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.6).frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stop.label).font(V8Font.text(15, weight: .bold)).lineLimit(1)
                            Text(stop.note).font(V8Font.text(12)).opacity(0.75).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text((stop.tag ?? "RES").uppercased())
                            .font(V8Font.mono(9)).fontWeight(.semibold).tracking(0.7)
                            .foregroundStyle(V8.orange)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(V8.ink))
                    }
                    .foregroundStyle(V8.ink)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rule: some View { Rectangle().fill(V8.ink.opacity(0.22)).frame(height: 1) }

    // MARK: Antes de sair

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHead(title: "Antes de sair", trailing: items.count == 1 ? "1 item" : "\(items.count) itens", mute: V8.ink.opacity(0.55))
            if items.isEmpty {
                Text("Nada a levar além do de sempre.").font(V8Font.text(14)).foregroundStyle(V8.ink.opacity(0.75))
            }
            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    Button { toggle(item) } label: { checkChip(item, on: checked.contains(item.id)) }
                        .buttonStyle(MustPressStyle())
                }
            }
            if let plan, let train = MorningText.firstTrain(plan, after: now) { trainRow(train, plan: plan).padding(.top, 4) }
        }
    }

    private func checkChip(_ item: MorningItem, on: Bool) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().strokeBorder(V8.ink, lineWidth: 1.5).background(Circle().fill(on ? V8.ink : .clear))
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(V8.orange) }
            }
            .frame(width: 18, height: 18)
            Text(item.text).font(V8Font.text(13, weight: .semibold)).foregroundStyle(V8.ink).lineLimit(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(minHeight: 32)
        .background(Capsule().fill(V8.ink.opacity(0.1)))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ item: MorningItem) {
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
        UserDefaults.standard.set(checked.sorted(), forKey: MorningChecklist.checkedKey(dayKey))
    }

    private func trainRow(_ leg: DayLeg, plan: DayPlan) -> some View {
        let parts = leg.detail.components(separatedBy: " · ")
        let to = plan.stops.first { $0.id == leg.to }.map { DayText.head($0.label) }
        return HStack(spacing: 12) {
            Text(leg.departAt.map(region.timeString) ?? "\(leg.minutes)′")
                .font(V8Font.mono(18)).fontWeight(.semibold)
            VStack(alignment: .leading, spacing: 1) {
                Text(parts.first ?? leg.detail).font(V8Font.text(13.5, weight: .bold)).lineLimit(1)
                Text(([to.map { "até \($0)" }] + parts.dropFirst().map(Optional.some)).compactMap { $0 }.joined(separator: " · "))
                    .font(V8Font.text(11.5)).opacity(0.75).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(V8.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(V8.ink.opacity(0.1)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Primeiro trem")
    }

    // MARK: Botões

    private var buttons: some View {
        HStack(spacing: 10) {
            BigButton(title: "Ver o dia", style: .line, lineColor: V8.ink) { router.push(.linha(date: today), on: .hoje) }
            BigButton(title: "Ajustar o dia", style: .ink, systemImage: "arrow.up.right") { router.push(.montar(date: today), on: .hoje) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 96)
        .background {
            LinearGradient(colors: [V8.orange.opacity(0), V8.orange], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.25))
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
