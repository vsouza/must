import Foundation
import Testing
@testable import Must

/// Referências: NOAA (cálculo do ângulo horário à mão) e timeanddate/Yandex pra BH em 15/11 (05:08 / 18:12).
/// O prompt 13 citava Tóquio 16:38 e BH 18:16 — os valores astronômicos são 16:34 e 18:05.
struct SunServiceTests {
    static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    static let bh = TimeZone(identifier: "America/Sao_Paulo")!

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0, _ tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func near(_ date: Date?, _ expected: Date, minutes: Double = 3) -> Bool {
        guard let date else { return false }
        return abs(date.timeIntervalSince(expected)) <= minutes * 60
    }

    @Test func tokyoMidNovember() {
        let tz = Self.tokyo
        let day = SunService.day(at(2026, 11, 15, 12, 0, tz), latitude: 35.7277, longitude: 139.7663, timeZone: tz)
        #expect(near(day.sunrise, at(2026, 11, 15, 6, 16, tz)))
        #expect(near(day.sunset, at(2026, 11, 15, 16, 34, tz)))
        #expect(near(day.solarNoon, at(2026, 11, 15, 11, 25, tz)))
        #expect(abs(day.noonElevation - 36) < 1)
        // Golden da tarde: sol a 6° até o pôr; azul até −6°.
        #expect(near(day.goldenPM?.start, at(2026, 11, 15, 15, 57, tz)))
        #expect(day.goldenPM?.end == day.sunset)
        #expect(near(day.bluePM?.end, at(2026, 11, 15, 17, 1, tz)))
        // No golden o sol fica a OSO (~242–247°).
        let az = SunService.position(at: day.goldenPM!.start, latitude: 35.7277, longitude: 139.7663).azimuth
        #expect((238...250).contains(az))
    }

    @Test func beloHorizonteNovember() {
        let tz = Self.bh
        let early = SunService.day(at(2026, 11, 2, 12, 0, tz), latitude: -19.9245, longitude: -43.9352, timeZone: tz)
        #expect(near(early.sunrise, at(2026, 11, 2, 5, 14, tz)))
        #expect(near(early.sunset, at(2026, 11, 2, 18, 5, tz)))
        let mid = SunService.day(at(2026, 11, 15, 12, 0, tz), latitude: -19.9245, longitude: -43.9352, timeZone: tz)
        #expect(near(mid.sunrise, at(2026, 11, 15, 5, 8, tz), minutes: 2))
        #expect(near(mid.sunset, at(2026, 11, 15, 18, 12, tz), minutes: 2))
        // Sol quase a pino no verão de BH.
        #expect(mid.noonElevation > 85)
    }

    @Test func cardinalAndAngles() {
        #expect(SunService.cardinal(248) == "OSO")
        #expect(SunService.cardinal(0) == "N")
        #expect(SunService.cardinal(359) == "N")
        #expect(SunService.angle(350, 10) == 20)
        #expect(LightDirection.describe(facing: 248, sunAzimuth: 242, when: "no golden", longShadow: nil).kind == .backlight)
        #expect(LightDirection.describe(facing: 60, sunAzimuth: 242, when: "no golden", longShadow: nil).kind == .front)
        #expect(LightDirection.describe(facing: 160, sunAzimuth: 242, when: "no golden", longShadow: nil).kind == .side)
    }
}

struct HourlyWeatherTests {
    @Test func parsesHourlyAndAQI() throws {
        let json = """
        {"daily":{"time":["2026-11-15"],"weather_code":[1],"temperature_2m_max":[16],"temperature_2m_min":[8],
          "precipitation_probability_max":[5],"sunrise":["2026-11-15T06:16"],"sunset":["2026-11-15T16:34"]},
         "hourly":{"time":["2026-11-15T15:00","2026-11-15T16:00"],"temperature_2m_jma_seamless":[14.2,13.1],
          "apparent_temperature":[13,12],"relative_humidity_2m":[48,52],"cloud_cover_best_match":[20,80],
          "visibility":[18000,15000],"precipitation_probability":[0,10],"wind_speed_10m":[9,7],
          "wind_direction_10m":[45,60],"uv_index":[1.2,0.3]}}
        """
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        var f = try WeatherService.parse(Data(json.utf8), timeZone: tz)
        let day = try #require(f.days.values.first)
        #expect(day.hours.count == 2)
        let h = day.hours[0]
        #expect(h.temp == 14.2 && h.cloud == 20 && h.visibility == 18000 && h.uv == 1.2 && h.windDir == 45)
        #expect(day.hours[1].cloud == 80)

        let aqi = try WeatherService.parseAQI(Data(#"{"hourly":{"time":["2026-11-15T15:00"],"us_aqi":[38]}}"#.utf8), timeZone: tz)
        f.mergeAQI(aqi)
        #expect(f.days.values.first?.hours.first?.aqi == 38)
        #expect(f.days.values.first?.hours.last?.aqi == nil)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let at = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 15, minute: 20))!
        #expect(f.hour(at: at, calendar: cal)?.temp == 14.2)
    }
}
