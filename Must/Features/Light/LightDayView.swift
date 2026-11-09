import CoreLocation
import SwiftData
import SwiftUI

/// Luz de hoje (V9): o dia pela luz — faixas azul/golden/dura, spots por hora, museu no sol alto.
/// Usa o dia aceito quando é de fotografia; senão, a sugestão do solver pra um dia de fotografia.
struct LightDayView: View {
    let date: Date

    @Environment(AppRouter.self) private var router
    @Environment(RegionStore.self) private var store
    @Environment(Services.self) private var services
    @Query private var places: [Place]
    @Query private var trips: [TripInfo]
    @Query private var settingsList: [Settings]
    @Query private var days: [PlannedDay]
    @Query private var flights: [Flight]

    init(date: Date) {
        self.date = date
        let d = date
        _days = Query(filter: #Predicate<PlannedDay> { $0.date == d })
    }

    private var region: Region { store.region }
    private var now: Date { AppClock.now }
    private var isToday: Bool { region.calendar.isDate(date, inSameDayAs: now) }

    /// Centro da cidade do dia (ou o GPS, se estiver nela).
    private var center: CLLocationCoordinate2D {
        let city = trips.first?.city(on: date, calendar: region.calendar)
        let c = CLLocationCoordinate2D(latitude: city?.lat ?? region.defaultCenter.latitude, longitude: city?.lng ?? region.defaultCenter.longitude)
        if let here = services.location.current, here.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 40_000 {
            return here.coordinate
        }
        return c
    }

    var body: some View {
        let sun = SunService.day(date.addingTimeInterval(12 * 3600), center, timeZone: region.timeZone)
        let weather = services.sync.weather(on: date, region: region, trip: trips.first)
        let rows = self.rows(sun: sun, weather: weather)
        List {
            Section {
                Text(headline(sun, weather: weather)).font(.subheadline).foregroundStyle(.secondary)
                dayLine(sun, weather: weather)
            } header: {
                Text("\(KindLines.weekdayDay(date, region: region)) · \(region.monthShort(date)) · dia de fotografia")
            }
            spots(rows, sun: sun, weather: weather)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Luz de hoje")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.push(.montar(date: date)) } label: { Image(systemName: "calendar.badge.plus") }
                    .accessibilityLabel("Montar dia de fotografia")
            }
        }
        .v9Screen(grouped: true)
    }

    /// "10h26 de sol · céu limpo até 18h · golden curto, 50 min"
    private func headline(_ sun: SunDay, weather: DayWeather?) -> String {
        var parts: [String] = []
        if let d = sun.daylight {
            let m = Int(d / 60)
            parts.append("\(m / 60)h\(String(format: "%02d", m % 60)) de sol")
        }
        if let hours = weather?.hours, !hours.isEmpty {
            let fromNow = hours.filter { $0.time >= (isToday ? now : date) }
            if let cloudy = fromNow.first(where: { ($0.cloud ?? 0) > 60 }) {
                parts.append("nublado a partir das \(region.calendar.component(.hour, from: cloudy.time))h")
            } else if let last = fromNow.last(where: { ($0.cloud ?? 100) < 30 && region.calendar.component(.hour, from: $0.time) <= 21 }) {
                parts.append("céu limpo até \(region.calendar.component(.hour, from: last.time))h")
            }
        }
        if let g = sun.goldenPM {
            let m = Int(g.duration / 60)
            parts.append("golden \(m <= 55 ? "curto" : "longo"), \(m) min")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Linha do dia

    private func dayLine(_ sun: SunDay, weather: DayWeather?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LightTimeline(sun: sun, now: isToday ? now : nil, region: region, coordinate: center)
            VStack(alignment: .leading, spacing: 4) {
                if let g = sun.goldenPM {
                    Text("Golden \(region.timeString(g.start))–\(region.timeString(g.end))").monospacedDigit()
                }
                if let b = sun.bluePM {
                    Text("Hora azul \(region.timeString(b.start))–\(region.timeString(b.end))").monospacedDigit()
                }
                let peak = Int(sun.noonElevation.rounded())
                Text(peak < 45 ? "Sol baixo o dia todo · \(peak)° no pico" : "Sol alto 11–15h · \(peak)° no pico")
                if let a = weather?.hour(at: isToday ? now : date.addingTimeInterval(9 * 3600))?.cloud,
                   let g = sun.goldenPM, let b = weather?.hour(at: g.start)?.cloud {
                    Text("Nuvens \(a)% → \(b)%").monospacedDigit()
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: Spots por hora

    struct Row: Identifiable {
        var id: String
        var placeId: String?
        var time: Date
        var name: String
        var meta: String
        var kind: ListKind
        var color: MustColor?
        var done: Bool
        var past: Bool
    }

    private func rows(sun: SunDay, weather: DayWeather?) -> [Row] {
        let byId = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let walkMax = settingsList.first?.walkMaxKm ?? 1.5
        var out: [Row] = []
        if let day = days.first, day.accepted, !day.stops.isEmpty {
            var previous: CLLocationCoordinate2D?
            for stop in day.orderedStops {
                guard let place = stop.place else { continue }
                out.append(row(id: stop.id.uuidString, place: place, at: stop.at, reason: nil, done: stop.done || place.isDone,
                               sun: sun, previous: previous, walkMax: walkMax))
                previous = place.coordinate
            }
        } else {
            // Sem dia de fotografia aceito: o que o solver faria hoje com a luz.
            let planner = DayPlanner(date: date, region: region, settings: settingsList.first, existing: nil)
            planner.kind = .photo
            planner.weather = weather
            planner.startAt = region.calendar.date(byAdding: .minute, value: settingsList.first?.dayStartMinutes ?? 570, to: date) ?? date
            let proposal = planner.solve(catalog: places.solverCatalog, trip: trips.first, settings: settingsList.first,
                                         location: services.location.current,
                                         flights: FlightRules.dayFlights(flights, on: planner.date, region: region))
            var previous: CLLocationCoordinate2D?
            for s in proposal.stops {
                guard let place = byId[s.place.id] else { continue }
                out.append(row(id: s.id, place: place, at: s.at, reason: s.reason, done: place.isDone, sun: sun, previous: previous, walkMax: walkMax))
                previous = place.coordinate
            }
        }
        return out
    }

    private func row(id: String, place: Place, at: Date, reason: String?, done: Bool, sun: SunDay,
                     previous: CLLocationCoordinate2D?, walkMax: Double) -> Row {
        var meta: [String] = []
        switch place.kind {
        case .photo:
            meta.append(light(at, sun: sun).label)
            if let facing = place.extra?.photo?.facing, let g = sun.goldenPM, g.contains(at) || abs(g.start.timeIntervalSince(at)) < 600,
               SunService.angle(facing, SunService.position(at: g.start, place.coordinate).azimuth) <= 25 {
                meta.append("sol no eixo da rua")
            }
            if let previous {
                let leg = DaySolver.leg(previous, place.coordinate, walkMax: walkMax)
                meta.append(leg.mode == .walk ? "\(leg.minutes) min a pé" : "saia \(region.timeString(at.addingTimeInterval(Double(-leg.minutes * 60))))")
            }
            if let gear = place.extra?.photo?.gear { meta.append(gear) }
        case .art:
            let sunHigh = (11...14).contains(region.calendar.component(.hour, from: at))
            meta.append(sunHigh ? "hora do sol alto = museu" : (reason ?? "museu"))
            meta.append("Must art")
            if let art = place.extra?.art, let left = art.daysLeft(from: date, calendar: region.calendar), left <= 7 { meta.append(DaySolver.endsText(left)) }
        default:
            if let reason { meta.append(reason) } else if let area = place.area { meta.append(area) }
        }
        return Row(id: id, placeId: place.id, time: at, name: place.name, meta: meta.joined(separator: " · "), kind: place.kind,
                   color: place.list?.color, done: done, past: isToday && at.addingTimeInterval(45 * 60) < now)
    }

    private func light(_ at: Date, sun: SunDay) -> (label: String, color: Color) {
        if let g = sun.goldenAM, (g.start.addingTimeInterval(-300)...g.end).contains(at) { return ("golden da manhã", KindPalette.goldSoft) }
        if let g = sun.goldenPM, (g.start.addingTimeInterval(-300)...g.end).contains(at) { return ("golden", KindPalette.goldArc) }
        if let b = sun.bluePM, (b.start...b.end).contains(at) { return ("hora azul", KindPalette.blue) }
        if let b = sun.blueAM, (b.start...b.end).contains(at) { return ("hora azul", KindPalette.blue) }
        if let h = sun.hardLight, h.contains(at) { return ("luz dura", KindPalette.hard) }
        return ("noite", Color.primary)
    }

    @ViewBuilder private func spots(_ rows: [Row], sun: SunDay, weather: DayWeather?) -> some View {
        let next = rows.first { !$0.done && !$0.past }?.id
        Section {
            if rows.isEmpty {
                Text("Nenhum spot pra hoje. Adicione lugares na lista Must photo ou monte um dia de fotografia.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                Button { if let id = r.placeId { router.push(.place(id: id)) } } label: {
                    rowView(r, isNext: r.id == next, sun: sun)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Spots por hora")
        } footer: {
            if let line = tomorrowLine(sun: sun) { Text(line) }
        }
    }

    private func rowView(_ r: Row, isNext: Bool, sun: SunDay) -> some View {
        let l = light(r.time, sun: sun)
        return HStack(alignment: .center, spacing: 12) {
            Text(region.timeString(r.time)).font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(isNext ? V9.accent : Color.primary)
                .lineLimit(1).fixedSize()
                .frame(minWidth: 52, alignment: .leading)
            // A barra é a luz da hora (golden, dura, azul): dado, não decoração.
            Capsule().fill(l.color).frame(width: 4, height: 34).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(r.name).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                    if r.done { Image(systemName: "checkmark").font(.footnote).foregroundStyle(.secondary) }
                }
                Text(r.meta).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if isNext {
                Text("próximo").font(.footnote.weight(.semibold)).foregroundStyle(V9.accent)
            }
        }
        .opacity(r.done || r.past ? 0.55 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Amanhã: 70% de nuvens à tarde — se quiser outro golden, é hoje."
    private func tomorrowLine(sun: SunDay) -> String? {
        guard let tomorrow = region.calendar.date(byAdding: .day, value: 1, to: date),
              let w = services.sync.weather(on: tomorrow, region: region, trip: trips.first) else { return nil }
        let tSun = SunService.day(tomorrow.addingTimeInterval(12 * 3600), center, timeZone: region.timeZone)
        guard let g = tSun.goldenPM, let cloud = w.hour(at: g.start)?.cloud else { return nil }
        if cloud > 60 { return "Amanhã: \(cloud)% de nuvens à tarde — se quiser outro golden, é hoje." }
        if cloud < 30 { return "Amanhã: céu limpo no golden também (\(cloud)% de nuvens) — dá pra repetir." }
        return "Amanhã: \(cloud)% de nuvens no golden — pode render céu dramático."
    }
}

/// Faixa 06 → 18 com azul, golden, luz dura, golden, azul e a hora de agora.
struct LightTimeline: View {
    var sun: SunDay
    var now: Date?
    var region: Region
    var coordinate: CLLocationCoordinate2D

    var body: some View {
        Canvas { ctx, size in
            guard let a = sun.blueAM?.start ?? sun.sunrise, let b = sun.bluePM?.end ?? sun.sunset else { return }
            let start = a.addingTimeInterval(-30 * 60), end = b.addingTimeInterval(30 * 60)
            let barY: CGFloat = 22, barH: CGFloat = 10
            func x(_ t: Date) -> CGFloat { CGFloat(t.timeIntervalSince(start) / end.timeIntervalSince(start)) * size.width }
            let track = Path(roundedRect: CGRect(x: 0, y: barY, width: size.width, height: barH), cornerRadius: 5)
            ctx.fill(track, with: .color(Color(uiColor: .quaternarySystemFill)))
            func band(_ i: DateInterval?, _ color: Color) {
                guard let i else { return }
                ctx.fill(Path(roundedRect: CGRect(x: x(i.start), y: barY, width: max(2, x(i.end) - x(i.start)), height: barH), cornerRadius: 3),
                         with: .color(color))
            }
            band(sun.hardLight, KindPalette.hard)
            band(sun.goldenAM, KindPalette.goldSoft)
            band(sun.goldenPM, KindPalette.goldArc)
            band(sun.blueAM, KindPalette.blue)
            band(sun.bluePM, KindPalette.blue)
            let mono = Font.caption2.monospacedDigit().weight(.semibold)
            let grey = Color.secondary
            if let r = sun.sunrise { ctx.draw(Text(region.timeString(r)).font(mono).foregroundStyle(grey), at: CGPoint(x: max(0, x(r) - 14), y: 50), anchor: .leading) }
            let peak = Int(sun.noonElevation.rounded())
            ctx.draw(Text("\(region.timeString(sun.solarNoon)) pico \(peak)°").font(mono).foregroundStyle(grey), at: CGPoint(x: x(sun.solarNoon), y: 50), anchor: .center)
            if let g = sun.goldenPM { ctx.draw(Text(region.timeString(g.start)).font(mono).foregroundStyle(grey), at: CGPoint(x: x(g.start), y: 12), anchor: .leading) }
            if let e = sun.bluePM?.end { ctx.draw(Text(region.timeString(e)).font(mono).foregroundStyle(grey), at: CGPoint(x: min(size.width, x(e) + 14), y: 50), anchor: .trailing) }
            if let now, now > start, now < end {
                let nx = x(now)
                ctx.stroke(Path { $0.move(to: CGPoint(x: nx, y: 6)); $0.addLine(to: CGPoint(x: nx, y: barY + barH + 4)) }, with: .color(Color.primary), lineWidth: 2.5)
                ctx.fill(Path(ellipseIn: CGRect(x: nx - 4, y: 2, width: 8, height: 8)), with: .color(Color.primary))
                ctx.draw(Text(region.timeString(now)).font(mono).foregroundStyle(Color.primary), at: CGPoint(x: nx, y: 60), anchor: .center)
            }
        }
        .frame(height: 66)
        .accessibilityLabel("Linha do dia")
    }
}
