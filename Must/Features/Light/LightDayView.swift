import CoreLocation
import SwiftData
import SwiftUI

/// Luz de hoje (Luz.png): o dia pela luz — faixas azul/golden/dura, spots por hora, museu no sol alto.
/// Usa o dia aceito quando é de fotografia; senão, a sugestão do solver pra um dia de fotografia.
struct LightDayView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar.padding(.top, 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Luz de hoje").mustTitle()
                    Text(headline(sun, weather: weather)).mustSerif(18).foregroundStyle(MustGradient.goldText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)

                dayLine(sun, weather: weather).padding(.top, 18)
                spots(rows, sun: sun, weather: weather).padding(.top, 14)
                TabBarSpacer()
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                Color.must.bg
                LinearGradient(stops: [.init(color: Color(hex: 0xFFF6E8), location: 0), .init(color: Color(hex: 0xFFE1B8), location: 0.45),
                                       .init(color: MustGradient.goldStrong, location: 0.78), .init(color: Color(hex: 0x8C9BFF), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(0.85)
                    .frame(height: 380)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom).frame(height: 140)
                    }
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Topo

    private var topBar: some View {
        HStack(spacing: 10) {
            IconButton(.voltar, style: .glass, label: "Voltar") { dismiss() }
            Spacer(minLength: 4)
            Micro("\(KindLines.weekdayDay(date, region: region)) · \(region.monthShort(date)) · dia de fotografia", color: MustGradient.goldText)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            IconButton(.ajustes, style: .glass, label: "Montar dia de fotografia") { router.push(.montar(date: date)) }
        }
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
            FlowLayout(spacing: 6) {
                if let g = sun.goldenPM {
                    TintTag("golden \(region.timeString(g.start))–\(region.timeString(g.end))", bg: MustGradient.goldStrong, fg: MustGradient.goldText)
                }
                if let b = sun.bluePM {
                    TintTag("azul \(region.timeString(b.start))–\(region.timeString(b.end))", bg: MustGradient.duskLight, fg: MustGradient.duskText)
                }
                let peak = Int(sun.noonElevation.rounded())
                Tag(peak < 45 ? "sol baixo o dia todo · \(peak)° no pico" : "sol alto 11–15h · \(peak)° no pico")
                if let a = weather?.hour(at: isToday ? now : date.addingTimeInterval(9 * 3600))?.cloud,
                   let g = sun.goldenPM, let b = weather?.hour(at: g.start)?.cloud {
                    Tag("nuvens \(a)% → \(b)%")
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.7)))
        .shadow(color: Color(hex: 0x121316, opacity: 0.08), radius: 15, y: 10)
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
        return ("noite", Color.must.ink)
    }

    private func spots(_ rows: [Row], sun: SunDay, weather: DayWeather?) -> some View {
        let next = rows.first { !$0.done && !$0.past }?.id
        return VStack(alignment: .leading, spacing: 0) {
            if rows.isEmpty {
                Text("Nenhum spot pra hoje. Adicione lugares na lista Must photo ou monte um dia de fotografia.")
                    .mustMeta().padding(.vertical, 18)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 && r.id != next && rows[i - 1].id != next { RowDivider() }
                Button { if let id = r.placeId { router.push(.place(id: id)) } } label: {
                    rowView(r, isNext: r.id == next, sun: sun)
                }
                .buttonStyle(MustPressStyle())
            }
            if let line = tomorrowLine(sun: sun) {
                Text(line).mustSerif(15).foregroundStyle(Color.must.secondary).padding(.top, 12).padding(.bottom, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.must.line))
        .shadow(color: Color(hex: 0x121316, opacity: 0.06), radius: 15, y: 10)
    }

    private func rowView(_ r: Row, isNext: Bool, sun: SunDay) -> some View {
        let l = light(r.time, sun: sun)
        return HStack(alignment: .center, spacing: 14) {
            Text(region.timeString(r.time)).font(.must.mono(14, .semibold))
                .foregroundStyle(isNext ? MustGradient.goldText : Color.must.ink)
                .lineLimit(1).fixedSize()
                .frame(minWidth: 50, alignment: .leading)
            // A barra é a luz da hora (golden, dura, azul); refeição fica na cor da lista.
            Capsule().fill(r.color == .eat ? MustColor.eat.strong : l.color).frame(width: 5, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(r.name).font(.must.archivo(16, .semibold)).foregroundStyle(Color.must.ink).multilineTextAlignment(.leading)
                    if r.done { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.must.secondary) }
                }
                Text(r.meta).font(.must.archivo(13)).foregroundStyle(Color.must.secondary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if isNext {
                Text("próximo").font(.must.archivo(13, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 34).background(Capsule().fill(Color.must.ink))
            } else if r.kind == .art {
                TintTag("art", bg: MustColor.art.light, fg: MustColor.art.text)
            } else if r.kind == .place, let c = r.color {
                Tag(c.label, dot: c.strong)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, isNext ? 10 : 0)
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [MustGradient.goldLight.opacity(0.85), MustGradient.goldStrong.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .padding(.horizontal, isNext ? -10 : 0)
        .padding(.vertical, isNext ? 4 : 0)
        .opacity(r.done || r.past ? 0.5 : 1)
        .contentShape(Rectangle())
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
            ctx.fill(track, with: .color(Color.must.line))
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
            let mono = Font.must.mono(9, .semibold)
            let grey = Color.must.secondary
            if let r = sun.sunrise { ctx.draw(Text(region.timeString(r)).font(mono).foregroundStyle(grey), at: CGPoint(x: max(0, x(r) - 14), y: 50), anchor: .leading) }
            let peak = Int(sun.noonElevation.rounded())
            ctx.draw(Text("\(region.timeString(sun.solarNoon)) pico \(peak)°").font(mono).foregroundStyle(grey), at: CGPoint(x: x(sun.solarNoon), y: 50), anchor: .center)
            if let g = sun.goldenPM { ctx.draw(Text(region.timeString(g.start)).font(mono).foregroundStyle(grey), at: CGPoint(x: x(g.start), y: 12), anchor: .leading) }
            if let e = sun.bluePM?.end { ctx.draw(Text(region.timeString(e)).font(mono).foregroundStyle(grey), at: CGPoint(x: min(size.width, x(e) + 14), y: 50), anchor: .trailing) }
            if let now, now > start, now < end {
                let nx = x(now)
                ctx.stroke(Path { $0.move(to: CGPoint(x: nx, y: 6)); $0.addLine(to: CGPoint(x: nx, y: barY + barH + 4)) }, with: .color(Color.must.ink), lineWidth: 2.5)
                ctx.fill(Path(ellipseIn: CGRect(x: nx - 4, y: 2, width: 8, height: 8)), with: .color(Color.must.ink))
                ctx.draw(Text(region.timeString(now)).font(mono).foregroundStyle(Color.must.ink), at: CGPoint(x: nx, y: 60), anchor: .center)
            }
        }
        .frame(height: 66)
        .accessibilityLabel("Linha do dia")
    }
}
