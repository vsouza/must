import CoreLocation
import SwiftData
import SwiftUI

// Desenhos e frases dos painéis photo / art / sport (Foto.png, Arte.png, Esporte.png, Luz.png).

enum KindPalette {
    static let goldArc = MustGradient.goldArc
    static let goldSoft = MustGradient.goldStrong
    static let blue = MustGradient.duskStrong
    static let hard = Color(hex: 0xFFE1B8)
    /// Verde → âmbar → coral (janela de esporte).
    static let levels: [Color] = [Color(hex: 0x22DD7E), Color(hex: 0xB9F5CF), Color(hex: 0xFFE3A3), Color(hex: 0xFFB020), Color(hex: 0xFF5A3C)]
    /// Terracota dos avisos ("termina em 4 dias", "quente · 31°").
    static let warnBg = MustColor.coffee.light
    static let warnText = MustColor.coffee.text
}

// MARK: - Frases

enum KindLines {
    /// "em 1h18", "em 23 min".
    static func inText(_ seconds: TimeInterval) -> String {
        let m = max(0, Int((seconds / 60).rounded()))
        if m < 60 { return "em \(m) min" }
        return m % 60 == 0 ? "em \(m / 60)h" : "em \(m / 60)h\(String(format: "%02d", m % 60))"
    }

    /// Chip dourado do título: "golden em 1h18" / "golden agora" / "azul agora" / "golden 15:48".
    static func goldenTag(_ sun: SunDay, now: Date, region: Region) -> String? {
        if let g = sun.goldenPM {
            if now < g.start { return "golden \(inText(g.start.timeIntervalSince(now)))" }
            if g.contains(now) { return "golden agora · até \(region.timeString(g.end))" }
        }
        if let b = sun.bluePM, b.contains(now) { return "azul agora · até \(region.timeString(b.end))" }
        if let g = sun.goldenAM, g.contains(now) { return "golden agora · até \(region.timeString(g.end))" }
        return sun.goldenPM.map { "golden amanhã ~\(region.timeString($0.start))" }
    }

    /// Lista › photo: "golden 15:48 · 12 min".
    static func photoMeta(_ place: Place, region: Region, now: Date, location: CLLocation?) -> String {
        let sun = SunService.day(now, place.coordinate, timeZone: region.timeZone)
        var parts: [String] = []
        if let g = sun.goldenPM { parts.append(now <= g.end ? "golden \(region.timeString(g.start))" : "golden amanhã") }
        if let d = place.distance(from: location) { parts.append(d <= 2500 ? "\(Walk.minutes(d)) min" : Walk.distanceText(d)) }
        return parts.joined(separator: " · ")
    }

    /// Lista › art: "até 30 nov · ¥1.400".
    static func artMeta(_ place: Place, region: Region, now: Date) -> String? {
        guard let art = place.extra?.art else { return nil }
        var parts: [String] = []
        if let until = art.runsUntil {
            let left = art.daysLeft(from: now, calendar: region.calendar) ?? 99
            parts.append(left < 0 ? "terminou" : (left <= 7 ? DaySolver.endsText(left) : "até \(region.shortDay(ArtEvent.localDay(until, calendar: region.calendar)))"))
        }
        if let p = art.priceAdult { parts.append(p == 0 ? "grátis" : region.money(p)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Lista › sport: "23° agora · UV 4".
    static func sportMeta(_ place: Place, weather: DayWeather?, now: Date) -> String? {
        guard let spot = place.extra?.sport else { return nil }
        if spot.activity == .watch {
            return spot.sessions.filter { $0.at > now }.min { $0.at < $1.at }.map { "jogo \($0.title)" }
        }
        guard let h = weather?.hour(at: now) else { return spot.distanceKm.map { "\(km($0)) km" } }
        var s = "\(Int(h.temp.rounded()))° agora"
        if let uv = h.uv { s += " · UV \(Int(uv.rounded()))" }
        return s
    }

    static func km(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "pt-BR")))
    }

    static func uvLabel(_ uv: Double) -> String {
        switch uv {
        case ..<3: "baixo"
        case ..<6: "moderado"
        case ..<8: "alto"
        case ..<11: "muito alto"
        default: "extremo"
        }
    }

    static func aqiLabel(_ aqi: Int) -> String {
        switch aqi {
        case ...50: "ar bom"
        case ...100: "ar ok"
        case ...150: "ar ruim p/ sensíveis"
        default: "ar ruim"
        }
    }

    /// "ter 18" (dia da semana + dia).
    static func weekdayDay(_ date: Date, region: Region) -> String {
        var style = Date.FormatStyle(locale: region.locale, calendar: region.calendar).weekday(.abbreviated)
        style.timeZone = region.timeZone
        return "\(date.formatted(style).replacingOccurrences(of: ".", with: "").lowercased()) \(region.dayNumber(date))"
    }

    /// "1h30", "45 min".
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(String(format: "%02d", minutes % 60))")
    }
}

// MARK: - Arco do sol

/// Elevação do sol de nascer a fim da hora azul: golden em laranja, azul em índigo, o sol de agora.
struct SunArcView: View {
    var sun: SunDay
    var now: Date
    var coordinate: CLLocationCoordinate2D
    var region: Region

    var body: some View {
        Canvas { ctx, size in
            guard let rise = sun.sunrise, let set = sun.sunset else { return }
            let end = sun.bluePM?.end ?? set
            let w = size.width, base = size.height - 18, top: CGFloat = 16
            let noon = max(sun.noonElevation, 1)
            func x(_ t: Date) -> CGFloat { 10 + CGFloat(t.timeIntervalSince(rise) / end.timeIntervalSince(rise)) * (w - 24) }
            func y(_ e: Double) -> CGFloat { e >= 0 ? base - CGFloat(e / noon) * (base - top) : base + CGFloat(-e / 6) * 9 }
            func point(_ t: Date) -> CGPoint { CGPoint(x: x(t), y: y(SunService.position(at: t, coordinate).elevation)) }
            func curve(_ a: Date, _ b: Date) -> Path {
                var p = Path()
                var t = a
                p.move(to: point(t))
                while t < b { t = min(b, t.addingTimeInterval(240)); p.addLine(to: point(t)) }
                return p
            }
            let ink = MustGradient.goldText
            // Linha do horizonte e o arco pontilhado.
            ctx.stroke(Path { $0.move(to: CGPoint(x: 10, y: base)); $0.addLine(to: CGPoint(x: w - 10, y: base)) }, with: .color(ink.opacity(0.3)), lineWidth: 1)
            ctx.stroke(curve(rise, set), with: .color(ink.opacity(0.28)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
            if let g = sun.goldenAM { ctx.stroke(curve(g.start, g.end), with: .color(KindPalette.goldSoft), style: StrokeStyle(lineWidth: 4, lineCap: .round)) }
            if let g = sun.goldenPM { ctx.stroke(curve(g.start, g.end), with: .color(KindPalette.goldArc), style: StrokeStyle(lineWidth: 5, lineCap: .round)) }
            if let b = sun.bluePM { ctx.stroke(curve(b.start, b.end), with: .color(KindPalette.blue), style: StrokeStyle(lineWidth: 5, lineCap: .round)) }

            let mono = Font.must.mono(10, .semibold)
            ctx.draw(Text(region.timeString(rise)).font(mono).foregroundStyle(ink), at: CGPoint(x: 2, y: size.height - 4), anchor: .bottomLeading)
            ctx.draw(Text(region.timeString(set)).font(mono).foregroundStyle(ink), at: CGPoint(x: x(set) - 8, y: size.height - 4), anchor: .bottomTrailing)
            if let g = sun.goldenPM {
                let p = point(g.start)
                ctx.draw(Text(region.timeString(g.start)).font(mono).foregroundStyle(ink), at: CGPoint(x: p.x + 8, y: p.y - 6), anchor: .bottomLeading)
            }
            // Sol agora.
            if now > rise && now < set {
                let pos = SunService.position(at: now, coordinate)
                let p = point(now)
                ctx.stroke(Path { $0.move(to: p); $0.addLine(to: CGPoint(x: p.x, y: base)) }, with: .color(ink.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                let r: CGFloat = 9
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(KindPalette.goldArc))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(.white), lineWidth: 2)
                let label = "\(Int(pos.elevation.rounded()))° · \(pos.cardinal)"
                // À esquerda do sol, na altura dele (não briga com as horas do golden à direita).
                ctx.draw(Text(label).font(mono).foregroundStyle(ink), at: CGPoint(x: max(p.x - r - 8, 60), y: min(p.y + 2, base - 10)), anchor: .trailing)
            }
        }
        .frame(height: 100)
        .accessibilityElement()
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        var parts: [String] = []
        if let r = sun.sunrise { parts.append("nasce \(region.timeString(r))") }
        if let g = sun.goldenPM { parts.append("golden \(region.timeString(g.start)) a \(region.timeString(g.end))") }
        if let b = sun.bluePM { parts.append("azul até \(region.timeString(b.end))") }
        return "Arco do sol: " + parts.joined(separator: ", ")
    }
}

// MARK: - Bússola da luz

/// Eixo do lugar (pra onde a câmera aponta) e o sol agora / no golden.
struct LightCompass: View {
    var facing: Double?
    var sunNow: Double?
    var sunGolden: Double?

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 4
            func at(_ az: Double, _ radius: CGFloat) -> CGPoint {
                let a = az * .pi / 180
                return CGPoint(x: c.x + radius * CGFloat(sin(a)), y: c.y - radius * CGFloat(cos(a)))
            }
            let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.fill(circle, with: .color(Color(hex: 0xF7F8FA)))
            ctx.stroke(circle, with: .color(Color(hex: 0xE6E8EC)), lineWidth: 1)
            var cross = Path()
            cross.move(to: CGPoint(x: c.x, y: c.y - r + 6)); cross.addLine(to: CGPoint(x: c.x, y: c.y + r))
            cross.move(to: CGPoint(x: c.x - r, y: c.y)); cross.addLine(to: CGPoint(x: c.x + r, y: c.y))
            ctx.stroke(cross, with: .color(Color(hex: 0xE6E8EC)), lineWidth: 1)
            ctx.draw(Text("N").font(.must.archivo(8, .bold)).foregroundStyle(Color(hex: 0xA9AEB6)), at: CGPoint(x: c.x, y: c.y - r - 1), anchor: .top)
            if let facing {
                var axis = Path()
                axis.move(to: at(facing + 180, r * 0.7)); axis.addLine(to: at(facing, r * 0.7))
                ctx.stroke(axis, with: .color(Color.must.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let sunNow {
                let p = at(sunNow, r * 0.88)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(KindPalette.goldSoft))
            }
            if let sunGolden {
                let p = at(sunGolden, r * 0.98)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(KindPalette.goldArc))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Color.must.blue))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(.white), lineWidth: 1.5)
        }
        .frame(width: 84, height: 84)
        .accessibilityLabel("Bússola da luz")
    }
}

// MARK: - Janela por hora

/// Barras por hora (06 → 19) coloridas pelo score de esporte, com a hora de agora.
struct HourBars: View {
    var levels: [Int: Int]
    var nowHour: Double?
    var hours: ClosedRange<Int> = 6...19

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let n = CGFloat(hours.count), gap: CGFloat = 3
                let barW = (geo.size.width - gap * (n - 1)) / n
                ZStack(alignment: .topLeading) {
                    HStack(spacing: gap) {
                        ForEach(Array(hours), id: \.self) { h in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(levels[h].map { KindPalette.levels[min(4, $0)] } ?? Color.must.line)
                        }
                    }
                    if let nowHour, nowHour >= Double(hours.lowerBound), nowHour <= Double(hours.upperBound + 1) {
                        let x = CGFloat(nowHour - Double(hours.lowerBound)) * (barW + gap)
                        Capsule().fill(Color.must.ink).frame(width: 2.5, height: geo.size.height + 6).offset(x: x - 1, y: -3)
                    }
                }
            }
            .frame(height: 26)
            // Rótulo alinhado com a barra da hora.
            GeometryReader { geo in
                let n = CGFloat(hours.count), gap: CGFloat = 3
                let barW = (geo.size.width - gap * (n - 1)) / n
                ForEach([6, 9, 12, 15, 18].filter { hours.contains($0) }, id: \.self) { h in
                    Text(String(format: "%02d", h)).font(.must.mono(9, .semibold)).foregroundStyle(Color.must.secondary)
                        .fixedSize()
                        .position(x: CGFloat(h - hours.lowerBound) * (barW + gap) + barW / 2, y: 6)
                }
            }
            .frame(height: 12)
        }
        .accessibilityLabel("Janela por hora")
    }
}

// MARK: - Perfil do percurso

struct ElevationProfile: View {
    var elevation: Int?
    var loop: Bool

    var body: some View {
        Canvas { ctx, size in
            let base = size.height - 6, amp = CGFloat(min(Double(elevation ?? 10), 120) / 120) * (size.height * 0.5) + 6
            var line = Path()
            let steps = 40
            for i in 0...steps {
                let t = Double(i) / Double(steps)
                // Ida e volta: sobe e desce; circuito: ondula.
                let shape = loop ? 0.5 + 0.5 * sin(t * 2 * .pi * 2 - .pi / 2) : sin(t * .pi)
                let p = CGPoint(x: 2 + CGFloat(t) * (size.width - 4), y: base - 14 - CGFloat(shape) * amp * 0.45)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width - 2, y: base)); fill.addLine(to: CGPoint(x: 2, y: base)); fill.closeSubpath()
            ctx.fill(fill, with: .color(MustColor.sport.light.opacity(0.8)))
            ctx.stroke(line, with: .color(MustColor.sport.strong), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            if let elevation {
                ctx.draw(Text("+\(elevation) m").font(.must.mono(9, .semibold)).foregroundStyle(Color.must.secondary),
                         at: CGPoint(x: 2, y: 2), anchor: .topLeading)
            }
        }
        .frame(width: 90, height: 80)
        .accessibilityLabel("Perfil do percurso")
    }
}

// MARK: - Pôr no dia

enum DayInsert {
    /// Hora sugerida pra encaixar hoje: 13:00 se ainda der, senão a próxima meia hora.
    static func suggestedTime(now: Date, region: Region, place: Place) -> Date {
        let cal = region.calendar
        let day = cal.startOfDay(for: now)
        let thirteen = day.addingTimeInterval(13 * 3600)
        if now < thirteen.addingTimeInterval(-30 * 60) { return thirteen }
        let minutes = Int(now.timeIntervalSince(day) / 60)
        return day.addingTimeInterval(Double(((minutes + 29) / 30) * 30 + 30) * 60)
    }

    /// Insere a parada no dia de hoje (cria o dia se não houver) na hora dada.
    @MainActor
    static func add(_ place: Place, at: Date, region: Region, context: ModelContext) {
        let date = region.calendar.startOfDay(for: at)
        let existing = try? context.fetch(FetchDescriptor<PlannedDay>(predicate: #Predicate { $0.date == date })).first
        let day: PlannedDay
        if let existing {
            day = existing
        } else {
            day = PlannedDay(date: date, budget: context.settings(for: region).perDayBudget, accepted: true)
            context.insert(day)
        }
        if day.stops.contains(where: { $0.place?.id == place.id }) { return }
        let stop = Stop(place: place, at: at, order: 0)
        context.insert(stop)
        day.stops.append(stop)
        for (i, s) in day.stops.sorted(by: { $0.at < $1.at }).enumerated() { s.order = i }
        try? context.save()
    }
}
