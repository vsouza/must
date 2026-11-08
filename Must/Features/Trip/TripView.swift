import SwiftData
import SwiftUI

/// Viagem: gasto total, fileira de dias, selos de bairro (prompt 18 · D.18), um card por trecho de cidade, progresso por lista.
/// Em BH (sem viagem): o mês, com 済 nos dias feitos e cards por semana — sem inventar viagem.
struct TripView: View {
    @Environment(\.dismiss) private var dismiss
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

        VStack(spacing: 0) {
            header(period)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    spendBlock(spent: spent, elapsed: elapsed).padding(.top, 22)
                    dayRow(cells).padding(.top, 20)
                    GrupoBlock().padding(.top, 24)
                    stampRow(stamps).padding(.top, 24)
                    if let trip { cityCards(trip).padding(.top, 28) } else { weekCards(period: period).padding(.top, 28) }
                    progressTags.padding(.top, 20)
                    V8BarSpacer()
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
        }
        .background(V8.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Topo

    private func header(_ period: ClosedRange<Date>) -> some View {
        CutScreenHeader(title: trip == nil ? region.displayName : "Viagem",
                        corner: [trip == nil
                                 ? "\(region.shortName) · \(monthName(period.lowerBound))"
                                 : "\(region.displayName) · \(region.dayNumber(period.lowerBound))–\(region.dayNumber(period.upperBound)) \(region.monthShort(period.upperBound))"],
                        subtitle: subtitle(period: period), height: 210, onBack: { dismiss() }) {
            CutCornerButton(systemName: "gearshape", label: "Ajustes", tint: theme.coverInk) { router.push(.settings, on: router.tab) }
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
                Text(trip == nil ? "Gasto no mês" : "Gasto na viagem").font(V8Font.text(14)).foregroundStyle(Color.must.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    MonoNumber(region.money(spent, symbol: false), size: 40)
                    Text(region.currency).font(V8Font.text(17, weight: .semibold))
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
                    .background(Rectangle().fill(Color.must.ink))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Voos e reservas")
        }
        .fixedSize(horizontal: false, vertical: true)
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
        // Datas = quadrados de borda de 2 pt; hoje em tinta, feito em laranja, outra cidade tracejado.
        let (fill, text): (Color, Color) = switch cell.state {
        case .done: (V8.orange, V8.ink)
        case .today: (V8.ink, V8.paper)
        case .otherCity, .future, .past: (Color.clear, V8.ink)
        }
        return Text("\(cell.number)")
            .font(V8Font.mono(14, weight: .semibold))
            .foregroundStyle(text)
            .frame(width: 44, height: 44)
            .background(Rectangle().fill(fill))
            .overlay(Rectangle().stroke(V8.ink, style: StrokeStyle(lineWidth: 2, dash: cell.state == .otherCity ? [4, 3] : [])))
            .overlay(alignment: .topTrailing) {
                if trip == nil, cell.state == .done { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(V8.ink).offset(x: -3, y: 3) }
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

    // MARK: Selos de bairro (prompt 18 · D.18)

    /// Um 済-selo por bairro com must feito (`AreaStamps`): kanji, borda dupla, rotação −6° a −10°.
    /// Sem bairro feito: uma linha em serif, sem selos vazios.
    private func stampRow(_ areas: [Area]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if areas.isEmpty {
                Text("nenhum selo ainda").mustSerif(18).foregroundStyle(Color.must.secondary)
            } else {
                MonoLabel("selos de bairro · \(areas.count)", color: theme.labelColor)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                            StationStamp(area.seal, sub: area.stampSub, size: 74, surface: .photo, filled: true,
                                         rotation: -6 - Double(index % 3) * 2, border: theme.tripColor)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: Cards por cidade (viagem)

    private func cityCards(_ trip: TripInfo) -> some View {
        let current = trip.city(on: now, calendar: cal)
        let shown = Array(trip.cities.prefix(3))
        // Pilha com altura do conteúdo (nada de altura fixa): a sobreposição é só a decorativa (−8 pt, abaixo do limite de 12).
        return VStack(alignment: .leading, spacing: -2) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, city in
                cityCard(city, trip: trip, isCurrent: city.id == current?.id, isLast: index == shown.count - 1, index: index)
                    .tripBand(orange: city.id == current?.id || (current == nil && index == 0))
            }
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

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TripFlag(theme)
                MonoLabel(label, color: V8.ink)
                    .lineLimit(1)
            }
            if isLast && !saveForEnd.isEmpty {
                saveForEndBlock(saveForEnd)
            } else {
                Text(title).font(V8Font.text(24, weight: .semibold)).foregroundStyle(Color.must.ink).lineLimit(2)
                Text(detail.joined(separator: " · ")).font(V8Font.text(13)).lineLimit(1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// "ficaram pro fim": o número grande e até três nomes. Altura natural: o texto que quebra empurra o resto.
    private func saveForEndBlock(_ items: [Place]) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            MonoNumber("\(items.count)", size: 64).foregroundStyle(Color.must.ink).fixedSize()
            VStack(alignment: .leading, spacing: 2) {
                Text("ficaram pro fim").font(V8Font.text(19, weight: .semibold)).foregroundStyle(Color.must.ink)
                Text(items.prefix(3).map(\.name).joined(separator: ", ")).font(V8Font.text(13)).foregroundStyle(V8.ink.opacity(0.7)).lineLimit(2)
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: Cards por semana (BH)

    private func weekCards(period: ClosedRange<Date>) -> some View {
        let today = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let lastWeek = cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let saveForEnd = places.filter { $0.saveForEnd && !$0.isDone }
        return VStack(alignment: .leading, spacing: -2) {
            weekCard(start: weekStart, title: "Esta semana")
                .tripBand(orange: true)
            weekCard(start: lastWeek, title: "Semana passada")
                .tripBand(orange: false)
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("fica pro fim · quando você pedir", color: V8.ink)
                saveForEndBlock(saveForEnd)
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .tripBand(orange: false)
        }
    }

    private func weekCard(start: Date, title: String) -> some View {
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let weekRange = start...end
        let doneCount = places.filter { $0.done.map { weekRange.contains(cal.startOfDay(for: $0.at)) } ?? false }.count
        let spent = TripStats.spent(expenses, in: weekRange, calendar: cal)
        return VStack(alignment: .leading, spacing: 8) {
            Micro("\(title) · \(region.shortDay(start))–\(region.shortDay(end))", color: Color.must.ink.opacity(0.7))
            Text(doneCount == 1 ? "1 must feito" : "\(doneCount) musts feitos").font(V8Font.text(24, weight: .semibold)).foregroundStyle(Color.must.ink)
            Text("gasto \(region.money(spent))").font(V8Font.text(13))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                // Compras da viagem (prompt 17 · B): a lista com a previsão e as regras da volta (`money.shoppingList`: Japão).
                if region.profile.money?.shoppingList == true {
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

extension View {
    /// Faixa da Viagem no corte: papel (ou laranja pro que é seu agora) com borda de 2 pt, sem rotação nem cor de lista.
    fileprivate func tripBand(orange: Bool) -> some View {
        background(orange ? V8.orange : Color.clear)
            .overlay(Rectangle().stroke(V8.ink, lineWidth: 2))
    }
}
