import SwiftData
import SwiftUI

/// Viagem: gasto total, fileira de dias, selos de bairro (prompt 18 · D.18), um card por trecho de cidade, progresso por lista.
/// Em BH (sem viagem): o mês, com 済 nos dias feitos e cards por semana — sem inventar viagem.
struct TripView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(\.tripTheme) private var theme

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
        let stamps = AreaStamps.earned(areas: AreaCatalog.areas(for: region), places: places.map(HomeState.areaPlace))

        List {
            Section {
                spendBlock(spent: spent, elapsed: elapsed)
                Button { router.push(.schedule(tab: .voos), on: router.tab) } label: {
                    Label("Voos e reservas", systemImage: "calendar")
                }
            } header: {
                Text(subtitle(period: period)).textCase(nil).font(.subheadline)
            }
            Section("Dias") { dayRow(cells) }
            if !stamps.isEmpty {
                Section("Bairros com Must feito · \(stamps.count)") { stampRow(stamps) }
            }
            if let trip { cityCards(trip) } else { weekCards(period: period) }
            progressTags
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle(trip == nil ? region.displayName : "Viagem")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Ajustes", systemImage: "gearshape") { router.push(.settings, on: router.tab) }
            }
        }
        .v9Screen(grouped: true)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(trip == nil ? "Gasto no mês" : "Gasto na viagem").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(region.money(spent, symbol: false)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                Text(region.currency).font(.headline)
            }
            Text(meta(spent: spent, elapsed: elapsed)).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
        }
        .accessibilityElement(children: .combine)
    }

    private func meta(spent: Double, elapsed: Int) -> String {
        var parts: [String] = []
        if region.profile.money?.showsBRL == true, let fx = settingsList.first?.fxRate, spent > 0 { parts.append("≈ \((spent * fx).formatted(.money("BRL")))") }
        // Média sem centavos (prompt 18 · D.20): o formatador mostra centavos quando o valor não é inteiro.
        parts.append("média \(region.money((spent / Double(max(elapsed, 1))).rounded()))/dia")
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
                            .buttonStyle(.plain)
                            .id(cell.date)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear { proxy.scrollTo(cal.startOfDay(for: now), anchor: .center) }
        }
    }

    private func dayDot(_ cell: TripStats.DayCell) -> some View {
        // Hoje = acento cheio; feito = acento suave; outra cidade = tracejado.
        let (fill, text): (Color, Color) = switch cell.state {
        case .done: (V9.accent.opacity(0.25), Color.primary)
        case .today: (V9.accent, Color.white)
        case .otherCity, .future, .past: (V9.fill, Color.primary)
        }
        return Text("\(cell.number)")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(text)
            .frame(width: 44, height: 44)
            .background(Circle().fill(fill))
            .overlay {
                if cell.state == .otherCity { Circle().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])) }
            }
            .overlay(alignment: .topTrailing) {
                if trip == nil, cell.state == .done { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).offset(x: -4, y: 4) }
            }
            .opacity(cell.state == .past ? 0.55 : 1)
            .accessibilityLabel("Dia \(cell.number)" + (cell.state == .today ? ", hoje" : cell.state == .done ? ", feito" : ""))
    }

    /// Dia aceito → o Hoje daquele dia; senão → Montar com a data.
    private func open(_ cell: TripStats.DayCell) {
        let accepted = days.contains { $0.date == cell.date && $0.accepted }
        if cell.state == .today && accepted {
            router.select(.hoje)
        } else if accepted {
            router.push(.linha(date: cell.date), on: router.tab)
        } else {
            router.push(.montar(date: cell.date), on: .hoje)
        }
    }

    // MARK: Selos de bairro

    private func stampRow(_ areas: [Area]) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(areas, id: \.id) { area in
                Text("\(area.seal) · \(area.name)").font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(V9.fill, in: Capsule())
            }
        }
    }

    // MARK: Cidades (viagem)

    @ViewBuilder private func cityCards(_ trip: TripInfo) -> some View {
        let current = trip.city(on: now, calendar: cal)
        let shown = Array(trip.cities.prefix(3))
        ForEach(Array(shown.enumerated()), id: \.element.id) { index, city in
            cityCard(city, trip: trip, isCurrent: city.id == current?.id, isLast: index == shown.count - 1, index: index)
        }
    }

    private func cityCard(_ city: City, trip: TripInfo, isCurrent: Bool, isLast: Bool, index: Int) -> some View {
        let cityPlaces = places.filter { $0.cityId == city.id }
        // Board importado com a volta antes da ida (`to` < `from`) derrubava a Viagem: `a...b` com a > b é trap.
        let lower = city.from ?? .distantPast
        let range = lower...max(lower, city.to ?? .distantFuture)
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

        return Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                if isLast && !saveForEnd.isEmpty {
                    Text("\(saveForEnd.count) ficaram pro fim: \(saveForEnd.prefix(3).map(\.name).joined(separator: ", "))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } header: {
            HStack(spacing: 8) {
                TripFlag(theme)
                Text(label).textCase(nil).lineLimit(1)
                    .foregroundStyle(isCurrent ? V9.accent : Color.secondary)
            }
        }
    }

    // MARK: Semanas (BH)

    @ViewBuilder private func weekCards(period: ClosedRange<Date>) -> some View {
        let today = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let lastWeek = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let saveForEnd = places.filter { $0.saveForEnd && !$0.isDone }
        weekCard(start: weekStart, title: "Esta semana")
        weekCard(start: lastWeek, title: "Semana passada")
        if !saveForEnd.isEmpty {
            Section("Fica pro fim · quando você pedir") {
                Text("\(saveForEnd.count) · \(saveForEnd.prefix(3).map(\.name).joined(separator: ", "))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func weekCard(start: Date, title: String) -> some View {
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let weekRange = start...end
        let doneCount = places.filter { $0.done.map { weekRange.contains(cal.startOfDay(for: $0.at)) } ?? false }.count
        let spent = TripStats.spent(expenses, in: weekRange, calendar: cal)
        return Section("\(title) · \(region.shortDay(start))–\(region.shortDay(end))") {
            VStack(alignment: .leading, spacing: 4) {
                Text(doneCount == 1 ? "1 must feito" : "\(doneCount) musts feitos").font(.title3.weight(.semibold))
                Text("gasto \(region.money(spent))").font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Progresso por lista

    private var progressTags: some View {
        Section("Listas e carteira") {
            // Central da viagem: a Carteira (cartões, passes, QR de entrada) fica junto.
            Button { router.push(.carteira, on: router.tab) } label: {
                row(wallet.isEmpty ? "Carteira" : "Carteira · \(wallet.count)")
            }
            // Compras da viagem: a lista com a previsão e as regras da volta (`money.shoppingList`: Japão).
            if region.profile.money?.shoppingList == true {
                Button { router.push(.compras, on: router.tab) } label: {
                    row(shopping.isEmpty ? "Compras" : "Compras · \(shopping.count)")
                }
            }
            ForEach(TripStats.progress(lists: lists), id: \.list.id) { item in
                Button { router.push(.list(id: item.list.id), on: router.tab) } label: {
                    row(item.list.name.capitalized, value: "\(item.done)/\(item.total)")
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func row(_ title: String, value: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary).monospacedDigit() }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}
