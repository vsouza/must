import CoreLocation
import SwiftData
import SwiftUI

/// Hoje: barra de gasto (dia + exceção), timeline das paradas, "+ gasto", refazer o dia.
struct TodayView: View {
    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Environment(\.tripTheme) private var theme

    @Query private var days: [PlannedDay]
    @Query private var expenses: [Expense]
    @Query private var settingsList: [Settings]
    @Query private var flights: [Flight]
    @Query private var trips: [TripInfo]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// Outro dia aceito (aberto pela Viagem). `nil` = hoje.
    var date: Date?

    private var region: Region { store.region }
    private var dayStart: Date { region.calendar.startOfDay(for: date ?? AppClock.now) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let now = AppClock.now
            let start = region.calendar.startOfDay(for: date ?? now)
            let today = days.first { $0.date == start && $0.accepted }
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar(hasDay: today != nil).padding(.top, 8)
                        if let today {
                            content(today, now: now)
                            Color.clear.frame(height: 132) // espaço pro FAB e o fade: a última linha termina acima deles
                        } else {
                            empty(now: now)
                        }
                        TabBarSpacer()
                    }
                    .padding(.horizontal, 22)
                }
                .scrollIndicators(.hidden)

                if today != nil {
                    // A timeline rola por trás de um fade branco: a hora da linha de baixo não fica sob o FAB.
                    // Sólido da altura do FAB pra baixo (FAB: 92 + 54 pt acima da área segura); a área do indicador
                    // também fica coberta: nada da timeline aparece embaixo da tab bar.
                    GeometryReader { geo in
                        LinearGradient(stops: [.init(color: Color.must.bg.opacity(0), location: 0),
                                               .init(color: Color.must.bg.opacity(0.95), location: 0.2),
                                               .init(color: Color.must.bg, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 194 + geo.safeAreaInsets.bottom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .allowsHitTesting(false)
                }

                Fab { router.sheet = .assistant }
                    .padding(.trailing, 22)
                    .padding(.bottom, 92)
            }
            .tripWash()
            .background {
                ZStack {
                    Color.must.bg
                    BlobBackground(style: .hoje)
                }
                .ignoresSafeArea()
            }
            // Dia aceito que ainda não está salvo: baixa no Wi-Fi com a tela aberta (prompt 18 · A.5). Sem Wi-Fi, não faz nada.
            .task(id: dayStart) {
                await services.prefetch.run(date: dayStart, context: context, region: region, network: services.connectivity.prefetchNetwork)
            }
        }
    }

    // MARK: Topo

    private func topBar(hasDay: Bool) -> some View {
        HStack {
            if date != nil {
                IconButton(.voltar, label: "Voltar") { dismiss() }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
            Spacer()
            Button { router.sheet = .expense(placeId: nil) } label: {
                Text("+ gasto")
                    .font(.must.archivo(15, .semibold))
                    .underline()
                    .foregroundStyle(Color.must.greenText)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.must.green))
            }
            .buttonStyle(MustPressStyle())
            Spacer()
            IconButton(.montarAjustar, label: hasDay ? "Refazer o dia" : "Montar o dia") {
                router.push(.montar(date: region.calendar.startOfDay(for: AppClock.now)), on: .hoje)
            }
        }
    }

    /// "Tóquio · dia 3/5" no topo, no tom do país (prompt 20); sem país, cinza como antes.
    private func cityLabel(_ now: Date) -> some View {
        Micro(HomeState.cityLine(now, region: region, trip: trips.first), color: theme.labelColor)
    }

    private func empty(now: Date) -> some View {
        let tomorrow = region.calendar.date(byAdding: .day, value: 1, to: region.calendar.startOfDay(for: now)) ?? now
        let tomorrowDay = days.first { $0.date == tomorrow && $0.accepted }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                cityLabel(now)
                Text("Hoje").mustTitle()
                Text("nada montado ainda · \(region.timeString(now))").mustSerif(18).foregroundStyle(Color.must.secondary)
            }
            .padding(.top, 22)
            spendCard(day: nil, now: now)
            PrimaryButton("Montar o dia", icon: .montarAjustar) {
                router.push(.montar(date: region.calendar.startOfDay(for: now)), on: .hoje)
            }
            if let tomorrowDay {
                Text("Amanhã já está montado · \(tomorrowDay.stops.count) paradas").mustMeta()
            }
        }
    }

    // MARK: Dia

    private func content(_ day: PlannedDay, now: Date) -> some View {
        let stops = day.orderedStops
        let done = stops.filter(\.done).count
        let current = stops.first { !$0.done }
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                cityLabel(now)
                Text(date.map { region.shortDay($0) } ?? "Hoje").mustTitle()
                Text("dia \(day.kind.label) · \(done) de \(stops.count) feitos").mustSerif(18).foregroundStyle(Color.must.secondary)
                offlineLine(day)
                mapHint(day.date)
            }
            .padding(.top, 22)
            flightNotes(day, now: now)
            if day.kind == .photo {
                // Dia de fotografia: a tela da luz (Luz.png).
                Button { router.push(.light(date: day.date)) } label: {
                    HStack(spacing: 10) {
                        MustIconView(.sol, size: 18)
                        Text("Luz de hoje").font(.must.archivo(15, .semibold))
                        Spacer()
                        MustIconView(.avancar, size: 14)
                    }
                    .foregroundStyle(MustGradient.goldText)
                    .padding(.horizontal, 16).frame(height: 50)
                    .background(MustGradient.gold, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(MustPressStyle())
            }
            spendCard(day: day, now: now)
            timeline(stops, current: current, now: now)
        }
    }

    /// "dia salvo offline ✓" · "salvando… 3/7" · "salva no Wi-Fi" (prompt 18 · A.5). Discreto, uma linha.
    private func offlineLine(_ day: PlannedDay) -> some View {
        let text = switch OfflineState.of(day, progress: services.prefetch.progress) {
        case .running(let done, let total): "salvando… \(done)/\(total)"
        case .saved: "dia salvo offline ✓"
        case .partial(let done, let total): "salvo \(done)/\(total) · completa no Wi-Fi"
        case .waitingWiFi: "salva no Wi-Fi"
        }
        return Text(text).mustMeta()
    }

    /// Mapa da cidade do dia não baixado: só a sugestão (o pacote tem ~100 MB; quem decide é o Vinicius).
    @ViewBuilder private func mapHint(_ date: Date) -> some View {
        let city = trips.first?.city(on: date, calendar: region.calendar)
        let center = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude,
                                            longitude: city?.lng ?? region.defaultCenter.longitude)
        if let pack = MapPack.catalog.first(where: { $0.region == region && $0.contains(center) }),
           !services.maps.isInstalled(pack.id) {
            Button { router.push(.offlineMaps, on: .hoje) } label: {
                Text("mapa de \(city?.name ?? pack.title) não baixado · baixar").underline().mustMeta()
            }
            .buttonStyle(.plain)
        }
    }

    /// Gasto do dia (verde) e da exceção aceita (azul).
    private func spendCard(day: PlannedDay?, now: Date) -> some View {
        let range = region.dayRange(date ?? now)
        let todays = expenses.filter { range.contains($0.at) }
        let exceptionIds = Set(day?.stops.filter(\.isException).compactMap { $0.place?.id } ?? [])
        let exception = todays.filter { $0.place.map { exceptionIds.contains($0.id) } ?? false }.reduce(0) { $0 + $1.amount }
        let dayTotal = todays.reduce(0) { $0 + $1.amount } - exception
        let budget = day?.budget ?? settingsList.first?.perDayBudget ?? region.defaultBudget
        let total = dayTotal + exception
        let scale = max(budget, total, 1)
        let exceptionName = day?.stops.first(where: \.isException)?.place?.name

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Gasto · meta \(region.money(budget))").font(.must.archivo(14)).foregroundStyle(Color.must.secondary)
                Spacer()
                MonoNumber(region.money(total), size: 26).foregroundStyle(dayTotal > budget ? Color(hex: 0xC2261D) : Color.must.ink)
            }
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Capsule().fill(Color.must.green).frame(width: geo.size.width * min(1, dayTotal / scale))
                    Capsule().fill(Color.must.blue).frame(width: geo.size.width * min(1, exception / scale))
                    Spacer(minLength: 0)
                }
                .background(Capsule().fill(Color.must.surface))
            }
            .frame(height: 10)
            HStack(spacing: 8) {
                Tag("dia \(region.money(dayTotal))", dot: Color.must.green)
                if exception > 0 || exceptionName != nil {
                    Tag("\(exceptionName ?? "exceção") \(region.money(exception)) · aceito", dot: Color.must.blue)
                }
            }
        }
        .padding(20)
        .glass(cornerRadius: 26)
    }

    private func timeline(_ stops: [Stop], current: Stop?, now: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                if stop.id == current?.id {
                    currentRow(stop, index: index, now: now)
                } else {
                    row(stop, index: index, isLast: index == stops.count - 1)
                }
            }
            if let last = lastTrain(after: stops.last) {
                HStack(spacing: 14) {
                    Text("·").font(.must.mono(15)).foregroundStyle(Color.must.secondary)
                        .frame(width: 30, height: 30).background(Circle().fill(Color.must.surface))
                    Text(last.label).font(.must.archivo(15)).foregroundStyle(Color.must.secondary).lineLimit(2)
                    Spacer()
                    Text(last.time).font(.must.mono(15, .semibold)).foregroundStyle(Color.must.ink)
                }
                .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
    }

    /// BH: horário do metrô (bh-lines.geojson). Japão: tabela `last-trains.json` perto da última parada.
    private func lastTrain(after stop: Stop?) -> LastTrain? {
        LastTrains.home(region: region, near: stop?.place?.coordinate, transit: TransitLoader.load(region))
    }

    private func row(_ stop: Stop, index: Int, isLast: Bool) -> some View {
        let place = stop.place
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                if stop.done {
                    KanjiSeal(done: true, size: 30, look: .soft)
                } else {
                    Text("\(index + 1)").font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.secondary)
                        .frame(width: 30, height: 30).background(Circle().fill(Color.must.surface))
                }
                if !isLast || region == .bh { Rectangle().fill(Color.must.line).frame(width: 2, height: 22) }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(place?.name ?? "Lugar removido").mustPlace().lineLimit(1)
                    Spacer()
                    Text(region.timeString(stop.at)).font(.must.mono(14)).foregroundStyle(Color.must.secondary)
                }
                Text(meta(stop)).mustMeta().lineLimit(2)
            }
        }
        .padding(.vertical, 10)
        .opacity(stop.done ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if let id = place?.id { router.push(.place(id: id), on: .hoje) } }
    }

    /// Dia de voo (prompt 15 · C): o voo é âncora dura e a hora de sair pro aeroporto. O deslocamento é estimativa (60 min) sem rota.
    @ViewBuilder
    private func flightNotes(_ day: PlannedDay, now: Date) -> some View {
        let today = FlightRules.dayFlights(flights, on: day.date, region: region)
        if !today.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(today, id: \.number) { flight in
                    // Mesmo cálculo e fuso do card de Voos: a hora é a do aeroporto de origem.
                    let zone = FlightFormat.zone(flight.from, fallback: region.timeZone)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        MustIconView(.rota, size: 16)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("voo \(flight.number) · \(FlightFormat.time(flight.departs, zone: zone))")
                                .font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
                            Text(flight.leaveAt > now
                                 ? "saia pro aeroporto às \(FlightFormat.time(flight.leaveAt, zone: zone)) · estimativa"
                                 : "hora de ir pro aeroporto · estimativa")
                                .mustMeta()
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.must.surface))
                }
            }
        }
    }

    private func currentRow(_ stop: Stop, index: Int, now: Date) -> some View {
        let place = stop.place
        var parts: [String] = []
        if stop.isAnchor { parts.append("reserva") }
        if let place, let here = services.location.current {
            // Mesma regra do solver: acima do "andar máximo entre paradas", metrô.
            let leg = DaySolver.leg(here.coordinate, place.coordinate, walkMax: settingsList.first?.walkMaxKm ?? 1.5)
            // ETA do MapKit quando já chegou; até lá, a estimativa do solver.
            let minutes = services.eta.minutes(from: here.coordinate, to: place.coordinate, transit: leg.mode == .metro) ?? leg.minutes
            let leave = RoutesService.leaveAt(stop.at, travelMinutes: minutes)
            if leave > now { parts.append("saia \(region.timeString(leave))") }
            parts.append(leg.mode == .walk ? "\(minutes) min a pé" : "metrô ~\(minutes) min")
        }
        if stop.isException { parts.append("fora da meta") }
        if let sub = place?.sub { parts.append(sub.lowercased()) }
        return Button { if let id = place?.id { router.push(.place(id: id), on: .hoje) } } label: {
            HStack(alignment: .center, spacing: 14) {
                KanjiSeal(done: false, number: index + 1, size: 30)
                if let place {
                    PlaceThumb(placeId: place.placeId, refs: place.photoRefs, color: place.list?.color ?? .eat, size: 44)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(place?.name ?? "Lugar removido").font(.must.archivo(18, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1)
                        Spacer()
                        Text(region.timeString(stop.at)).font(.must.mono(15, .semibold)).foregroundStyle(MustColor.eat.text)
                    }
                    Text(parts.joined(separator: " · ")).font(.must.archivo(14)).foregroundStyle(MustColor.eat.text).lineLimit(2)
                }
                MustIconView(.avancar, size: 14).foregroundStyle(MustColor.eat.text)
            }
            .padding(16)
            .background(MustColor.eat.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, -6)
            .padding(.vertical, 6)
        }
        .buttonStyle(MustPressStyle())
        .contextMenu {
            if let place {
                Button("Como chegar") { router.push(.comoChegar(placeId: place.id), on: .hoje) }
                Button("Apple Maps · transporte") { MapsLinks.openApple(to: place.coordinate, name: place.name, mode: .transit) }
                Button("Google Maps") { MapsLinks.openGoogle(to: place.coordinate, mode: .transit) }
            }
        }
    }

    private func meta(_ stop: Stop) -> String {
        guard let place = stop.place else { return "" }
        var parts: [String] = []
        if let area = place.area { parts.append(area) }
        if let sub = place.sub { parts.append(sub.lowercased()) }
        if let q = place.queueMinutes, q > 0 { parts.append("\(q) min de fila") }
        if stop.done, let spent = place.done?.spent { parts.append(region.money(spent)) }
        else if let price = place.price { parts.append(region.money(price)) }
        return parts.joined(separator: " · ")
    }
}
