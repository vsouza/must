import CoreLocation
import SwiftData
import SwiftUI

/// Início: gasto do dia, próxima parada, montar amanhã e "perto de você".
struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services

    @Query private var places: [Place]
    @Query private var expenses: [Expense]
    @Query private var days: [PlannedDay]
    @Query private var settingsList: [Settings]
    @Query private var trips: [TripInfo]

    @State private var headerTab = HeaderTab.hoje
    /// "Por perto:" da Home (prompt 14 · B): só o cache de 30 min e o board.
    @State private var nearbyHint: NearbyScored?
    @State private var nearbyCheckedAt = Date.distantPast
    @Environment(\.scenePhase) private var scenePhase

    private enum HeaderTab: String, CaseIterable { case hoje = "Hoje", musts = "Musts", viagem = "Viagem" }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var budget: Double { settingsList.first?.perDayBudget ?? region.defaultBudget }

    var body: some View {
        let tomorrow = region.calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let model = HomeModel(places: places, expenses: expenses, days: days, trip: trips.first,
                              region: region, now: now, location: services.location.current,
                              tomorrowWeather: services.sync.weather(on: tomorrow, region: region, trip: trips.first),
                              nowTemp: services.sync.now(region: region, trip: trips.first)?.temp)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar.padding(.top, 8)
                    greeting.padding(.top, 34)
                    headerTabs(badge: model.openNearby.count, proxy: proxy).padding(.top, 26)
                    spend(model).padding(.top, 26).id(HeaderTab.hoje)
                    cards(model).padding(.top, 56).id(HeaderTab.musts)
                    Color.clear.frame(height: 1).id(HeaderTab.viagem)
                    TabBarSpacer()
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
            .task(id: nearbyKey) { await refreshNearbyHint() }
            // Voltou pra frente depois de 20 min: olha o cache de novo (sem rede).
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, AppClock.now.timeIntervalSince(nearbyCheckedAt) > 20 * 60 {
                    Task { await refreshNearbyHint() }
                }
            }
        }
        .background {
            ZStack {
                Color.must.bg
                BlobBackground(style: .home)
            }
            .ignoresSafeArea()
        }
    }

    private var nearbyKey: String {
        services.location.current.map { NearbyCell.key(lat: $0.coordinate.latitude, lng: $0.coordinate.longitude, region: region) } ?? ""
    }

    /// Lê só o cache (até 30 min) e o board. Nunca chama Google, Wikipedia nem Foursquare.
    private func refreshNearbyHint() async {
        let now = AppClock.now
        nearbyCheckedAt = now
        guard settingsList.first?.suggestNearby ?? true, let location = services.location.current else {
            nearbyHint = nil
            return
        }
        let batch = await services.nearby.cached(lat: location.coordinate.latitude, lng: location.coordinate.longitude,
                                                 region: region, now: now)
        nearbyHint = DiscoverBuilder.hint(batch: batch, places: places, origin: location, now: now, region: region)
    }

    // MARK: Topo

    private var topBar: some View {
        HStack {
            ZStack {
                Circle().fill(Color.must.ink)
                Text("済").font(.must.kanji(15)).foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)
            .onLongPressGesture(minimumDuration: 0.6) {
                #if DEBUG
                router.cover = .gallery
                #endif
            }
            .accessibilityLabel("Must")

            Spacer()

            HStack(spacing: 8) {
                IconButton(.exportar, label: "Adicionar por link") { router.sheet = .addLink(url: nil, listId: nil) }
                HStack(spacing: -8) {
                    Button { router.push(.settings, on: .inicio) } label: {
                        Text("V")
                            .font(.must.archivo(15, .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(MustGradient.avatar))
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                    .buttonStyle(MustPressStyle())
                    .zIndex(1)
                    .accessibilityLabel("Ajustes")
                    IconButton(.adicionar, style: .dark, label: "Assistente") { router.sheet = .assistant }
                }
            }
        }
    }

    private var greeting: some View {
        HStack {
            Text("Olá, Vinicius!").mustTitle()
            Spacer()
            // Sem rede de verdade (prompt 18 · A.4): o mesmo chip, dizendo que o offline funciona.
            if services.connectivity.isOffline {
                Tag("offline ok", dot: Color(hex: 0xC5C9D0))
                    .accessibilityLabel("Sem internet; o app funciona offline")
            } else if services.sync.status.isProblem || !DevOverrides.liveData {
                Tag("sem dados ao vivo", dot: Color(hex: 0xC5C9D0))
                    .accessibilityHint("Mostrando só o que está em cache")
            }
            // Toggle de tema: só visual (o app é sempre claro).
            Capsule()
                .fill(.white)
                .overlay(Capsule().strokeBorder(Color.must.lineStrong))
                .frame(width: 54, height: 28)
                .overlay(alignment: .leading) {
                    MustIconView(.sol, size: 12)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.must.surface))
                        .padding(.leading, 3)
                }
                .accessibilityLabel("Tema claro")
        }
    }

    private func headerTabs(badge: Int, proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 22) {
                ForEach(HeaderTab.allCases, id: \.self) { tab in
                    Button {
                        if tab == .viagem {
                            router.push(.trip, on: .inicio)
                            return
                        }
                        headerTab = tab
                        withAnimation(.snappy) { proxy.scrollTo(tab, anchor: .top) }
                    } label: {
                        Text(tab.rawValue)
                            .font(.must.archivo(14, headerTab == tab ? .semibold : .regular))
                            .foregroundStyle(headerTab == tab ? Color.must.ink : Color.must.secondary)
                            .padding(.bottom, 10)
                            .overlay(alignment: .bottom) {
                                if headerTab == tab { Rectangle().fill(Color.must.ink).frame(height: 2) }
                            }
                            .overlay(alignment: .topTrailing) {
                                if tab == .musts, badge > 0 {
                                    Text("\(badge)")
                                        .font(.must.mono(9, .semibold))
                                        .foregroundStyle(Color.must.greenText)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.must.green))
                                        .offset(x: 14, y: -6)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Rectangle().fill(Color.must.line).frame(height: 1)
        }
    }

    // MARK: Gasto

    private func spend(_ model: HomeModel) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gasto hoje").font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    MonoNumber(region.money(model.spentToday, symbol: false), size: 44)
                    Text(region.currency).font(.must.archivo(17, .semibold))
                }
                .foregroundStyle(Color.must.ink)
                Text(metaLine(model))
                    .font(.must.meta)
                    .foregroundStyle(Color.must.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button { router.select(.hoje) } label: {
                MustIconView(.avancar, size: 18)
                    .foregroundStyle(Color.must.greenText)
                    .frame(width: 48)
                    .frame(maxHeight: .infinity)
                    .background(Capsule().fill(Color.must.green))
            }
            .buttonStyle(MustPressStyle())
            .accessibilityLabel("Abrir o dia")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metaLine(_ model: HomeModel) -> String {
        var parts = ["Meta \(region.money(budget))"]
        if let day = model.today {
            let done = day.stops.filter(\.done).count
            parts.append("\(done) de \(day.stops.count) feitos")
        } else {
            parts.append("nenhum dia montado")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Cards

    private func cards(_ model: HomeModel) -> some View {
        ZStack(alignment: .topLeading) {
            nextCard(model)
                .frame(height: 118)
                .stackCard(color: .drink, rotation: -2)
                .padding(.leading, 78)
                .padding(.trailing, -62)

            tomorrowCard(model)
                .frame(height: 118)
                .stackCard(color: .eat, rotation: 1.5)
                .padding(.leading, 38)
                .padding(.trailing, -42)
                .offset(y: 86)

            nearbyCard(model)
                .frame(height: 250)
                .stackCard(tint: .sky)
                .offset(y: 172)
        }
        .frame(height: 430, alignment: .top)
    }

    private func nextCard(_ model: HomeModel) -> some View {
        let next = model.next
        let title = next.map { "Próxima · \($0.place.name)" } ?? "Montar o dia"
        var subtitle = "nada montado pra hoje · toque pra montar"
        if let next {
            var parts = [region.timeString(next.at)]
            let distance = next.place.distance(from: services.location.current)
            if next.isReservation {
                // "Saia às" = reserva − caminhada − 5 min (o prompt 07 troca pela ETA do MapKit).
                let walk = distance.map(Walk.minutes) ?? 0
                if distance != nil, let leave = region.calendar.date(byAdding: .minute, value: -(walk + 5), to: next.at), leave > now {
                    parts.append("saia \(region.timeString(leave))")
                } else {
                    parts.append("reserva")
                }
            }
            if let distance { parts.append("\(Walk.shortText(distance)) a pé") }
            subtitle = parts.joined(separator: " · ")
        }
        return Button {
            if let id = next?.place.id {
                router.push(.place(id: id), on: .inicio)
            } else {
                router.push(.montar(date: region.calendar.startOfDay(for: now)), on: .hoje)
            }
        } label: {
            stackRow(icon: .relogio, title: title, subtitle: subtitle, subtitleColor: Color.must.blueText)
        }
        .buttonStyle(MustPressStyle())
    }

    private func tomorrowCard(_ model: HomeModel) -> some View {
        Button {
            let tomorrow = region.calendar.date(byAdding: .day, value: 1, to: region.calendar.startOfDay(for: now)) ?? now
            router.push(.montar(date: tomorrow), on: .hoje)
        } label: {
            stackRow(icon: .montarAjustar, title: "Montar amanhã", subtitle: model.tomorrowLine, subtitleColor: Color.must.greenTextSoft)
        }
        .buttonStyle(MustPressStyle())
    }

    private func nearbyCard(_ model: HomeModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                router.mapShowsOpenNow = true
                router.select(.mapa)
            } label: {
                nearbyContent(model)
            }
            .buttonStyle(MustPressStyle())
            if let hint = nearbyHint {
                Button { router.push(.discover, on: .inicio) } label: { hintLine(hint) }
                    .buttonStyle(MustPressStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func nearbyContent(_ model: HomeModel) -> some View {
        VStack(alignment: .leading) {
            HStack(spacing: 14) {
                iconCircle(.mapa)
                Text("Perto de você").font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.ink)
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 10) {
                MonoNumber("\(model.openNearby.count)", size: 64).foregroundStyle(Color.must.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.openNearby.count == 1 ? "must aberto" : "musts abertos")
                        .font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.ink)
                    Text(model.nearbyLine).font(.must.archivo(13)).foregroundStyle(Color.must.blueText).lineLimit(1)
                }
                .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// "Por perto: Starbucks Reserve Roastery · 4,5 · 450 m": toque abre Descobrir.
    private func hintLine(_ item: NearbyScored) -> some View {
        let c = item.candidate
        var parts = [c.place.name]
        if let rating = c.place.rating { parts.append(rating.formatted(.number.precision(.fractionLength(1)).locale(region.locale))) }
        parts.append(Walk.distanceText(c.distance))
        return HStack(spacing: 8) {
            Text("Por perto:").font(.must.archivo(13, .semibold)).foregroundStyle(Color.must.blueText)
            Text(parts.joined(separator: " · ")).font(.must.archivo(13)).foregroundStyle(Color.must.blueText).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .contentShape(Rectangle())
    }

    private func iconCircle(_ icon: MustIcon) -> some View {
        MustIconView(icon, size: 20)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color.white.opacity(0.55)))
    }

    private func stackRow(icon: MustIcon, title: String, subtitle: String, subtitleColor: Color) -> some View {
        HStack(spacing: 14) {
            iconCircle(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.must.archivo(19, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                Text(subtitle).font(.must.archivo(13)).foregroundStyle(subtitleColor).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

/// Contas da Início, separadas da view pra ficar fácil de ler.
@MainActor
struct HomeModel {
    var places: [Place]
    var expenses: [Expense]
    var days: [PlannedDay]
    var trip: TripInfo?
    var region: Region
    var now: Date
    var location: CLLocation?
    var tomorrowWeather: DayWeather?
    var nowTemp: Double?

    /// Raio do "Perto de você".
    static let nearbyRadius: Double = 1500

    var spentToday: Double {
        let range = region.dayRange(now)
        return expenses.filter { range.contains($0.at) }.reduce(0) { $0 + $1.amount }
    }

    var today: PlannedDay? {
        let start = region.calendar.startOfDay(for: now)
        return days.first { $0.date == start && $0.accepted }
    }

    var nextStop: Stop? {
        today?.orderedStops.first { !$0.done && $0.place != nil }
    }

    /// Próxima coisa do dia: a próxima parada do dia aceito ou, sem dia montado, a reserva de hoje.
    var next: (place: Place, at: Date, isReservation: Bool)? {
        if let stop = nextStop, let place = stop.place {
            return (place, stop.at, place.hasReservation(on: now, calendar: region.calendar))
        }
        let soon = now.addingTimeInterval(-3600)
        return places
            .compactMap { p in p.reservation.map { (p, $0.at) } }
            .filter { region.calendar.isDate($0.1, inSameDayAs: now) && $0.1 >= soon && !$0.0.isDone }
            .min { $0.1 < $1.1 }
            .map { ($0.0, $0.1, true) }
    }

    /// Lugares do board abertos agora a ≤ 1,5 km. Sem horário não conta.
    var openNearby: [Place] {
        guard let location else { return [] }
        return places.filter { place in
            !place.isDone
                && place.openState(at: now, timeZone: region.timeZone).isOpen
                && place.location.distance(from: location) <= Self.nearbyRadius
        }
    }

    var nearbyLine: String {
        let time = region.timeString(now)
        guard let location else { return "sem GPS · \(time)" }
        let nearest = places.filter { $0.area != nil }.min { $0.location.distance(from: location) < $1.location.distance(from: location) }
        let area = nearest.flatMap { $0.location.distance(from: location) < 3000 ? $0.area : nil }
            ?? trip?.city(on: now, calendar: region.calendar)?.name ?? region.displayName
        return [area, time, nowTemp.map { "\(Int($0.rounded()))°" }].compactMap { $0 }.joined(separator: " · ")
    }

    var tomorrowLine: String {
        let cal = region.calendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now
        var style = Date.FormatStyle(locale: region.locale, calendar: cal).weekday(.wide)
        style.timeZone = region.timeZone
        let weekday = tomorrow.formatted(style)
        let reservations = places.filter { $0.hasReservation(on: tomorrow, calendar: cal) }.count
        let reserved = reservations == 0 ? "nada reservado" : reservations == 1 ? "1 reserva" : "\(reservations) reservas"
        // Dia de fotografia amanhã: a hora do golden no lugar das reservas.
        let start = cal.startOfDay(for: tomorrow)
        if days.contains(where: { $0.date == start && $0.kind == .photo }) {
            let city = trip?.city(on: tomorrow, calendar: cal)
            let c = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude, longitude: city?.lng ?? region.defaultCenter.longitude)
            if let g = SunService.day(start.addingTimeInterval(12 * 3600), c, timeZone: region.timeZone).goldenPM {
                return [weekday, tomorrowWeather?.short, "golden \(region.timeString(g.start))"].compactMap { $0 }.joined(separator: " · ")
            }
        }
        return [weekday, tomorrowWeather?.short, reserved].compactMap { $0 }.joined(separator: " · ")
    }
}
