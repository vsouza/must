import CoreLocation
import SwiftData
import SwiftUI

// Painéis do Lugar por tipo: photo (Foto.png), art (Arte.png), sport (Esporte.png).

private struct ChipRow: View {
    var items: [String]
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) { ForEach(items, id: \.self) { Tag($0) } }
        }
        .scrollIndicators(.hidden)
    }
}

/// Tag com cores livres (dourado, terracota, verde claro).
struct TintTag: View {
    var text: String
    var bg: Color
    var fg: Color
    var icon: MustIcon?

    init(_ text: String, bg: Color, fg: Color, icon: MustIcon? = nil) {
        self.text = text
        self.bg = bg
        self.fg = fg
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon { MustIconView(icon, size: 12) }
            Text(text).lineLimit(1)
        }
        .font(.must.archivo(12))
        .foregroundStyle(fg)
        .padding(.vertical, 5)
        .padding(.horizontal, 9)
        .background(bg, in: Capsule())
    }
}

// MARK: - photo

struct PhotoPanel: View {
    var place: Place
    var spot: PhotoSpot
    var region: Region
    var now: Date
    var weather: DayWeather?
    var fetchedAt: Date?

    var body: some View {
        let sun = SunService.day(now, place.coordinate, timeZone: region.timeZone)
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: -22) {
                sunCard(sun)
                    .stackCard(tint: .gold, rotation: -1.2)
                    .zIndex(0)
                skyCard(sun)
                    .stackCard(tint: .gray, rotation: 1.4)
                    .padding(.leading, 34).padding(.trailing, -28)
                    .zIndex(1)
                lightCard(sun)
                    .stackCard(tint: .slate)
                    .zIndex(2)
            }
            ChipRow(items: chips)
        }
    }

    private var chips: [String] {
        var out: [String] = []
        if let gear = spot.gear { out.append(gear) }
        if let tripod = spot.tripodAllowed { out.append(tripod ? "tripé ok" : "tripé não") }
        if let crowd = spot.crowdNote { out.append(crowd) }
        if !spot.bestLight.isEmpty { out.append(spot.bestLight.map(\.label).joined(separator: " · ")) }
        return out
    }

    private func sunCard(_ sun: SunDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Micro("Sol hoje · \(KindLines.weekdayDay(now, region: region)) \(region.monthShort(now))", color: MustGradient.goldText)
                Spacer()
                Text("agora \(region.timeString(now))").font(.must.mono(12, .semibold))
            }
            SunArcView(sun: sun, now: now, coordinate: place.coordinate, region: region)
            FlowLayout(spacing: 6) {
                if let g = sun.goldenPM {
                    TintTag("golden \(region.timeString(g.start))–\(region.timeString(g.end))", bg: .white.opacity(0.6), fg: MustGradient.goldText)
                }
                if let b = sun.bluePM {
                    TintTag("azul \(region.timeString(b.start))–\(region.timeString(b.end))", bg: KindPalette.blue.opacity(0.18), fg: MustGradient.duskText)
                }
                if let g = sun.goldenPM {
                    let az = SunService.position(at: g.start, place.coordinate).azimuth
                    let axis = spot.facing.map { SunService.angle($0, az) <= 25 ? " · bate no eixo da rua" : "" } ?? ""
                    TintTag("sol a \(Int(az.rounded()))°\(axis)", bg: .white.opacity(0.6), fg: MustGradient.goldText)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skyCard(_ sun: SunDay) -> some View {
        let hour = weather?.hour(at: now)
        let goldenHour = sun.goldenPM.flatMap { weather?.hour(at: $0.start) }
        let phrase = SkyVerdict.phrase(cloud: goldenHour?.cloud ?? hour?.cloud, rain: goldenHour?.precipProb, golden: goldenHour != nil)
        let good = (goldenHour?.cloud ?? hour?.cloud ?? 100) < 30
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Micro("Céu · Open-Meteo")
                Spacer()
                if let fetchedAt { Text("atualizado \(region.timeString(fetchedAt))").font(.must.archivo(12)).foregroundStyle(Color.must.secondary) }
            }
            if let hour {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    MonoNumber("\(Int(hour.temp.rounded()))°", size: 26).foregroundStyle(Color.must.ink)
                    skyLine(hour)
                }
            } else {
                Text("Sem previsão hora a hora ainda — abre de novo com internet.").font(.must.archivo(13)).foregroundStyle(Color.must.secondary)
            }
            Text(phrase).mustSerif(15).foregroundStyle(good ? Color.must.greenTextSoft : KindPalette.warnText)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skyLine(_ h: HourWeather) -> some View {
        var t = Text("")
        func bold(_ s: String) -> Text { Text(s).foregroundStyle(Color.must.ink).fontWeight(.semibold) }
        if let c = h.cloud { t = t + Text("nuvens ") + bold("\(c)%") }
        if let v = h.visibility { t = t + Text(" · visibilidade ") + bold("\(Int((v / 1000).rounded())) km") }
        if let r = h.precipProb { t = t + Text(" · chuva ") + bold("\(r)%") }
        if let w = h.wind { t = t + Text(" · vento \(Int(w.rounded())) km/h") }
        return t.font(.must.archivo(13)).foregroundStyle(Color.must.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func lightCard(_ sun: SunDay) -> some View {
        let golden = sun.goldenPM
        let goldenAz = golden.map { SunService.position(at: $0.start, place.coordinate).azimuth }
        let nowPos = SunService.position(at: now, place.coordinate)
        let shadow: String? = golden.flatMap { g in
            guard now < g.end else { return nil }
            guard let t = SunService.time(below: 15, after: max(now, sun.solarNoon), until: g.end, place.coordinate) else { return nil }
            return t <= now.addingTimeInterval(120) ? "Sombras já compridas." : "Sombra longa às \(region.timeString(t))."
        }
        let direction: LightDirection? = spot.facing.flatMap { f in
            goldenAz.map { LightDirection.describe(facing: f, sunAzimuth: $0, when: "no golden", longShadow: shadow) }
        }
        return HStack(spacing: 14) {
            LightCompass(facing: spot.facing, sunNow: nowPos.elevation > 0 ? nowPos.azimuth : nil, sunGolden: goldenAz)
            VStack(alignment: .leading, spacing: 4) {
                Text(direction?.title ?? "Direção da luz").font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
                Text(direction?.detail ?? "Sem eixo marcado — edite o lugar e diga pra onde a câmera aponta (graus).")
                    .font(.must.archivo(12.5)).foregroundStyle(Color.must.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Sessões com ingresso (art e jogos)

struct SessionsCard: View {
    var sessions: [EventSession]
    var region: Region
    var fallbackURL: URL?
    var onToggleBought: (EventSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Micro("Também aqui")
                Spacer()
                Text("eventos com ingresso").font(.must.archivo(12)).foregroundStyle(Color.must.secondary)
            }
            .padding(.bottom, 8)
            ForEach(sessions.sorted { $0.at < $1.at }) { s in
                RowDivider()
                row(s)
            }
            if sessions.isEmpty {
                Text("Nenhuma sessão com ingresso cadastrada.").font(.must.archivo(13)).foregroundStyle(Color.must.secondary).padding(.top, 8)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ s: EventSession) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(KindLines.weekdayDay(s.at, region: region))
                Text(region.timeString(s.at))
            }
            .font(.must.mono(12, .semibold)).foregroundStyle(Color.must.ink)
            .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.must.archivo(14, .semibold)).foregroundStyle(Color.must.ink).lineLimit(2)
                let meta = [s.price.map { $0 == 0 ? "grátis" : region.money($0) }, s.note].compactMap { $0 }.joined(separator: " · ")
                if !meta.isEmpty { Text(meta).font(.must.archivo(12)).foregroundStyle(Color.must.secondary).lineLimit(1) }
            }
            Spacer(minLength: 6)
            if s.bought {
                Tag("comprado", style: .green)
            } else if s.soldOut {
                TintTag("esgotado", bg: KindPalette.warnBg, fg: KindPalette.warnText)
            } else if let url = s.url ?? fallbackURL {
                Link(destination: url) {
                    Text("Comprar").font(.must.archivo(13, .semibold)).foregroundStyle(Color.must.ink)
                        .padding(.horizontal, 12).frame(height: 32).background(Capsule().fill(Color.white))
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            Button(s.bought ? "Desmarcar ingresso comprado" : "Marcar ingresso comprado (vira âncora)") { onToggleBought(s) }
        }
    }
}

// MARK: - art

struct ArtPanel: View {
    var place: Place
    var art: ArtEvent
    var region: Region
    var now: Date
    var onToggleBought: (EventSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: -22) {
                entryCard.stackCard(color: .art, rotation: -1.2).zIndex(0)
                styleCard.stackCard(tint: .gray, rotation: 1.4).padding(.leading, 34).padding(.trailing, -28).zIndex(1)
                SessionsCard(sessions: art.sessions, region: region, fallbackURL: art.ticketURL, onToggleBought: onToggleBought)
                    .stackCard(tint: .slate).zIndex(2)
            }
            ChipRow(items: footer)
        }
    }

    private var footer: [String] {
        var out: [String] = []
        if let s = place.source, s.kind != .board, s.kind != .manual { out.append("fonte: \(s.kind.label) · lido no aparelho") }
        if art.ticketURL != nil { out.append("ingresso online · link") }
        return out
    }

    private var entryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Micro("Entrada · temporada", color: MustColor.art.text)
                Spacer()
                if let until = art.runsUntil {
                    Text("até \(region.shortDay(ArtEvent.localDay(until, calendar: region.calendar)))").font(.must.mono(12, .semibold))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                MonoNumber(art.priceAdult.map { $0 == 0 ? "grátis" : region.money($0) } ?? "—", size: 30)
                    .foregroundStyle(Color.must.ink)
                    .fixedSize()
                priceLine.font(.must.archivo(13)).fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 6) {
                ForEach(hoursChips, id: \.self) { TintTag($0, bg: .white.opacity(0.6), fg: MustColor.art.text) }
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var priceLine: Text {
        var t = Text("")
        if let s = art.priceStudent { t = t + Text("estudante \(region.money(s))") }
        if let free = art.freeNote {
            if art.priceStudent != nil { t = t + Text(" · ") }
            t = t + Text("grátis").fontWeight(.semibold) + Text(" \(free)")
        }
        return t
    }

    private var hoursChips: [String] {
        var out: [String] = []
        let tz = region.timeZone
        if let h = place.hours, h.hasPeriods {
            if let today = h.todayText(now, timeZone: tz) { out.append(today) }
            if let last = art.lastEntryMinutes, let close = closeToday(h) {
                out.append("última entrada \(region.timeString(close.addingTimeInterval(Double(-last * 60))))")
            }
            if !h.closedDays.isEmpty { out.append("fecha \(h.closedDays.joined(separator: ", "))") }
        } else if let last = art.lastEntryMinutes {
            out.append("última entrada \(last) min antes de fechar")
        }
        out.append(art.needsBooking ? "reserva obrigatória" : "sem reserva · fila")
        return out
    }

    private func closeToday(_ h: PlaceHours) -> Date? {
        let wd = region.calendar.component(.weekday, from: now) - 1
        guard let c = (h.periods ?? []).filter({ $0.open.day == wd }).compactMap(\.close).max(by: { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) else { return nil }
        return region.calendar.startOfDay(for: now).addingTimeInterval(Double(c.hour * 3600 + c.minute * 60))
    }

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Micro("Estilo")
                Spacer()
                let meta = [art.durationMinutes.map(KindLines.duration), art.floors.map { "\($0) \($0 == 1 ? "andar" : "andares")" }].compactMap { $0 }
                Text(meta.joined(separator: " · ")).font(.must.archivo(12)).foregroundStyle(Color.must.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(Array(art.style.enumerated()), id: \.offset) { i, s in
                    if i == 0 { Tag(s, style: .dark) } else { Tag(s) }
                }
            }
            let photoNote = art.note ?? art.photographyAllowed.map { $0 ? "Fotografar: liberado." : "Fotografar: proibido nas salas." }
            if let photoNote {
                Text(photoNote).font(.must.archivo(12.5)).foregroundStyle(Color.must.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - sport

struct SportPanel: View {
    var place: Place
    var spot: SportSpot
    var region: Region
    var now: Date
    var weather: DayWeather?
    var onToggleBought: (EventSession) -> Void

    private var hours: [HourWeather] { weather?.hours ?? [] }
    private var current: HourWeather? { weather?.hour(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: -22) {
                if spot.activity == .watch {
                    SessionsCard(sessions: spot.sessions, region: region, fallbackURL: nil, onToggleBought: onToggleBought)
                        .stackCard(color: .sport, rotation: -1.2).zIndex(0)
                } else {
                    conditionsCard.stackCard(color: .sport, rotation: -1.2).zIndex(0)
                    windowCard.stackCard(tint: .gray, rotation: 1.4).padding(.leading, 34).padding(.trailing, -28).zIndex(1)
                }
                routeCard.stackCard(tint: .slate).zIndex(2)
            }
            ChipRow(items: spot.facilities)
        }
    }

    private var conditionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Micro("Condições · \(KindLines.weekdayDay(now, region: region)) \(region.monthShort(now)) · \(region.timeString(now))", color: MustColor.sport.text)
                Spacer()
                Text("Open-Meteo").font(.must.mono(12, .semibold))
            }
            if let h = current {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    MonoNumber("\(Int(h.temp.rounded()))°", size: 34).foregroundStyle(Color.must.ink).fixedSize()
                    feelsLine(h).font(.must.archivo(13)).fixedSize(horizontal: false, vertical: true)
                }
                metrics(h)
                Text(windowPhrase).mustSerif(15).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Sem previsão hora a hora — abre de novo com internet.").font(.must.archivo(13))
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feelsLine(_ h: HourWeather) -> Text {
        var t = Text("")
        if let a = h.apparent { t = t + Text("sensação ") + Text("\(Int(a.rounded()))°").fontWeight(.semibold) }
        let later = hours.filter { $0.time > now && region.calendar.isDate($0.time, inSameDayAs: now) }
        if let peak = later.max(by: { $0.temp < $1.temp }), peak.temp >= h.temp + 2 {
            t = t + Text(" · sobe pra ") + Text("\(Int(peak.temp.rounded()))°").fontWeight(.semibold)
                + Text(" às \(region.calendar.component(.hour, from: peak.time))h")
        }
        return t
    }

    private func metrics(_ h: HourWeather) -> some View {
        HStack(spacing: 4) {
            metric(h.humidity.map { "\($0)%" } ?? "—", "umidade")
            metric(h.wind.map { "\(Int($0.rounded()))" } ?? "—", "km/h \(h.windDir.map(SunService.cardinal) ?? "")")
            metric(h.uv.map { "\(Int($0.rounded()))" } ?? "—", "UV")
            metric(h.aqi.map { "AQI \($0)" } ?? "AQI —", h.aqi.map(KindLines.aqiLabel) ?? "ar")
            metric(h.precipProb.map { "\($0)%" } ?? "—", "chuva")
        }
        .padding(.vertical, 8).padding(.horizontal, 6)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.must.mono(14, .semibold)).foregroundStyle(Color.must.ink).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.must.micro).textCase(.uppercase).tracking(0.8).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// "corra até as 9h: depois esquenta (31° às 11h)".
    private var windowPhrase: String {
        let verb = spot.activity.imperative
        if let until = SportScore.goodUntil(hours, from: now, spot: spot) {
            let h = region.calendar.component(.hour, from: until)
            let after = hours.first { $0.time >= until }
            let why = after.flatMap { DaySolver.sportRejection(spot, at: $0.time, hourly: hours) }.map { ": depois fica \($0)" } ?? ""
            return "\(verb) até as \(h)h\(why)"
        }
        if let next = SportScore.nextGood(hours, after: now, spot: spot), region.calendar.isDate(next, inSameDayAs: now) {
            return "agora não — melhor a partir das \(region.calendar.component(.hour, from: next))h"
        }
        return "hoje não tem janela boa — \(DaySolver.sportRejection(spot, at: now, hourly: hours) ?? "tempo ruim")"
    }

    private var windowCard: some View {
        var levels: [Int: Int] = [:]
        for h in hours where region.calendar.isDate(h.time, inSameDayAs: now) {
            levels[region.calendar.component(.hour, from: h.time)] = SportScore.level(h, spot: spot)
        }
        let c = region.calendar.dateComponents([.hour, .minute], from: now)
        let nowHour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Micro("Melhor janela hoje")
                Spacer()
                Text("verde = bom · vermelho = evitar").font(.must.archivo(12)).foregroundStyle(Color.must.secondary)
            }
            HourBars(levels: levels, nowHour: nowHour)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeCard: some View {
        let title = [spot.distanceKm.map { "\(KindLines.km($0)) km" }, spot.loop ? "circuito" : "ida e volta",
                     spot.estimatedMinutes.map { "~\($0) min" }].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 14) {
            ElevationProfile(elevation: spot.elevationM, loop: spot.loop)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.must.archivo(15, .semibold)).foregroundStyle(Color.must.ink)
                if let note = spot.routeNote {
                    Text(note).font(.must.archivo(12.5)).foregroundStyle(Color.must.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
