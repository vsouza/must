import SwiftData
import SwiftUI

/// Viagem: gasto total, fileira de dias, um card por trecho de cidade, progresso por lista.
/// Em BH (sem viagem): o mês, com 済 nos dias feitos e cards por semana — sem inventar viagem.
struct TripView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store

    @Query(sort: \MustList.order) private var lists: [MustList]
    @Query private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var days: [PlannedDay]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var events: [TripEvent]
    @Query private var wallet: [WalletItem]
    @Query private var shopping: [ShoppingItem]

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var cal: Calendar { region.calendar }
    private var trip: TripInfo? { trips.first?.hasTrip == true ? trips.first : nil }
    private var budget: Double { settingsList.first?.perDayBudget ?? region.defaultBudget }

    var body: some View {
        let period = TripStats.period(trip: trip, now: now, calendar: cal)
        let doneDays = TripStats.doneDays(places: places, days: days, calendar: cal)
        let cells = TripStats.days(in: period, trip: trip, now: now, calendar: cal, doneDays: doneDays)
        let spent = TripStats.spent(expenses, in: period, calendar: cal)
        let elapsed = TripStats.elapsedDays(period, now: now, calendar: cal)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar(period).padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(trip == nil ? region.displayName : "Viagem").mustTitle()
                    Text(subtitle(period: period)).mustSerif(18).foregroundStyle(Color.must.secondary)
                }
                .padding(.top, 22)
                spendBlock(spent: spent, elapsed: elapsed).padding(.top, 26)
                dayRow(cells).padding(.top, 20)
                if let trip { cityCards(trip).padding(.top, 34) } else { weekCards(period: period).padding(.top, 34) }
                progressTags.padding(.top, 16)
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .custom([
                    Blob(cx: 330, cy: 300, rx: 110, ry: 90, rotation: -10, fill: .green, opacity: 0.85),
                    Blob(cx: 20, cy: 560, rx: 80, ry: 70, rotation: 10, fill: .sky),
                ]))
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Topo

    private func topBar(_ period: ClosedRange<Date>) -> some View {
        HStack {
            IconButton(.voltar, label: "Voltar") { dismiss() }
            Spacer()
            Micro(trip == nil
                  ? "\(region.shortName) · \(monthName(period.lowerBound))"
                  : "\(region.displayName) · \(region.dayNumber(period.lowerBound))–\(region.dayNumber(period.upperBound)) \(region.monthShort(period.upperBound))")
            Spacer()
            IconButton(.ajustes, label: "Ajustes") { router.push(.settings, on: router.tab) }
        }
    }

    private func monthName(_ date: Date) -> String {
        var style = Date.FormatStyle(locale: region.locale, calendar: cal).month(.wide)
        style.timeZone = region.timeZone
        return date.formatted(style)
    }

    private func subtitle(period: ClosedRange<Date>) -> String {
        let done = places.filter(\.isDone).count
        let musts = "\(done) musts feitos de \(places.count)"
        guard trip != nil else { return "\(monthName(now)) · \(musts)" }
        let today = cal.startOfDay(for: now)
        let total = (cal.dateComponents([.day], from: period.lowerBound, to: period.upperBound).day ?? 0) + 1
        if today < period.lowerBound {
            let left = cal.dateComponents([.day], from: today, to: period.lowerBound).day ?? 0
            return "faltam \(left) dias · \(musts)"
        }
        if today > period.upperBound { return "viagem feita · \(musts)" }
        let index = (cal.dateComponents([.day], from: period.lowerBound, to: today).day ?? 0) + 1
        return "dia \(index) de \(total) · \(musts)"
    }

    // MARK: Gasto

    private func spendBlock(spent: Double, elapsed: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(trip == nil ? "Gasto no mês" : "Gasto na viagem").font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    MonoNumber(region.money(spent, symbol: false), size: 40)
                    Text(region.currency).font(.must.archivo(17, .semibold))
                }
                .foregroundStyle(Color.must.ink)
                Text(meta(spent: spent, elapsed: elapsed)).font(.must.meta).foregroundStyle(Color.must.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { router.push(.schedule(tab: .voos), on: router.tab) } label: {
                MustIconView(.calendario, size: 20)
                    .foregroundStyle(.white)
                    .frame(width: 48)
                    .frame(maxHeight: .infinity)
                    .background(Capsule().fill(Color.must.ink))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Voos e reservas")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func meta(spent: Double, elapsed: Int) -> String {
        var parts: [String] = []
        if region == .jp, let fx = settingsList.first?.fxRate, spent > 0 { parts.append("≈ \((spent * fx).formatted(.money("BRL")))") }
        parts.append("média \(region.money(spent / Double(elapsed)))/dia")
        parts.append("meta \(region.money(budget))")
        return parts.joined(separator: " · ")
    }

    // MARK: Dias

    private func dayRow(_ cells: [TripStats.DayCell]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cells) { cell in
                        Button { open(cell) } label: { dayDot(cell) }
                            .buttonStyle(MustPressStyle())
                            .id(cell.date)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(cal.startOfDay(for: now), anchor: .center) }
        }
    }

    private func dayDot(_ cell: TripStats.DayCell) -> some View {
        let (fill, text): (Color, Color) = switch cell.state {
        case .done: (Color.must.green, Color.must.greenText)
        case .today: (Color.must.ink, .white)
        case .otherCity: (Color(hex: 0xE6F1FF), Color.must.blueText)
        case .future, .past: (Color.must.surface, Color.must.ink)
        }
        return Text("\(cell.number)")
            .font(.must.mono(14, .semibold))
            .foregroundStyle(text)
            .frame(width: 40, height: 40)
            .background(Circle().fill(fill))
            .overlay {
                if cell.state == .today { Circle().strokeBorder(Color.must.green, lineWidth: 2.5).padding(-4) }
            }
            .overlay(alignment: .topTrailing) {
                if trip == nil, cell.state == .done { Text("済").font(.must.kanji(9)).foregroundStyle(Color.must.greenText).offset(x: 2, y: -2) }
            }
            .opacity(cell.state == .past ? 0.5 : 1)
            .accessibilityLabel("dia \(cell.number)")
    }

    /// Dia aceito → o Hoje daquele dia; senão → Montar com a data.
    private func open(_ cell: TripStats.DayCell) {
        let accepted = days.contains { $0.date == cell.date && $0.accepted }
        if cell.state == .today && accepted {
            router.select(.hoje)
        } else if accepted {
            router.push(.day(date: cell.date), on: router.tab)
        } else {
            router.push(.montar(date: cell.date), on: .hoje)
        }
    }

    // MARK: Cards por cidade (viagem)

    private func cityCards(_ trip: TripInfo) -> some View {
        let cities = trip.cities
        let current = trip.city(on: now, calendar: cal)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(cities.prefix(3).enumerated()), id: \.element.id) { index, city in
                cityCard(city, trip: trip, isCurrent: city.id == current?.id, isLast: index == min(2, cities.count - 1), index: index)
                    .frame(height: index == min(2, cities.count - 1) ? 250 : 118)
                    .stackCard(tint: index == 0 ? .must(.eat) : index == 1 ? .must(.drink) : .sky,
                               rotation: index == 0 ? -2 : index == 1 ? 1.5 : 0)
                    .padding(.leading, index == 0 ? 78 : index == 1 ? 38 : 0)
                    .padding(.trailing, index == 0 ? -62 : index == 1 ? -42 : 0)
                    .offset(y: CGFloat(index) * 86)
            }
        }
        .frame(height: CGFloat(min(3, cities.count) - 1) * 86 + 250, alignment: .top)
    }

    private func cityCard(_ city: City, trip: TripInfo, isCurrent: Bool, isLast: Bool, index: Int) -> some View {
        let cityPlaces = places.filter { $0.cityId == city.id }
        let range = (city.from ?? .distantPast)...(city.to ?? .distantFuture)
        let reservations = cityPlaces.filter { $0.reservation.map { range.contains($0.at) } ?? false }
        let cityEvents = events.filter { range.contains($0.at) }
        let repeated = trip.cities.prefix(index).contains { $0.name == city.name }
        var label = "\(city.name)\(repeated ? " de novo" : "")"
        if let from = city.from, let to = city.to { label += " · \(region.dayNumber(from))–\(region.dayNumber(to)) \(region.monthShort(to))" }
        if isCurrent { label += " · agora" }

        let saveForEnd = cityPlaces.filter { $0.saveForEnd && !$0.isDone }
        let pending = cityPlaces.filter { !$0.isDone }.count
        let title: String = {
            if isCurrent, let idx = trip.dayIndex(in: city, on: now, calendar: cal) { return "Dia \(idx.index) de \(idx.total)" }
            return pending == 1 ? "1 must esperando" : "\(pending) musts esperando"
        }()
        var detail = [trip.home.map { isCurrent ? $0 : "" } ?? "", "\(cityPlaces.filter(\.isDone).count) feitos"].filter { !$0.isEmpty }
        let anchors = reservations.map(\.name) + cityEvents.map(\.title)
        if !anchors.isEmpty { detail.append("\(anchors.count) \(anchors.count == 1 ? "reserva" : "reservas"): \(anchors.prefix(2).joined(separator: ", "))") }

        return VStack(alignment: .leading, spacing: 8) {
            Micro(label, color: isLast ? Color.must.blueText : (index == 0 ? MustColor.eat.text : Color.must.blueText))
            if isLast && !saveForEnd.isEmpty {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    MonoNumber("\(saveForEnd.count)", size: 64).foregroundStyle(Color.must.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ficaram pro fim").font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.ink)
                        Text(saveForEnd.prefix(3).map(\.name).joined(separator: ", ")).font(.must.archivo(13)).foregroundStyle(Color.must.blueText).lineLimit(2)
                    }
                    .padding(.bottom, 6)
                }
            } else {
                Text(title).font(.must.archivo(24, .semibold)).foregroundStyle(Color.must.ink)
                Text(detail.joined(separator: " · ")).font(.must.archivo(13)).lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Cards por semana (BH)

    private func weekCards(period: ClosedRange<Date>) -> some View {
        let today = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let lastWeek = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let saveForEnd = places.filter { $0.saveForEnd && !$0.isDone }
        return ZStack(alignment: .topLeading) {
            weekCard(start: weekStart, title: "Esta semana")
                .frame(height: 118).stackCard(color: .eat, rotation: -2)
                .padding(.leading, 78).padding(.trailing, -62)
            weekCard(start: lastWeek, title: "Semana passada")
                .frame(height: 118).stackCard(color: .drink, rotation: 1.5)
                .padding(.leading, 38).padding(.trailing, -42).offset(y: 86)
            VStack(alignment: .leading, spacing: 8) {
                Micro("fica pro fim · quando você pedir", color: Color.must.blueText)
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    MonoNumber("\(saveForEnd.count)", size: 64).foregroundStyle(Color.must.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ficaram pro fim").font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.ink)
                        Text(saveForEnd.prefix(3).map(\.name).joined(separator: ", ")).font(.must.archivo(13)).foregroundStyle(Color.must.blueText).lineLimit(2)
                    }
                    .padding(.bottom, 6)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: 250).stackCard(tint: .sky).offset(y: 172)
        }
        .frame(height: 422, alignment: .top)
    }

    private func weekCard(start: Date, title: String) -> some View {
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let weekRange = start...end
        let doneCount = places.filter { $0.done.map { weekRange.contains(cal.startOfDay(for: $0.at)) } ?? false }.count
        let spent = TripStats.spent(expenses, in: weekRange, calendar: cal)
        return VStack(alignment: .leading, spacing: 8) {
            Micro("\(title) · \(region.shortDay(start))–\(region.shortDay(end))", color: Color.must.ink.opacity(0.7))
            Text(doneCount == 1 ? "1 must feito" : "\(doneCount) musts feitos").font(.must.archivo(24, .semibold)).foregroundStyle(Color.must.ink)
            Text("gasto \(region.money(spent))").font(.must.archivo(13))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Progresso por lista

    private var progressTags: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Central da viagem: a Carteira (cartões, passes, QR de entrada) fica na mesma fileira.
                Button { router.push(.carteira, on: router.tab) } label: {
                    Tag(wallet.isEmpty ? "Carteira" : "Carteira · \(wallet.count)")
                }
                .buttonStyle(MustPressStyle())
                // Compras da viagem (prompt 17 · B): a lista com a previsão e as regras da volta (só Japão).
                if region == .jp {
                    Button { router.push(.compras, on: router.tab) } label: {
                        Tag(shopping.isEmpty ? "Compras" : "Compras · \(shopping.count)")
                    }
                    .buttonStyle(MustPressStyle())
                }
                ForEach(TripStats.progress(lists: lists), id: \.list.id) { item in
                    Button { router.push(.list(id: item.list.id), on: router.tab) } label: {
                        Tag("\(item.list.name.capitalized) \(item.done)/\(item.total)", dot: item.list.color.strong)
                    }
                    .buttonStyle(MustPressStyle())
                }
            }
        }
        .scrollClipDisabled()
    }
}
