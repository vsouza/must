import CoreLocation
import Foundation

/// Sol num instante: azimute (0 = norte, sentido horário) e elevação geométrica, em graus.
struct SunPosition: Sendable, Hashable {
    var azimuth: Double
    var elevation: Double

    /// "SO", "ONO"… (16 pontos).
    var cardinal: String { SunService.cardinal(azimuth) }
}

/// Luz de um dia num lugar. Golden = sol entre 6° e o horizonte; azul = do horizonte a −6°
/// (as faixas do design: golden 15:48–16:38 termina no pôr, azul 16:38–17:06).
struct SunDay: Sendable, Hashable {
    var sunrise: Date?
    var sunset: Date?
    var solarNoon: Date
    /// Elevação no meio-dia solar.
    var noonElevation: Double
    var blueAM: DateInterval?
    var goldenAM: DateInterval?
    var goldenPM: DateInterval?
    var bluePM: DateInterval?

    /// Horas de sol (nascer → pôr).
    var daylight: TimeInterval? {
        guard let sunrise, let sunset else { return nil }
        return sunset.timeIntervalSince(sunrise)
    }

    /// Sol alto (luz dura): entre o fim do golden da manhã e o começo do da tarde.
    var hardLight: DateInterval? {
        guard let a = goldenAM?.end, let b = goldenPM?.start, b > a else { return nil }
        return DateInterval(start: a, end: b)
    }

    func interval(_ light: LightKind) -> DateInterval? {
        switch light {
        case .goldenAM: goldenAM
        case .goldenPM: goldenPM
        case .blue: bluePM
        case .hard: hardLight
        case .night: bluePM.map { DateInterval(start: $0.end, duration: 3 * 3600) }
        }
    }
}

/// Posição do sol sem rede (algoritmo da NOAA, o da planilha "Solar Calculations").
/// Erro de ~1 min no nascer/pôr pras latitudes do app.
enum SunService {
    /// Nascer/pôr: centro do sol a −0,833° (refração + raio).
    static let horizon = -0.833
    static let goldenTop = 6.0
    static let blueBottom = -6.0

    static func position(at date: Date, latitude: Double, longitude: Double) -> SunPosition {
        let rad = Double.pi / 180
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545) / 36_525
        let l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m * rad) * (0.019993 - 0.000101 * t) + sin(3 * m * rad) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(omega * rad)
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(omega * rad)
        let decl = asin(sin(eps * rad) * sin(lambda * rad))
        let y = pow(tan(eps * rad / 2), 2)
        let eqTime = 4 / rad * (y * sin(2 * l0 * rad) - 2 * e * sin(m * rad) + 4 * e * y * sin(m * rad) * cos(2 * l0 * rad)
            - 0.5 * y * y * sin(4 * l0 * rad) - 1.25 * e * e * sin(2 * m * rad))

        let utcMinutes = (date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) + 86_400)
            .truncatingRemainder(dividingBy: 86_400) / 60
        var trueSolar = (utcMinutes + eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if trueSolar < 0 { trueSolar += 1440 }
        let hourAngle = trueSolar / 4 < 0 ? trueSolar / 4 + 180 : trueSolar / 4 - 180
        let lat = latitude * rad
        let cosZenith = max(-1, min(1, sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(hourAngle * rad)))
        let zenith = acos(cosZenith)
        let elevation = 90 - zenith / rad

        var azimuth: Double
        let denom = cos(lat) * sin(zenith)
        if abs(denom) > 0.0001 {
            let cosAz = max(-1, min(1, (sin(lat) * cos(zenith) - sin(decl)) / denom))
            let az = acos(cosAz) / rad
            azimuth = hourAngle > 0 ? (az + 180).truncatingRemainder(dividingBy: 360) : (540 - az).truncatingRemainder(dividingBy: 360)
        } else {
            azimuth = latitude > 0 ? 180 : 0
        }
        return SunPosition(azimuth: azimuth, elevation: elevation)
    }

    static func position(at date: Date, _ c: CLLocationCoordinate2D) -> SunPosition {
        position(at: date, latitude: c.latitude, longitude: c.longitude)
    }

    /// Luz do dia civil que contém `date`, no fuso dado.
    static func day(_ date: Date, latitude: Double, longitude: Double, timeZone: TimeZone) -> SunDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        func elev(_ d: Date) -> Double { position(at: d, latitude: latitude, longitude: longitude).elevation }

        // Meio-dia solar: máximo da elevação (amostra de 5 min + refinamento).
        var noon = start
        var best = -91.0
        var t = start
        while t < end {
            let e = elev(t)
            if e > best { best = e; noon = t }
            t.addTimeInterval(300)
        }
        var lo = noon.addingTimeInterval(-300), hi = noon.addingTimeInterval(300)
        for _ in 0..<30 {
            let a = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 3), b = hi.addingTimeInterval(-hi.timeIntervalSince(lo) / 3)
            if elev(a) < elev(b) { lo = a } else { hi = b }
        }
        noon = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
        let noonElevation = elev(noon)

        /// Instante em que a elevação cruza `target` entre `a` e `b` (subindo ou descendo).
        func crossing(_ target: Double, from a: Date, to b: Date) -> Date? {
            let ea = elev(a) - target, eb = elev(b) - target
            guard ea.sign != eb.sign else { return nil }
            var lo = a, hi = b, flo = ea
            for _ in 0..<40 {
                let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
                let fm = elev(mid) - target
                if fm.sign == flo.sign { lo = mid; flo = fm } else { hi = mid }
            }
            return lo.addingTimeInterval(hi.timeIntervalSince(lo) / 2)
        }
        func rising(_ target: Double) -> Date? { crossing(target, from: noon.addingTimeInterval(-14 * 3600), to: noon) }
        func setting(_ target: Double) -> Date? { crossing(target, from: noon, to: noon.addingTimeInterval(14 * 3600)) }

        let sunrise = rising(horizon), sunset = setting(horizon)
        let blueStartAM = rising(blueBottom), goldenEndAM = rising(goldenTop)
        let goldenStartPM = setting(goldenTop), blueEndPM = setting(blueBottom)

        func interval(_ a: Date?, _ b: Date?) -> DateInterval? {
            guard let a, let b, b > a else { return nil }
            return DateInterval(start: a, end: b)
        }
        return SunDay(sunrise: sunrise, sunset: sunset, solarNoon: noon, noonElevation: noonElevation,
                      blueAM: interval(blueStartAM, sunrise), goldenAM: interval(sunrise, goldenEndAM),
                      goldenPM: interval(goldenStartPM, sunset), bluePM: interval(sunset, blueEndPM))
    }

    static func day(_ date: Date, _ c: CLLocationCoordinate2D, timeZone: TimeZone) -> SunDay {
        day(date, latitude: c.latitude, longitude: c.longitude, timeZone: timeZone)
    }

    /// Primeiro instante depois de `from` com elevação abaixo de `degrees` (sombra longa). `nil` se não houver no dia.
    static func time(below degrees: Double, after from: Date, until: Date, _ c: CLLocationCoordinate2D) -> Date? {
        var t = from
        while t < until {
            if position(at: t, c).elevation < degrees { return t }
            t.addTimeInterval(120)
        }
        return nil
    }

    private static let points = ["N", "NNE", "NE", "ENE", "L", "ESE", "SE", "SSE", "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"]
    private static let names = ["norte", "norte-nordeste", "nordeste", "leste-nordeste", "leste", "leste-sudeste", "sudeste", "sul-sudeste",
                                "sul", "sul-sudoeste", "sudoeste", "oeste-sudoeste", "oeste", "oeste-noroeste", "noroeste", "norte-noroeste"]

    static func cardinal(_ azimuth: Double) -> String { points[index(azimuth)] }
    static func cardinalName(_ azimuth: Double) -> String { names[index(azimuth)] }

    private static func index(_ azimuth: Double) -> Int {
        let a = (azimuth.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return Int((a / 22.5).rounded()) % 16
    }

    /// Diferença angular em [0, 180].
    static func angle(_ a: Double, _ b: Double) -> Double {
        let d = abs((a - b).truncatingRemainder(dividingBy: 360))
        return d > 180 ? 360 - d : d
    }
}

/// Luz sobre o eixo de um spot: frase de orientação do card "Direção da luz".
struct LightDirection: Sendable, Hashable {
    enum Kind: Sendable { case backlight, front, side }
    var kind: Kind
    var title: String
    var detail: String

    /// `facing` = pra onde a câmera aponta; `sunAzimuth` = sol no golden (ou agora).
    /// `longShadow` = frase pronta ("Sombra longa às 16:20." / "Sombras já compridas.").
    static func describe(facing: Double, sunAzimuth: Double, when: String, longShadow: String?) -> LightDirection {
        let diff = SunService.angle(facing, sunAzimuth)
        let where_ = "Sol a \(SunService.cardinalName(sunAzimuth))"
        let shadow = longShadow.map { " \($0)" } ?? ""
        if diff <= 45 {
            return LightDirection(kind: .backlight, title: "Contraluz \(when)",
                                  detail: "\(where_), alinhado com o eixo do lugar. Olhando pra lá: silhuetas; de costas pro sol: luz na cara.\(shadow)")
        }
        if diff >= 135 {
            return LightDirection(kind: .front, title: "Luz na cara \(when)",
                                  detail: "\(where_), atrás de quem fotografa: o lugar fica iluminado de frente, cor cheia.\(shadow)")
        }
        return LightDirection(kind: .side, title: "Luz lateral \(when)",
                              detail: "\(where_), de lado pro eixo: textura e sombras compridas atravessando a cena.\(shadow)")
    }
}
